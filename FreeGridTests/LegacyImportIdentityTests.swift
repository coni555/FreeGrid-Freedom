// 旧备份没有 UUID，去重必须兼容分类映射、空白和备注截断。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct LegacyImportIdentityTests {
    private func data(_ records: [BackupEnvelope.ExpenseJSON]) throws -> Data {
        try JSONEncoder().encode(BackupEnvelope(schemaVersion: 1, expenses: records))
    }

    @Test(arguments: ["transport", "自定义分类", " 午餐 "])
    func reimportAfterMappingDoesNotAddTheSameExpense(category: String) throws {
        let context = try TestSupport.makeContext()
        let json = try data([.init(amount: 30, category: category, date: "2026-01-01", note: "原分类·手写备注")])
        let first = try DataIO.previewJSON(data: json, context: context)
        let map = category == "自定义分类" ? [category: "购物"] : [:]
        _ = try DataIO.commitImport(preview: first, strategy: .skipAssets, categoryMap: map, context: context)
        let second = try DataIO.previewJSON(data: json, context: context)
        #expect(second.expensesNew.isEmpty)
        #expect(second.expenseDuplicates.existing == 1)
    }

    @Test(arguments: [0, 1991, 1992, 1999, 2000])
    func truncatedProvenanceNeedsUserDecision(noteLength: Int) throws {
        let context = try TestSupport.makeContext()
        let note = String(repeating: "记", count: noteLength)
        let json = try data([.init(amount: 30, category: "外卖", date: "2026-01-01", note: note)])
        // 构造旧版已经存好的随机 UUID，不能依赖本轮导入时才新增的身份机制。
        let storedNote = String((note.isEmpty ? "原分类·外卖" : "\(note) · 原分类·外卖").prefix(2000))
        context.insert(Expense(amount: 30, category: "晚餐", note: storedNote, date: TestSupport.day("2026-01-01")))
        try context.save()
        let preview = try DataIO.previewJSON(data: json, context: context)
        if noteLength <= 1991 {
            #expect(preview.expensesNew.isEmpty)
            #expect(preview.expenseDuplicates.existing == 1)
        } else {
            #expect(preview.expensesNew.count == 1)
            #expect(preview.suspectedExpenseIndices == [0])
            #expect(preview.expensesSkipped == 0)
        }
    }

    @Test(arguments: [false, true])
    func unrelatedStoredLunchDoesNotSilentlyDiscardTaxi(skip: Bool) throws {
        let context = try TestSupport.makeContext()
        let note = String(repeating: "记", count: 2000)
        context.insert(Expense(amount: 30, category: "午餐", note: note, date: TestSupport.day("2026-01-01")))
        try context.save()
        let json = try data([.init(amount: 30, category: "taxi", date: "2026-01-01", note: note)])
        let preview = try DataIO.previewJSON(data: json, context: context)
        #expect(preview.expensesNew.count == 1)
        #expect(preview.suspectedExpenseIndices == [0])
        #expect(preview.expensesSkipped == 0)
        let result = try DataIO.commitImport(preview: preview, strategy: .skipAssets,
            skippingSuspectedExpenses: skip ? [0] : [], context: context)
        #expect(result.expensesAdded == (skip ? 0 : 1))
        let records = try context.fetch(FetchDescriptor<Expense>())
        #expect(records.count == (skip ? 1 : 2))
        #expect(records.reduce(0) { $0 + $1.amount } == (skip ? 30 : 60))
    }

    @Test(arguments: [1992, 1999, 2000])
    func differentFilesWithPartlyOrFullyTruncatedCategoriesNeedReview(noteLength: Int) throws {
        let context = try TestSupport.makeContext()
        let note = String(repeating: "记", count: noteLength)
        for raw in ["taxi", "transport"] {
            let json = try data([.init(amount: 30, category: raw, date: "2026-01-01", note: note)])
            let preview = try DataIO.previewJSON(data: json, context: context)
            #expect(preview.expensesNew.count == 1)
            #expect(preview.expensesSkipped == 0)
            #expect(preview.suspectedExpenseIndices == (raw == "taxi" ? [] : [0]))
            _ = try DataIO.commitImport(preview: preview, strategy: .skipAssets, categoryMap: [raw: "交通"], context: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 2)
    }

    @Test func distinctCanonicalCategoriesAndExplicitIDsAreNotMerged() throws {
        let context = try TestSupport.makeContext()
        let note = String(repeating: "记", count: 2000)
        let existing = Expense(amount: 30, category: "午餐", note: note, date: TestSupport.day("2026-01-01"))
        context.insert(existing)
        try context.save()
        let json = try data([
            .init(amount: 30, category: "晚餐", date: "2026-01-01", note: note),
            .init(id: UUID().uuidString, amount: 30, category: "午餐", date: "2026-01-01", note: note),
            .init(id: UUID().uuidString, amount: 30, category: "午餐", date: "2026-01-01", note: note),
        ])
        let preview = try DataIO.previewJSON(data: json, context: context)
        #expect(preview.expensesNew.count == 3)
        #expect(preview.expensesSkipped == 0)
    }

    @Test func differentRawCategoriesInSameFileSurviveTruncatedMapping() throws {
        let context = try TestSupport.makeContext()
        let note = String(repeating: "记", count: 2000)
        let json = try data([
            .init(amount: 30, category: "transport", date: "2026-01-01", note: note),
            .init(amount: 30, category: "taxi", date: "2026-01-01", note: note),
        ])
        let preview = try DataIO.previewJSON(data: json, context: context)
        #expect(preview.expensesNew.count == 2)
        _ = try DataIO.commitImport(preview: preview, strategy: .skipAssets, context: context)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 2)
    }

    @Test func changedAmountDateOrNoteIsANewRecord() throws {
        let context = try TestSupport.makeContext()
        let json = try data([.init(amount: 30, category: "transport", date: "2026-01-01", note: "地铁")])
        _ = try DataIO.commitImport(preview: DataIO.previewJSON(data: json, context: context), strategy: .skipAssets, context: context)
        let changed = try data([
            .init(amount: 31, category: "transport", date: "2026-01-01", note: "地铁"),
            .init(amount: 30, category: "transport", date: "2026-01-02", note: "地铁"),
            .init(amount: 30, category: "transport", date: "2026-01-01", note: "公交"),
        ])
        #expect(try DataIO.previewJSON(data: changed, context: context).expensesNew.count == 3)
    }
}
