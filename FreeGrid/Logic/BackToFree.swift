// 体验结束或退款后，体验期间加的 Pro 内容怎么回到免费版：哪些要整理、整理后自由天数变成多少。
// 用户 2026-10-18：不想买断的人要有引导，告诉他怎么回到免费版正常用。

import Foundation

struct BackToFreePlan: Equatable {
    /// 拆出来的资产项。合并回一个总数后，免费版就能直接改资产
    let assetItems: [String]
    /// 设成不计入自由天数的资产项
    let excludedAssets: [String]
    /// 合并后资产整体算不算进自由天数：只要有一项算着就算，一项都没算就不算（见 `AssetItemStore.switchAfterMerging`）
    let assetsCountAfterMerging: Bool
    let cashAccounts: [String]
    let excludedCash: [String]
    /// 带期数的贷款（Pro）。没有 Pro 时停用：不自动记账、不算进自由天数，只能删，重新解锁后恢复。
    /// 不限期的固定支出是免费的，不算在这里
    let loans: [String]

    init(assetItems: [AssetItem], cashAccounts: [CashAccount], loans: [Loan]) {
        self.assetItems = assetItems.map(\.name)
        excludedAssets = assetItems.filter { !$0.countsInFreedom }.map(\.name)
        assetsCountAfterMerging = AssetItemStore.switchAfterMerging(assetItems)
        self.cashAccounts = cashAccounts.map(\.name)
        excludedCash = cashAccounts.filter { !$0.countsInFreedom }.map(\.name)
        self.loans = loans.filter { !$0.isOngoing }.map(\.name)
    }

    /// 有要整理或要说明的东西。只用了分类、视图、自由卡的人什么都不用做，不弹引导
    var hasProContent: Bool { !assetItems.isEmpty || !cashAccounts.isEmpty || !loans.isEmpty }

    /// 还剩几样要调整（资产、现金、贷款各算一样）。设置页 Pro 卡写「2 项待调整」
    var pendingCount: Int { [!assetItems.isEmpty, !cashAccounts.isEmpty, !loans.isEmpty].filter { $0 }.count }

    /// 购买卡上那句：保留的是哪些
    var keepLine: String {
        let accounts = !assetItems.isEmpty || !cashAccounts.isEmpty
        switch (accounts, !loans.isEmpty) {
        case (true, true): return String(localized: "保留子账户和贷款，继续使用全部功能")
        case (true, false): return String(localized: "保留子账户，继续使用全部功能")
        default: return String(localized: "保留贷款，继续使用全部功能")
        }
    }

    /// 合并后的自由天数：资产或现金换回一个总数，原来不计入的那部分也算进去。
    /// 资产总开关按合并时的规则接回去：只要有一项算着就开（见 `AssetItemStore.mergeIntoTotalKeepingSwitch`）
    static func freedomAfterMerging(assets mergeAssets: Bool, cash mergeCash: Bool,
                                    expenses: [Expense], passiveSources: [PassiveSource], assets: UserAssets?,
                                    assetItems: [AssetItem], cashAccounts: [CashAccount], loans: [Loan],
                                    now: Date = .now) -> FreedomState {
        let countsAssets = mergeAssets
            ? AssetItemStore.switchAfterMerging(assetItems)
            : FreedomSettings.countsAssets
        return FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assets,
                                 assetItems: mergeAssets ? [] : assetItems,
                                 cashAccounts: mergeCash ? [] : cashAccounts,
                                 loans: loans, now: now, countsAssets: countsAssets).freedom
    }
}
