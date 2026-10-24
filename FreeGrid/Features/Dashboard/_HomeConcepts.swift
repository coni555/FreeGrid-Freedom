// 临时：首页改造的几个方向，只在 DEBUG 里、带启动参数 `-homeConcept A|B|C|BC` 时出现。
// A 格子海报 / B 日历上的自由 / C 今天的自由账 / BC 日历 + 今天一行。用户选定后整个文件删掉。

#if DEBUG
import SwiftUI
import SwiftData

enum HomeConcept: String {
    case poster = "A", calendar = "B", today = "C", calendarToday = "BC"

    static let current: HomeConcept? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-homeConcept"), i + 1 < args.count else { return nil }
        return HomeConcept(rawValue: args[i + 1])
    }()
}

struct HomeConceptBody: View {
    let concept: HomeConcept
    let snapshot: FinancialSnapshot
    let history: [FreedomMath.HistoryPoint]
    let todaySpending: Double
    let isDark: Bool
    var onExpense: () -> Void
    var onIncome: () -> Void
    var onSimulate: () -> Void

    @Query private var todayExpenses: [Expense]

    init(concept: HomeConcept, snapshot: FinancialSnapshot, history: [FreedomMath.HistoryPoint],
         todaySpending: Double, isDark: Bool,
         onExpense: @escaping () -> Void, onIncome: @escaping () -> Void, onSimulate: @escaping () -> Void) {
        self.concept = concept
        self.snapshot = snapshot
        self.history = history
        self.todaySpending = todaySpending
        self.isDark = isDark
        self.onExpense = onExpense
        self.onIncome = onIncome
        self.onSimulate = onSimulate
        let start = Calendar.current.startOfDay(for: .now)
        _todayExpenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.countsInBurn },
                               sort: \Expense.createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            switch concept {
            case .poster: poster
            case .calendar: calendarHome(withToday: false)
            case .today: todayHome
            case .calendarToday: calendarHome(withToday: true)
            }
        }
    }

    // MARK: - 共用

    private var gridState: FreedomMath.GridState {
        let run = snapshot.freedomRun
        return FreedomMath.gridState(for: run.state, lockedAssets: snapshot.countedAssets, netWorth: snapshot.freedomBase,
                                     paymentDays: run.paymentDays, missedPaymentDay: run.missedPaymentDay)
    }
    /// 每花 1 天的钱：日常减去被动收入，和推演自由天数用的口径一致
    private var netBurn: Double { snapshot.dailyBurn - snapshot.dailyPassive }
    private func days(_ amount: Double) -> Double { netBurn > 0 ? amount / netBurn : 0 }
    private var todayDays: Double { days(todaySpending) }
    private var tailCells: Int { max(0, Int(todayDays.rounded())) }
    private func minusDays(_ d: Double) -> String { "−\(String(format: "%.1f", d)) 天" }
    private var number: String { FreedomMath.freedomDaysDisplay(snapshot.freedom) }
    private var unitLabel: String { FreedomMath.gridUnit(for: snapshot.freedom).label }
    private var depleteDate: Date? {
        if case .finite(let d) = snapshot.freedom { return FreedomMath.depleteDate(freedomDays: d) }
        return nil
    }
    /// GAP 目标还没做，日历里先放一个示意日期
    private var sampleGoal: Date? { Calendar.current.date(from: DateComponents(year: 2027, month: 6, day: 30)) }

    private var topRow: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle().stroke(Color.ink, lineWidth: 1).frame(width: 22, height: 22)
                if isDark {
                    Image(systemName: "moon.fill").font(.system(size: 10)).foregroundStyle(Color.sky)
                } else {
                    Circle().fill(Color.sky).frame(width: 9, height: 9)
                }
            }
            Text("FreeGrid")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.ink)
            Spacer()
        }
    }

    private var actions: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                VaultButton(title: "记支出", icon: "minus", style: .destructive, action: onExpense)
                VaultButton(title: "记收入", icon: "plus", style: .primary, action: onIncome)
            }
            GhostButton(title: "模拟一笔 · 看决策影响", icon: "wand.and.stars", action: onSimulate)
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(_ label: String, _ color: Color, hollow: Bool = false) -> some View {
        HStack(spacing: 6) {
            if hollow {
                RoundedRectangle(cornerRadius: 1.5).stroke(color, lineWidth: 1).frame(width: 8, height: 8)
            } else {
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 8, height: 8)
            }
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkMuted)
        }
    }

    private func ringLegend(_ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().stroke(Color.skyDeep, lineWidth: 1).frame(width: 9, height: 9)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkMuted)
        }
    }

    /// 日均、今天、被动覆盖、趋势收成一行，不再各占一张卡
    private func fineFacts(showsToday: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            fact("日均", "¥" + String(format: "%.1f", snapshot.dailyCost))
            if showsToday {
                fact("今天", todaySpending > 0 ? minusDays(todayDays) : "0 天")
            }
            if snapshot.dailyPassive > 0 {
                fact("被动覆盖", FinancialFormatting.percentage(snapshot.passiveRatio))
            }
            if let first = history.first, let last = history.last, history.count >= 3,
               let values = FreedomMath.historyPlotValues(history) {
                VStack(alignment: .leading, spacing: 3) {
                    Sparkline(values: values, lineWidth: 1).frame(width: 64, height: 18)
                    Text("\(history.count - 1) 周 · \(FreedomMath.trendSummaryText(first: first, last: last, hidesFlooredStart: snapshot.hasUncountedMoney))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.ink)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - A 格子海报：数字和格子是一张画面，没有卡片

    private var poster: some View {
        let state = gridState
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                KickerLabel(text: "Freedom Days")
                Spacer()
                if let d = depleteDate {
                    Text("撑到 \(FreedomMath.depleteDateText(d))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .padding(.top, Spacing.xxl)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(number)
                    .font(.system(size: 132, weight: .ultraLight, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(unitLabel)
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
            }
            .padding(.vertical, -10)

            emphasized("你的", "自由", " 还能撑这么多\(unitLabel)", size: 17)
                .padding(.top, Spacing.xs)

            // 一行 28 格 = 4 周
            ConceptDotGrid(count: state.count, assetCells: state.assetCells, columns: 28)
                .padding(.top, Spacing.xl)

            HStack(spacing: Spacing.lg) {
                legend("资产", .assetGold)
                legend("现金", .cashBlue)
                Spacer()
                Text("每格 1 天 · 每行 4 周")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.top, Spacing.md)

            Hairline().padding(.vertical, Spacing.lg)
            fineFacts(showsToday: true)
            actions.padding(.top, Spacing.xl)
        }
    }

    // MARK: - B 日历上的自由：一行一个月，最后一格落在撑到的那天

    private func calendarHome(withToday: Bool) -> some View {
        let state = gridState
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 0) {
                KickerLabel(text: "Freedom Days")
                HStack(alignment: .lastTextBaseline, spacing: Spacing.lg) {
                    Text(number)
                        .font(.system(size: 100, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .padding(.vertical, -10)
                    VStack(alignment: .leading, spacing: 2) {
                        emphasized("你的", "自由", "能撑到", size: 17)
                        if let d = depleteDate {
                            Text(FreedomMath.depleteDateText(d))
                                .font(.system(size: 17, weight: .regular, design: .rounded))
                                .foregroundStyle(Color.skyDeep)
                        }
                    }
                    .padding(.bottom, 14)
                }
                if withToday, todaySpending > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("今天")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                        Text(minusDays(todayDays))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.flame)
                        Text("· \(todayExpenses.count) 笔 ¥\(FinancialFormatting.wholeNumber(todaySpending))")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                    }
                    .padding(.top, Spacing.xs)
                }
            }
            .padding(.top, Spacing.xl)

            VaultCard(padding: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        KickerLabel(text: "Freedom Calendar")
                        Spacer()
                        Text("每格 = 1 天")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                    }
                    ConceptCalendar(count: state.count, assetCells: state.assetCells,
                                    paymentDays: Set(snapshot.freedomRun.paymentDays),
                                    tail: withToday ? tailCells : 0, goal: sampleGoal)
                    HStack(spacing: Spacing.md) {
                        legend("资产", .assetGold)
                        legend("现金", .cashBlue)
                        legend("还没撑到", .inkGhost, hollow: true)
                        if withToday, tailCells > 0 { legend("今天花掉", .flame, hollow: true) }
                        ringLegend("GAP（示意）")
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }

            actions
            Hairline()
            fineFacts(showsToday: !withToday)
        }
    }

    // MARK: - C 今天的自由账：每一笔都换成天数

    private var todayHome: some View {
        let state = gridState
        return VStack(spacing: Spacing.lg) {
            VaultCard(emphasis: .high, padding: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        KickerLabel(text: "Freedom Days")
                        Spacer()
                        if todaySpending > 0 {
                            Text("今天 \(minusDays(todayDays))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.flame)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .overlay(Capsule().stroke(Color.flame.opacity(0.6), lineWidth: 1))
                        }
                    }
                    HStack(alignment: .lastTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            emphasized("你的", "自由", "", size: 18)
                            Text("还能撑这么多\(unitLabel)")
                                .font(.system(size: 18, weight: .light, design: .rounded))
                                .foregroundStyle(Color.ink)
                            if let d = depleteDate {
                                Text("大约撑到 \(FreedomMath.depleteDateText(d))")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color.inkFaint)
                                    .padding(.top, 4)
                            }
                        }
                        Spacer()
                        Text(number)
                            .font(.system(size: 110, weight: .ultraLight, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .padding(.vertical, -8)
                    }
                }
            }

            VaultCard(padding: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    KickerLabel(text: "Freedom Grid")
                    ConceptDotGrid(count: state.count, assetCells: state.assetCells, columns: 32, tail: tailCells)
                    HStack(spacing: Spacing.lg) {
                        legend("资产", .assetGold)
                        legend("现金", .cashBlue)
                        if tailCells > 0 { legend("今天花掉", .flame, hollow: true) }
                        Spacer()
                    }
                }
            }

            actions

            VaultCard(padding: Spacing.lg) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        KickerLabel(text: "Today")
                        Spacer()
                        Text(todaySpending > 0 ? minusDays(todayDays) : "0 天")
                            .font(.system(size: 22, weight: .thin, design: .rounded).monospacedDigit())
                            .foregroundStyle(todaySpending > 0 ? Color.flame : Color.ink)
                    }
                    .padding(.bottom, Spacing.sm)
                    ForEach(todayExpenses.reversed()) { expense in
                        Hairline(color: .hairlineSoft)
                        HStack(spacing: Spacing.md) {
                            Image(systemName: ExpenseCategoryIcons.defaultIcon(for: expense.category))
                                .font(.system(size: 14, weight: .light))
                                .foregroundStyle(Color.inkMuted)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(expense.note.isEmpty ? expense.category : expense.note)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.ink)
                                if !expense.note.isEmpty {
                                    Text(expense.category)
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(Color.inkFaint)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("¥\(FinancialFormatting.wholeNumber(expense.amount))")
                                    .font(.system(.subheadline, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Color.ink)
                                Text(minusDays(days(expense.amount)))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Color.flame)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    Hairline(color: .hairlineSoft)
                    Text(todaySummary)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.top, Spacing.md)
                }
            }
        }
        .padding(.top, Spacing.lg)
    }

    private var todaySummary: String {
        guard snapshot.dailyBurn > 0 else { return "" }
        let diff = todaySpending - snapshot.dailyBurn
        if todaySpending == 0 { return "今天还没花钱，自由一天没少" }
        return diff > 0
            ? "比日常多花 ¥\(String(format: "%.1f", diff))，多用了 \(String(format: "%.1f", days(diff))) 天"
            : "比日常少花 ¥\(String(format: "%.1f", -diff))，省下 \(String(format: "%.1f", days(-diff))) 天"
    }
}

// MARK: - 格子（Canvas 画，最后一格发光；tail 是今天花掉的空心格）

struct ConceptDotGrid: View {
    let count: Int
    let assetCells: Int
    var columns: Int
    var gapRatio: CGFloat = 0.28
    var tail: Int = 0

    @Environment(\.colorScheme) private var scheme

    private var rows: Int { max(1, Int(ceil(Double(count + tail) / Double(columns)))) }

    var body: some View {
        let c = CGFloat(columns), r = CGFloat(rows), k = gapRatio
        Canvas { ctx, size in
            let cell = size.width / (c + (c - 1) * k)
            let gap = cell * k
            func rect(_ i: Int) -> CGRect {
                CGRect(x: CGFloat(i % columns) * (cell + gap), y: CGFloat(i / columns) * (cell + gap),
                       width: cell, height: cell)
            }
            for i in 0..<max(0, count - 1) {
                ctx.fill(Path(roundedRect: rect(i), cornerRadius: cell * 0.18),
                         with: .color(i < assetCells ? .assetGold : .cashBlue))
            }
            for i in count..<(count + tail) {
                ctx.stroke(Path(roundedRect: rect(i).insetBy(dx: 0.5, dy: 0.5), cornerRadius: cell * 0.18),
                           with: .color(.flame.opacity(0.75)), lineWidth: 1)
            }
            if count > 0 {
                ConceptFrontier.draw(in: &ctx, rect: rect(count - 1), isCash: count - 1 >= assetCells,
                                     dark: scheme == .dark)
            }
        }
        .aspectRatio((c + (c - 1) * k) / (r + (r - 1) * k), contentMode: .fit)
    }
}

/// 最后一格：和 LifeGrid 同样的亮色和光晕，静态
enum ConceptFrontier {
    static func draw(in ctx: inout GraphicsContext, rect: CGRect, isCash: Bool, dark: Bool) {
        let color: Color = dark
            ? (isCash ? Color(red: 0.83, green: 0.92, blue: 1.00) : Color(red: 1.00, green: 0.92, blue: 0.65))
            : (isCash ? Color(red: 0.20, green: 0.50, blue: 0.78) : Color(red: 0.72, green: 0.58, blue: 0.20))
        let glow: Color = isCash ? .cashBlue : .assetGold
        let big = rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: glow.opacity(dark ? 0.6 : 0.45), radius: rect.width * 0.9))
            layer.fill(Path(roundedRect: big, cornerRadius: big.width * 0.18), with: .color(color))
        }
    }
}

// MARK: - 日历：一行一个月，从这个月排到撑到的那个月

struct ConceptCalendar: View {
    let count: Int
    let assetCells: Int
    var paymentDays: Set<Int> = []
    var tail: Int = 0
    var goal: Date? = nil
    var maxMonths = 14

    @Environment(\.colorScheme) private var scheme
    private let cal = Calendar.current
    private let slots = 31
    private let k: CGFloat = 0.3

    private struct Month: Identifiable {
        let id: Int
        let first: Date
        let days: Int
        let label: String
    }

    private var months: [Month] {
        let today = cal.startOfDay(for: .now)
        guard let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: today)),
              let end = cal.date(byAdding: .day, value: max(count + tail, 1) - 1, to: today) else { return [] }
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US_POSIX")
        var result: [Month] = []
        var cursor = thisMonth
        var i = 0
        while cursor <= end, i < maxMonths {
            let days = cal.range(of: .day, in: .month, for: cursor)?.count ?? 30
            let month = cal.component(.month, from: cursor)
            en.dateFormat = (month == 1 || i == 0) ? "MMM ’yy" : "MMM"
            result.append(Month(id: i, first: cursor, days: days, label: en.string(from: cursor).uppercased()))
            cursor = cal.date(byAdding: .month, value: 1, to: cursor) ?? end.addingTimeInterval(1)
            i += 1
        }
        return result
    }

    var body: some View {
        let today = cal.startOfDay(for: .now)
        let goalOffset = goal.flatMap { cal.dateComponents([.day], from: today, to: cal.startOfDay(for: $0)).day }
        VStack(alignment: .leading, spacing: 4) {
            ForEach(months) { month in
                let base = cal.dateComponents([.day], from: today, to: month.first).day ?? 0
                HStack(spacing: 6) {
                    Text(month.label)
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Color.inkFaint)
                        .frame(width: 44, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Canvas { ctx, size in
                        let cell = size.width / (CGFloat(slots) + CGFloat(slots - 1) * k)
                        let gap = cell * k
                        for d in 0..<month.days {
                            let offset = base + d
                            let r = CGRect(x: CGFloat(d) * (cell + gap), y: (size.height - cell) / 2, width: cell, height: cell)
                            let shape = Path(roundedRect: r, cornerRadius: cell * 0.2)
                            if offset < 0 {
                                // 已经过去的日子：一个小点
                                ctx.fill(Path(ellipseIn: r.insetBy(dx: cell * 0.36, dy: cell * 0.36)),
                                         with: .color(.inkGhost))
                            } else if offset == count - 1 {
                                ConceptFrontier.draw(in: &ctx, rect: r, isCash: offset >= assetCells,
                                                     dark: scheme == .dark)
                            } else if offset < count {
                                if paymentDays.contains(offset + 1) {
                                    var p = shape
                                    let hole = cell * 0.34
                                    p.addEllipse(in: CGRect(x: r.midX - hole / 2, y: r.midY - hole / 2, width: hole, height: hole))
                                    ctx.fill(p, with: .color(offset < assetCells ? .assetGold : .cashBlue),
                                             style: FillStyle(eoFill: true))
                                } else {
                                    ctx.fill(shape, with: .color(offset < assetCells ? .assetGold : .cashBlue))
                                }
                            } else if offset < count + tail {
                                ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cell * 0.2),
                                           with: .color(.flame.opacity(0.8)), lineWidth: 1)
                            } else {
                                ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cell * 0.2),
                                           with: .color(.hairline), lineWidth: 1)
                            }
                            if let goalOffset, offset == goalOffset {
                                let ring = r.insetBy(dx: -cell * 0.3, dy: -cell * 0.3)
                                ctx.stroke(Path(ellipseIn: ring), with: .color(.skyDeep), lineWidth: 1.2)
                            }
                        }
                    }
                    .frame(height: 12)
                }
            }
        }
    }
}
#endif
