// 内存中的恢复断言之外，重新打开磁盘库，确认失败操作没有写入半份数据。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct DiskRollbackTests {
    private enum Failure: Error { case save }

    @Test func importUndoAndPurgeFailuresLeaveDiskBackupUnchanged() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.store")
        let expected = try exerciseFailures(at: url)
        let reopened = try context(at: url)
        #expect(try DataIO.exportJSON(context: reopened) == expected)
    }

    private func exerciseFailures(at url: URL) throws -> Data {
        let context = try context(at: url)
        let json = Data(#"{"schema_version":2,"assets":{"total":300,"locked_assets":200,"cash":100},"expenses":[{"amount":30,"category":"午餐","date":"2026-01-01"}],"incomes":[{"amount":40,"source":"工资","date":"2026-01-02"}],"devices":[{"name":"电脑","category":"数码","price":100,"purchase_date":"2026-01-01"}],"passive_sources":[{"name":"利息","monthly_amount":10}]}"#.utf8)
        _ = try DataIO.commitImport(preview: DataIO.previewJSON(data: json, context: context), strategy: .replace, context: context)
        let expected = try DataIO.exportJSON(context: context)
        // 使用不同记录 ID，保证失败导入确实触及五种模型。
        let incoming = try TestSupport.makeContext()
        _ = try DataIO.commitImport(preview: DataIO.previewJSON(data: json, context: incoming), strategy: .replace, context: incoming)
        try LedgerStore.updateAssets(in: incoming) { $0.cash = 500 }
        let preview = try DataIO.previewJSON(data: DataIO.exportJSON(context: incoming), context: context)
        #expect(preview.expensesNew.count == 1 && preview.incomesNew.count == 1)
        #expect(preview.devicesNew.count == 1 && preview.passiveSourcesNew.count == 1)
        let plan = try DataIO.makeImportPlan(preview: preview, strategy: .replace)
        #expect(throws: Failure.self) {
            _ = try DataIO.commitImport(plan: plan, context: context) { _ in throw Failure.save }
        }
        #expect(try DataIO.exportJSON(context: context) == expected)
        let expense = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        #expect(throws: Failure.self) {
            try LedgerStore.undo(id: expense.id, kind: .expense, in: context) { _ in throw Failure.save }
        }
        #expect(try DataIO.exportJSON(context: context) == expected)
        #expect(throws: Failure.self) {
            try DataIO.purgeAll(context: context) { _ in throw Failure.save }
        }
        #expect(!context.hasChanges)
        #expect(try DataIO.exportJSON(context: context) == expected)
        return expected
    }

    private func context(at url: URL) throws -> ModelContext {
        let schema = StoreBootstrap.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
}
