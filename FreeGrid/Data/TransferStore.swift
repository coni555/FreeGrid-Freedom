// 调拨：在资产和现金之间、或者同一边的两个账户之间挪钱，净值不变。
// 拆过的一边必须指定是哪一项 / 哪个账户；没拆的一边就是那个总数。实际挪走的不超过来源里有的。

import Foundation
import SwiftData

@MainActor
enum TransferStore {
    enum Place: Hashable {
        case assetsTotal
        case assetItem(UUID)
        case cashTotal
        case cashAccount(UUID)

        var isCash: Bool {
            switch self {
            case .cashTotal, .cashAccount: return true
            case .assetsTotal, .assetItem: return false
            }
        }
    }

    enum TransferError: Error, LocalizedError {
        case samePlace
        case missingPlace

        var errorDescription: String? {
            switch self {
            case .samePlace: return "转出和转入是同一个地方。"
            case .missingPlace: return "这个账户或资产项已经不在账本里。"
            }
        }
    }

    /// 返回实际挪了多少
    @discardableResult
    static func transfer(
        _ amount: Double, from source: Place, to destination: Place,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> Double {
        guard FinancialFormatting.validAmount(amount) else { throw AssetItemError.invalidAmount }
        guard source != destination else { throw TransferError.samePlace }
        let items = try AssetItemStore.items(in: context)
        let accounts = try CashAccountStore.accounts(in: context)
        for place in [source, destination] {
            if place == .assetsTotal, !items.isEmpty { throw AssetItemError.hasItems }
            if place == .cashTotal, !accounts.isEmpty { throw CashAccountError.hasAccounts }
        }
        let itemState = items.map { ($0, $0.amount, $0.updatedAt) }
        var moved = 0.0
        try LedgerStore.updateAssets(in: context, save: save, restore: {
            for (item, amount, updated) in itemState { (item.amount, item.updatedAt) = (amount, updated) }
        }) { assets in
            moved = min(amount, max(0, try balance(of: source, assets: assets, items: items, accounts: accounts)))
            try change(source, by: -moved, assets: assets, items: items, accounts: accounts)
            try change(destination, by: moved, assets: assets, items: items, accounts: accounts)
            if !items.isEmpty { assets.lockedAssets = items.reduce(0) { $0 + $1.amount } }
            if !accounts.isEmpty { assets.cash = accounts.reduce(0) { $0 + $1.amount } }
            assets.updatedAt = .now
        }
        return moved
    }

    private static func balance(of place: Place, assets: UserAssets,
                                items: [AssetItem], accounts: [CashAccount]) throws -> Double {
        switch place {
        case .assetsTotal: return assets.lockedAssets
        case .cashTotal: return assets.cash
        case .assetItem(let id):
            guard let item = items.first(where: { $0.id == id }) else { throw TransferError.missingPlace }
            return item.amount
        case .cashAccount(let id):
            guard let account = accounts.first(where: { $0.id == id }) else { throw TransferError.missingPlace }
            return account.amount
        }
    }

    private static func change(_ place: Place, by delta: Double, assets: UserAssets,
                               items: [AssetItem], accounts: [CashAccount]) throws {
        switch place {
        case .assetsTotal: assets.lockedAssets += delta
        case .cashTotal: assets.cash += delta
        case .assetItem(let id):
            guard let item = items.first(where: { $0.id == id }) else { throw TransferError.missingPlace }
            item.amount += delta
            item.updatedAt = .now
        case .cashAccount(let id):
            guard let account = accounts.first(where: { $0.id == id }) else { throw TransferError.missingPlace }
            account.amount += delta
            account.updatedAt = .now
        }
    }
}
