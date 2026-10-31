import Foundation
import Testing
@testable import FreeGrid

@MainActor
struct FreedomHistoryTests {
    @Test func noonBaselineMatchesCurrentSnapshotAndIncludesTodaysIncome() throws {
        let now = TestSupport.day("2026-10-05").addingTimeInterval(18 * 3600)
        let first = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: now))!.addingTimeInterval(12 * 3600)
        // 今天也记了一笔：只有 30 天前一笔的话，最后 16 天算断档；中间再记一天，记录才够算大数字（见 MonthlySpendingTests）
        let middle = Calendar.current.date(byAdding: .day, value: 15, to: first)!
        let expenses = [Expense(amount: 1000, category: "午餐", date: first), Expense(amount: 1000, category: "午餐", date: middle),
                        Expense(amount: 1100, category: "午餐", date: now)]
        let income = Income(amount: 1000, source: "工资", date: now)
        let assets = UserAssets(); assets.cash = 10000
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: assets, now: now)
        let history = FreedomMath.freedomDaysHistory(expenses: expenses, incomes: [income], currentNetWorth: assets.cash, firstRecordDate: first, now: now)
        #expect(snapshot.trackDays == 31)
        #expect(snapshot.freedom == .finite(days: 100))
        #expect(history.last?.state == snapshot.freedom)
        #expect(history.last?.description == "100 天")
    }

    @Test func moneyInAnUncountedAccountDoesNotBendTheTrend() {
        let now = TestSupport.day("2026-10-05").addingTimeInterval(18 * 3600)
        let first = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: now))!.addingTimeInterval(12 * 3600)
        let savings = UUID()
        let expenses = [Expense(amount: 3100, category: "午餐", date: first)]
        let income = Income(amount: 5000, source: "工资", date: Calendar.current.date(byAdding: .day, value: -2, to: now)!)
        income.cashAccountID = savings
        // 工资进了不计入自由天数的账户：自由天数里的钱从来没变过，往回推时不该扣掉它
        let skipped = FreedomMath.freedomDaysHistory(expenses: expenses, incomes: [income], currentNetWorth: 10_000,
                                                     firstRecordDate: first, uncountedAccounts: [savings], now: now)
        let without = FreedomMath.freedomDaysHistory(expenses: expenses, incomes: [], currentNetWorth: 10_000,
                                                     firstRecordDate: first, now: now)
        #expect(skipped.count == 5)
        #expect(skipped.map(\.state) == without.map(\.state))
    }

    @Test func coveredStateNeverBecomes1825OrANegativeDelta() {
        let now = TestSupport.day("2026-10-05")
        let first = Calendar.current.date(byAdding: .day, value: -28, to: now)!
        let expenses = [Expense(amount: 4100, category: "购物", date: first), Expense(amount: 100, category: "购物", date: now)]
        let history = FreedomMath.freedomDaysHistory(expenses: expenses, incomes: [], currentNetWorth: 10_000_000, firstRecordDate: first, dailyPassive: 150, now: now)
        #expect(history.count == 5)
        #expect(history.last?.state == .covered)
        #expect(history.last?.description == "已覆盖")
        #expect(FreedomMath.deltaSummary(history: history) == nil)
        #expect(FreedomMath.historyPlotValues(history) == nil)
    }

    @Test func coverageLossAndInvalidRefundTotalsKeepTheirStates() {
        let now = TestSupport.day("2026-10-05")
        let first = Calendar.current.date(byAdding: .day, value: -28, to: now)!
        let expenses = [Expense(amount: 30, category: "午餐", date: first), Expense(amount: 6000, category: "购物", date: now)]
        let history = FreedomMath.freedomDaysHistory(expenses: expenses, incomes: [], currentNetWorth: 1000, firstRecordDate: first, dailyPassive: 100, now: now)
        #expect(history.first?.state == .covered)
        #expect(history.last?.state == .finite(days: 1000 / (6030.0 / 29 - 100)))
        #expect(FreedomMath.deltaSummary(history: history) == nil)
        #expect(FreedomMath.historyPlotValues(history) == nil)
        let refunded = FreedomMath.freedomDaysHistory(expenses: [Expense(amount: -30, category: "其他", date: first)], incomes: [], currentNetWorth: 1000, firstRecordDate: first, now: now)
        #expect(refunded.allSatisfy { $0.state == .invalidData })
        #expect(FreedomMath.historyPlotValues(refunded) == nil)
    }

    @Test func finiteEndpointsDoNotHideAnIntermediateCoverageState() {
        let history: [FreedomMath.HistoryPoint] = [
            .init(date: .distantPast, state: .finite(days: 100)),
            .init(date: .now, state: .covered),
            .init(date: .distantFuture, state: .finite(days: 110))
        ]
        #expect(FreedomMath.deltaSummary(history: history)?.delta == 10)
        #expect(FreedomMath.historyPlotValues(history) == nil)
        #expect(FreedomMath.historyPlotValues([history[0], history[2]]) == [100, 110])
    }

    @Test(arguments: ["2026-03-10", "2026-11-03"])
    func daylightSavingBoundariesUseCalendarDays(nowText: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let now = try #require(formatter.date(from: nowText))
        let first = calendar.date(byAdding: .day, value: -28, to: now)!.addingTimeInterval(12 * 3600)
        let expenses = [Expense(amount: 2800, category: "购物", date: first), Expense(amount: 100, category: "购物", date: now)]
        let history = FreedomMath.freedomDaysHistory(expenses: expenses, incomes: [], currentNetWorth: 10000, firstRecordDate: first, now: now, calendar: calendar)
        #expect(history.count == 5)
        #expect(history.last?.state == .finite(days: 100))
        // 往回推现金时今天那 100 加回去
        #expect(history.first?.state == .finite(days: 10100.0 / 2800))
    }

    @Test func weeklyAggregationMatchesAReferenceWithRefundsAndIntradayTransactions() {
        let now = TestSupport.day("2026-10-05").addingTimeInterval(20 * 3600)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -90, to: today)!.addingTimeInterval(12 * 3600)
        let expenses = (0..<1000).map { i in
            Expense(amount: i.isMultiple(of: 11) ? -5 : 30, category: "午餐",
                    date: calendar.date(byAdding: .day, value: -(i % 91), to: today)!.addingTimeInterval(12 * 3600))
        }
        let incomes = (0..<40).map { i in
            Income(amount: 100, source: "工资", date: calendar.date(byAdding: .day, value: -(i * 2), to: today)!.addingTimeInterval(18 * 3600))
        }
        let history = FreedomMath.freedomDaysHistory(expenses: expenses, incomes: incomes, currentNetWorth: 10000, firstRecordDate: first, dailyPassive: 10, now: now)
        #expect(history.count == 13)
        for point in history {
            let cutoff = calendar.date(byAdding: .day, value: 1, to: point.date)!
            let spent = expenses.filter { $0.date < cutoff }.reduce(0) { $0 + $1.amount }
            let laterSpent = expenses.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.amount }
            let laterIncome = incomes.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.amount }
            let burn = spent / Double(FreedomMath.trackDays(firstRecordDate: first, now: point.date))
            let expected = FreedomMath.freedomState(netWorth: 10000 + laterSpent - laterIncome, dailyBurn: burn, dailyPassive: 10, hasExpenses: true)
            #expect(point.state == expected)
        }
    }

    @Test func emptyShortInvalidAndNegativeWeekRequestsReturnNoHistory() {
        let now = TestSupport.day("2026-10-05")
        #expect(FreedomMath.freedomDaysHistory(expenses: [], incomes: [], currentNetWorth: 0, firstRecordDate: nil, now: now).isEmpty)
        let expense = Expense(amount: 30, category: "午餐", date: now)
        #expect(FreedomMath.freedomDaysHistory(expenses: [expense], incomes: [], currentNetWorth: 1000, firstRecordDate: now, now: now).isEmpty)
        let first = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        #expect(FreedomMath.freedomDaysHistory(expenses: [], incomes: [], currentNetWorth: 1000, firstRecordDate: first, weeks: -1, now: now).isEmpty)
        expense.amount = .infinity
        #expect(FreedomMath.freedomDaysHistory(expenses: [expense], incomes: [], currentNetWorth: 1000, firstRecordDate: first, now: now).isEmpty)
    }
}
