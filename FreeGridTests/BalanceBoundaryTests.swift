// 最终余额必须合法；拦截失败不能留下半笔交易，也不能吞掉其他未保存修改。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct BalanceBoundaryTests {
    @Test(arguments: [1e12 + 1, -1e12 - 1, Double.infinity, Double.nan])
    func invalidResultRestoresOriginalCash(cash: Double) throws {
        let context = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: context) { $0.cash = 100; $0.lockedAssets = 200 }
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(throws: ImportValidationError.self) {
            try LedgerStore.updateAssets(in: context) { $0.cash = cash }
        }
        #expect(assets.cash == 100)
        #expect(assets.lockedAssets == 200)
        #expect(!context.hasChanges)
    }

    @Test(arguments: [true, false])
    func transferCannotOverflowEitherBucket(toCash: Bool) throws {
        let context = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: context) { $0.cash = 1e12; $0.lockedAssets = 1e12 }
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(throws: ImportValidationError.self) {
            try LedgerStore.updateAssets(in: context) {
                $0.cash += toCash ? 1 : -1
                $0.lockedAssets += toCash ? -1 : 1
            }
        }
        #expect(assets.cash == 1e12)
        #expect(assets.lockedAssets == 1e12)
        #expect(throws: Never.self) { _ = try DataIO.exportJSON(context: context) }
    }

    @Test func incomeAtLimitSucceedsButNextIncomeIsRejected() throws {
        let context = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: context) { $0.cash = 1e12 - 1 }
        try LedgerStore.add(.income(Income(amount: 1, source: "工资")), in: context)
        #expect(throws: ImportValidationError.self) {
            try LedgerStore.add(.income(Income(amount: 1, source: "工资")), in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<Income>()) == 1)
        #expect(try context.fetch(FetchDescriptor<UserAssets>()).first?.cash == 1e12)
    }

    @Test func undoAtUpperLimitKeepsExpenseAndTrackingDate() throws {
        let context = try TestSupport.makeContext()
        let expense = Expense(amount: 1, category: "午餐", date: TestSupport.day("2026-01-01"))
        try LedgerStore.add(.expense(expense), in: context)
        try LedgerStore.updateAssets(in: context) { $0.cash = 1e12 }
        #expect(throws: ImportValidationError.self) {
            try LedgerStore.undo(id: expense.id, kind: .expense, in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1)
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(assets.cash == 1e12)
        #expect(assets.firstRecordDate == expense.date)
    }

    @Test func addingValidBackupToCashCannotSaveInvalidCombinedBalance() throws {
        let context = try TestSupport.makeContext()
        let json = Data(#"{"schema_version":2,"assets":{"total":2e12,"locked_assets":1e12,"cash":1e12},"expenses":[{"amount":30,"category":"午餐","date":"2026-01-01"}]}"#.utf8)
        let preview = try DataIO.previewJSON(data: json, context: context)
        #expect(throws: ImportValidationError.self) {
            _ = try DataIO.commitImport(preview: preview, strategy: .addToCash, context: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UserAssets>()) == 0)
        // 同一份合法双桶备份仍能按原桶恢复。
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: context)
        #expect(throws: Never.self) { _ = try DataIO.exportJSON(context: context) }
    }

    @Test func pendingChangesAreRejectedBeforeMutationAndRemainSaveable() throws {
        let context = try TestSupport.makeContext()
        context.autosaveEnabled = false
        try LedgerStore.updateAssets(in: context) { $0.cash = 100 }
        let pending = Income(amount: 7, source: "尚未保存")
        context.insert(pending)
        var mutationRan = false
        #expect(throws: LedgerStore.StoreError.self) {
            try LedgerStore.updateAssets(in: context) { assets in
                mutationRan = true
                assets.cash = 90
            }
        }
        #expect(!mutationRan)
        #expect(try context.fetchCount(FetchDescriptor<Income>()) == 1)
        #expect(context.hasChanges)
        try context.save()
        let fresh = ModelContext(context.container)
        #expect(try fresh.fetch(FetchDescriptor<Income>()).first?.id == pending.id)
        #expect(try fresh.fetch(FetchDescriptor<UserAssets>()).first?.cash == 100)
    }
}
