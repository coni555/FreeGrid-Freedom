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

    /// 统计起点只按日期取最前面的两笔：磁盘库按已保存的日期排序，正在加、改、删的那笔也要算对
    @Test func firstRecordDateFollowsAddEditAndUndoOnDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = ModelConfiguration(schema: StoreBootstrap.schema, url: folder.appendingPathComponent("ledger.store"))
        let context = ModelContext(try ModelContainer(for: StoreBootstrap.schema, configurations: [configuration]))
        let march = Expense(amount: 30, category: "午餐", date: TestSupport.day("2026-03-01"))
        let april = Expense(amount: 40, category: "午餐", date: TestSupport.day("2026-04-01"))
        try LedgerStore.add(.expense(march), in: context)
        try LedgerStore.add(.expense(april), in: context)
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(assets.firstRecordDate == march.date)

        let january = Expense(amount: 10, category: "午餐", date: TestSupport.day("2026-01-01"))
        try LedgerStore.add(.expense(january), in: context)
        #expect(assets.firstRecordDate == january.date)

        // 最早那笔改到最晚：起点落到原来的第二笔
        try LedgerStore.edit(id: january.id, kind: .expense, in: context,
                             to: .init(amount: 10, title: "午餐", note: "", date: TestSupport.day("2026-05-01")))
        #expect(assets.firstRecordDate == march.date)
        // 改到最早：起点跟着它走
        try LedgerStore.edit(id: april.id, kind: .expense, in: context,
                             to: .init(amount: 40, title: "午餐", note: "", date: TestSupport.day("2025-12-01")))
        #expect(assets.firstRecordDate == TestSupport.day("2025-12-01"))

        try LedgerStore.undo(id: april.id, kind: .expense, in: context)
        #expect(assets.firstRecordDate == march.date)
        try LedgerStore.undo(id: march.id, kind: .expense, in: context)
        try LedgerStore.undo(id: january.id, kind: .expense, in: context)
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

    @Test func editingAnExpenseMovesCashByTheDifferenceAndRecomputesTrackingStart() throws {
        let context = try TestSupport.makeContext()
        let rent = Expense(amount: 3_700, category: "其他", note: "租房", date: TestSupport.day("2026-07-30"))
        let lunch = Expense(amount: 15, category: "午餐", date: TestSupport.day("2026-07-01"))
        try LedgerStore.add(.expense(rent), in: context)
        try LedgerStore.add(.expense(lunch), in: context)
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(assets.cash == -3_715)

        // 只改分类：现金不动
        try LedgerStore.edit(id: rent.id, kind: .expense, in: context,
                             to: .init(amount: 3_700, title: "房租", note: "租房", date: rent.date))
        #expect(rent.category == "房租")
        #expect(assets.cash == -3_715)

        // 金额 3700 → 3500，日期提前到 6 月：现金多回 200，统计起点跟着提前
        try LedgerStore.edit(id: rent.id, kind: .expense, in: context,
                             to: .init(amount: 3_500, title: "房租", note: "", date: TestSupport.day("2026-06-15")))
        #expect(rent.amount == 3_500)
        #expect(rent.note == "")
        #expect(assets.cash == -3_515)
        #expect(assets.firstRecordDate == TestSupport.day("2026-06-15"))
    }

    @Test func editingAnIncomeMovesCashTheOtherWay() throws {
        let context = try TestSupport.makeContext()
        let income = Income(amount: 1_000, source: "工资", date: TestSupport.day("2026-07-01"))
        try LedgerStore.add(.income(income), in: context)
        try LedgerStore.edit(id: income.id, kind: .income, in: context,
                             to: .init(amount: 1_900, title: "工资 7 月", note: "补发", date: income.date))
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(assets.cash == 1_900)
        #expect(income.source == "工资 7 月")
        #expect(income.note == "补发")
        #expect(assets.firstRecordDate == nil)
    }

    @Test func failedEditRestoresRecordFieldsAndCash() throws {
        let context = try TestSupport.makeContext()
        let expense = Expense(amount: 50, category: "午餐", note: "面", date: TestSupport.day("2026-01-10"))
        try LedgerStore.add(.expense(expense), in: context)
        #expect(throws: Failure.self) {
            try LedgerStore.edit(id: expense.id, kind: .expense, in: context,
                                 to: .init(amount: 80, title: "晚餐", note: "", date: TestSupport.day("2026-01-01"))) { _ in
                throw Failure.save
            }
        }
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(expense.amount == 50)
        #expect(expense.category == "午餐")
        #expect(expense.note == "面")
        #expect(expense.date == TestSupport.day("2026-01-10"))
        #expect(assets.cash == -50)
        #expect(assets.firstRecordDate == TestSupport.day("2026-01-10"))
        #expect(!context.hasChanges)
    }

    @Test func editingAMissingRecordThrowsAndWritesNothing() throws {
        let context = try TestSupport.makeContext()
        #expect(throws: LedgerStore.StoreError.self) {
            try LedgerStore.edit(id: UUID(), kind: .expense, in: context,
                                 to: .init(amount: 1, title: "午餐", note: "", date: .now))
        }
        #expect(try context.fetchCount(FetchDescriptor<UserAssets>()) == 0)
    }

    @Test func editRejectsAnAmountThatPushesCashPastTheLimit() throws {
        let context = try TestSupport.makeContext()
        let income = Income(amount: 1_000, source: "工资")
        try LedgerStore.add(.income(income), in: context)
        #expect(throws: (any Error).self) {
            try LedgerStore.edit(id: income.id, kind: .income, in: context,
                                 to: .init(amount: FinancialLimits.maximumAmount * 2, title: "工资", note: "", date: income.date))
        }
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(income.amount == 1_000)
        #expect(assets.cash == 1_000)
    }

    @Test func editFormKeepsUntouchedRefundAmountAndOriginalTimeOfDay() {
        let noon = TestSupport.day("2026-03-05").addingTimeInterval(12 * 3600)
        let refund = LedgerTransaction.expense(Expense(amount: -30, category: "购物", note: "退款", date: noon))
        // 只改分类：负数金额和具体时刻原样保留
        let recategorized = EditTransactionSheet.edit(
            for: refund, amountText: "-30", title: " 退货 ", note: "退款", date: TestSupport.day("2026-03-05"))
        #expect(recategorized == .init(amount: -30, title: "退货", note: "退款", date: noon))
        // 动了金额就按新增的规则校验：负数、零、非数字都不行
        for text in ["-20", "0", "abc", ""] {
            #expect(EditTransactionSheet.edit(for: refund, amountText: text, title: "购物", note: "", date: noon) == nil)
        }
        #expect(EditTransactionSheet.edit(for: refund, amountText: "12.5", title: "购物", note: "", date: noon)?.amount == 12.5)
        #expect(EditTransactionSheet.edit(for: refund, amountText: "-30", title: "  ", note: "", date: noon) == nil)
    }
}
