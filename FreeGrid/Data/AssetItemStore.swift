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
    case notEnough(name: String, available: Double)

    var errorDescription: String? {
        switch self {
        case .invalidName: return "资产项名称请填写 1–20 个字，不包含换行。"
        case .invalidAmount: return "金额不对，或者超出了能记的范围。"
        case .missingItem: return "这一项已经不在账本里。"
        case .hasItems: return "资产已经拆成多项，请在资产明细里修改。"
        case .needsItem: return "请先选择是哪一项资产。"
        case .notEnough(let name, let available):
            return "「\(name)」只有 ¥\(available.formatted(.number))，拆不出这么多。"
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

    /// 老用户第一次拆分：原来的总数变成一项「资产」，净值和自由天数不变。
    /// `countsInFreedom` 传拆分前总开关的状态：拆开以后由各项自己决定，原来没算的那笔钱拆开后仍然不算。
    /// 已经有项，或总数是 0 时什么都不做，返回 nil。
    @discardableResult
    static func migrateIfNeeded(
        in context: ModelContext,
        countsInFreedom: Bool = true,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> AssetItem? {
        guard let item = try unsplitItem(in: context, countsInFreedom: countsInFreedom) else { return nil }
        try LedgerStore.updateAssets(in: context, save: save) { _ in
            context.insert(item)
        }
        return item
    }

    /// 拆分时原来的总数变成的那一项，还没插进账本。已经有项，或总数是 0 时为 nil
    private static func unsplitItem(in context: ModelContext, countsInFreedom: Bool) throws -> AssetItem? {
        guard try items(in: context).isEmpty,
              let assets = try context.fetch(FetchDescriptor<UserAssets>()).first,
              assets.lockedAssets > 0 else { return nil }
        return AssetItem(name: "资产", amount: assets.lockedAssets, sortOrder: 0, countsInFreedom: countsInFreedom)
    }

    /// 新加的一项从哪来：新增的钱（总数变大），或者从已有的一项里拆出来（总数不变）
    enum Source: Hashable {
        /// 还没拆过时的那个总数；拆分时它先变成一项「资产」
        case unsplitTotal
        case item(UUID)
    }

    /// 新增（existing 为 nil）或修改一项。`countsInFreedom` 为 nil 时保持原样（新增的项默认计入）。
    /// `source` 只对新增有效：给了就从那一项里扣掉同样的金额，不够扣时报 `notEnough`。
    /// `totalCounts` 是拆分前总开关的状态，只在这次新增触发拆分时用到。
    @discardableResult
    static func save(
        _ existing: AssetItem?, name: String, amount: Double, countsInFreedom: Bool? = nil,
        source: Source? = nil, totalCounts: Bool = true,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> AssetItem {
        let name = try cleanName(name)
        let amount = try validAmount(amount)
        // 还没拆过就直接加第一项：先把原来的总数变成一项，否则总数会被新的这一项顶掉。
        // 和新的这一项在同一次保存里，加不成时账本也不会只拆了一半
        let migrated = existing == nil ? try unsplitItem(in: context, countsInFreedom: totalCounts) : nil
        let all = try items(in: context) + (migrated.map { [$0] } ?? [])
        let from: AssetItem?
        switch existing == nil ? source : nil {
        case .unsplitTotal: from = migrated
        case .item(let id): from = all.first { $0.id == id }
        case nil: from = nil
        }
        if let from, amount > from.amount + FinancialLimits.assetChecksumTolerance {
            throw AssetItemError.notEnough(name: from.name, available: from.amount)
        }
        let item = existing ?? AssetItem(name: name, amount: amount, sortOrder: (all.map(\.sortOrder).max() ?? -1) + 1)
        let previous = snapshot(all)
        let previousItem = (item.name, item.amount, item.countsInFreedom, item.updatedAt)
        try LedgerStore.updateAssets(in: context, save: save, restore: {
            restore(previous)
            (item.name, item.amount, item.countsInFreedom, item.updatedAt) = previousItem
        }) { assets in
            if let migrated { context.insert(migrated) }
            if existing == nil { context.insert(item) }
            item.name = name
            item.amount = amount
            if let countsInFreedom { item.countsInFreedom = countsInFreedom }
            item.updatedAt = .now
            if let from {
                from.amount = max(0, from.amount - amount)
                from.updatedAt = .now
            }
            try syncTotal(assets, in: context)
        }
        return item
    }

    /// 只改这一项算不算进自由天数（列表上点方格）
    static func setCountsInFreedom(
        _ counts: Bool, for item: AssetItem,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws {
        let previous = (item.countsInFreedom, item.updatedAt)
        try LedgerStore.perform(in: context, save: save, restore: {
            (item.countsInFreedom, item.updatedAt) = previous
        }) {
            item.countsInFreedom = counts
            item.updatedAt = .now
        }
    }

    /// 拆分以前关着总开关、拆分后又没让各项接手的旧状态（只在开发版出现过）：
    /// 把各项都标成不计入，自由天数和以前一样。有改动时返回 true，调用方随后把总开关打开。
    @discardableResult
    static func adoptSwitchOff(
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> Bool {
        let all = try items(in: context)
        guard !all.isEmpty else { return false }
        let previous = snapshot(all)
        try LedgerStore.perform(in: context, save: save, restore: { restore(previous) }) {
            for item in all { item.countsInFreedom = false }
        }
        return true
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

    /// 调整顺序：把 `item` 挪到第 `index` 位。顺序只影响列表、净值分段和调拨菜单，不影响金额
    static func move(
        _ item: AssetItem, to index: Int,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws {
        var all = try items(in: context)
        guard let from = all.firstIndex(where: { $0.id == item.id }) else { return }
        let target = max(0, min(all.count - 1, index))
        guard target != from else { return }
        let previous = all.map { ($0, $0.sortOrder) }
        all.insert(all.remove(at: from), at: target)
        try LedgerStore.perform(in: context, save: save, restore: {
            for (entry, order) in previous { entry.sortOrder = order }
        }) {
            for (order, entry) in all.enumerated() { entry.sortOrder = order }
        }
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
        let countsInFreedom: Bool
        let updatedAt: Date
    }

    private static func snapshot(_ items: [AssetItem]) -> [ItemState] {
        items.map { ItemState(item: $0, name: $0.name, amount: $0.amount, sortOrder: $0.sortOrder,
                              countsInFreedom: $0.countsInFreedom, updatedAt: $0.updatedAt) }
    }

    private static func restore(_ states: [ItemState]) {
        for state in states {
            state.item.name = state.name
            state.item.amount = state.amount
            state.item.sortOrder = state.sortOrder
            state.item.countsInFreedom = state.countsInFreedom
            state.item.updatedAt = state.updatedAt
        }
    }
}
