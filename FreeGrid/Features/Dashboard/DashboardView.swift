// 首页：读取账目，展示自由天数、网格和记账入口。

import SwiftUI
import SwiftData

struct DashboardView: View {

    let onOpenAssets: () -> Void

    // ===== SwiftData 反应式查询 =====
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]

    var body: some View {
        DashboardContent(
            expenses: expenses, incomes: incomes,
            snapshot: FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first),
            todaySpending: expenses.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amount },
            onOpenAssets: onOpenAssets
        )
    }
}

private struct DashboardContent: View {
    let expenses: [Expense]
    let incomes: [Income]
    let snapshot: FinancialSnapshot
    let todaySpending: Double
    let onOpenAssets: () -> Void

    @Environment(\.modelContext) private var modelContext

    // ===== Sheet 状态 =====
    @State private var saveError: String?
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false
    @State private var showingSimulate = false

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

    /// Hero 布局偏好: "leading" (mockup hero-a, 副标左 + 数字右) 或 "vertical" (居中堆叠)
    @AppStorage("heroLayout") private var heroLayout: String = "leading"

    var body: some View {
        // 大数字卡和趋势卡共用同一份历史, 只算一次
        let history = FreedomMath.freedomDaysHistory(
            expenses: expenses,
            incomes: incomes,
            currentNetWorth: snapshot.netWorth,
            firstRecordDate: snapshot.firstExpenseDate,
            dailyPassive: snapshot.dailyPassive,
            now: snapshot.now
        )
        return NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // 首屏: 结论(数字) → 它的图(格子) → 动作(记账、模拟); 回顾类的往下放
                    topBar           // 一行 wordmark
                    heroCard(history: history)
                    gridSection      // 按天、月或年显示自由网格
                    actionRow        // 支出 + 收入
                    simulateRow      // 模拟决策
                    if snapshot.hasExpenses {
                        statsRow     // 净值 ÷ 日均 = 上面的大数字, 再加今天; 一笔支出都没有时不显示
                    }
                    FreedomTrendCard(history: history, hasPassiveIncome: snapshot.dailyPassive > 0,
                                     trackDays: snapshot.trackDays)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
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
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseSheet(onSaved: { exp in
                    showUndoToast(id: exp.id, amount: exp.amount, isExpense: true)
                })
            }
            .sheet(isPresented: $showingAddIncome) {
                AddIncomeSheet(onSaved: { inc in
                    showUndoToast(id: inc.id, amount: inc.amount, isExpense: false)
                })
            }
            .sheet(isPresented: $showingSimulate) {
                SimulateSheet()
            }
            .saveErrorAlert($saveError)
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

    /// 顶部只留一行小 wordmark: 首屏的高度让给数字、格子和记账。
    private var topBar: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.ink, lineWidth: 1)
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(Color.sky)
                    .frame(width: 6, height: 6)
            }
            .accessibilityHidden(true)
            Text("FreeGrid")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.ink)
            Spacer()
        }
    }

    // ============================================================================
    // MARK: - Hero & 三联卡 (UI 组件)
    // ============================================================================

    /// 三张卡连起来是大数字的算式: 净值 ÷ 日均 = 自由天数, 第三张是今天花了多少。
    /// 追踪天数挪到趋势卡的说明里; 被动覆盖率没有被动收入时不出现。
    private var statsRow: some View {
        HStack(spacing: Spacing.md) {
            statCard(label: "Net",
                     value: FinancialFormatting.wholeNumber(snapshot.netWorth),
                     unit: "元净值")
            statCard(label: "Daily",
                     value: snapshot.dailyBurn.isFinite ? String(format: "%.1f", snapshot.dailyBurn) : "—",
                     unit: snapshot.dailyPassive > 0
                        ? "元/天 · 被动 \(FinancialFormatting.percentage(snapshot.passiveRatio))"
                        : "元/天")
            statCard(label: "Today",
                     value: todaySpending.isFinite ? String(format: "%.1f", todaySpending) : "—",
                     unit: todayUnitText,
                     valueColor: todaySpending > snapshot.dailyBurn && snapshot.dailyBurn > 0 ? .flame : .ink)
        }
    }

    /// 今日卡的小字: 和日均比多了还是少了
    private var todayUnitText: String {
        guard snapshot.dailyBurn.isFinite, snapshot.dailyBurn > 0, todaySpending.isFinite else { return "元今日" }
        if todaySpending == 0 { return "今日未消费" }
        if todaySpending < 0 { return "今日净退款" }
        let diff = FinancialFormatting.clampedInteger(abs(todaySpending - snapshot.dailyBurn), range: 0...999_999,
                                                      rounded: .toNearestOrAwayFromZero)
        return todaySpending > snapshot.dailyBurn ? "比日均多 \(diff)" : "比日均少 \(diff)"
    }

    /// 空账本时整张大数字卡是一扇门: 没记过钱就去 Assets, 记过钱就打开记支出
    @ViewBuilder
    private func heroCard(history: [FreedomMath.HistoryPoint]) -> some View {
        let hero = DashboardHero(history: history, snapshot: snapshot,
                                 isDarkMode: isDarkMode, heroLayout: heroLayout, needsSavings: needsSavings)
        if case .insufficientData = snapshot.freedom {
            Button {
                if needsSavings { onOpenAssets() } else { showingAddExpense = true }
            } label: {
                hero.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hero-start")
            .accessibilityHint(needsSavings ? "前往资产页面，选择资产或现金录入" : "打开支出记录表单")
        } else {
            hero
        }
    }

    /// 单个 stat 卡片:数字 / hairline / kicker / sub label 四层(silverline)
    private func statCard(label: String, value: String, unit: String, valueColor: Color = .ink) -> some View {
        VaultCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                // 大 thin 数字(silverline 风格)
                Text(value)
                    .font(.system(size: 28, weight: .thin, design: .rounded).monospacedDigit())
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                // 短 hairline 短横线
                Rectangle()
                    .fill(Color.inkGhost)
                    .frame(width: 22, height: 1)
                    .padding(.vertical, 2)
                // kicker
                KickerLabel(text: label)
                // sub unit
                Text(unit)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }

    // MARK: - 自由网格
    private var gridSection: some View {
        let state = FreedomMath.gridState(for: snapshot.freedom,
                                          lockedAssets: snapshot.lockedAssets, netWorth: snapshot.netWorth)
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
                             assetCells: state.assetCells)
                        .padding(.vertical, Spacing.sm)
                }

                if state.count > 0 {
                HStack(spacing: Spacing.lg) {
                    legendDot(color: .assetGold, label: "资产")
                    legendDot(color: .cashBlue, label: "现金")
                    Spacer()
                    Text("每格 = 1 \(state.unit.label)自由")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
                .padding(.top, Spacing.xs)
                }
            }
        }
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

    /// 空网格时的提示:暗色 SF symbol + 文案
    private var emptyGridHint: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.inkFaint)
            Text(gridEmptyText)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }

    private var gridEmptyText: String {
        switch snapshot.freedom {
        case .invalidData: return "数据异常, 检查金额后再生成网格"
        // 该先做什么上面的大数字卡已经说了, 这里只解释格子是什么
        case .insufficientData: return "每一格是一天自由，有了数据后在这里点亮"
        case .finite, .covered: return "当前净值还没有可点亮的自由格"
        }
    }

    private var needsSavings: Bool {
        snapshot.netWorth <= 0
    }

    /// 收支入口：支出使用 flame，收入使用 skyDeep。
    private var actionRow: some View {
        // 账本里几乎全是支出: 记支出占两份宽, 记收入占一份
        GeometryReader { geo in
            let unit = (geo.size.width - Spacing.md) / 3
            HStack(spacing: Spacing.md) {
                VaultButton(title: "记支出",
                            icon: "minus",
                            style: .destructive) {
                    showingAddExpense = true
                }
                .frame(width: unit * 2)
                VaultButton(title: "记收入",
                            icon: "plus",
                            style: .primary) {
                    showingAddIncome = true
                }
                .frame(width: unit)
            }
        }
        .frame(height: 52)
    }

    /// 模拟决策:ghost button,放在主按钮下方
    private var simulateRow: some View {
        HStack {
            Spacer()
            GhostButton(title: "模拟一笔 · 看决策影响",
                        icon: "wand.and.stars") {
                showingSimulate = true
            }
            Spacer()
        }
        .padding(.top, Spacing.xs)
    }

}
