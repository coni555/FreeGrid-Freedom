// 趋势由当前净值与账目反推；没有历史资产/被动收入快照，因此是估算。
import Foundation

extension FreedomMath {
    struct HistoryPoint {
        let date: Date
        let state: FreedomState
        /// 往回推出的钱小于 0，天数是被压到 0 的，不是真正算出来的
        var isFloored = false

        var description: String {
            switch state {
            case .finite(let days):
                return GridUnit.day.amount(FinancialFormatting.clampedInteger(days.rounded(.down), range: 0...Int.max))
            case .covered: return String(localized: "已覆盖")
            case .insufficientData: return String(localized: "数据不足")
            case .invalidData: return String(localized: "无法估算")
            }
        }
    }

    /// 先生成周点的次日零点，再把每笔交易放入对应区间。
    /// 日期只用自然日边界比较，不对每个周点重新扫描账本或转换所有交易日期。
    /// 有贷款时每个周点都按那天的扣款计划推演：那天之后才扣的月供在那天还没还。
    /// 不算日均的支出（月供）照样参与往回推现金，只是不进日均消费。
    /// 记在不计入自由天数的现金账户（`uncountedAccounts`）里的收支没动过自由天数里的钱，不参与往回推，支出照样进日均。
    static func freedomDaysHistory(
        expenses: [Expense],
        incomes: [Income],
        currentNetWorth: Double,
        firstRecordDate: Date?,
        dailyPassive: Double = 0,
        loans: [Loan] = [],
        uncountedAccounts: Set<UUID> = [],
        /// 每月日常估算：断档那几天按它补，和首页的日均同一个口径
        monthlyEstimate: Double? = nil,
        weeks: Int = 12,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [HistoryPoint] {
        guard let firstRecordDate, weeks > 0,
              currentNetWorth.isFinite, dailyPassive.isFinite, dailyPassive >= 0 else { return [] }
        let firstDay = calendar.startOfDay(for: firstRecordDate)
        let today = calendar.startOfDay(for: now)
        let elapsedDays = trackDays(firstRecordDate: firstDay, now: today, calendar: calendar) - 1
        guard elapsedDays >= 14 else { return [] }
        let availableWeeks = min(weeks, elapsedDays / 7)
        let dates = (0...availableWeeks).reversed().compactMap {
            calendar.date(byAdding: .day, value: -7 * $0, to: today)
        }
        let boundaries = dates.compactMap { calendar.date(byAdding: .day, value: 1, to: $0) }
        guard boundaries.count == dates.count else { return [] }

        // 最后一个桶保留今天之后的记录，兼容本地时钟曾经调快的账本。
        func bucket(for date: Date) -> Int {
            var low = 0
            var high = boundaries.count
            while low < high {
                let middle = (low + high) / 2
                if date < boundaries[middle] { high = middle }
                else { low = middle + 1 }
            }
            return low
        }
        // cashOut 是全部扣过现金的支出（含房租、月供），用来往回推现金；日均只看 burnEntries
        var cashOutSums = Array(repeating: 0.0, count: dates.count + 1)
        var incomeSums = Array(repeating: 0.0, count: dates.count + 1)
        func movedFreedomMoney(_ account: UUID?) -> Bool {
            account.map { !uncountedAccounts.contains($0) } ?? true
        }
        for expense in expenses {
            let amount = expense.amount
            guard amount.isFinite else { return [] }
            if movedFreedomMoney(expense.cashAccountID) { cashOutSums[bucket(for: expense.date)] += amount }
        }
        let burnEntries = burnEntries(expenses)
        for income in incomes {
            let amount = income.amount
            guard amount.isFinite else { return [] }
            if movedFreedomMoney(income.cashAccountID) { incomeSums[bucket(for: income.date)] += amount }
        }

        // 独立求后缀，避免用巨大总额减去巨大前缀时丢失小额后续交易。
        var expensesAfter = Array(repeating: 0.0, count: dates.count)
        var incomesAfter = Array(repeating: 0.0, count: dates.count)
        var laterExpenses = cashOutSums.last ?? 0
        var laterIncomes = incomeSums.last ?? 0
        for index in dates.indices.reversed() {
            expensesAfter[index] = laterExpenses
            incomesAfter[index] = laterIncomes
            laterExpenses += cashOutSums[index]
            laterIncomes += incomeSums[index]
        }

        let payments = loans.isEmpty ? [] : expenses.filter { $0.loanID != nil }
        return dates.indices.map { index in
            // 终点用全部记录（含时钟调快时记下的未来日期），和 FinancialSnapshot 一分不差
            let isCurrent = index == dates.count - 1
            let entries = isCurrent ? burnEntries : burnEntries.filter { $0.date < boundaries[index] }
            let netWorth = isCurrent ? currentNetWorth
                : currentNetWorth + expensesAfter[index] - incomesAfter[index]
            let burn = burnEstimate(entries, monthlyEstimate: monthlyEstimate, now: dates[index], calendar: calendar).dailyBurn
            let plan = loans.isEmpty ? LoanSchedule.Plan() : LoanSchedule.plan(
                loans: loans,
                payments: payments.filter { $0.date < boundaries[index] },
                now: dates[index], calendar: calendar)
            return HistoryPoint(date: dates[index], state: freedomRun(
                netWorth: netWorth, dailyBurn: burn, dailyPassive: dailyPassive,
                hasExpenses: !entries.isEmpty, loans: plan
            ).state, isFloored: netWorth < 0)
        }
    }

    /// 趋势摘要行的右侧文字。`hidesFlooredStart` 为真且起点是被压到 0 的值时，
    /// 不显示「0 天 →」这一段，只显示现在的天数。
    static func trendSummaryText(first: HistoryPoint, last: HistoryPoint, hidesFlooredStart: Bool) -> String {
        if hidesFlooredStart, first.isFloored { return last.description }
        return "\(first.description) → \(last.description)"
    }

    /// 只有有限天数之间才能相减；覆盖与无数据不能伪装成某个天数。
    static func deltaSummary(history: [HistoryPoint]) -> (start: Int, end: Int, delta: Int)? {
        guard history.count >= 2,
              case .finite(let first) = history.first?.state,
              case .finite(let last) = history.last?.state,
              first >= 0, last >= 0,
              let start = FinancialFormatting.integer(first.rounded(.down)),
              let end = FinancialFormatting.integer(last.rounded(.down)) else { return nil }
        return (start, end, end - start)
    }

    /// 不把覆盖态或缺失数据连成数值折线，避免造成下降或零天的错觉。
    static func historyPlotValues(_ history: [HistoryPoint]) -> [Double]? {
        let values = history.compactMap { point -> Double? in
            guard case .finite(let days) = point.state, days.isFinite, days >= 0 else { return nil }
            return days
        }
        return !values.isEmpty && values.count == history.count ? values : nil
    }
}
