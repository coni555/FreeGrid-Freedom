// 固定支出和贷款的到期日、已付几期、哪期没扣成，以及按日历往后推的扣款计划。
// 只做计算，不改任何记录；到期自动扣款在 `LoanStore`。

import Foundation

extension Loan {
    /// 首页格子上打不打孔：只有贷款打，房租这类生活成本不打
    var punchesGrid: Bool { !isOngoing }

    /// 折成每月多少：每 3 个月 7,500 就是每月 2,500
    var monthlyEquivalent: Double { monthlyAmount / Double(max(1, intervalMonths)) }
}

extension PassiveSource {
    /// 不按月到账时写「每年 ¥6,000」，列表里放在名字旁边；每月到账时为 nil
    var intervalNote: String? {
        guard intervalMonths > 1 else { return nil }
        return "\(LoanSchedule.intervalLabel(intervalMonths)) ¥\(FinancialFormatting.wholeNumber(monthlyAmount * Double(intervalMonths)))"
    }
}

enum LoanSchedule {
    /// 一笔贷款最多填 600 期（50 年）
    static let maxPeriods = FinancialLimits.loanPeriods
    /// 固定支出和被动收入可选的周期（月）
    static let intervals = [1, 2, 3, 6, 12]

    static func intervalLabel(_ months: Int) -> String {
        switch months {
        case 1: return "每月"
        case 3: return "每季度"
        case 6: return "每半年"
        case 12: return "每年"
        default: return "每 \(months) 个月"
        }
    }
    /// 固定支出没有最后一期；界面上的状态（下次哪天、哪期没扣）只往后看这么多天，够看到一年一次的下一期
    static let statusHorizonDays = 400
    /// 推演最多往后推 100 年，和格子年档的上限（99 年）对应
    static let maxRunDays = 36_525

    /// 某年某月的到期日（零点）。当月没有这一天时取月底，例如 31 号在 11 月是 30 号。
    static func dueDate(year: Int, month: Int, dueDay: Int, calendar: Calendar = .current) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: first) else { return nil }
        let day = min(max(1, dueDay), days.count)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
            .map { calendar.startOfDay(for: $0) }
    }

    /// `after` 那天之后（不含当天）的到期日，从早到晚：第一个是之后最近的那个，然后每隔 `intervalMonths` 个月一次。
    /// 到 `count` 个，或者过了 `limit`，就停。
    static func dueDates(after: Date, dueDay: Int, intervalMonths: Int = 1, count: Int,
                         through limit: Date? = nil, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        let start = calendar.startOfDay(for: after)
        let parts = calendar.dateComponents([.year, .month], from: start)
        guard var year = parts.year, var month = parts.month else { return [] }
        func advance(_ months: Int) {
            month += months
            while month > 12 { month -= 12; year += 1 }
        }
        // 第一个月的到期日可能已经过了，就看下个月
        if let date = dueDate(year: year, month: month, dueDay: dueDay, calendar: calendar), date <= start {
            advance(1)
        }
        let step = max(1, intervalMonths)
        var result: [Date] = []
        while result.count < count, let date = dueDate(year: year, month: month, dueDay: dueDay, calendar: calendar) {
            if let limit, date > limit { break }
            result.append(date)
            advance(step)
        }
        return result
    }

    /// 这笔钱从 `startDate` 之后的到期日。贷款就是那几期；固定支出没有尽头，到 `limit` 为止。
    static func schedule(of loan: Loan, through limit: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: loan.startDate)
        if loan.isOngoing {
            return dueDates(after: start, dueDay: loan.dueDay, intervalMonths: loan.intervalMonths,
                            count: .max, through: limit, calendar: calendar)
        }
        return dueDates(after: start, dueDay: loan.dueDay, intervalMonths: loan.intervalMonths,
                        count: min(max(0, loan.periodsAtStart), maxPeriods), calendar: calendar)
    }

    // MARK: - 一笔现在的状态

    struct Status: Equatable {
        /// 到期日已过（含今天）但还没付上的
        let overdue: [Date]
        /// 其中自动扣款已经试过、因为现金不够没扣成的。界面上请用户处理的就是这几期
        let pending: [Date]
        /// 今天之后还要付的到期日。固定支出只列到 `statusHorizonDays` 天以内
        let upcoming: [Date]

        /// 还剩几期（含到期了还没付上的）。只对贷款有意义
        var remaining: Int { overdue.count + upcoming.count }
        var isPaidOff: Bool { remaining == 0 }
        var nextDue: Date? { upcoming.first }
        var lastDue: Date? { upcoming.last ?? overdue.last }
    }

    /// 已付的 = 指向这笔的扣款记录 + 用户说「从别处付的」到期日，只算 `startDate` 之后的。
    /// 先按日期对上到期日；日期被改过、对不上的，按顺序抵掉最早没付的那几期。
    /// `horizonDays`：固定支出往后列多少天的到期日。
    static func status(of loan: Loan, payments: [Expense], now: Date = .now,
                       horizonDays: Int = statusHorizonDays, calendar: Calendar = .current) -> Status {
        let start = calendar.startOfDay(for: loan.startDate)
        let today = calendar.startOfDay(for: now)
        let limit = calendar.date(byAdding: .day, value: horizonDays, to: max(today, start)) ?? today
        let schedule = schedule(of: loan, through: limit, calendar: calendar)
        let paidDays = payments.compactMap { payment -> Date? in
            guard payment.loanID == loan.id else { return nil }
            let day = calendar.startOfDay(for: payment.date)
            return day > start ? day : nil
        } + loan.settledDates.map { calendar.startOfDay(for: $0) }.filter { $0 > start }
        let covered = Set(paidDays)
        var unpaid = schedule.filter { !covered.contains($0) }
        let unmatched = paidDays.count - (schedule.count - unpaid.count)
        unpaid.removeFirst(min(max(0, unmatched), unpaid.count))

        let processed = calendar.startOfDay(for: loan.processedThrough ?? start)
        let overdue = unpaid.filter { $0 <= today }
        return Status(overdue: overdue,
                      pending: overdue.filter { $0 <= processed },
                      upcoming: unpaid.filter { $0 > today })
    }

    /// 每月一共要付多少：固定支出折成每月，贷款只算还没还清的
    static func monthlyTotal(loans: [Loan], payments: [Expense], now: Date = .now,
                             calendar: Calendar = .current) -> Double {
        guard !loans.isEmpty else { return 0 }
        let linked = payments.filter { $0.loanID != nil }
        return loans.reduce(0) { total, loan in
            guard loan.monthlyAmount.isFinite, loan.monthlyAmount > 0 else { return total }
            if loan.isOngoing { return total + loan.monthlyEquivalent }
            let status = status(of: loan, payments: linked, now: now, calendar: calendar)
            return status.isPaidOff ? total : total + loan.monthlyEquivalent
        }
    }

    // MARK: - 推演用的扣款计划

    struct Event: Equatable {
        /// 第几天扣，明天是 1
        let day: Int
        let amount: Double
        /// 这天有贷款要还：首页格子在这一格打孔。只有房租这类固定支出的日子不打
        var punched = true
    }

    /// 一笔固定支出在 `events` 之后的部分：没有尽头，推演需要多远就往后展开多远
    struct Recurring: Equatable {
        let amount: Double
        let dueDay: Int
        let intervalMonths: Int
        /// `events` 里没列的第一个到期日，从它（含）开始每隔 `intervalMonths` 个月一次
        let first: Date
    }

    struct Plan: Equatable {
        /// 已经到期还没付上的，推演时当作今天就要付
        var dueNow: Double = 0
        /// 今天之后的扣款，同一天的合在一起，按天从早到晚。固定支出只列到 `statusHorizonDays` 天以内
        var events: [Event] = []
        /// 固定支出在 `events` 之后的部分
        var recurring: [Recurring] = []
        /// 算第几天用的今天
        var today: Date = .distantPast
        var calendar: Calendar = .current

        var isEmpty: Bool { dueNow == 0 && events.isEmpty && recurring.isEmpty }

        /// 固定支出折成每天多少：长期看，每天除了日常开销还要再花这么多
        var recurringDaily: Double {
            recurring.reduce(0) { $0 + $1.amount / (Double($1.intervalMonths) * FreedomMath.GridUnit.month.daysPerCell) }
        }

        /// 第 `day` 天及以前的全部扣款：`events` 加上固定支出往后展开的，同一天的合在一起
        func events(through day: Int) -> [Event] {
            guard !recurring.isEmpty else { return events.filter { $0.day <= day } }
            var byDay: [Int: (amount: Double, punched: Bool)] = [:]
            for event in events where event.day <= day {
                byDay[event.day] = (event.amount, event.punched)
            }
            if let limit = calendar.date(byAdding: .day, value: day, to: today) {
                for item in recurring {
                    let after = calendar.date(byAdding: .day, value: -1, to: item.first) ?? item.first
                    for date in LoanSchedule.dueDates(after: after, dueDay: item.dueDay,
                                                      intervalMonths: item.intervalMonths, count: .max,
                                                      through: limit, calendar: calendar) {
                        guard let offset = calendar.dateComponents([.day], from: today, to: date).day,
                              offset > 0 else { continue }
                        let current = byDay[offset]
                        byDay[offset] = ((current?.amount ?? 0) + item.amount, current?.punched ?? false)
                    }
                }
            }
            return byDay.keys.sorted().map { Event(day: $0, amount: byDay[$0]!.amount, punched: byDay[$0]!.punched) }
        }
    }

    /// 所有固定支出和贷款合在一起的扣款计划。`payments` 传全部支出即可，这里只看指向它们的那些。
    static func plan(loans: [Loan], payments: [Expense], now: Date = .now,
                     calendar: Calendar = .current) -> Plan {
        guard !loans.isEmpty else { return Plan() }
        let linked = payments.filter { $0.loanID != nil }
        let today = calendar.startOfDay(for: now)
        var plan = Plan(today: today, calendar: calendar)
        var byDay: [Int: (amount: Double, punched: Bool)] = [:]
        for loan in loans where loan.monthlyAmount.isFinite && loan.monthlyAmount > 0 {
            let status = status(of: loan, payments: linked, now: now, calendar: calendar)
            plan.dueNow += Double(status.overdue.count) * loan.monthlyAmount
            for date in status.upcoming {
                guard let day = calendar.dateComponents([.day], from: today, to: date).day, day > 0 else { continue }
                let current = byDay[day]
                byDay[day] = ((current?.amount ?? 0) + loan.monthlyAmount, (current?.punched ?? false) || loan.punchesGrid)
            }
            // 接着 `status` 列到的最后一期往后：按周期跳，不是下个月
            if loan.isOngoing {
                let start = calendar.startOfDay(for: loan.startDate)
                let listedThrough = calendar.date(byAdding: .day, value: statusHorizonDays, to: max(today, start)) ?? today
                let interval = max(1, loan.intervalMonths)
                if let last = schedule(of: loan, through: listedThrough, calendar: calendar).last,
                   let month = calendar.date(byAdding: .month, value: interval, to: last) {
                    let parts = calendar.dateComponents([.year, .month], from: month)
                    if let year = parts.year, let number = parts.month,
                       let first = dueDate(year: year, month: number, dueDay: loan.dueDay, calendar: calendar) {
                        plan.recurring.append(Recurring(amount: loan.monthlyAmount, dueDay: loan.dueDay,
                                                        intervalMonths: interval, first: first))
                    }
                }
            }
        }
        plan.events = byDay.keys.sorted().map { Event(day: $0, amount: byDay[$0]!.amount, punched: byDay[$0]!.punched) }
        return plan
    }
}

extension FreedomMath {
    struct FreedomRun: Equatable {
        let state: FreedomState
        /// 推演里真的还了贷款的那几天（明天是 1）。首页格子在这几格打孔；只扣了房租的日子不算
        let paymentDays: [Int]
        /// 钱撑不到的下一次还贷是第几天；nil 表示后面没有付不起的贷款。首页在最后一格后面补一个淡色的孔
        var missedPaymentDay: Int? = nil
    }

    /// 有固定支出或贷款时的自由天数：从明天起按日历往后推，每天扣「日均消费 − 日均被动收入」，
    /// 到期日再扣那笔钱，推到钱不够为止。没有时和 `freedomState` 完全一样。
    ///
    /// - 某个到期日付不起：停在前一天（整数天）。房租交不上，自由就到头了。
    /// - 钱在两个到期日之间花完：停在花完的那一刻（可以带小数）。
    /// - 每天净消耗 ≤ 0、所有扣款都付得起：已覆盖（∞）。有固定支出时，长期每天的净消耗要把它们也算上；
    ///   算上以后仍 ≤ 0，推过贷款最后一期再两年都付得起就是已覆盖；> 0 就一直推，100 年后还有钱也算已覆盖。
    static func freedomRun(netWorth: Double, dailyBurn: Double, dailyPassive: Double = 0,
                           hasExpenses: Bool, loans: LoanSchedule.Plan) -> FreedomRun {
        let plain = freedomState(netWorth: netWorth, dailyBurn: dailyBurn,
                                 dailyPassive: dailyPassive, hasExpenses: hasExpenses)
        switch plain {
        case .insufficientData, .invalidData:
            return FreedomRun(state: plain, paymentDays: [])
        case .finite, .covered:
            guard !loans.isEmpty else { return FreedomRun(state: plain, paymentDays: []) }
        }

        let net = dailyBurn - dailyPassive
        var cash = netWorth
        guard cash >= loans.dueNow else {
            return FreedomRun(state: .finite(days: 0), paymentDays: [], missedPaymentDay: 0)
        }
        cash -= loans.dueNow

        // 固定支出没有尽头，只展开到这次推演用得到的地方
        let lastListed = loans.events.last?.day ?? 0
        let horizon: Int
        if loans.recurring.isEmpty {
            horizon = lastListed
        } else if net > 0 {
            // 扣款只会让钱花得更快，钱光靠日常开销撑不过这么多天
            horizon = min(LoanSchedule.maxRunDays, Int((cash / net).rounded(.up)) + 1)
        } else if net + loans.recurringDaily <= 0 {
            horizon = lastListed + 2 * 366
        } else {
            horizon = LoanSchedule.maxRunDays
        }
        let events = loans.events(through: horizon)

        var lived = 0
        var paid: [Int] = []
        for (index, event) in events.enumerated() {
            let cost = net * Double(event.day - lived)
            if net > 0, cash - cost < 0 {
                return FreedomRun(state: .finite(days: Double(lived) + max(0, cash) / net), paymentDays: paid,
                                  missedPaymentDay: events[index...].first(where: \.punched)?.day)
            }
            cash -= cost
            guard cash >= event.amount else {
                return FreedomRun(state: .finite(days: Double(event.day - 1)), paymentDays: paid,
                                  missedPaymentDay: events[index...].first(where: \.punched)?.day)
            }
            cash -= event.amount
            if event.punched { paid.append(event.day) }
            lived = event.day
        }
        guard net > 0 else { return FreedomRun(state: .covered, paymentDays: paid) }
        let days = Double(lived) + max(0, cash) / net
        guard days.isFinite else { return FreedomRun(state: .invalidData, paymentDays: []) }
        return FreedomRun(state: .finite(days: days), paymentDays: paid)
    }
}
