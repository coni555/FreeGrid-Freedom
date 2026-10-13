// 从原始账目得到当前财务摘要。它只是计算结果，不是另一份数据库或缓存。

import Foundation

/// 自由天数的口径：资产（锁定的钱）算不算进去。默认算；关掉后只按现金算，净值不受影响。
enum FreedomSettings {
    static let countsAssetsKey = "countAssetsInFreedom"
    #if DEBUG
    /// 仅 Debug 生效：资产不计入时首页格子的画法，`drop`（方案 A，默认）或 `hollow`（方案 B）。
    /// 用户选定后删掉另一种。
    static let uncountedAssetStyleKey = "uncountedAssetStyle"
    #endif

    /// 本机偏好，不进备份。没设过时是开。
    static func isOn(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: countsAssetsKey) == nil || defaults.bool(forKey: countsAssetsKey)
    }

    static var countsAssets: Bool { isOn(in: AppPreferences.store) }

    /// Pro 逐项开关：不计入自由天数的那些资产项加起来是多少。
    /// 没有 Pro 时照样按各项原来的设置算（退款后数字不会突然变大）。
    static func excludedAmount(of items: [AssetItem]) -> Double {
        items.reduce(0) { $1.countsInFreedom ? $0 : $0 + $1.amount }
    }
}

struct FinancialSnapshot {
    let countsAssets: Bool
    let lockedAssets: Double
    /// Pro 逐项开关：关掉「计入自由天数」的那些资产项金额之和。没有资产项时是 0。
    let excludedItemAssets: Double
    let cash: Double
    let totalExpenses: Double
    let firstExpenseDate: Date?
    let trackDays: Int
    let dailyBurn: Double
    let dailyPassive: Double
    let hasExpenses: Bool
    let now: Date

    var netWorth: Double { lockedAssets + cash }
    /// 画成金色格子、并算进自由天数的那部分资产。
    /// 总开关是总闸：关 → 一项都不算；开 → 资产桶减去逐项关掉的那些。
    /// 用「总数减不计入」而不是「计入项相加」；没有逐项关掉的时候直接用总数，和以前的数一分不差。
    var countedAssets: Double {
        guard countsAssets else { return 0 }
        return excludedItemAssets == 0 ? lockedAssets : max(0, lockedAssets - excludedItemAssets)
    }
    /// 在净值里、但没算进自由天数的资产
    var uncountedAssets: Double { lockedAssets - countedAssets }
    /// 用来算自由天数的钱：现金加计入的资产
    var freedomBase: Double { countsAssets && excludedItemAssets == 0 ? netWorth : cash + countedAssets }
    /// 首页图例旁的说明：资产全部计入时没有；一点没计入是「资产未计入」，只算了一部分是「部分资产未计入」
    var uncountedAssetsNote: String? {
        guard uncountedAssets > 0 else { return nil }
        return countedAssets > 0 ? "部分资产未计入" : "资产未计入"
    }
    var passiveRatio: Double {
        FreedomMath.passiveRatio(dailyPassive: dailyPassive, dailyBurn: dailyBurn)
    }
    var freedom: FreedomState {
        FreedomMath.freedomState(
            netWorth: freedomBase, dailyBurn: dailyBurn,
            dailyPassive: dailyPassive, hasExpenses: hasExpenses
        )
    }

    /// `assetItems` 只用来知道哪些项不计入；资产总数仍以 `assets.lockedAssets` 为准。
    init(expenses: [Expense], passiveSources: [PassiveSource], assets: UserAssets?,
         assetItems: [AssetItem] = [], now: Date = .now,
         countsAssets: Bool = FreedomSettings.countsAssets) {
        self.countsAssets = countsAssets
        lockedAssets = assets?.lockedAssets ?? 0
        excludedItemAssets = FreedomSettings.excludedAmount(of: assetItems)
        cash = assets?.cash ?? 0
        totalExpenses = expenses.reduce(0) { $0 + $1.amount }
        firstExpenseDate = FreedomMath.earliestExpenseDate(expenses)
        trackDays = FreedomMath.trackDays(firstRecordDate: firstExpenseDate, now: now)
        dailyBurn = FreedomMath.dailyBurn(totalExpenses: totalExpenses, trackDays: trackDays)
        dailyPassive = FreedomMath.dailyPassive(sources: passiveSources)
        hasExpenses = !expenses.isEmpty
        self.now = now
    }
}
