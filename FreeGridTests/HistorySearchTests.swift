import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct HistorySearchTests {
    nonisolated private static func isOffMainThread() -> Bool { !Thread.isMainThread }

    private func index(_ expenses: [Expense], _ incomes: [Income] = [], previous: HistorySearch.Index? = nil) throws -> HistorySearch.Index {
        try HistorySearch.Index(
            expenses: expenses.sorted { $0.date > $1.date }.map { LedgerTransaction.expense($0).searchRecord },
            incomes: incomes.sorted { $0.date > $1.date }.map { LedgerTransaction.income($0).searchRecord }, previous: previous)
    }

    private func load(_ state: HistorySearchState, expenses: [Expense], incomes: [Income] = []) {
        let expenses = expenses.sorted { $0.date > $1.date }.map(LedgerTransaction.expense)
        let incomes = incomes.sorted { $0.date > $1.date }.map(LedgerTransaction.income)
        state.replaceData(expenses: expenses.map(\.searchRecord), incomes: incomes.map(\.searchRecord),
                          records: Dictionary(uniqueKeysWithValues: (expenses + incomes).map { ($0.searchRecord.key, $0) }))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<3000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("搜索状态未在预期时间内更新")
    }

    @Test func automaticFocusIsConsumedOncePerSearchSession() {
        let state = HistorySearchState()
        #expect(!state.takeInitialFocus())
        state.begin(filter: .all)
        #expect(state.takeInitialFocus())
        #expect(!state.takeInitialFocus())
        state.setText("Coffee")
        state.setFilter(.income)
        #expect(!state.takeInitialFocus())
        state.end()
        #expect(!state.takeInitialFocus())
        state.begin(filter: .income)
        #expect(state.takeInitialFocus())
    }

    @Test func rowLabelsMatchExistingFormattingAndRefreshWithLocaleOrDate() throws {
        let expense = Expense(amount: -1234.5, category: "购物", note: "退款", date: TestSupport.day("2026-10-09"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let us = Locale(identifier: "en_US")
        let first = try HistorySearch.Index(expenses: [LedgerTransaction.expense(expense).searchRecord], incomes: [], locale: us, calendar: calendar)
        let row = first.entries[0].row
        #expect(row.amount == FinancialFormatting.signedYuan(1234.5, locale: us))
        #expect(row.day == calendar.component(.day, from: expense.date))
        #expect(try first.search("退款").months[0].rows == [row])
        expense.date = TestSupport.day("2026-09-01")
        let german = Locale(identifier: "de_DE")
        let next = try HistorySearch.Index(expenses: [LedgerTransaction.expense(expense).searchRecord], incomes: [], previous: first, locale: german, calendar: calendar)
        #expect(next.preparedCount == 1)
        #expect(next.entries[0].row.amount == FinancialFormatting.signedYuan(1234.5, locale: german))
        #expect(next.entries[0].row.day == calendar.component(.day, from: expense.date))
        #expect(next.entries[0].row != row)
    }

    @Test func modelObservationRefreshesEditsAndIgnoresReplacedObjects() async throws {
        let a = Expense(amount: 20, category: "购物", note: "Coffee", date: TestSupport.day("2026-10-01"))
        let b = Expense(amount: 10, category: "交通", note: "Coffee", date: TestSupport.day("2026-09-01"))
        let income = Income(amount: 100, source: "Salary")
        let state = HistorySearchState(debounce: .zero)
        let observer = HistorySearchModelObserver()
        observer.update(search: state, expenses: [a, b], incomes: [income])
        state.begin(filter: .all)
        state.setText("Coffee", immediately: true)
        try await waitUntil { state.result?.summary.count == 2 }
        let revision = state.indexRevision
        a.note = "Tea"
        a.amount = -25
        b.date = TestSupport.day("2026-11-01")
        income.source = "Bonus"
        try await waitUntil { state.indexRevision > revision && state.result?.summary.count == 1 }
        #expect(state.result?.months.first?.month == HistoryMonth(year: 2026, month: 11))
        state.setText("Tea", immediately: true)
        try await waitUntil { state.result?.query == "Tea" }
        #expect(state.result?.summary.expense == -25)
        state.setText("Bonus", immediately: true)
        try await waitUntil { state.result?.query == "Bonus" }
        #expect(state.result?.summary.income == 100)
        // 字段通知已经排队时替换导入，新集合必须胜出。
        a.note = "失效对象"
        let replacement = Expense(amount: 50, category: "购物", note: "新账本")
        replacement.id = a.id
        observer.update(search: state, expenses: [replacement], incomes: [])
        state.setText("新账本", immediately: true)
        try await waitUntil { state.result?.query == "新账本" && state.result?.summary.count == 1 }
        #expect(state.result?.summary.expense == 50)
        a.note = "旧对象再次修改"
        for _ in 0..<3 { await Task.yield() }
        #expect(state.result?.summary.expense == 50)
        #expect(state.transaction(for: .init(id: a.id, isIncome: false))?.searchRecord == LedgerTransaction.expense(replacement).searchRecord)
    }

    @Test func queuedFieldNotificationDoesNotReadASavedDeletedModel() async throws {
        let context = try TestSupport.makeContext()
        let expense = Expense(amount: 20, category: "购物", note: "Coffee")
        context.insert(expense)
        try context.save()
        let state = HistorySearchState(debounce: .zero)
        let observer = HistorySearchModelObserver()
        observer.update(search: state, expenses: [expense], incomes: [])
        state.begin(filter: .all)
        state.setText("Coffee", immediately: true)
        try await waitUntil { state.result?.summary.count == 1 }
        let id = expense.id
        expense.note = "Coffee 修改"
        context.delete(expense)
        try context.save()
        try await waitUntil { state.result?.summary.count == 0 }
        #expect(state.transaction(for: .init(id: id, isIncome: false)) == nil)
    }

    @Test func indexOrdersDateEditsBeforeTheQueryHasReorderedItsModels() throws {
        let older = Expense(amount: 10, category: "购物", note: "Coffee", date: TestSupport.day("2026-09-01"))
        let newer = Expense(amount: 20, category: "购物", note: "Coffee", date: TestSupport.day("2026-10-01"))
        let prepared = try HistorySearch.Index(expenses: [older, newer].map { LedgerTransaction.expense($0).searchRecord }, incomes: [])
        #expect(try prepared.search("Coffee").months.flatMap(\.keys).map(\.id) == [newer.id, older.id])
    }

    @Test func resultsMatchLegacyForEveryFilterAndQuery() throws {
        let (expenses, incomes) = HistorySearchPerformanceTests.ledger(count: 1000)
        let prepared = try index(expenses, incomes)
        let transactions = HistoryLedger.transactions(expenses: expenses, incomes: incomes, scope: .allTime)
        for filter: HistorySearch.Filter in [.all, .income, .fixed, .category("购物"), .category("交通"), .category("不存在")] {
            let pool = HistoryLedger.filter(transactions, by: filter)
            #expect(try prepared.frequentNotes(filter: filter) == HistoryLedger.frequentNotes(pool))
            for query in HistorySearchPerformanceTests.queries + ["购物", "交通", "coffee 4", "   ", "  咖啡  COFFEE  "] {
                let expected = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : HistoryLedger.search(pool, query: query)
                let actual = try prepared.search(query, filter: filter)
                #expect(actual.months.flatMap(\.keys).map(\.id) == expected.map(\.id))
                #expect(actual.summary == HistoryLedger.summary(expected))
                let groups = HistoryLedger.months(expected)
                #expect(actual.months.map(\.month) == groups.map(\.month))
                #expect(actual.months.map(\.summary) == groups.map(\.summary))
            }
        }
    }

    @Test func mergeKeepsSameDateExpenseBeforeIncomeAndCrossYearMonths() throws {
        let day = TestSupport.day("2026-01-01")
        let a = Expense(amount: -1234.5, category: "购物", note: "咖啡 Coffee", date: day)
        let b = Expense(amount: 0, category: "交通", note: "咖啡 Coffee", date: TestSupport.day("2025-12-31"))
        let income = Income(amount: 1234.5, source: "Coffee", date: day)
        let prepared = try index([a, b], [income])
        let found = try prepared.search("coffee")
        #expect(found.months.flatMap(\.keys).map(\.id) == [a.id, income.id, b.id])
        #expect(found.summary.expense == -1234.5)
        #expect(found.summary.income == 1234.5)
        #expect(try prepared.search("1,234.5").summary.count == 2)
        #expect(try prepared.search("1234.5").summary.count == 2)
        #expect(try prepared.search("0").months.flatMap(\.keys).map(\.id) == [b.id])
    }

    @Test func preparingAgainReusesUnchangedRowsAndUpdatesAllSearchableFields() throws {
        let a = Expense(amount: 12, category: "交通", note: "旧备注")
        let b = Income(amount: 100, source: "旧来源")
        let first = try index([a], [b])
        #expect(first.preparedCount == 2)
        #expect(try index([a], [b], previous: first).preparedCount == 0)
        a.note = "新备注"
        a.category = "购物"
        a.amount = -99
        a.date = TestSupport.day("2024-01-01")
        b.source = "新来源"
        let next = try index([a], [b], previous: first)
        #expect(next.preparedCount == 2)
        #expect(try next.search("旧备注").summary.count == 0)
        #expect(try next.search("新备注 99", filter: .category("购物")).summary.expense == -99)
        #expect(try next.search("新来源").summary.count == 1)
        #expect(try next.search("新备注").months.first?.month == HistoryMonth(year: 2024, month: 1))
        let removed = try index([], [b], previous: next)
        #expect(removed.preparedCount == 0)
        #expect(try removed.search("新备注").summary.count == 0)
    }

    @Test func displaySnapshotKeepsLoanAndBurnFlagsWithoutHoldingAModel() {
        let expense = Expense(amount: 50, category: "房贷", note: "自动扣款")
        expense.loanID = UUID()
        expense.countsInBurn = false
        let loan = LedgerTransaction.expense(expense).searchRecord
        #expect(loan.isLoanPayment && !loan.isExcludedFromBurn && loan.cashChange == -50)
        expense.loanID = nil
        let manual = LedgerTransaction.expense(expense).searchRecord
        #expect(!manual.isLoanPayment && manual.isExcludedFromBurn)
        #expect(loan.isLoanPayment)
    }

    @Test func localeChangeInvalidatesFormattedAmounts() throws {
        let expense = Expense(amount: 1234.5, category: "购物")
        let record = LedgerTransaction.expense(expense).searchRecord
        let us = try HistorySearch.Index(expenses: [record], incomes: [], locale: Locale(identifier: "en_US"))
        let de = try HistorySearch.Index(expenses: [record], incomes: [], previous: us, locale: Locale(identifier: "de_DE"))
        #expect(de.preparedCount == 1)
        #expect(try de.search("1.234,5").summary.count == 1)
    }

    @Test func clearingAndCancellingInvalidatePendingRequestsImmediately() async throws {
        let state = HistorySearchState(debounce: .milliseconds(180))
        load(state, expenses: [Expense(amount: 20, category: "午餐", note: "Coffee")])
        try await waitUntil { state.indexRevision == 1 }
        state.begin(filter: .all)
        state.setText("Coffee", immediately: true)
        try await waitUntil { state.result?.summary.count == 1 }
        state.setText("Co")
        state.setText("")
        #expect(state.result == nil && state.months.isEmpty && state.isEmpty)
        state.setText("Coffee")
        state.end()
        try await Task.sleep(for: .milliseconds(220))
        #expect(state.text.isEmpty && state.result == nil && state.months.isEmpty)
        state.begin(filter: .all)
        #expect(state.result == nil)
    }

    actor Queries {
        var queries: [String] = []
        var old: CheckedContinuation<Void, Never>?
        func run(_ query: String) async {
            queries.append(query)
            if query == "old" { await withCheckedContinuation { old = $0 } }
        }
        func release() { old?.resume(); old = nil }
        func values() -> [String] { queries }
    }

    @Test func latestRequestWinsEvenWhenAnOldWorkerIgnoresCancellation() async throws {
        let calls = Queries()
        let state = HistorySearchState(debounce: .zero) { _, query, _ in
            await calls.run(query)
            return HistorySearch.Result(query: query)
        }
        load(state, expenses: [Expense(amount: 20, category: "午餐")])
        try await waitUntil { state.indexRevision == 1 }
        state.begin(filter: .all)
        state.setText("old", immediately: true)
        for _ in 0..<1000 {
            if await calls.values().contains("old") { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        state.setText("new", immediately: true)
        try await waitUntil { state.result?.query == "new" }
        await calls.release()
        try await Task.sleep(for: .milliseconds(20))
        #expect(state.result?.query == "new")
    }

    @Test func rapidTypingIsCoalescedAndSuggestionBypassesDebounce() async throws {
        let calls = Queries()
        let state = HistorySearchState(debounce: .milliseconds(180)) { index, query, filter in
            #expect(Self.isOffMainThread())
            await calls.run(query)
            return try index.search(query, filter: filter)
        }
        load(state, expenses: [Expense(amount: 20, category: "午餐", note: "Coffee")])
        try await waitUntil { state.indexRevision == 1 }
        state.begin(filter: .all)
        for query in ["C", "Co", "Cof", "Coff", "Coffe", "Coffee"] { state.setText(query) }
        #expect(state.text == "Coffee")
        try await waitUntil { state.result?.query == "Coffee" }
        #expect(await calls.values() == ["Coffee"])
        state.setText("20", immediately: true)
        try await waitUntil { state.result?.query == "20" }
        #expect(state.result?.summary.count == 1)
    }

    @Test func activeQueryUpdatesAfterEditDeleteAndReplaceWithSameUUID() async throws {
        let state = HistorySearchState(debounce: .zero)
        let original = Expense(amount: 20, category: "午餐", note: "Coffee")
        load(state, expenses: [original])
        try await waitUntil { state.indexRevision == 1 }
        state.begin(filter: .all)
        state.setText("coffee", immediately: true)
        try await waitUntil { state.result?.summary.count == 1 }
        original.note = "Tea"
        load(state, expenses: [original])
        try await waitUntil { state.result?.summary.count == 0 }
        let replacement = Expense(amount: 99, category: "购物", note: "Coffee")
        replacement.id = original.id
        load(state, expenses: [replacement])
        try await waitUntil { state.result?.summary.expense == 99 }
        if case .expense(let mapped) = state.transaction(for: LedgerTransaction.expense(replacement).searchRecord.key) { #expect(mapped === replacement) }
        else { Issue.record("没有映射到恢复后的记录") }
        let equivalent = Expense(amount: replacement.amount, category: replacement.category, note: replacement.note, date: replacement.date)
        equivalent.id = replacement.id
        let previousRevision = state.indexRevision
        load(state, expenses: [equivalent])
        try await waitUntil { state.indexRevision > previousRevision && state.result != nil }
        if case .expense(let mapped) = state.transaction(for: LedgerTransaction.expense(equivalent).searchRecord.key) {
            #expect(mapped === equivalent)
        } else { Issue.record("UUID 和内容相同的恢复记录没有更新模型映射") }
        state.setFilter(.category("午餐"))
        try await waitUntil { state.result?.summary.count == 0 }
        state.setFilter(.all)
        try await waitUntil { state.result?.summary.count == 1 }
        load(state, expenses: [])
        try await waitUntil { state.result?.summary.count == 0 }
    }

    @Test func backupRestoreProducesTheSameSearchAndRecommendations() async throws {
        let source = try TestSupport.makeContext()
        source.insert(Expense(amount: -1234.5, category: "购物", note: "咖啡 Coffee"))
        source.insert(Expense(amount: 20, category: "午餐", note: "咖啡 Coffee"))
        source.insert(Income(amount: 50, source: "Salary", note: "奖金"))
        try source.save()
        let data = try DataIO.exportJSON(context: source)
        let target = try TestSupport.makeContext()
        let validated = try ImportValidator.validate(data: data)
        let preview = try DataIO.preview(validated: validated, context: target)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)
        let expenses = try target.fetch(FetchDescriptor<Expense>())
        let incomes = try target.fetch(FetchDescriptor<Income>())
        let prepared = try index(expenses, incomes)
        #expect(try prepared.search("coffee").summary == HistorySummary(expense: -1214.5, income: 0, count: 2))
        #expect(try prepared.search("Salary").summary.income == 50)
        #expect(try prepared.frequentNotes() == ["咖啡 Coffee"])
    }
}
