// 从原始账目得到当前财务摘要。它只是计算结果，不是另一份数据库或缓存。

import Foundation

/// 自由天数的口径：资产（锁定的钱）算不算进去。默认算；关掉后只按现金算，净值不受影响。
enum FreedomSettings {
    static let countsAssetsKey = "countAssetsInFreedom"
    static var countsAssets: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: countsAssetsKey) == nil || defaults.bool(forKey: countsAssetsKey)
    }
}

struct FinancialSnapshot {
    let countsAssets: Bool
    let lockedAssets: Double
    let cash: Double
    let totalExpenses: Double
    let firstExpenseDate: Date?
    let trackDays: Int
    let dailyBurn: Double
    let dailyPassive: Double
    let hasExpenses: Bool
    let now: Date

    var netWorth: Double { lockedAssets + cash }
    /// 用来算自由天数的钱：资产不计入时只有现金
    var freedomBase: Double { countsAssets ? netWorth : cash }
    /// 画成金色格子的那部分
    var countedAssets: Double { countsAssets ? lockedAssets : 0 }
    var passiveRatio: Double {
        FreedomMath.passiveRatio(dailyPassive: dailyPassive, dailyBurn: dailyBurn)
    }
    var freedom: FreedomState {
        FreedomMath.freedomState(
            netWorth: freedomBase, dailyBurn: dailyBurn,
            dailyPassive: dailyPassive, hasExpenses: hasExpenses
        )
    }

    init(expenses: [Expense], passiveSources: [PassiveSource], assets: UserAssets?, now: Date = .now,
         countsAssets: Bool = FreedomSettings.countsAssets) {
        self.countsAssets = countsAssets
        lockedAssets = assets?.lockedAssets ?? 0
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
