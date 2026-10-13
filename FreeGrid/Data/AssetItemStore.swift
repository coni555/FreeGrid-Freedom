// Pro 资产逐项记录的写入边界。
// 不变量：只要有资产项，`UserAssets.lockedAssets` 就等于各项金额之和；
// 每一次增删改和调拨都在同一次保存里更新它，失败时现金、各项和总数一起回到原样。

import Foundation
import SwiftData

enum AssetItemError: Error, LocalizedError, Equatable {
    case invalidName
    case invalidAmount
    case missingItem
    case hasItems
    case needsItem

    var errorDescription: String? {
        switch self {
        case .invalidName: return "资产项名称请填写 1–20 个字，不包含换行。"
        case .invalidAmount: return "金额无效或超出允许范围。"
        case .missingItem: return "这一项已经不在账本里。"
        case .hasItems: return "资产已经拆成多项，请在资产明细里修改。"
        case .needsItem: return "请先选择是哪一项资产。"
        }
    }
}

@MainActor
enum AssetItemStore {
    static let maximumNameCharacters = FinancialLimits.assetItemNameCharacters

    // MARK: - 校验

    static func cleanName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maximumNameCharacters,
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw AssetItemError.invalidName
        }
        return name
    }

    static func validAmount(_ value: Double) throws -> Double {
        guard FinancialFormatting.validAmount(value, allowsZero: true) else { throw AssetItemError.invalidAmount }
        return value
    }

    // MARK: - 读取

    static func items(in context: ModelContext) throws -> [AssetItem] {
        try context.fetch(FetchDescriptor<AssetItem>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]))
    }

    /// 各项之和。没有资产项时返回 nil：这时总数就是用户自己填的那个数。
    static func total(of items: [AssetItem]) -> Double? {
        items.isEmpty ? nil : items.reduce(0) { $0 + $1.amount }
    }

    // MARK: - 写入

    /// 老用户第一次进逐项管理：原来的总数变成一项「资产」，净值和自由天数不变。
    /// 已经有项，或总数是 0 时什么都不做。
    @discardableResult
    static func migrateIfNeeded(
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> Bool {
        guard try items(in: context).isEmpty,
              let assets = try context.fetch(FetchDescriptor<UserAssets>()).first,
              assets.lockedAssets > 0 else { return false }
        let total = assets.lockedAssets
        try LedgerStore.updateAssets(in: context, save: save) { _ in
            context.insert(AssetItem(name: "资产", amount: total, sortOrder: 0))
        }
        return true
    }

    /// 新增（existing 为 nil）或修改一项。
    @discardableResult
    static func save(
        _ existing: AssetItem?, name: String, amount: Double,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> AssetItem {
        let name = try cleanName(name)
        let amount = try validAmount(amount)
        // 还没拆过就直接加第一项：先把原来的总数变成一项，否则总数会被新的这一项顶掉
        if existing == nil { try migrateIfNeeded(in: context, save: save) }
        let all = try items(in: context)
        let item = existing ?? AssetItem(name: name, amount: amount, sortOrder: (all.map(\.sortOrder).max() ?? -1) + 1)
        let previous = snapshot(all)
        let previousItem = (item.name, item.amount, item.updatedAt)
        try LedgerStore.updateAssets(in: context, save: save, restore: {
            restore(previous)
            (item.name, item.amount, item.updatedAt) = previousItem
        }) { assets in
            if existing == nil { context.insert(item) }
            item.name = name
            item.amount = amount
            item.updatedAt = .now
            try syncTotal(assets, in: context)
        }
        return item
    }

    static func delete(
        _ item: AssetItem,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws {
        let previous = snapshot(try items(in: context))
        try LedgerStore.updateAssets(in: context, save: save, restore: { restore(previous) }) { assets in
            context.delete(item)
            try syncTotal(assets, in: context, excluding: item.id)
        }
    }

    /// 把所有项合并回一个总数：总数不变，各项删除。给没有 Pro、想回到「只改总数」的人用。
    static func mergeIntoTotal(
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws {
        let all = try items(in: context)
        let previous = snapshot(all)
        try LedgerStore.updateAssets(in: context, save: save, restore: { restore(previous) }) { assets in
            let sum = all.reduce(0) { $0 + $1.amount }
            for item in all { context.delete(item) }
            assets.lockedAssets = sum
            assets.updatedAt = .now
        }
    }

    enum TransferDirection { case cashToItem, itemToCash }

    /// 现金和指定一项之间调拨；实际调走的不超过来源里有的。返回实际金额。
    @discardableResult
    static func transfer(
        _ direction: TransferDirection, amount: Double, item: AssetItem,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> Double {
        guard FinancialFormatting.validAmount(amount) else { throw AssetItemError.invalidAmount }
        let previous = snapshot(try items(in: context))
        var moved = 0.0
        try LedgerStore.updateAssets(in: context, save: save, restore: { restore(previous) }) { assets in
            switch direction {
            case .cashToItem:
                moved = min(amount, max(0, assets.cash))
                assets.cash -= moved
                item.amount += moved
            case .itemToCash:
                moved = min(amount, max(0, item.amount))
                item.amount -= moved
                assets.cash += moved
            }
            item.updatedAt = .now
            assets.updatedAt = .now
            try syncTotal(assets, in: context)
        }
        return moved
    }

    // MARK: - 内部

    /// 资产桶 = 各项之和；一项都没有时保持用户填的总数不动。
    private static func syncTotal(_ assets: UserAssets, in context: ModelContext, excluding removed: UUID? = nil) throws {
        let remaining = try items(in: context).filter { $0.id != removed }
        if remaining.isEmpty {
            // 最后一项删掉后，总数跟着归零，而不是留下一个没有来源的数
            assets.lockedAssets = 0
        } else {
            assets.lockedAssets = remaining.reduce(0) { $0 + $1.amount }
        }
        assets.updatedAt = .now
    }

    private struct ItemState {
        let item: AssetItem
        let name: String
        let amount: Double
        let sortOrder: Int
        let updatedAt: Date
    }

    private static func snapshot(_ items: [AssetItem]) -> [ItemState] {
        items.map { ItemState(item: $0, name: $0.name, amount: $0.amount, sortOrder: $0.sortOrder, updatedAt: $0.updatedAt) }
    }

    private static func restore(_ states: [ItemState]) {
        for state in states {
            state.item.name = state.name
            state.item.amount = state.amount
            state.item.sortOrder = state.sortOrder
            state.item.updatedAt = state.updatedAt
        }
    }
}
