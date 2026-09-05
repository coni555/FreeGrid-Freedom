// 用真实 SwiftData 内存库验证：记录、现金与追踪起点必须一起成功或一起恢复。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct LedgerStoreTests {
    private enum Failure: Error { case save }

    @Test func addingAndUndoingTransactionsUpdatesCashOnlyOnce() throws {
        let context = try TestSupport.makeContext()
        let income = Income(amount: 1_000, source: "工资")
        try LedgerStore.add(.income(income), in: context)
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(assets.cash == 1_000)
        #expect(assets.firstRecordDate == nil)
        let early = Expense(amount: 100, category: "午餐", date: TestSupport.day("2026-01-01"))
        let later = Expense(amount: 20, category: "午餐", date: TestSupport.day("2026-02-01"))
        try LedgerStore.add(.expense(early), in: context)
        try LedgerStore.add(.expense(later), in: context)
        #expect(assets.cash == 880)
        try LedgerStore.undo(id: early.id, kind: .expense, in: context)
        try LedgerStore.undo(id: early.id, kind: .expense, in: context)
        #expect(assets.cash == 980)
        #expect(assets.firstRecordDate == later.date)
        try LedgerStore.undo(id: later.id, kind: .expense, in: context)
        try LedgerStore.undo(id: income.id, kind: .income, in: context)
        #expect(assets.cash == 0)
        #expect(assets.firstRecordDate == nil)
    }

    @Test func failedAddDoesNotCreateRecordOrAssetSingleton() throws {
        let context = try TestSupport.makeContext()
        #expect(throws: Failure.self) {
            try LedgerStore.add(.expense(Expense(amount: 50, category: "午餐")), in: context) { _ in throw Failure.save }
        }
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UserAssets>()) == 0)
    }

    @Test func failedUndoRestoresRecordCashAndTrackingDate() throws {
        let context = try TestSupport.makeContext()
        let expense = Expense(amount: 50, category: "午餐", date: TestSupport.day("2026-01-01"))
        try LedgerStore.add(.expense(expense), in: context)
        #expect(throws: Failure.self) {
            try LedgerStore.undo(id: expense.id, kind: .expense, in: context) { _ in throw Failure.save }
        }
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1)
        #expect(assets.cash == -50)
        #expect(assets.firstRecordDate == TestSupport.day("2026-01-01"))
    }

    @Test func refundUndoSubtractsCash() throws {
        let context = try TestSupport.makeContext()
        let refund = Expense(amount: -30, category: "购物")
        try LedgerStore.add(.expense(refund), in: context)
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(assets.cash == 30)
        try LedgerStore.undo(id: refund.id, kind: .expense, in: context)
        #expect(assets.cash == 0)
    }

    @Test func failedAssetAndPassiveEditsRestoreOriginalReferences() throws {
        let context = try TestSupport.makeContext()
        let assets = UserAssets(total: 0)
        assets.cash = 100
        let passive = PassiveSource(name: "利息", monthlyAmount: 10)
        context.insert(assets)
        context.insert(passive)
        try context.save()
        #expect(throws: Failure.self) {
            try LedgerStore.updateAssets(in: context, save: { _ in throw Failure.save }) { assets in
                assets.cash -= 40
                assets.lockedAssets += 40
            }
        }
        #expect(assets.cash == 100)
        #expect(assets.lockedAssets == 0)
        #expect(throws: Failure.self) {
            try LedgerStore.savePassiveSource(passive, name: "新名字", monthlyAmount: 20,
                                              in: context, save: { _ in throw Failure.save })
        }
        #expect(passive.name == "利息")
        #expect(passive.monthlyAmount == 10)
        #expect(!context.hasChanges)
        try context.save()
        let fresh = ModelContext(context.container)
        #expect(try fresh.fetch(FetchDescriptor<UserAssets>()).first?.cash == 100)
        #expect(try fresh.fetch(FetchDescriptor<PassiveSource>()).first?.monthlyAmount == 10)
    }

    @Test func changesThrowingBeforeSaveAlsoRestoreOriginalReference() throws {
        let context = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: context) { $0.cash = 100 }
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(throws: Failure.self) {
            try LedgerStore.updateAssets(in: context) { assets in
                assets.cash = 200
                throw Failure.save
            }
        }
        #expect(assets.cash == 100)
        #expect(!context.hasChanges)
    }

    @Test(arguments: [TransactionKind.expense, .income])
    func failedAdditionKeepsExistingCash(kind: TransactionKind) throws {
        let context = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: context) { $0.cash = 1_000 }
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        let transaction: LedgerTransaction = kind == .expense
            ? .expense(Expense(amount: 100, category: "午餐"))
            : .income(Income(amount: 100, source: "工资"))
        #expect(throws: Failure.self) {
            try LedgerStore.add(transaction, in: context, save: { _ in throw Failure.save })
        }
        #expect(assets.cash == 1_000)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Income>()) == 0)
        #expect(!context.hasChanges)
    }

    @Test func purgeFailureRestoresEveryModelThenSuccessfulPurgeRemovesAll() throws {
        let context = try TestSupport.makeContext()
        context.insert(Expense(amount: 1, category: "午餐"))
        context.insert(Income(amount: 2, source: "工资"))
        context.insert(Device(name: "电脑", category: "数码", price: 3, purchaseDate: .now))
        context.insert(PassiveSource(name: "利息", monthlyAmount: 4))
        context.insert(UserAssets(total: 5))
        try context.save()
        #expect(throws: Failure.self) {
            try DataIO.purgeAll(context: context) { _ in throw Failure.save }
        }
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Income>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Device>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PassiveSource>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<UserAssets>()) == 1)
        try DataIO.purgeAll(context: context)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Income>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Device>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PassiveSource>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UserAssets>()) == 0)
    }
}
