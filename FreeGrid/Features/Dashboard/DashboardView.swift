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

    /// 首次引导的一次性闸门:存款与支出齐备过一次即永久落闸
    @AppStorage("onboardingCompleted") private var onboardingCompleted: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    topBar           // 圆点 + FreeGrid + 副标
                    DashboardHero(expenses: expenses, incomes: incomes, snapshot: snapshot,
                                  isDarkMode: isDarkMode, heroLayout: heroLayout, needsSavings: needsSavings)
                    if needsOnboarding {
                        onboardingPrompt // 存款与支出齐备后自动消失
                    }
                    gridSection      // 按天、月或年显示自由网格
                    statsRow         // 3 个 stat 卡片横向
                    actionRow        // 支出 + 收入 (提前,放在 stats 后方便操作)
                    simulateRow      // 模拟决策
                    todaySection     // 今日 vs 日均 (推到最底,是 review 信息)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollContentBackground(.hidden)
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
            .onAppear { latchOnboardingIfSatisfied() }
            .onChange(of: onboardingSatisfied) { _, _ in latchOnboardingIfSatisfied() }
        }
    }

    /// 只单向落闸,不会再打开——净值以后跌回 0 以下也不重新弹引导。
    private func latchOnboardingIfSatisfied() {
        if onboardingSatisfied { onboardingCompleted = true }
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

    /// 顶部 brand bar:靶心 mark(同时是 dark/light 切换按钮) + 品牌名 + VOL 标识
    /// mark 内部:light mode = sky 实心点(太阳),dark mode = moon icon
    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            // 主题切换按钮:外圈 outline + 内 sun/moon
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isDarkMode.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.ink, lineWidth: 1)
                        .frame(width: 22, height: 22)
                    if isDarkMode {
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
            .accessibilityLabel(isDarkMode ? "切换浅色模式" : "切换深色模式")

            VStack(alignment: .leading, spacing: 1) {
                Text("FreeGrid")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                Text("通往财富自由之路")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }

            Spacer()

            // Hero 布局切换 toggle (leading 副标左数字右 ↔ vertical 居中堆叠)
            // 放在右侧 utility 区,跟左侧 dark mode toggle 形成两端 cluster
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
            .accessibilityLabel(heroLayout == "vertical" ? "切换左右布局" : "切换居中堆叠布局")
        }
        .padding(.bottom, Spacing.xs)
    }

    // ============================================================================
    // MARK: - Hero & 三联卡 (UI 组件)
    // ============================================================================

    private var statsRow: some View {
        HStack(spacing: Spacing.md) {
            statCard(label: "Daily",
                     value: snapshot.dailyBurn.isFinite ? String(format: "%.1f", snapshot.dailyBurn) : "—",
                     unit: "元/天")
            statCard(label: "Passive",
                     value: FinancialFormatting.percentage(snapshot.passiveRatio),
                     unit: "被动覆盖")
            statCard(label: "Track",
                     value: "\(snapshot.trackDays)",
                     unit: "天追踪")
        }
    }

    /// 单个 stat 卡片:数字 / hairline / kicker / sub label 四层(silverline)
    private func statCard(label: String, value: String, unit: String) -> some View {
        VaultCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                // 大 thin 数字(silverline 风格)
                Text(value)
                    .font(.system(size: 28, weight: .thin, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
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
                        let pct = max(0.04, min(todayPercent, 1.0))
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
                        KickerLabel(text: "avg")
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
            return "等待有效日均数据"
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
        if todaySpending > snapshot.dailyBurn {
            let over = todaySpending - snapshot.dailyBurn
            return "高于日均 \(diffPct)% · 多花 ¥\(String(format: "%.1f", over))"
        } else {
            let savings = snapshot.dailyBurn - todaySpending
            return "低于日均 \(diffPct)% · 节省 ¥\(String(format: "%.1f", savings))"
        }
    }

    /// 今日花费占日均的百分比(用于颜色判断)
    private var todayPercent: Double {
        guard snapshot.dailyBurn > 0 else { return 0 }
        return todaySpending / snapshot.dailyBurn
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

    /// 网格右上角文案:按档位显示当前格数 + 单位
    /// 日档 "127 天" / 月档 "16 月" / 年档 "34 年" / 溢出 "99+ 年"
    private func gridSummary(state: FreedomMath.GridState) -> String {
        if state.count == 0 { return "等待数据" }
        if state.isOverflow { return "\(state.count)+ \(state.unit.label)" }
        return "\(state.count) \(state.unit.label)"
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
        case .insufficientData:
            return needsSavings
                ? "先记下你有多少钱，再记一笔支出，网格开始点亮"
                : "记录第一笔支出后, 网格开始点亮"
        case .finite, .covered: return "当前净值还没有可点亮的自由格"
        }
    }

    /// 首次使用的两步引导：先建立存款净值，再用第一笔支出建立日均消费。
    /// 两类数据齐备后 @Query 自动更新，入口随即消失，不长期挤占品牌主视觉。
    private var onboardingPrompt: some View {
        Button {
            if needsSavings {
                onOpenAssets()
            } else {
                showingAddExpense = true
            }
        } label: {
            VaultCard(emphasis: .high, padding: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: needsSavings ? "banknote.fill" : "minus.circle.fill")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(needsSavings ? Color.cashBlue : Color.flame)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(onboardingTitle)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Text(onboardingDetail)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                    }

                    Spacer(minLength: Spacing.xs)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding-prompt")
        .accessibilityLabel(onboardingTitle)
        .accessibilityHint(needsSavings ? "前往资产页面，选择资产或现金录入" : "打开支出记录表单")
    }

    private var needsSavings: Bool {
        snapshot.netWorth <= 0
    }

    /// 存款 + 支出同时齐备过一次,引导就算走完。
    private var onboardingSatisfied: Bool {
        !needsSavings && !expenses.isEmpty
    }

    /// 引导是一次性的:走完就永久关掉。
    /// 不能只看 `needsSavings`——记支出会把现金扣成负数(cash 无下限),
    /// 老用户净值跌到 0 以下时这张卡会重新常驻,那正是被否决过的常驻卡形态。
    private var needsOnboarding: Bool {
        !onboardingCompleted && !onboardingSatisfied
    }

    /// 文案刻意不用"存款":点进去是 Assets 页,资产和现金都能填,
    /// 说"存款"会让用户以为只收现金。
    private var onboardingTitle: String {
        if needsSavings {
            return expenses.isEmpty ? "先记下你有多少钱" : "还差一步:记下你有多少钱"
        }
        return "再记一笔支出"
    }

    private var onboardingDetail: String {
        if needsSavings {
            return expenses.isEmpty
                ? "定期、股票、现金都算，记完再记一笔支出，格子就会点亮"
                : "已经有支出了，补上手里的钱，格子就能点亮"
        }
        return "已经知道你有多少钱了，再建立日均消费，格子就能点亮"
    }

    /// 收支入口：支出使用 flame，收入使用 skyDeep。
    private var actionRow: some View {
        HStack(spacing: Spacing.md) {
            VaultButton(title: "记支出",
                        icon: "minus",
                        style: .destructive) {
                showingAddExpense = true
            }
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
            Spacer()
        }
        .padding(.top, Spacing.xs)
    }

}
