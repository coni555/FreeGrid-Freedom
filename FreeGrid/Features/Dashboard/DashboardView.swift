// 首页：读取账目，展示自由天数、网格和记账入口。

import SwiftUI
import SwiftData
import StoreKit

struct DashboardView: View {
    // ===== SwiftData 反应式查询 =====
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]
    /// Pro 逐项开关：哪些资产项不计入自由天数
    @Query private var assetItems: [AssetItem]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    /// Pro 每月还款
    @Query private var loans: [Loan]
    /// 在 Assets 或设置里改了口径，首页跟着重算
    @AppStorage(FreedomSettings.countsAssetsKey, store: AppPreferences.store) private var countsAssets = true

    /// 整本账的计算都在这里做：只有账本或口径变了才重算。
    /// 首页自己的弹层、撤销条变化时只重画 DashboardContent，不再扫一遍几千笔支出
    var body: some View {
        let loansInEffect = ProFeatures.loansInEffect(loans)
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                                         assetItems: assetItems, cashAccounts: cashAccounts, loans: loansInEffect,
                                         countsAssets: countsAssets)
        let history = FreedomMath.freedomDaysHistory(
            expenses: expenses,
            incomes: incomes,
            currentNetWorth: snapshot.freedomBase,
            firstRecordDate: snapshot.firstExpenseDate,
            dailyPassive: snapshot.dailyPassive,
            loans: loansInEffect,
            uncountedAccounts: Set(cashAccounts.filter { !$0.countsInFreedom }.map(\.id)),
            now: snapshot.now
        )
        // 今天的起止只算一次；逐笔调 isDateInToday 在几千笔的账本上要好几毫秒
        let today = Calendar.current.dateInterval(of: .day, for: snapshot.now)
        return DashboardContent(
            snapshot: snapshot,
            history: history,
            statInputs: HomeStat.Inputs(snapshot: snapshot, expenses: expenses, incomes: incomes, loans: loansInEffect),
            // 和日均比的是日常开销，自动扣的房租、月供不算
            todaySpending: today.map { day in
                expenses.reduce(0) { sum, expense in
                    expense.countsInBurn && expense.date >= day.start && expense.date < day.end ? sum + expense.amount : sum
                }
            } ?? 0
        )
    }
}

extension DashboardContent {
    fileprivate static let topID = "dashboard-top"
}

/// 点了第几张数字小卡
private struct StatPick: Identifiable {
    let index: Int
    var id: Int { index }
}

/// 一次「打开记支出表单」的请求
private struct ExpenseDraft: Identifiable {
    let id = UUID()
    var amount = ""
}

private struct DashboardContent: View {
    let snapshot: FinancialSnapshot
    /// 自由天数趋势，由 DashboardView 随账本一起算好
    let history: [FreedomMath.HistoryPoint]
    /// 底部三张数字小卡要的数，同样由 DashboardView 随账本算好
    let statInputs: HomeStat.Inputs
    let todaySpending: Double

    @Environment(\.modelContext) private var modelContext
    /// 讲解和起步引导要圈出这一页上的位置
    @Environment(AppGuide.self) private var guide

    // ===== Sheet 状态 =====
    @State private var saveError: String?
    /// 非 nil 时打开记支出表单; 里面带着要预填的金额 (平时是空串)。
    /// 用 item 而不是布尔开关: 表单内容要跟着这次请求的金额走, 不能读到上一次的旧值。
    @State private var expenseDraft: ExpenseDraft?
    @State private var showingAddIncome = false
    @State private var showingSimulate = false
    /// 自由卡：首页升级提示和长按大数字都打开它
    @State private var showingFreedomCard = false
    @AppStorage(FreedomCardPrompt.highestSeenKey, store: AppPreferences.store) private var highestSeenCard = -1
    @AppStorage("setupGuideCompleted", store: AppPreferences.store) private var setupFinished = false
    /// 底部三张数字小卡放哪三个指标
    @AppStorage(HomeStat.slotsKey, store: AppPreferences.store) private var storedStatSlots = ""
    /// 点了某张数字小卡：弹出选它显示什么的半屏
    @State private var statPick: StatPick?
    /// 正在拖数字小卡时首页不跟着滚
    @State private var draggingStat = false
    /// 模拟里点了「记为支出」时先记下金额, 等模拟表单收完再打开记支出
    @State private var amountFromSimulation: String?

    // ===== 撤销 Toast(刚刚记的一笔有 5 秒撤销窗口) =====
    /// 待撤销交易 ID, nil = 不显示 toast
    @State private var pendingUndoID: UUID? = nil
    /// toast 文案(含金额),已计算好
    @State private var pendingUndoLabel: String = ""
    /// 撤销的是支出还是收入(决定还原 cash 是 + 还是 −)
    @State private var pendingUndoIsExpense: Bool = true
    /// 5 秒倒计时 task,新 toast 进来时 cancel 旧的
    @State private var pendingUndoTimer: Task<Void, Never>? = nil

    // ===== 主题切换 (与 ContentView 共享同一 key) =====
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage(AppTheme.followsSystemKey, store: AppPreferences.store) private var followsSystem = false
    /// 现在实际是深色还是浅色（跟随系统时看系统）
    @Environment(\.colorScheme) private var colorScheme
    private var showsDark: Bool { colorScheme == .dark }

    /// Hero 布局偏好: "leading" (mockup hero-a, 副标左 + 数字右) 或 "vertical" (居中堆叠)
    @AppStorage("heroLayout") private var heroLayout: String = "leading"


    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    #if DEBUG
                    // 临时：首页改造方向的对比，带 -homeConcept 时换掉整页
                    if let concept = HomeConcept.current {
                        HomeConceptBody(concept: concept, snapshot: snapshot, history: history,
                                        todaySpending: todaySpending, isDark: showsDark,
                                        onExpense: { expenseDraft = ExpenseDraft() },
                                        onIncome: { showingAddIncome = true },
                                        onSimulate: { showingSimulate = true })
                            .id(Self.topID)
                    } else {
                        classicHome
                    }
                    #else
                    classicHome
                    #endif
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            // 「认识首页」: 先回到顶部, 等位置排好再开始
            .task(id: guide.replays(of: .dashboard)) {
                guard snapshot.hasExpenses, guide.takeReplay(.dashboard) else { return }
                // 新用户刚记完第一笔: 等记支出的表单收完
                try? await Task.sleep(for: .milliseconds(900))
                scroller.scrollTo(Self.topID, anchor: .top)
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, expenseDraft == nil, !showingAddIncome, !showingSimulate else { return }
                withAnimation(.easeInOut(duration: 0.25)) { guide.start(.dashboard) }
            }
            }
            .scrollDisabled(draggingStat)
            .scrollContentBackground(.hidden)
            // 隐藏导航栏后, 贴着安全区顶边的滚动视图会把内容画到状态栏底下;
            // 让出 1pt 它就只在安全区内裁剪, 数字不再压到时间和电量上
            .padding(.top, 1)
            .background(Color.paper.ignoresSafeArea())
            .hideNavBar()
            .safeAreaInset(edge: .top) {
                if pendingUndoID != nil {
                    undoToast
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(item: $expenseDraft) { draft in
                AddExpenseSheet(initialAmount: draft.amount, onSaved: { exp in
                    showUndoToast(id: exp.id, amount: exp.amount, isExpense: true)
                })
            }
            .sheet(isPresented: $showingFreedomCard) { FreedomCardSheet() }
            .sheet(item: $statPick) { pick in
                HomeStatPicker(index: pick.index, slots: statSlots, inputs: statInputs) { stat in
                    withAnimation(.snappy(duration: 0.3)) {
                        storedStatSlots = HomeStat.encode(HomeStat.replacing(statSlots, at: pick.index, with: stat))
                    }
                }
            }
            .sheet(isPresented: $showingAddIncome) {
                AddIncomeSheet(onSaved: { inc in
                    showUndoToast(id: inc.id, amount: inc.amount, isExpense: false)
                })
            }
            // 模拟里点了「记为支出」: 等模拟这张表单收完, 再带着金额打开记支出
            .sheet(isPresented: $showingSimulate, onDismiss: {
                if let amount = amountFromSimulation {
                    amountFromSimulation = nil
                    expenseDraft = ExpenseDraft(amount: amount)
                }
            }) {
                SimulateSheet(onRecordExpense: { amountFromSimulation = $0 })
            }
            .background {
                ReviewInvitationPresenter(
                    blocked: showingSimulate || showingFreedomCard || statPick != nil || saveError != nil,
                    busy: expenseDraft != nil || showingAddIncome || pendingUndoID != nil
                )
            }
            .saveErrorAlert($saveError)
        }
    }

    /// 首页现在的样子
    @ViewBuilder
    private var classicHome: some View {
                    // 首屏: 结论(数字, 带可收起的趋势) → 它的图(格子) → 动作(记账、模拟)
                    topBar           // 一行 wordmark
                        .id(Self.topID)
                    DashboardHero(history: history, snapshot: snapshot,
                                  isDarkMode: showsDark, heroLayout: heroLayout, needsSavings: needsSavings,
                                  cardPrompt: cardPrompt, onOpenCard: { showingFreedomCard = true })
                    gridSection      // 按天、月或年显示自由网格
                        .guideTarget(.grid, in: guide)
                    actionRow        // 支出 + 收入
                    simulateRow      // 模拟决策
                    if snapshot.hasExpenses {
                        statsRow     // stat 卡片横向; 一笔支出都没有时只会是「—」和 0
                    }
                    if snapshot.dailyBurn.isFinite, snapshot.dailyBurn > 0 {
                        todaySection // 今日 vs 日均; 还没有日均时没有可比的东西
                    }
    }

    // ============================================================================
    // MARK: - 撤销 Toast UI + 逻辑
    // ============================================================================

    /// Toast bar: 1 个 dot + 文案 + 撤销链接, silverline mist 底
    private var undoToast: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(pendingUndoIsExpense ? Color.flame : Color.skyDeep)
                .frame(width: 6, height: 6)
            Text(pendingUndoLabel)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Spacer()
            Button("撤销", action: undoLastTx)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.skyDeep)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous).fill(Color.mist)
        )
        .overlay(
            Capsule(style: .continuous).stroke(Color.hairlineSoft, lineWidth: 1)
        )
        .padding(.horizontal, Spacing.lg)
        .padding(.top, 6)
    }

    /// 启动 5 秒倒计时 toast(取消上一次 timer)
    private func showUndoToast(id: UUID, amount: Double, isExpense: Bool) {
        pendingUndoTimer?.cancel()

        let sign = isExpense ? "支出" : "收入"
        let formatted = amount.formatted(.number.precision(.fractionLength(0...2)))
        withAnimation(.spring(duration: 0.3)) {
            pendingUndoID = id
            pendingUndoLabel = "已记\(sign) ¥\(formatted)"
            pendingUndoIsExpense = isExpense
        }

        pendingUndoTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                pendingUndoID = nil
            }
        }
    }

    /// 撤销:按 ID 找到记录,删掉并还原 cash
    private func undoLastTx() {
        guard let id = pendingUndoID else { return }
        do {
            try LedgerStore.undo(id: id, kind: pendingUndoIsExpense ? .expense : .income, in: modelContext)
            ReviewInvitationStore.shared.didUndo(transactionID: id)
        } catch {
            saveError = error.localizedDescription
            return
        }

        pendingUndoTimer?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            pendingUndoID = nil
        }
    }

    // ============================================================================
    // MARK: - 顶部 wordmark
    // ============================================================================

    /// 顶部一行: 左边的靶心是深浅色开关, 右边切换大数字布局。
    /// 两个开关 Settings 的「外观」里也有; 首页这两个留给已经用惯的老用户。
    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: {
                // 首页这个开关只在浅色、深色之间切；跟随系统时点它，就固定成和现在相反的那个
                withAnimation(.easeInOut(duration: 0.25)) {
                    isDarkMode = !showsDark
                    followsSystem = false
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.ink, lineWidth: 1)
                        .frame(width: 22, height: 22)
                    if showsDark {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.sky)
                    } else {
                        Circle()
                            .fill(Color.sky)
                            .frame(width: 9, height: 9)
                    }
                }
                .contentShape(Rectangle())   // 扩大点击区
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsDark ? "切换浅色模式" : "切换深色模式")

            Text("FreeGrid")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.ink)

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    heroLayout = (heroLayout == "leading") ? "vertical" : "leading"
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.ink, lineWidth: 1)
                        .frame(width: 22, height: 22)
                    Image(systemName: heroLayout == "vertical"
                          ? "rectangle.split.1x2"
                          : "rectangle.split.2x1")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.sky)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(heroLayout == "vertical" ? "大数字放右边" : "大数字放中间")
        }
    }

    // ============================================================================
    // MARK: - Hero & 三联卡 (UI 组件)
    // ============================================================================

    /// 固定三张：点一张选它显示什么，按住拖动换位置
    private var statSlots: [HomeStat] {
        HomeStat.slots(stored: storedStatSlots, hasPassive: snapshot.dailyPassive > 0)
    }

    private var statsRow: some View {
        HomeStatRow(slots: statSlots, inputs: statInputs,
                    onReorder: { storedStatSlots = HomeStat.encode($0) },
                    onPick: { statPick = StatPick(index: $0) },
                    onDraggingChange: { draggingStat = $0 })
    }

    /// Today: Silverline 版 — 单行 bar 设计
    /// 左 ¥5 (today) — bar with marker — 右 ¥72 (avg)
    /// 下方 delta caption 居中
    private var todaySection: some View {
        VaultCard(padding: Spacing.lg) {
            VStack(spacing: Spacing.md) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    // 左:今日金额
                    VStack(alignment: .leading, spacing: 2) {
                        Text(todaySpending.isFinite ? String(format: "¥%.1f", todaySpending) : "¥—")
                            .font(.system(size: 24, weight: .thin, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.ink)
                        KickerLabel(text: "Today")
                    }
                    .frame(minWidth: 60, alignment: .leading)

                    // 中:bar with sky fill + marker
                    GeometryReader { geo in
                        // 花了一点点也至少画出一小段; 一分没花就是空的
                        let pct = todayPercent > 0 ? max(0.04, min(todayPercent, 1.0)) : 0
                        ZStack(alignment: .leading) {
                            // mist 底 bar
                            Rectangle()
                                .fill(Color.mist2)
                                .frame(height: 2)
                            // sky fill
                            Rectangle()
                                .fill(Color.sky)
                                .frame(width: geo.size.width * CGFloat(pct), height: 2)
                            // sky-deep marker (短竖线在 fill 末端)
                            Rectangle()
                                .fill(Color.skyDeep)
                                .frame(width: 1.5, height: 10)
                                .offset(x: geo.size.width * CGFloat(pct) - 0.75)
                        }
                    }
                    .frame(height: 10)

                    // 右:日均金额
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(snapshot.dailyBurn.isFinite ? String(format: "¥%.1f", snapshot.dailyBurn) : "¥—")
                            .font(.system(size: 24, weight: .thin, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkMuted)
                        KickerLabel(text: averageWord == "日均" ? "avg" : "日常")
                    }
                    .frame(minWidth: 60, alignment: .trailing)
                }

                // delta caption (居中)
                if snapshot.dailyBurn > 0 {
                    Text(todayDeltaText)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                }
            }
        }
    }

    /// today bar 下方的 delta 文案
    private var todayDeltaText: String {
        guard snapshot.dailyBurn.isFinite, snapshot.dailyBurn > 0, todaySpending.isFinite else {
            return "再记几笔，就能和平时比"
        }
        if todaySpending == 0 {
            return "今日尚未消费"
        }
        // 当天净额为负(退款/冲正大于消费)时,"低于日均 N%" 会算出 100% 以上的
        // 荒唐数字。这种日子本来就不是"省钱",单独说清楚。
        if todaySpending < 0 {
            return "今日净退款 ¥\(String(format: "%.1f", -todaySpending))"
        }
        let diffPct = FinancialFormatting.clampedInteger(
            abs((1 - todayPercent) * 100),
            range: 0...9_999
        )
        // 差不到一毛钱时说持平，不写「低 0% · 少花 ¥0.0」
        if abs(todaySpending - snapshot.dailyBurn) < 0.05 {
            return "和\(averageWord)差不多"
        }
        if todaySpending > snapshot.dailyBurn {
            let over = todaySpending - snapshot.dailyBurn
            return "比\(averageWord)高 \(diffPct)% · 多花 ¥\(String(format: "%.1f", over))"
        } else {
            let savings = snapshot.dailyBurn - todaySpending
            return "比\(averageWord)低 \(diffPct)% · 少花 ¥\(String(format: "%.1f", savings))"
        }
    }

    /// Today 只和日常开销比。有固定支出时上面 Daily 卡的日均含固定，这里改叫「日常开销」免得两个数对不上
    private var averageWord: String { snapshot.dailyFixed > 0 ? "日常开销" : "日均" }

    /// 今日花费占日均的百分比(用于颜色判断)
    private var todayPercent: Double {
        guard snapshot.dailyBurn > 0 else { return 0 }
        return todaySpending / snapshot.dailyBurn
    }

    // MARK: - 自由网格
    private var gridSection: some View {
        let run = snapshot.freedomRun
        let state = FreedomMath.gridState(for: run.state,
                                          lockedAssets: snapshot.countedAssets, netWorth: snapshot.freedomBase,
                                          paymentDays: run.paymentDays, missedPaymentDay: run.missedPaymentDay)
        return VaultCard(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "Freedom Grid")
                    Spacer()
                    Text(gridSummary(state: state))
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.inkFaint)
                }

                if state.count == 0 {
                    emptyGridHint
                } else {
                    LifeGrid(unit: state.unit, count: state.count,
                             assetCells: state.assetCells, paymentCells: state.paymentCells,
                             showsMissedPayment: state.showsMissedPayment)
                        .padding(.vertical, Spacing.xs)
                }

                if state.count > 0 {
                    // 一行放不下（例如同时有「部分资产未计入」和「还款日」）时，「每格 = …」挪到第二行，图例不缩
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.lg) {
                            legendItems(state: state)
                            Spacer(minLength: Spacing.sm)
                            cellUnitText(state: state)
                        }
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.lg) { legendItems(state: state) }
                            cellUnitText(state: state)
                        }
                    }
                    .padding(.top, Spacing.xs)
                }
            }
        }
    }

    @ViewBuilder
    private func legendItems(state: FreedomMath.GridState) -> some View {
        // 金色图例：总开关开、且至少有一部分资产在格子里（或者根本没有不计入的）
        if snapshot.countsAssets, snapshot.countedAssets > 0 || snapshot.uncountedAssets == 0 {
            legendDot(color: .assetGold, label: "资产")
        }
        // 蓝色图例同理：现金账户全部不计入时格子里没有蓝色
        if snapshot.countedCash > 0 || snapshot.excludedCash == 0 {
            legendDot(color: .cashBlue, label: "现金")
        }
        if !state.paymentCells.isEmpty || state.showsMissedPayment {
            HStack(spacing: 6) {
                PunchedCell(cornerRadius: 1)
                    .fill(Color.inkFaint, style: FillStyle(eoFill: true))
                    .frame(width: 8, height: 8)
                Text("还款日")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
            }
            .accessibilityIdentifier("repayment-day-legend")
            .guideTarget(.repaymentDays, in: guide)
        }
        if let note = snapshot.uncountedAssetsNote {
            Text(note)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .fixedSize()
                .accessibilityIdentifier("uncounted-assets-note")
        }
    }

    private func cellUnitText(state: FreedomMath.GridState) -> some View {
        Text("每格 = 1 \(state.unit.label)自由")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Color.inkFaint)
            .fixedSize()
    }

    /// 图例:silverline 版小方块 + 标签(无 glow)
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 8)
                .cornerRadius(1)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkMuted)
        }
    }

    /// 网格右上角文案: 格数和上面的大数字是同一个数, 只在格子画不下时说明 ("99+ 年")
    private func gridSummary(state: FreedomMath.GridState) -> String {
        state.isOverflow ? "\(state.count)+ \(state.unit.label)" : ""
    }

    /// 空网格时的提示：九个还没点亮的描边小格 + 文案
    private var emptyGridHint: some View {
        VStack(spacing: Spacing.md) {
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    GridRow {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .stroke(Color.inkGhost, lineWidth: 1)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
            Text(gridEmptyText)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }

    private var gridEmptyText: String {
        switch snapshot.freedom {
        case .invalidData: return "有一笔金额不对，去 History 找找特别大或负数的"
        // 该先做什么上面的大数字卡已经说了, 这里只解释格子是什么
        case .insufficientData: return "每一格是一天自由，有了数据后在这里点亮"
        case .finite, .covered: return "当前净值还没有可点亮的自由格"
        }
    }

    /// 卡第一次升到某个更高的等级时，大数字下面提示一次；起步引导走完之前不打扰
    private var cardPrompt: (text: String, tier: FreedomCardTier)? {
        guard setupFinished else { return nil }
        let tier = FreedomCardTier.tier(for: snapshot.freedom)
        let hasNumber: Bool
        switch snapshot.freedom {
        case .finite, .covered: hasNumber = true
        case .insufficientData, .invalidData: hasNumber = false
        }
        return FreedomCardPrompt.text(current: tier, highestSeen: highestSeenCard, hasFreedomNumber: hasNumber)
            .map { ($0, tier) }
    }

    private var needsSavings: Bool {
        snapshot.netWorth <= 0
    }

    /// 收支入口：支出使用 flame，收入使用 skyDeep。
    private var actionRow: some View {
        HStack(spacing: Spacing.md) {
            VaultButton(title: "记支出",
                        icon: "minus",
                        style: .destructive) {
                expenseDraft = ExpenseDraft()
            }
            .guideTarget(.expenseButton, in: guide)
            VaultButton(title: "记收入",
                        icon: "plus",
                        style: .primary) {
                showingAddIncome = true
            }
        }
    }

    /// 模拟决策:ghost button,放在主按钮下方
    private var simulateRow: some View {
        HStack {
            Spacer()
            GhostButton(title: "模拟一笔 · 看决策影响",
                        icon: "wand.and.stars") {
                showingSimulate = true
            }
            .guideTarget(.simulate, in: guide)
            Spacer()
        }
        .padding(.top, Spacing.xs)
    }

}

/// 评价邀请。只有这个不显示任何东西的小视图观察邀请和根层的放行条件：
/// 切 Tab、保存时这些条件会变，放在首页本体里会让整页连同几千笔账的计算重来一遍
private struct ReviewInvitationPresenter: View {
    /// 首页开着模拟、自由卡或错误提示：这次邀请作废
    let blocked: Bool
    /// 首页还开着记账表单或撤销条：等它们收起
    let busy: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @State private var reviewInvitation = ReviewInvitationStore.shared

    private struct ReviewContext: Equatable {
        let opportunity: UUID?
        let allowed: Bool
        let resting: Bool
    }

    private var reviewContext: ReviewContext {
        ReviewContext(opportunity: reviewInvitation.opportunity?.id,
                      allowed: reviewInvitation.presentationAllowed && !blocked,
                      resting: !reviewInvitation.formPresented && !busy)
    }

    var body: some View {
        Color.clear.task(id: reviewContext) { await offerReview() }
    }

    private func offerReview() async {
        let context = reviewContext
        guard let id = context.opportunity else { return }
        guard !ReviewInvitationStore.isSuppressedForTesting else { reviewInvitation.discard(id); return }
        guard context.allowed else { reviewInvitation.discard(id); return }
        guard context.resting else { return }
        // 已经等过表单和撤销窗口，再留一个安静间隙；继续操作会取消这次任务。
        do { try await Task.sleep(for: .seconds(1)) } catch { return }
        guard !Task.isCancelled,
              let currentExpenses = try? modelContext.fetch(FetchDescriptor<Expense>()) else { return }
        reviewInvitation.requestIfEligible(id, recordedDays: FirstWeekRecap.recordedDays(currentExpenses)) {
            #if DEBUG
            if ReviewInvitationStore.usesRequestProbe {
                ReviewInvitationStore.recordRequestProbe()
                return
            }
            #endif
            requestReview()
        }
    }
}
