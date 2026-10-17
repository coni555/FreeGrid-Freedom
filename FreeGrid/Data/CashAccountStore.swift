// Pro 现金账户的写入边界。
// 不变量：只要有现金账户，`UserAssets.cash` 就等于各账户余额之和；
// 记账、撤销、改账、月供扣款和调拨都经过 `applyCashChange`，失败时由 `LedgerStore.updateAssets` 把各账户一起恢复。

import Foundation
import SwiftData

enum CashAccountError: Error, LocalizedError, Equatable {
    case invalidName
    case invalidAmount
    case hasAccounts
    case notEnough(name: String, available: Double)

    var errorDescription: String? {
        switch self {
        case .invalidName: return "账户名称请填写 1–20 个字，不包含换行。"
        case .invalidAmount: return "金额无效或超出允许范围。"
        case .hasAccounts: return "现金已经拆成多个账户，请在账户里修改。"
        case .notEnough(let name, let available):
            return "「\(name)」只有 ¥\(available.formatted(.number))，拆不出这么多。"
        }
    }
}

@MainActor
enum CashAccountStore {
    static let maximumNameCharacters = FinancialLimits.assetItemNameCharacters

    // MARK: - 校验与读取

    static func cleanName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maximumNameCharacters,
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw CashAccountError.invalidName
        }
        return name
    }

    /// 按扣款顺序
    static func accounts(in context: ModelContext) throws -> [CashAccount] {
        try context.fetch(FetchDescriptor<CashAccount>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]))
    }

    /// 记一笔支出默认扣哪个：按顺序第一个够付的；都不够时是第一个（记完它会是负数）
    static func payer(for amount: Double, in accounts: [CashAccount]) -> CashAccount? {
        accounts.first { $0.amount >= amount } ?? accounts.first
    }

    // MARK: - 记账时动哪个账户

    /// 现金变动落到账户上：没拆账户时只改总数；拆了就改 `accountID` 指的那个（找不到时支出按顺序挑、收入进第一个），
    /// 再把总数对齐成各账户之和。返回实际动了的账户。只在 `LedgerStore.updateAssets` 的修改闭包里调用。
    @discardableResult
    static func applyCashChange(
        _ delta: Double, accountID: UUID?, assets: UserAssets, in context: ModelContext
    ) throws -> CashAccount? {
        let all = try accounts(in: context)
        guard !all.isEmpty else {
            assets.cash += delta
            return nil
        }
        let target = all.first { $0.id == accountID } ?? (delta < 0 ? payer(for: -delta, in: all) : all.first)
        if let target {
            target.amount += delta
            target.updatedAt = .now
        }
        assets.cash = all.reduce(0) { $0 + $1.amount }
        return target
    }

    // MARK: - 拆分、增删改、排序

    /// 第一次拆分：原来的现金总数变成一个账户「现金」，余额不变。已经有账户，或现金是 0 时什么都不做。
    @discardableResult
    static func migrateIfNeeded(
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> CashAccount? {
        guard try accounts(in: context).isEmpty,
              let assets = try context.fetch(FetchDescriptor<UserAssets>()).first,
              assets.cash != 0 else { return nil }
        let account = CashAccount(name: "现金", amount: assets.cash, sortOrder: 0)
        try LedgerStore.updateAssets(in: context, save: save) { _ in
            context.insert(account)
        }
        return account
    }

    /// 新加的账户里的钱从哪来：新的钱（现金总数变大），或者从已有账户里分出来（总数不变）
    enum Source: Hashable {
        /// 还没拆过时的那个现金总数；拆分时它先变成一个账户「现金」
        case unsplitTotal
        case account(UUID)
    }

    /// 新增（existing 为 nil）或修改一个账户。`source` 只对新增有效。新账户排在最后。
    /// `countsInFreedom` 为 nil 时保持原样（新增的账户默认计入）。
    @discardableResult
    static func save(
        _ existing: CashAccount?, name: String, amount: Double, countsInFreedom: Bool? = nil, source: Source? = nil,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> CashAccount {
        let name = try cleanName(name)
        guard FinancialFormatting.validAmount(amount, allowsZero: true) else { throw CashAccountError.invalidAmount }
        let migrated = existing == nil ? try migrateIfNeeded(in: context, save: save) : nil
        let all = try accounts(in: context)
        let from: CashAccount?
        switch existing == nil ? source : nil {
        case .unsplitTotal: from = migrated
        case .account(let id): from = all.first { $0.id == id }
        case nil: from = nil
        }
        if let from, amount > from.amount + FinancialLimits.assetChecksumTolerance {
            throw CashAccountError.notEnough(name: from.name, available: from.amount)
        }
        let account = existing ?? CashAccount(name: name, amount: amount, sortOrder: (all.map(\.sortOrder).max() ?? -1) + 1)
        let previousAccount = (account.name, account.amount, account.countsInFreedom)
        try LedgerStore.updateAssets(in: context, save: save, restore: {
            (account.name, account.amount, account.countsInFreedom) = previousAccount
        }) { assets in
            if existing == nil { context.insert(account) }
            account.name = name
            account.amount = amount
            if let countsInFreedom { account.countsInFreedom = countsInFreedom }
            account.updatedAt = .now
            if let from {
                from.amount -= amount
                from.updatedAt = .now
            }
            try syncTotal(assets, in: context)
        }
        return account
    }

    /// 只改这个账户算不算进自由天数（列表上点序号）
    static func setCountsInFreedom(
        _ counts: Bool, for account: CashAccount,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws {
        let previous = (account.countsInFreedom, account.updatedAt)
        try LedgerStore.perform(in: context, save: save, restore: {
            (account.countsInFreedom, account.updatedAt) = previous
        }) {
            account.countsInFreedom = counts
            account.updatedAt = .now
        }
    }

    /// 删掉一个账户：它的余额从现金总数里去掉；删到一个不剩时现金归零。记过的账不改，撤销时退回第一个账户。
    static func delete(
        _ account: CashAccount,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws {
        try LedgerStore.updateAssets(in: context, save: save) { assets in
            context.delete(account)
            try syncTotal(assets, in: context, excluding: account.id)
        }
    }

    /// 把账户合并回一个现金总数：总数不变，账户删除。给没有 Pro、想回到只改总数的人用。
    static func mergeIntoTotal(
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws {
        let all = try accounts(in: context)
        try LedgerStore.updateAssets(in: context, save: save) { assets in
            assets.cash = all.reduce(0) { $0 + $1.amount }
            for account in all { context.delete(account) }
            assets.updatedAt = .now
        }
    }

    /// 调整扣款顺序：把 `account` 挪到第 `index` 位
    static func move(
        _ account: CashAccount, to index: Int,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws {
        var all = try accounts(in: context)
        guard let from = all.firstIndex(where: { $0.id == account.id }) else { return }
        let target = max(0, min(all.count - 1, index))
        guard target != from else { return }
        let previous = all.map { ($0, $0.sortOrder) }
        all.insert(all.remove(at: from), at: target)
        try LedgerStore.perform(in: context, save: save, restore: {
            for (item, order) in previous { item.sortOrder = order }
        }) {
            for (order, item) in all.enumerated() { item.sortOrder = order }
        }
    }

    // MARK: - 内部

    private static func syncTotal(_ assets: UserAssets, in context: ModelContext, excluding removed: UUID? = nil) throws {
        let remaining = try accounts(in: context).filter { $0.id != removed }
        assets.cash = remaining.reduce(0) { $0 + $1.amount }
        assets.updatedAt = .now
    }
}
