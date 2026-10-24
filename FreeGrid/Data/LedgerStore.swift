// 手动记账与导入的保存边界：记录和现金一起保存，失败一起恢复。

import Foundation
import SwiftData

@MainActor
enum LedgerStore {
    typealias SaveAction = (ModelContext) throws -> Void

    enum StoreError: Error, LocalizedError {
        case pendingChanges
        case missingRecord

        var errorDescription: String? {
            switch self {
            case .pendingChanges: return String(localized: "有一处还没保存。先保存或取消它，再试一次。")
            case .missingRecord: return String(localized: "这笔记录已经不在账本里，可能刚被撤销。")
            }
        }
    }

    /// 修改一笔已有记录时可以改的内容。title 对支出是分类，对收入是来源。
    struct TransactionEdit: Equatable {
        var amount: Double
        var title: String
        var note: String
        var date: Date
        /// Pro 现金账户：换到哪个账户。nil 表示不换
        var cashAccountID: UUID? = nil
    }

    /// 页面只在成功返回后关闭表单或显示成功。整个操作同步执行，不在中途让出执行权。
    static func perform(
        in context: ModelContext,
        save: SaveAction = { try $0.save() },
        restore: () -> Void = {},
        changes: () throws -> Void
    ) throws {
        // rollback 作用于整个上下文。开始前拒绝混入其他操作，且不要回滚它们。
        guard !context.hasChanges else { throw StoreError.pendingChanges }
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
    /// 现金账户（Pro）的余额也在这里一起保留和恢复，所以任何动现金的路径都不用自己记。
    static func updateAssets(
        in context: ModelContext,
        save: SaveAction = { try $0.save() },
        restore: () -> Void = {},
        changes: (UserAssets) throws -> Void
    ) throws {
        let existing = try context.fetch(FetchDescriptor<UserAssets>()).first
        let assets = existing ?? UserAssets(total: 0)
        let previous = (assets.cash, assets.lockedAssets, assets.updatedAt, assets.firstRecordDate)
        let accounts = try context.fetch(FetchDescriptor<CashAccount>()).map { ($0, $0.name, $0.amount, $0.sortOrder, $0.updatedAt) }
        try perform(in: context, save: save, restore: {
            (assets.cash, assets.lockedAssets, assets.updatedAt, assets.firstRecordDate) = previous
            for (account, name, amount, order, updated) in accounts {
                (account.name, account.amount, account.sortOrder, account.updatedAt) = (name, amount, order, updated)
            }
            restore()
        }) {
            if existing == nil { context.insert(assets) }
            try changes(assets)
            try ImportValidator.validateBalances(lockedAssets: assets.lockedAssets, cash: assets.cash)
        }
    }

    /// `monthlyAmount` 是折合的每月；`intervalMonths` 只记几个月到账一次，方便下次按「每次到账多少」改
    static func savePassiveSource(
        _ existing: PassiveSource?, name: String, monthlyAmount: Double, intervalMonths: Int = 1,
        in context: ModelContext,
        save: SaveAction = { try $0.save() }
    ) throws {
        guard LoanSchedule.intervals.contains(intervalMonths) else { throw LoanError.invalidInterval }
        let source = existing ?? PassiveSource(name: name, monthlyAmount: monthlyAmount, intervalMonths: intervalMonths)
        let previous = (source.name, source.monthlyAmount, source.intervalMonths)
        try perform(in: context, save: save, restore: {
            (source.name, source.monthlyAmount, source.intervalMonths) = previous
        }) {
            if existing == nil { context.insert(source) }
            source.name = name
            source.monthlyAmount = monthlyAmount
            source.intervalMonths = intervalMonths
        }
    }

    /// Pro 分类改名：用这个分类的旧账一起改成新名字（月供扣款的「分类」是贷款名，不碰）。
    /// 返回改了几笔。失败时所有记录回到原名。
    @discardableResult
    static func renameCategory(
        from old: String, to new: String,
        in context: ModelContext,
        save: SaveAction = { try $0.save() }
    ) throws -> Int {
        guard old != new else { return 0 }
        let records = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.category == old }))
            .filter { $0.loanID == nil }
        guard !records.isEmpty else { return 0 }
        try perform(in: context, save: save, restore: {
            for record in records { record.category = old }
        }) {
            for record in records { record.category = new }
        }
        return records.count
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
                assets.firstRecordDate = try earliestExpenseDate(in: context, except: expense.id, orAlso: expense.date)
            case .income(let income):
                context.insert(income)
            }
            let account = try CashAccountStore.applyCashChange(
                transaction.cashChange, accountID: transaction.cashAccountID, assets: assets, in: context)
            transaction.setCashAccountID(account?.id)
            assets.updatedAt = .now
        }
    }

    private static func expense(id: UUID, in context: ModelContext) throws -> Expense? {
        try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first
    }

    /// 最早一笔支出的日期。按日期只取最前面两条，不把整本账读进来（几千笔时每次保存要多等几十毫秒）。
    /// 数据库按已保存的日期排序，所以正在加、改、删的那一笔先排除，再拿它的新日期来比
    private static func earliestExpenseDate(in context: ModelContext, except id: UUID, orAlso date: Date?) throws -> Date? {
        var earliest = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)])
        earliest.fetchLimit = 2
        let others = try context.fetch(earliest).first { $0.id != id }?.date
        return [others, date].compactMap { $0 }.min()
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
            guard let expense = try expense(id: id, in: context) else { return }
            transaction = .expense(expense)
        case .income:
            guard let income = try context.fetch(FetchDescriptor<Income>(predicate: #Predicate { $0.id == id })).first
            else { return }
            transaction = .income(income)
        }
        try updateAssets(in: context, save: save) { assets in
            let account = CashAccountStore.recordedAccount(
                transaction.cashAccountID, in: try CashAccountStore.accounts(in: context))
            try CashAccountStore.applyCashChange(
                -transaction.cashChange, accountID: account, assets: assets, in: context)
            switch transaction {
            case .expense(let expense):
                context.delete(expense)
                assets.firstRecordDate = try earliestExpenseDate(in: context, except: id, orAlso: nil)
            case .income(let income):
                context.delete(income)
            }
            assets.updatedAt = .now
        }
    }

    /// 修改已有记录：现金只补上新旧金额的差额，支出改日期后重算统计起点。
    /// 失败时记录的字段和现金一起回到修改前。
    static func edit(
        id: UUID,
        kind: TransactionKind,
        in context: ModelContext,
        to edit: TransactionEdit,
        save: SaveAction = { try $0.save() }
    ) throws {
        switch kind {
        case .expense:
            guard let expense = try expense(id: id, in: context) else { throw StoreError.missingRecord }
            let previous = (expense.amount, expense.category, expense.note, expense.date, expense.cashAccountID)
            try updateAssets(in: context, save: save, restore: {
                (expense.amount, expense.category, expense.note, expense.date, expense.cashAccountID) = previous
            }) { assets in
                expense.cashAccountID = try moveCash(old: -expense.amount, new: -edit.amount,
                                                     from: expense.cashAccountID, to: edit.cashAccountID,
                                                     assets: assets, in: context)
                (expense.amount, expense.category, expense.note, expense.date)
                    = (edit.amount, edit.title, edit.note, edit.date)
                assets.firstRecordDate = try earliestExpenseDate(in: context, except: id, orAlso: edit.date)
                assets.updatedAt = .now
            }
        case .income:
            let incomes = try context.fetch(FetchDescriptor<Income>())
            guard let income = incomes.first(where: { $0.id == id }) else { throw StoreError.missingRecord }
            let previous = (income.amount, income.source, income.note, income.date, income.cashAccountID)
            try updateAssets(in: context, save: save, restore: {
                (income.amount, income.source, income.note, income.date, income.cashAccountID) = previous
            }) { assets in
                income.cashAccountID = try moveCash(old: income.amount, new: edit.amount,
                                                    from: income.cashAccountID, to: edit.cashAccountID,
                                                    assets: assets, in: context)
                (income.amount, income.source, income.note, income.date)
                    = (edit.amount, edit.title, edit.note, edit.date)
                assets.updatedAt = .now
            }
        }
    }

    /// 改账时的现金：同一个账户只补差额；换了账户就把旧的整笔退回原账户、新的整笔记到新账户。
    /// `old` / `new` 是这笔对现金的影响（支出为负）。返回这笔之后记在哪个账户。
    /// 原来没记账户（拆账户以前记的）或账户已删时按第一个算，改过以后就记在它上面。
    private static func moveCash(
        old: Double, new: Double, from oldAccount: UUID?, to newAccount: UUID?,
        assets: UserAssets, in context: ModelContext
    ) throws -> UUID? {
        let current = CashAccountStore.recordedAccount(oldAccount, in: try CashAccountStore.accounts(in: context))
        guard let newAccount, newAccount != current else {
            try CashAccountStore.applyCashChange(new - old, accountID: current, assets: assets, in: context)
            return current
        }
        try CashAccountStore.applyCashChange(-old, accountID: current, assets: assets, in: context)
        return try CashAccountStore.applyCashChange(new, accountID: newAccount, assets: assets, in: context)?.id
    }
}
