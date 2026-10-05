import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct ImportFreshnessTests {
    private func backup(withIDs: Bool = true) -> Data {
        let id = withIDs ? "\"id\":\"00000000-0000-0000-0000-000000000001\"," : ""
        return Data("""
        {"schema_version":2,"assets":{"total":500,"locked_assets":300,"cash":200},
         "expenses":[{\(id)"amount":30,"category":"午餐","date":"2026-01-01"}],
         "incomes":[{\(id)"amount":80,"source":"工资","date":"2026-01-01"}],
         "devices":[{\(id)"name":"电脑","category":"数码","price":100,"purchase_date":"2026-01-01"}],
         "passive_sources":[{\(id)"name":"利息","monthly_amount":10}]}
        """.utf8)
    }

    @Test(arguments: [true, false], [DataIO.AssetsImportStrategy.replace, .addToCash, .skipAssets])
    func secondPreviewCannotDuplicateAnyModelOrApplyAssetsAgain(withIDs: Bool, strategy: DataIO.AssetsImportStrategy) throws {
        let context = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: context) { $0.cash = 1000 }
        let data = backup(withIDs: withIDs)
        let first = try DataIO.previewJSON(data: data, context: context)
        let stalePlan = try DataIO.makeImportPlan(preview: DataIO.previewJSON(data: data, context: context), strategy: strategy)
        _ = try DataIO.commitImport(preview: first, strategy: strategy, context: context)
        let savedBackup = try DataIO.exportJSON(context: context)
        var didSave = false
        #expect(throws: DataIO.DataIOError.stalePreview) {
            _ = try DataIO.commitImport(plan: stalePlan, context: context) { _ in didSave = true }
        }
        #expect(!didSave)
        #expect(!context.hasChanges)
        #expect(try DataIO.exportJSON(context: context) == savedBackup)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Income>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Device>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PassiveSource>()) == 1)
        let refreshed = try DataIO.previewJSON(data: data, context: context)
        #expect(refreshed.expensesSkipped == 1)
        #expect(refreshed.incomesSkipped == 1)
        _ = try DataIO.commitImport(preview: refreshed, strategy: .skipAssets, context: context)
        #expect(try DataIO.exportJSON(context: context) == savedBackup)

        let restored = try TestSupport.makeContext()
        _ = try DataIO.commitImport(preview: DataIO.previewJSON(data: savedBackup, context: restored), strategy: .replace, context: restored)
        #expect(try context.fetch(FetchDescriptor<Expense>()).map(\.id) == restored.fetch(FetchDescriptor<Expense>()).map(\.id))
    }

    @Test(arguments: ["expense", "income", "device", "passive", "assets", "delete", "replace", "insert"])
    func changesAfterPreviewAreRejectedEvenWhenCountsStayTheSame(change: String) throws {
        let context = try TestSupport.makeContext()
        _ = try DataIO.commitImport(preview: DataIO.previewJSON(data: backup(), context: context), strategy: .replace, context: context)
        let preview = try DataIO.previewJSON(data: Data(#"{"assets":{"total":999}}"#.utf8), context: context)
        let expense = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        switch change {
        case "expense": expense.note = "新的备注"
        case "income": try context.fetch(FetchDescriptor<Income>()).first?.amount = 90
        case "device": try context.fetch(FetchDescriptor<Device>()).first?.status = "retired"
        case "passive": try context.fetch(FetchDescriptor<PassiveSource>()).first?.monthlyAmount = 20
        case "assets": try context.fetch(FetchDescriptor<UserAssets>()).first?.cash = 201
        case "delete": context.delete(expense)
        case "replace":
            let replacement = Expense(amount: expense.amount, category: expense.category, date: expense.date)
            replacement.id = expense.id
            context.delete(expense)
            context.insert(replacement)
        default: context.insert(Income(amount: 1, source: "新收入", date: TestSupport.day("2026-01-01")))
        }
        try context.save()
        let before = try DataIO.exportJSON(context: context)
        #expect(throws: DataIO.DataIOError.stalePreview) {
            _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: context)
        }
        #expect(try DataIO.exportJSON(context: context) == before)
        #expect(!context.hasChanges)
    }

    @Test func pendingEditsAreNotRolledBackAndFailedSaveCanBeRetried() throws {
        enum Failure: Error { case save }
        let context = try TestSupport.makeContext()
        let preview = try DataIO.previewJSON(data: backup(), context: context)
        let plan = try DataIO.makeImportPlan(preview: preview, strategy: .replace)
        #expect(throws: Failure.self) {
            _ = try DataIO.commitImport(plan: plan, context: context) { _ in throw Failure.save }
        }
        #expect(!context.hasChanges)
        _ = try DataIO.commitImport(plan: plan, context: context)
        let next = try DataIO.previewJSON(data: backup(), context: context)
        let income = try #require(try context.fetch(FetchDescriptor<Income>()).first)
        income.note = "尚未保存"
        #expect(throws: LedgerStore.StoreError.self) {
            _ = try DataIO.commitImport(preview: next, strategy: .replace, context: context)
        }
        #expect(context.hasChanges)
        #expect(income.note == "尚未保存")
    }
}
