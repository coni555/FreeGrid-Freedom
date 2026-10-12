// 首页：读取账目，展示自由天数、网格和记账入口。

import SwiftUI
import SwiftData

struct DashboardView: View {

    // ===== SwiftData 反应式查询 =====
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]

    var body: some View {
        DashboardContent(
            expenses: expenses, incomes: incomes,
            snapshot: FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first),
            todaySpending: expenses.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amount }
        )
    }
}

private struct DashboardContent: View {
    let expenses: [Expense]
    let incomes: [Income]
    let snapshot: FinancialSnapshot
    let todaySpending: Double

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
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // 每天都用的排在上面: 记账、今日对比; 偶尔看的排在下面
                    topBar           // 圆点 + FreeGrid + 副标
                    DashboardHero(expenses: expenses, incomes: incomes, snapshot: snapshot,
                                  isDarkMode: isDarkMode, heroLayout: heroLayout, needsSavings: needsSavings)
                    actionRow        // 支出 + 收入
                    if snapshot.dailyBurn.isFinite, snapshot.dailyBurn > 0 {
                        todaySection // 今日 vs 日均; 还没有日均时没有可比的东西
                    }
                    gridSection      // 按天、月或年显示自由网格
                    statsRow         // stat 卡片横向
                    simulateRow      // 模拟决策
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

    /// 顶部 brand bar: 靶心 mark + 品牌名 + 副标。主题和首页布局在 Settings 的「外观」里改。
    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .stroke(Color.ink, lineWidth: 1)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(Color.sky)
                    .frame(width: 9, height: 9)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("FreeGrid")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                Text("通往财富自由之路")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }

            Spacer()
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
            // 没有被动收入时这张卡永远是 0%, 不占位置
            if snapshot.dailyPassive > 0 {
                statCard(label: "Passive",
                         value: FinancialFormatting.percentage(snapshot.passiveRatio),
                         unit: "被动覆盖")
            }
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
        case .insufficientData:
            return needsSavings
                ? "先记下你有多少钱，再记一笔支出，网格开始点亮"
                : "记录第一笔支出后, 网格开始点亮"
        case .finite, .covered: return "当前净值还没有可点亮的自由格"
        }
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
