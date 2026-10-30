// 首页底部的卡片：几张小卡、今日对比长条和自己的目标长条，放哪些、什么顺序由用户定（免费；目标本身是 Pro）。首页上按住拖动排序，
// 点卡片或「编辑卡片」打开面板加、移除、恢复默认。这里决定有哪些卡、没改过时放哪些、怎么排成行，以及每张显示什么。

import Foundation

enum HomeStat: Hashable, Identifiable {
    // 顺序就是选卡时的顺序：先「花了多少」，再「坚持了多久」，再「有多少钱」，再是要留意的，最后是长条
    case daily, month, today, track, base, passive, next
    /// 今日对比长条：和小卡一样能拖、能移除，但总是占一整行
    case todayBar
    /// 自己的一个目标（Pro）：每个目标一张长条，用目标的 id 认；没改过时不在首页上，没有 Pro 时不显示、也不能加
    case goal(UUID)

    /// 固定的这几张，按选卡时的顺序
    static let builtIn: [HomeStat] = [.daily, .month, .today, .track, .base, .passive, .next, .todayBar]

    /// 存在偏好里的名字；目标是「goal-」加 id
    var rawValue: String {
        switch self {
        case .daily: return "daily"
        case .month: return "month"
        case .today: return "today"
        case .track: return "track"
        case .base: return "base"
        case .passive: return "passive"
        case .next: return "next"
        case .todayBar: return "todayBar"
        case .goal(let id): return "goal-" + id.uuidString
        }
    }

    init?(rawValue: String) {
        if let stat = Self.builtIn.first(where: { $0.rawValue == rawValue }) {
            self = stat
        } else if rawValue.hasPrefix("goal-"), let id = UUID(uuidString: String(rawValue.dropFirst(5))) {
            self = .goal(id)
        } else {
            return nil
        }
    }

    /// 占一整行的长条
    var isWide: Bool {
        switch self {
        case .todayBar, .goal: return true
        default: return false
        }
    }

    var id: String { rawValue }

    /// 卡上等宽大写的小标签
    var kicker: String {
        switch self {
        case .daily: return "Daily"
        case .month: return "Month"
        case .today: return "Today"
        case .track: return "Track"
        case .base: return "Funds"
        case .passive: return "Passive"
        case .next: return "Next"
        case .todayBar: return "Today"
        case .goal: return "Goal"
        }
    }

    /// 选卡时的名字；目标用它自己的名字，见 `title(in:)`
    var title: String {
        switch self {
        case .daily: return String(localized: "日均消费")
        case .month: return String(localized: "本月花销")
        case .today: return String(localized: "今日花销")
        case .track: return String(localized: "记账天数")
        case .base: return String(localized: "可动用资产")
        case .passive: return String(localized: "被动收入覆盖率")
        case .next: return String(localized: "下次固定支出")
        case .todayBar: return String(localized: "今日对比长条")
        case .goal: return String(localized: "我的目标")
        }
    }

    func title(in inputs: Inputs) -> String {
        guard let goal = inputs.goal(for: self) else { return title }
        return String(localized: "目标 · \(goal.goal.displayName)")
    }

    // MARK: - 放哪几张

    static let slotsKey = "homeStatSlots"
    /// 用户把卡都移除了时存这个，和「没改过」的空串分开
    private static let noneValue = "none"

    /// 没改过（空串）时和 2.0 一样：日均、被动覆盖、记账天数，下面是今日对比长条；没有被动收入的人 2.0 里那张是藏起来的，这里补成本月花销。
    /// 改过的按存的顺序，认不出的（比如已经拿掉的「本月结余率」）和重复的跳过
    static func slots(stored: String, hasPassive: Bool) -> [HomeStat] {
        if stored.isEmpty { return [.daily, hasPassive ? .passive : .month, .track, .todayBar] }
        if stored == noneValue { return [] }
        var result: [HomeStat] = []
        for raw in stored.split(separator: ",") {
            if let stat = HomeStat(rawValue: String(raw)), !result.contains(stat) { result.append(stat) }
        }
        return result
    }

    static func encode(_ slots: [HomeStat]) -> String {
        slots.isEmpty ? noneValue : slots.map(\.rawValue).joined(separator: ",")
    }

    /// 排成行：长条单独占一行；长条之间连着的几张小卡按 `rowSizes` 分行
    static func rows(_ items: [HomeStat]) -> [[HomeStat]] {
        rowRanges(wide: items.map(\.isWide)).map { Array(items[$0]) }
    }

    /// `rows` 的下标版，首页的排版直接用它：`wide[i]` 是第 i 张是不是长条
    static func rowRanges(wide: [Bool]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var runStart = 0
        func flush(upTo end: Int) {
            var start = runStart
            for size in rowSizes(count: end - runStart) {
                ranges.append(start..<(start + size))
                start += size
            }
        }
        for (index, isWide) in wide.enumerated() where isWide {
            flush(upTo: index)
            ranges.append(index..<(index + 1))
            runStart = index + 1
        }
        flush(upTo: wide.count)
        return ranges
    }

    /// 一行最多三张；不整除时前面的行多一张，4 张排成两行两张，不留单独一张
    static func rowSizes(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let rows = (count + 2) / 3
        return (0..<rows).map { $0 < count % rows ? count / rows + 1 : count / rows }
    }

    // MARK: - 显示什么

    struct Display: Equatable {
        let value: String
        let unit: String
    }

    func display(_ inputs: Inputs) -> Display {
        let snapshot = inputs.snapshot
        switch self {
        case .daily:
            // 日均含固定支出折成的每天；有固定支出时小字拆开写，和只比日常的今日对得上
            return Display(value: snapshot.dailyCost.isFinite ? String(format: "%.1f", snapshot.dailyCost) : "—",
                           unit: Self.dailyNote(snapshot))
        case .month:
            return Display(value: FinancialFormatting.wholeNumber(inputs.monthSpent),
                           unit: Self.monthComparison(spent: inputs.monthSpent, lastMonth: inputs.lastMonthSameSpan))
        case .today:
            return Display(value: FinancialFormatting.wholeNumber(inputs.todaySpending),
                           unit: Self.todayComparison(today: inputs.todaySpending, dailyBurn: snapshot.dailyBurn,
                                                      routine: snapshot.dailyFixed > 0))
        case .track:
            // 不满 90 天时大额支出还在摊，日均会变；告诉用户再记多久就稳了（用户 2026-10-24 定的说法）。
            // 不记账、只填了每月花销的人不催他记账
            let days = snapshot.trackDays
            return Display(value: "\(days)",
                           unit: snapshot.hasRecords && days < FreedomMath.lumpSpreadDays
                               ? String(localized: "再记录 \(FreedomMath.lumpSpreadDays - days) 天，日均趋势会更清晰")
                               : String(localized: "天记账"))
        case .base:
            return Display(value: FinancialFormatting.wholeNumber(snapshot.freedomBase),
                           unit: Self.baseSplit(assets: snapshot.countedAssets, cash: snapshot.countedCash))
        case .passive:
            return Display(value: FinancialFormatting.percentage(snapshot.passiveRatio),
                           unit: snapshot.dailyPassive > 0 ? String(localized: "被动收入覆盖") : String(localized: "还没有被动收入"))
        case .next:
            guard let next = inputs.nextFixed else { return Display(value: "—", unit: String(localized: "没有固定支出")) }
            return Display(value: "\(next.daysAway)",
                           unit: String(localized: "天后 · \(next.name) \(FinancialFormatting.yuan(next.amount, precision: 0))"))
        case .todayBar:
            // 首页上长条自己画；这里是编辑面板里那一行
            return Display(value: FinancialFormatting.wholeNumber(inputs.todaySpending), unit: String(localized: "占一整行 · 今天和日常比"))
        case .goal:
            // 首页上长条自己画；这里是编辑面板里那一行：现在的自由天数，还差多少
            guard let result = inputs.goal(for: self) else { return Display(value: "—", unit: "") }
            return Display(value: result.freedomDaysText ?? (result.enough == true ? "∞" : "—"),
                           unit: result.targetLine ?? result.freedomLine)
        }
    }

    /// 日均卡的小字。按估算、断档时先说清楚日均是怎么来的，其次才是日常 / 固定拆开
    static func dailyNote(_ snapshot: FinancialSnapshot) -> String {
        let fixed = snapshot.dailyFixed > 0 && snapshot.dailyBurn.isFinite
        if snapshot.burnBasis == .estimate { return String(localized: "按每月估算") }
        if snapshot.burnGapDays > 0 {
            let quiet = snapshot.burnGapDays + FreedomMath.burnGraceDays
            return snapshot.burnBasis == .recordsAndEstimate
                ? String(localized: "\(quiet) 天没记 · 空档按估算")
                : String(localized: "\(quiet) 天没记 · 日均先停住")
        }
        // 刚开始记账，还在从每月花销往记录过渡
        if snapshot.burnBasis == .recordsAndEstimate { return String(localized: "按估算和记账") }
        return fixed
            ? String(localized: "日常 \(FinancialFormatting.wholeNumber(snapshot.dailyBurn)) · 固定 \(FinancialFormatting.wholeNumber(snapshot.dailyFixed))")
            : String(localized: "元/天")
    }

    /// 本月到今天花的和上个月同一段（1 号到同一天）比。上个月这段没有记录时只写「本月已花」
    static func monthComparison(spent: Double, lastMonth: Double?) -> String {
        guard let lastMonth, lastMonth > 0 else { return String(localized: "元 · 本月已花") }
        let change = (spent - lastMonth) / lastMonth
        if abs(change) < 0.01 { return String(localized: "和上月同期差不多") }
        let pct = FinancialFormatting.percentage(abs(change), maximum: 999)
        return change > 0 ? String(localized: "比上月同期多 \(pct)") : String(localized: "比上月同期少 \(pct)")
    }

    /// 今天的日常支出和日常日均比；房租这类自动扣的不算。有固定支出时叫「日常」，和含固定的日均分开。
    /// 每种说法写成整句，英文语序不同，不拼词
    static func todayComparison(today: Double, dailyBurn: Double, routine: Bool) -> String {
        if today < 0 { return String(localized: "今天净退款") }
        if today == 0 { return String(localized: "今天还没花") }
        guard dailyBurn.isFinite, dailyBurn > 0 else { return String(localized: "元 · 今天") }
        if abs(today - dailyBurn) < 0.05 {
            return routine ? String(localized: "和日常差不多") : String(localized: "和日均差不多")
        }
        let pct = FinancialFormatting.percentage(abs(today - dailyBurn) / dailyBurn, maximum: 9_999)
        switch (today > dailyBurn, routine) {
        case (true, true): return String(localized: "比日常高 \(pct)")
        case (true, false): return String(localized: "比日均高 \(pct)")
        case (false, true): return String(localized: "比日常低 \(pct)")
        case (false, false): return String(localized: "比日均低 \(pct)")
        }
    }

    /// 计入自由天数的钱里资产和现金各占多少，两个百分比加起来正好 100%
    static func baseSplit(assets: Double, cash: Double) -> String {
        let total = assets + cash
        guard total > 0, assets.isFinite, cash.isFinite else { return String(localized: "元 · 可动用资产") }
        if assets <= 0 { return String(localized: "全是现金") }
        if cash <= 0 { return String(localized: "全是资产") }
        let assetPct = FinancialFormatting.clampedInteger(assets / total * 100, range: 1...99,
                                                          rounded: .toNearestOrAwayFromZero)
        return String(localized: "资产 \(assetPct)% · 现金 \(100 - assetPct)%")
    }

    // MARK: - 算这些指标要的数

    struct NextFixed: Equatable {
        let name: String
        let amount: Double
        let daysAway: Int
    }

    /// 除了 `FinancialSnapshot` 以外，几个指标要的数。账本变了才重算，和首页其他数字一起
    struct Inputs {
        let snapshot: FinancialSnapshot
        /// 本月 1 号到现在的全部支出，自动扣的房租、月供也算
        let monthSpent: Double
        /// 上个月 1 号到同一天的支出；上个月整月一笔都没有时为 nil
        let lastMonthSameSpan: Double?
        /// 今天的日常支出（自动扣的不算），和首页今日对比同一个数
        let todaySpending: Double
        /// 最近一笔还没付的固定支出或月供
        let nextFixed: NextFixed?
        /// 自己的目标和首页自由天数比的结果；没有 Pro 时是空的（首页上不显示目标卡）。首页另外算好填进来
        var goals: [FreedomGoalProgress] = []

        func goal(for stat: HomeStat) -> FreedomGoalProgress? {
            guard case .goal(let id) = stat else { return nil }
            return goals.first { $0.goal.id == id }
        }

        /// 现在能放到首页的目标卡
        var goalStats: [HomeStat] { goals.map { .goal($0.goal.id) } }

        init(snapshot: FinancialSnapshot, monthSpent: Double, lastMonthSameSpan: Double?,
             todaySpending: Double, nextFixed: NextFixed?) {
            self.snapshot = snapshot
            self.monthSpent = monthSpent
            self.lastMonthSameSpan = lastMonthSameSpan
            self.todaySpending = todaySpending
            self.nextFixed = nextFixed
        }

        /// `loans` 传起作用的那些（`ProFeatures.loansInEffect`）：贷款停用时不显示它的下次还款
        init(snapshot: FinancialSnapshot, expenses: [Expense], loans: [Loan], calendar: Calendar = .current) {
            let now = snapshot.now
            let today = calendar.startOfDay(for: now)
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? today
            let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
            // 上个月的同一天（上个月没有这一天时到月底），包含那一整天
            let dayOfMonth = calendar.component(.day, from: now)
            let lastMonthDays = calendar.range(of: .day, in: .month, for: lastMonthStart)?.count ?? 28
            let lastSpanEnd = calendar.date(byAdding: .day, value: min(dayOfMonth, lastMonthDays), to: lastMonthStart)
                ?? monthStart
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now

            var monthSpent = 0.0, lastSpan = 0.0, lastMonthAny = false, todaySpending = 0.0
            for expense in expenses {
                let date = expense.date
                if date >= monthStart, date < tomorrow {
                    monthSpent += expense.amount
                    if date >= today, expense.countsInBurn { todaySpending += expense.amount }
                } else if date >= lastMonthStart, date < monthStart {
                    lastMonthAny = true
                    if date < lastSpanEnd { lastSpan += expense.amount }
                }
            }

            let payments = expenses.filter { $0.loanID != nil }
            let next = loans.compactMap { loan -> (Loan, Date)? in
                guard loan.monthlyAmount.isFinite, loan.monthlyAmount > 0,
                      let due = LoanSchedule.status(of: loan, payments: payments, now: now, calendar: calendar).nextDue
                else { return nil }
                return (loan, due)
            }
            .min { $0.1 < $1.1 }

            self.init(snapshot: snapshot, monthSpent: monthSpent,
                      lastMonthSameSpan: lastMonthAny ? lastSpan : nil,
                      todaySpending: todaySpending,
                      nextFixed: next.map { loan, due in
                          NextFixed(name: loan.name, amount: loan.monthlyAmount,
                                    daysAway: calendar.dateComponents([.day], from: today,
                                                                      to: calendar.startOfDay(for: due)).day ?? 0)
                      })
        }
    }
}
