// 手动记账与导入的保存边界：记录和现金一起保存，失败一起恢复。

import Foundation
import SwiftData

@MainActor
enum LedgerStore {
    typealias SaveAction = (ModelContext) throws -> Void

    /// 页面只在成功返回后关闭表单或显示成功。整个操作同步执行，不在中途让出执行权。
    static func perform(
        in context: ModelContext,
        save: SaveAction = { try $0.save() },
        restore: () -> Void = {},
        changes: () throws -> Void
    ) throws {
        do {
            try changes()
            try save(context)
        } catch {
            // 先恢复页面持有对象的字段；单独 rollback 在部分修改路径中会留下旧引用的新值。
            restore()
            context.rollback()
            throw error
        }
    }

    /// 余额及统计起点只有这一处修改边界。修改前保留值，失败后页面和账本都回到原态。
    static func updateAssets(
        in context: ModelContext,
        save: SaveAction = { try $0.save() },
        changes: (UserAssets) throws -> Void
    ) throws {
        let assets: UserAssets
        if let existing = try context.fetch(FetchDescriptor<UserAssets>()).first {
            assets = existing
        } else {
            assets = UserAssets(total: 0)
            context.insert(assets)
        }
        let previous = (assets.cash, assets.lockedAssets, assets.updatedAt, assets.firstRecordDate)
        try perform(in: context, save: save, restore: {
            (assets.cash, assets.lockedAssets, assets.updatedAt, assets.firstRecordDate) = previous
        }) {
            try changes(assets)
        }
    }

    static func savePassiveSource(
        _ existing: PassiveSource?, name: String, monthlyAmount: Double,
        in context: ModelContext,
        save: SaveAction = { try $0.save() }
    ) throws {
        let source = existing ?? PassiveSource(name: name, monthlyAmount: monthlyAmount)
        let previous = (source.name, source.monthlyAmount)
        try perform(in: context, save: save, restore: {
            (source.name, source.monthlyAmount) = previous
        }) {
            if existing == nil { context.insert(source) }
            source.name = name
            source.monthlyAmount = monthlyAmount
        }
    }

    static func add(
        _ transaction: LedgerTransaction,
        in context: ModelContext,
        save: SaveAction = { try $0.save() }
    ) throws {
        try updateAssets(in: context, save: save) { assets in
            switch transaction {
            case .expense(let expense):
                context.insert(expense)
                let expenses = try context.fetch(FetchDescriptor<Expense>())
                assets.firstRecordDate = FreedomMath.earliestExpenseDate(expenses)
            case .income(let income):
                context.insert(income)
            }
            assets.cash += transaction.cashChange
            assets.updatedAt = .now
        }
    }

    /// 按 ID 重查，同一记录从历史页和首页先后撤销时只回退一次现金。
    static func undo(
        id: UUID,
        kind: TransactionKind,
        in context: ModelContext,
        save: SaveAction = { try $0.save() }
    ) throws {
        // 在创建资产行之前确认记录存在，无记录的撤销不会写入空资产。
        let transaction: LedgerTransaction
        switch kind {
        case .expense:
            let expenses = try context.fetch(FetchDescriptor<Expense>())
            guard let expense = expenses.first(where: { $0.id == id }) else { return }
            transaction = .expense(expense)
        case .income:
            let incomes = try context.fetch(FetchDescriptor<Income>())
            guard let income = incomes.first(where: { $0.id == id }) else { return }
            transaction = .income(income)
        }
        try updateAssets(in: context, save: save) { assets in
            assets.cash -= transaction.cashChange
            switch transaction {
            case .expense(let expense):
                context.delete(expense)
                let expenses = try context.fetch(FetchDescriptor<Expense>())
                assets.firstRecordDate = FreedomMath.earliestExpenseDate(expenses.filter { $0.id != id })
            case .income(let income):
                context.delete(income)
            }
            assets.updatedAt = .now
        }
    }
}
