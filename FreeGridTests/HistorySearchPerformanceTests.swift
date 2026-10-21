import Foundation
import Testing
@testable import FreeGrid

@MainActor
struct HistorySearchPerformanceTests {
    static func ledger(count: Int) -> (expenses: [Expense], incomes: [Income]) {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        var expenses: [Expense] = []
        var incomes: [Income] = []
        for index in (0..<count).reversed() {
            let date = start.addingTimeInterval(Double(index) * 3_600)
            if index % 10 == 0 {
                incomes.append(Income(amount: Double(index % 200 + 1), source: "工资 Salary", note: "奖金", date: date))
            } else {
                expenses.append(Expense(amount: index % 17 == 0 ? -1234.5 : Double(index % 200 + 1),
                                        category: index % 2 == 0 ? "购物" : "交通",
                                        note: index % 3 == 0 ? "咖啡 Coffee" : "高铁票", date: date))
            }
        }
        return (expenses, incomes)
    }

    static let queries = ["咖啡", "COFFEE", "coffee 4", "1,234.5", "工资", "高铁", "不存在"]

    @Test(arguments: [100, 1000, 5000, 10000])
    func legacySearchBaseline(count: Int) {
        let (expenses, incomes) = Self.ledger(count: count)
        var emptyTimes: [Double] = []
        var inputTimes: [Double] = []
        var found = 0
        for _ in 0..<4 {
            var started = CFAbsoluteTimeGetCurrent()
            let pool = HistoryLedger.transactions(expenses: expenses, incomes: incomes, scope: .allTime)
            let notes = HistoryLedger.frequentNotes(pool)
            emptyTimes.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
            #expect(!notes.isEmpty)
            for query in Self.queries {
                started = CFAbsoluteTimeGetCurrent()
                let pool = HistoryLedger.transactions(expenses: expenses, incomes: incomes, scope: .allTime)
                let matches = HistoryLedger.search(pool, query: query)
                let groups = HistoryLedger.months(matches)
                found += HistoryLedger.summary(matches).count + groups.count
                inputTimes.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
            }
        }
        #expect(found > 0)
        print("HISTORY_PERF legacy rows=\(count) empty_ms=\(median(emptyTimes)) input_ms=\(median(inputTimes))")
    }

    @Test(arguments: [100, 1000, 5000, 10000])
    func preparedSearchBenchmark(count: Int) async throws {
        let (expenses, incomes) = Self.ledger(count: count)
        let snapshotStart = CFAbsoluteTimeGetCurrent()
        let expenseRows = expenses.map { LedgerTransaction.expense($0).searchRecord }
        let incomeRows = incomes.map { LedgerTransaction.income($0).searchRecord }
        let snapshotMS = (CFAbsoluteTimeGetCurrent() - snapshotStart) * 1000
        let queries = Self.queries
        let metrics = try await HistorySearch.background {
            let started = CFAbsoluteTimeGetCurrent()
            let prepared = try HistorySearch.Index(expenses: expenseRows, incomes: incomeRows)
            let notes = try prepared.frequentNotes()
            let prepareMS = (CFAbsoluteTimeGetCurrent() - started) * 1000
            var timings: [Double] = []
            for _ in 0..<4 {
                for query in queries {
                    let started = CFAbsoluteTimeGetCurrent()
                    let result = try prepared.search(query)
                    timings.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
                    #expect(result.query == query)
                }
            }
            #expect(!notes.isEmpty)
            return (prepareMS, timings.sorted()[timings.count / 2])
        }
        print("HISTORY_PERF prepared rows=\(count) snapshot_main_ms=\(snapshotMS) prepare_background_ms=\(metrics.0) input_background_ms=\(metrics.1)")
    }

    private func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
}
