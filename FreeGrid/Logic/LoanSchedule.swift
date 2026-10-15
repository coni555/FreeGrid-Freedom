// 每月还款的到期日、已还几期、哪期没扣成，以及按日历往后推的扣款计划。
// 只做计算，不改任何记录；到期自动扣款在 `LoanStore`。

import Foundation

enum LoanSchedule {
    /// 一笔贷款最多填 600 期（50 年）
    static let maxPeriods = FinancialLimits.loanPeriods

    /// 某年某月的到期日（零点）。当月没有这一天时取月底，例如 31 号在 11 月是 30 号。
    static func dueDate(year: Int, month: Int, dueDay: Int, calendar: Calendar = .current) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: first) else { return nil }
        let day = min(max(1, dueDay), days.count)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
            .map { calendar.startOfDay(for: $0) }
    }

    /// `after` 那天之后（不含当天）的前 `count` 个到期日，从早到晚。
    static func dueDates(after: Date, dueDay: Int, count: Int, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        let start = calendar.startOfDay(for: after)
        let parts = calendar.dateComponents([.year, .month], from: start)
        guard var year = parts.year, var month = parts.month else { return [] }
        var result: [Date] = []
        // 第一个月的到期日可能已经过了，最多多看一个月
        for _ in 0...count where result.count < count {
            if let date = dueDate(year: year, month: month, dueDay: dueDay, calendar: calendar), date > start {
                result.append(date)
            }
            month += 1
            if month > 12 { month = 1; year += 1 }
        }
        return result
    }

    /// `date` 离某个到期日不超过 `days` 天。记支出时用它提醒「月供会自动扣，不用再记」。
    static func isNearDueDate(_ date: Date, dueDay: Int, within days: Int = 3,
                              calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard let monthBefore = calendar.date(byAdding: .month, value: -1, to: day) else { return false }
        return dueDates(after: calendar.date(byAdding: .day, value: -1, to: monthBefore) ?? monthBefore,
                        dueDay: dueDay, count: 3, calendar: calendar)
            .contains { abs(calendar.dateComponents([.day], from: day, to: $0).day ?? .max) <= days }
    }

    // MARK: - 一笔贷款现在的状态

    struct Status: Equatable {
        /// 到期日已过（含今天）但还没还上的
        let overdue: [Date]
        /// 其中自动扣款已经试过、因为现金不够没扣成的。界面上请用户处理的就是这几期
        let pending: [Date]
        /// 今天之后还要还的到期日
        let upcoming: [Date]

        /// 还剩几期（含到期了还没还上的）
        var remaining: Int { overdue.count + upcoming.count }
        var isPaidOff: Bool { remaining == 0 }
        var nextDue: Date? { upcoming.first }
        var lastDue: Date? { upcoming.last ?? overdue.last }
    }

    /// 已还的 = 指向这笔贷款的扣款记录 + 用户说「从别处还的」到期日，只算 `startDate` 之后的。
    /// 先按日期对上到期日；日期被改过、对不上的，按顺序抵掉最早没还的那几期。
    static func status(of loan: Loan, payments: [Expense], now: Date = .now,
                       calendar: Calendar = .current) -> Status {
        let start = calendar.startOfDay(for: loan.startDate)
        let today = calendar.startOfDay(for: now)
        let schedule = dueDates(after: start, dueDay: loan.dueDay,
                                count: min(max(0, loan.periodsAtStart), maxPeriods), calendar: calendar)
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

    // MARK: - 推演用的扣款计划

    struct Event: Equatable {
        /// 第几天扣，明天是 1
        let day: Int
        let amount: Double
    }

    struct Plan: Equatable {
        /// 已经到期还没还上的，推演时当作今天就要付
        var dueNow: Double = 0
        /// 今天之后的扣款，同一天的合在一起，按天从早到晚
        var events: [Event] = []

        var isEmpty: Bool { dueNow == 0 && events.isEmpty }
    }

    /// 所有贷款合在一起的扣款计划。`payments` 传全部支出即可，这里只看指向贷款的那些。
    static func plan(loans: [Loan], payments: [Expense], now: Date = .now,
                     calendar: Calendar = .current) -> Plan {
        guard !loans.isEmpty else { return Plan() }
        let linked = payments.filter { $0.loanID != nil }
        let today = calendar.startOfDay(for: now)
        var plan = Plan()
        var byDay: [Int: Double] = [:]
        for loan in loans where loan.monthlyAmount.isFinite && loan.monthlyAmount > 0 {
            let status = status(of: loan, payments: linked, now: now, calendar: calendar)
            plan.dueNow += Double(status.overdue.count) * loan.monthlyAmount
            for date in status.upcoming {
                guard let day = calendar.dateComponents([.day], from: today, to: date).day, day > 0 else { continue }
                byDay[day, default: 0] += loan.monthlyAmount
            }
        }
        plan.events = byDay.keys.sorted().map { Event(day: $0, amount: byDay[$0] ?? 0) }
        return plan
    }
}

extension FreedomMath {
    struct FreedomRun: Equatable {
        let state: FreedomState
        /// 推演里真的扣了月供的那几天（明天是 1）。首页格子在这几格打孔
        let paymentDays: [Int]
        /// 钱撑不到的下一次还款是第几天；nil 表示后面没有付不起的月供。首页在最后一格后面补一个淡色的孔
        var missedPaymentDay: Int? = nil
    }

    /// 有贷款时的自由天数：从明天起按日历往后推，每天扣「日均消费 − 日均被动收入」，
    /// 到还款日再扣月供，推到钱不够为止。没有贷款时和 `freedomState` 完全一样。
    ///
    /// - 某个还款日付不起月供：停在前一天（整数天）。
    /// - 钱在两个还款日之间花完：停在花完的那一刻（可以带小数）。
    /// - 每天净消耗 ≤ 0、所有月供都付得起：已覆盖（∞）。
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

        var lived = 0
        var paid: [Int] = []
        for event in loans.events {
            let cost = net * Double(event.day - lived)
            if net > 0, cash - cost < 0 {
                return FreedomRun(state: .finite(days: Double(lived) + max(0, cash) / net), paymentDays: paid,
                                  missedPaymentDay: event.day)
            }
            cash -= cost
            guard cash >= event.amount else {
                return FreedomRun(state: .finite(days: Double(event.day - 1)), paymentDays: paid,
                                  missedPaymentDay: event.day)
            }
            cash -= event.amount
            paid.append(event.day)
            lived = event.day
        }
        guard net > 0 else { return FreedomRun(state: .covered, paymentDays: paid) }
        let days = Double(lived) + max(0, cash) / net
        guard days.isFinite else { return FreedomRun(state: .invalidData, paymentDays: []) }
        return FreedomRun(state: .finite(days: days), paymentDays: paid)
    }
}
