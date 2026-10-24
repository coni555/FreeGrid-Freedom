// 临时：首页底部改成「组件区」的效果图，只在 DEBUG 里、带 `-homeModulesMock <mode>` 时出现。
// home：三张小卡 + GAP 目标 + 今日；two：两张小卡 + GAP；edit：编辑状态；add：添加组件；widgets：搬到桌面小组件。
// 用户定了方向后，留下的部分改成正式实现，这个文件删掉。

#if DEBUG
import SwiftUI
import SwiftData

enum HomeModulesMock: String {
    case home, two, edit, add, widgets

    static let current: HomeModulesMock? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-homeModulesMock"), i + 1 < args.count else { return nil }
        return HomeModulesMock(rawValue: args[i + 1])
    }()

    /// add、widgets 换掉整页；其余只换首页底部
    var replacesPage: Bool { self == .add || self == .widgets }
}

// MARK: - 小格子条：每张卡的签名

/// 一格的样子
enum MicroCell {
    case filled(Color, opacity: Double = 1)
    case empty
    /// 还款、交租那天：中间打孔
    case punched(Color)
    /// 现在走到的那一格：亮一点
    case current(Color)
}

/// 一排小格子，和首页大格子同一种圆角和配色
struct MicroGrid: View {
    let cells: [MicroCell]
    var cellSize: CGFloat = 7
    var spacing: CGFloat = 2.5

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                let shape = RoundedRectangle(cornerRadius: cellSize * 0.2, style: .continuous)
                switch cell {
                case .filled(let color, let opacity):
                    shape.fill(color.opacity(opacity)).frame(width: cellSize, height: cellSize)
                case .empty:
                    shape.stroke(Color.hairline, lineWidth: 1).frame(width: cellSize - 1, height: cellSize - 1)
                        .frame(width: cellSize, height: cellSize)
                case .punched(let color):
                    PunchedCell(cornerRadius: cellSize * 0.2)
                        .fill(color, style: FillStyle(eoFill: true))
                        .frame(width: cellSize, height: cellSize)
                case .current(let color):
                    shape.fill(color).frame(width: cellSize, height: cellSize)
                        .shadow(color: color.opacity(0.6), radius: 3)
                }
            }
        }
    }
}

// MARK: - 指标换成 FreeGrid 的语言：数字 + 10 格 + 用天数说话的小字

struct MockMetricData {
    let inputs: HomeStat.Inputs
    /// 最近 10 天每天的日常支出，旧的在前
    let recentDays: [Double]
    /// 最近 90 天平均每天存下多少（收入 − 支出）
    let dailySaving: Double

    var snapshot: FinancialSnapshot { inputs.snapshot }
    var netBurn: Double { max(snapshot.dailyCost - snapshot.dailyPassive, 0.01) }
    func days(_ amount: Double) -> Double { amount / netBurn }
}

extension HomeStat {
    func mockUnit(_ data: MockMetricData) -> String {
        let inputs = data.inputs
        switch self {
        case .month:
            return "花掉 \(FinancialFormatting.wholeNumber(data.days(inputs.monthSpent))) 天自由"
        case .next:
            guard let next = inputs.nextFixed else { return "没有固定支出" }
            return "天后 · \(next.name) = \(FinancialFormatting.wholeNumber(data.days(next.amount))) 天"
        case .base:
            let base = data.snapshot.freedomBase
            let assets = base > 0 ? data.snapshot.countedAssets / base : 0
            return "资产 \(FinancialFormatting.percentage(assets)) · 现金 \(FinancialFormatting.percentage(1 - assets))"
        case .track:
            let recorded = data.recentDays.filter { $0 > 0 }.count
            return "近 10 天记了 \(recorded) 天"
        case .daily:
            return "近 10 天，越深花得越多"
        default:
            return display(inputs).unit
        }
    }

    /// 每张卡 10 格
    func cells(_ data: MockMetricData) -> [MicroCell] {
        let inputs = data.inputs
        func ratio(_ r: Double, _ color: Color) -> [MicroCell] {
            let n = min(max(Int((r * 10).rounded()), 0), 10)
            return (0..<10).map { $0 < n ? .filled(color) : .empty }
        }
        switch self {
        case .daily:
            // 每天和日均比：花得越多格子越深
            let avg = max(data.snapshot.dailyBurn, 0.01)
            return data.recentDays.map { day in
                day <= 0 ? .empty : .filled(.cashBlue, opacity: min(0.25 + 0.75 * day / (avg * 1.5), 1))
            }
        case .month:
            let n = min(Int(data.days(inputs.monthSpent).rounded()), 10)
            return (0..<10).map { $0 < n ? .filled(.flame, opacity: 0.85) : .empty }
        case .saved:
            guard inputs.monthIncome > 0 else { return Array(repeating: .empty, count: 10) }
            return ratio((inputs.monthIncome - inputs.monthSpent) / inputs.monthIncome, .skyDeep)
        case .next:
            // 一格一天，最后一格是交租那天
            guard let next = inputs.nextFixed else { return Array(repeating: .empty, count: 10) }
            let away = min(next.daysAway, 10)
            return (0..<10).map { i in
                i == away - 1 ? .punched(.inkMuted) : i < away - 1 ? .filled(.inkGhost) : .empty
            }
        case .passive:
            return ratio(data.snapshot.passiveRatio, .mossGreen)
        case .base:
            let base = data.snapshot.freedomBase
            let gold = base > 0 ? Int((data.snapshot.countedAssets / base * 10).rounded()) : 0
            return (0..<10).map { $0 < gold ? .filled(.assetGold) : .filled(.cashBlue) }
        case .track:
            return data.recentDays.map { $0 > 0 ? .filled(.ink, opacity: 0.55) : .empty }
        }
    }
}

/// 新样子的小卡：短横线换成 10 格
struct MockMetricCard: View {
    let stat: HomeStat
    let data: MockMetricData
    var large = false
    var framed = true

    var body: some View {
        MockFrame(framed: framed, padding: Spacing.md) {
            VStack(alignment: .leading, spacing: 7) {
                Text(stat.display(data.inputs).value)
                    .font(.system(size: large ? 40 : 28, weight: .thin, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                MicroGrid(cells: stat.cells(data), cellSize: large ? 11 : 7, spacing: large ? 3.5 : 2.2)
                    .padding(.vertical, 1)
                KickerLabel(text: stat.kicker)
                Text(stat.mockUnit(data))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

// MARK: - GAP 目标：倒计时 + 12 个月格

struct MockGoalCard: View {
    let data: MockMetricData
    var targetMonths = 12
    var compact = false
    var framed = true

    private var daysToGo: Int? { MockModules.daysToGo(data, months: targetMonths) }
    private var monthsNow: Double { MockModules.currentDays(data) / 30.4 }

    var body: some View {
        MockFrame(framed: framed, padding: compact ? Spacing.md : Spacing.lg) {
            VStack(alignment: .leading, spacing: compact ? Spacing.sm : Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "Goal · GAP \(targetMonths) 个月")
                    Spacer()
                    if let days = daysToGo, days > 0,
                       let date = Calendar.current.date(byAdding: .day, value: days, to: .now) {
                        Text(FreedomMath.depleteDateText(date))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                    }
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    if let days = daysToGo {
                        if days == 0 {
                            emphasized("已经", "够了", "，随时可以出发", size: 20)
                        } else {
                            Text("还差")
                                .font(.system(size: 17, weight: .light, design: .rounded))
                                .foregroundStyle(Color.inkMuted)
                            Text("\(days)")
                                .font(.system(size: compact ? 44 : 56, weight: .ultraLight, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.ink)
                                .padding(.vertical, -6)
                            Text("天")
                                .font(.system(size: 17, weight: .light, design: .rounded))
                                .foregroundStyle(Color.inkMuted)
                        }
                    } else {
                        Text("按现在的结余，还攒不到")
                            .font(.system(size: 17, weight: .light, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                    }
                }
                // 12 个月，一格一个月：现在能撑几个月就亮几格，正在攒的那格发光
                let full = min(Int(monthsNow), targetMonths)
                MicroGrid(cells: (0..<targetMonths).map { i in
                    i < full ? .filled(i < Int(Double(full) * 0.6) ? .assetGold : .cashBlue)
                        : i == full ? .current(.cashBlue) : .empty
                }, cellSize: compact ? 15 : 20, spacing: compact ? 4 : 5)
                Text("现在能撑 \(String(format: "%.1f", monthsNow)) 个月 · 按近 90 天每天存 ¥\(FinancialFormatting.wholeNumber(data.dailySaving)) 估算")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

private struct MockFrame<Content: View>: View {
    let framed: Bool
    let padding: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if framed {
            VaultCard(padding: padding) { content }
        } else {
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 首页底部组件区

struct MockModulesArea: View {
    let mode: HomeModulesMock
    let inputs: HomeStat.Inputs
    let todayCard: AnyView

    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]

    private var data: MockMetricData { MockModules.data(inputs: inputs, expenses: expenses, incomes: incomes) }

    var body: some View {
        let data = data
        let editing = mode == .edit
        VStack(spacing: Spacing.md) {
            if editing {
                HStack {
                    Text("拖动换位置 · 点 − 移除")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    Spacer()
                    Text("完成")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.skyDeep)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
                }
            }
            HStack(spacing: Spacing.md) {
                ForEach(Array((mode == .two ? [HomeStat.month, .next] : [.daily, .month, .next]).enumerated()),
                        id: \.offset) { i, stat in
                    MockMetricCard(stat: stat, data: data, large: mode == .two)
                        .modifier(Jiggle(on: editing, seed: i))
                }
            }
            MockGoalCard(data: data)
                .modifier(Jiggle(on: editing, seed: 3))
            if mode != .two {
                todayCard
                    .modifier(Jiggle(on: editing, seed: 4))
            }
            if editing {
                // 加一个组件：虚线框
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                    Text("添加组件")
                        .font(.system(.subheadline, design: .rounded))
                }
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.inkGhost, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            } else {
                Text("长按这一块可以增减、拖动组件")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkGhost)
                    .padding(.top, Spacing.xs)
            }
        }
    }
}

/// 编辑状态：微微倾斜（截图是静止的），左上角 − 号
private struct Jiggle: ViewModifier {
    let on: Bool
    let seed: Int

    func body(content: Content) -> some View {
        if on {
            content
                .rotationEffect(.degrees(seed % 2 == 0 ? -0.8 : 0.8))
                .overlay(alignment: .topLeading) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.mist2))
                        .overlay(Circle().stroke(Color.hairline, lineWidth: 1))
                        .offset(x: -6, y: -6)
                }
        } else {
            content
        }
    }
}

enum MockModules {
    static func currentDays(_ data: MockMetricData) -> Double {
        if case .finite(let d) = data.snapshot.freedom { return d }
        return 0
    }

    /// 按近 90 天的结余速度，还要多少天才能撑 `months` 个月；攒不到时为 nil
    static func daysToGo(_ data: MockMetricData, months: Int) -> Int? {
        let missing = (Double(months) * 30.4 - currentDays(data)) * data.netBurn
        if missing <= 0 { return 0 }
        guard data.dailySaving > 0 else { return nil }
        return Int((missing / data.dailySaving).rounded(.up))
    }

    static func data(inputs: HomeStat.Inputs, expenses: [Expense], incomes: [Income]) -> MockMetricData {
        let cal = Calendar.current
        let today = cal.startOfDay(for: inputs.snapshot.now)
        var recent = Array(repeating: 0.0, count: 10)
        let start90 = cal.date(byAdding: .day, value: -90, to: today) ?? today
        var spent90 = 0.0
        for e in expenses {
            let day = cal.startOfDay(for: e.date)
            if let ago = cal.dateComponents([.day], from: day, to: today).day, ago >= 0, ago < 10, e.countsInBurn {
                recent[9 - ago] += e.amount
            }
            if e.date >= start90 { spent90 += e.amount }
        }
        let earned90 = incomes.filter { $0.date >= start90 }.reduce(0) { $0 + $1.amount }
        return MockMetricData(inputs: inputs, recentDays: recent, dailySaving: (earned90 - spent90) / 90)
    }
}

// MARK: - 整页：添加组件、桌面小组件

struct MockModulesPage: View {
    let mode: HomeModulesMock
    let inputs: HomeStat.Inputs

    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]

    var body: some View {
        let data = MockModules.data(inputs: inputs, expenses: expenses, incomes: incomes)
        if mode == .add { addPage(data) } else { widgetsPage(data) }
    }

    private func addPage(_ data: MockMetricData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                KickerLabel(text: "Add to Home")
                Text("添加组件")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, Spacing.xl)
            Text("小卡 · 一行最多三张")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 3), spacing: Spacing.md) {
                ForEach(HomeStat.allCases) { stat in
                    MockMetricCard(stat: stat, data: data)
                        .overlay(alignment: .topTrailing) {
                            let added = [.daily, .month, .next].contains(stat)
                            Image(systemName: added ? "checkmark" : "plus")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(added ? Color.mist : Color.skyDeep)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(added ? Color.skyDeep : Color.mist))
                                .overlay(Circle().stroke(Color.skyDeep, lineWidth: 1))
                                .offset(x: 5, y: -5)
                        }
                }
            }
            Text("长卡 · 占一整行")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .padding(.top, Spacing.xs)
            MockGoalCard(data: data, compact: true)
            HStack(spacing: Spacing.md) {
                wideOption("今日对比", "今天花的和日常比", added: true)
                wideOption("支出结构", "每类每月占掉几天自由 · 2.2", added: false)
            }
        }
    }

    private func wideOption(_ title: String, _ note: String, added: Bool) -> some View {
        VaultCard(padding: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.subheadline, design: .rounded)).foregroundStyle(Color.ink)
                    Text(note).font(.system(.caption2, design: .rounded)).foregroundStyle(Color.inkFaint)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(Color.skyDeep)
            }
        }
    }

    private func widgetsPage(_ data: MockMetricData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                KickerLabel(text: "Widgets")
                Text("同一套组件，搬到桌面")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, Spacing.xl)
            HStack(spacing: 22) {
                widget(width: 170) { freedomWidget(data) }
                widget(width: 170) {
                    MockMetricCard(stat: .month, data: data, large: true, framed: false)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            widget(width: 362) { MockGoalCard(data: data, compact: true, framed: false).frame(maxHeight: .infinity) }
            Text("锁屏")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
            HStack(spacing: Spacing.md) {
                lockWidget {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(FreedomMath.freedomDescription(data.snapshot.freedom))自由")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        MicroGrid(cells: (0..<10).map { $0 < 6 ? .filled(.white) : .filled(.white, opacity: 0.3) },
                                  cellSize: 8, spacing: 2.5)
                        if case .finite(let d) = data.snapshot.freedom, let date = FreedomMath.depleteDate(freedomDays: d) {
                            Text("撑到 \(FreedomMath.depleteDateText(date))").font(.system(size: 12, design: .rounded)).opacity(0.7)
                        }
                    }
                }
                lockWidget {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(MockModules.daysToGo(data, months: 12).map { "GAP 还差 \($0) 天" } ?? "GAP 还攒不到")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        MicroGrid(cells: (0..<12).map { Double($0) < MockModules.currentDays(data) / 30.4 - 1
                                    ? .filled(.white) : .filled(.white, opacity: 0.3) },
                                  cellSize: 8, spacing: 2.5)
                        Text("12 个月目标").font(.system(size: 12, design: .rounded)).opacity(0.7)
                    }
                }
            }
        }
    }

    private func freedomWidget(_ data: MockMetricData) -> some View {
        let state = FreedomMath.gridState(for: data.snapshot.freedom, lockedAssets: data.snapshot.countedAssets,
                                          netWorth: data.snapshot.freedomBase,
                                          paymentDays: data.snapshot.freedomRun.paymentDays,
                                          missedPaymentDay: data.snapshot.freedomRun.missedPaymentDay)
        // 小组件放不下几百格：一格 = 一周
        let weeks = max(1, state.count / 7)
        let goldWeeks = state.count > 0 ? weeks * state.assetCells / state.count : 0
        return VStack(alignment: .leading, spacing: 6) {
            KickerLabel(text: "Freedom Days")
            Text(FreedomMath.freedomDaysDisplay(data.snapshot.freedom))
                .font(.system(size: 52, weight: .ultraLight, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.ink)
                .padding(.vertical, -6)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(9), spacing: 2.5), count: 12), alignment: .leading, spacing: 2.5) {
                ForEach(0..<weeks, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                        .fill(i < goldWeeks ? Color.assetGold : Color.cashBlue)
                        .frame(width: 9, height: 9)
                }
            }
            Spacer(minLength: 0)
            Text("一格一周")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func widget<C: View>(width: CGFloat, @ViewBuilder content: () -> C) -> some View {
        content()
            .frame(width: width, height: 170)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.mist))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private func lockWidget<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.75)))
    }
}
#endif
