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
                return "\(FinancialFormatting.wholeNumber(days.rounded(.down))) 天"
            case .covered: return "已覆盖"
            case .insufficientData: return "数据不足"
            case .invalidData: return "无法估算"
            }
        }
    }

    /// 先生成周点的次日零点，再把每笔交易放入对应区间。
    /// 日期只用自然日边界比较，不对每个周点重新扫描账本或转换所有交易日期。
    /// 有贷款时每个周点都按那天的扣款计划推演：那天之后才扣的月供在那天还没还。
    /// 不算日均的支出（月供）照样参与往回推现金，只是不进日均消费。
    static func freedomDaysHistory(
        expenses: [Expense],
        incomes: [Income],
        currentNetWorth: Double,
        firstRecordDate: Date?,
        dailyPassive: Double = 0,
        loans: [Loan] = [],
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
        // burn 是算日均的支出，cashOut 是全部扣过现金的支出（含月供）
        var burnSums = Array(repeating: 0.0, count: dates.count + 1)
        var expenseCounts = Array(repeating: 0, count: dates.count + 1)
        var cashOutSums = Array(repeating: 0.0, count: dates.count + 1)
        var incomeSums = Array(repeating: 0.0, count: dates.count + 1)
        var totalExpenses = 0.0
        var hasBurnExpenses = false
        for expense in expenses {
            let amount = expense.amount
            guard amount.isFinite else { return [] }
            let index = bucket(for: expense.date)
            cashOutSums[index] += amount
            guard expense.countsInBurn else { continue }
            burnSums[index] += amount
            expenseCounts[index] += 1
            totalExpenses += amount
            hasBurnExpenses = true
        }
        for income in incomes {
            let amount = income.amount
            guard amount.isFinite else { return [] }
            incomeSums[bucket(for: income.date)] += amount
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
        var spent = 0.0
        var count = 0
        return dates.indices.map { index in
            spent += burnSums[index]
            count += expenseCounts[index]
            // 终点与 FinancialSnapshot 使用同一累计顺序，避免浮点累加顺序造成差异。
            let isCurrent = index == dates.count - 1
            let expenseTotal = isCurrent ? totalExpenses : spent
            let netWorth = isCurrent ? currentNetWorth
                : currentNetWorth + expensesAfter[index] - incomesAfter[index]
            let burn = dailyBurn(totalExpenses: expenseTotal,
                                 trackDays: trackDays(firstRecordDate: firstDay, now: dates[index], calendar: calendar))
            let plan = loans.isEmpty ? LoanSchedule.Plan() : LoanSchedule.plan(
                loans: loans,
                payments: payments.filter { $0.date < boundaries[index] },
                now: dates[index], calendar: calendar)
            return HistoryPoint(date: dates[index], state: freedomRun(
                netWorth: netWorth, dailyBurn: burn, dailyPassive: dailyPassive,
                hasExpenses: isCurrent ? hasBurnExpenses : count > 0, loans: plan
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
