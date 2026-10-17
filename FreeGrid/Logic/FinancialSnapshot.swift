// 从原始账目得到当前财务摘要。它只是计算结果，不是另一份数据库或缓存。

import Foundation

/// 自由天数的口径：资产（锁定的钱）算不算进去。默认算；关掉后只按现金算，净值不受影响。
/// 资产没拆分时由总开关决定；拆成多项（Pro）后每一项自己决定，总开关不再参与。
enum FreedomSettings {
    static let countsAssetsKey = "countAssetsInFreedom"

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
    /// 实际生效的总开关：有资产项时恒为开，由各项自己决定算不算
    let countsAssets: Bool
    let lockedAssets: Double
    /// Pro 逐项开关：关掉「计入自由天数」的那些资产项金额之和。没有资产项时是 0。
    let excludedItemAssets: Double
    let cash: Double
    let totalExpenses: Double
    let firstExpenseDate: Date?
    let trackDays: Int
    let dailyBurn: Double
    /// 记账不满 90 天、有大额支出被摊开算时，摊开的那几笔加起来是多少；否则是 0（见 `FreedomMath.burnEstimate`）
    let spreadLumps: Double
    /// 算日均的那些支出。记一笔的预览要在它上面加一笔重新估日均
    let burnEntries: [FreedomMath.BurnEntry]
    let dailyPassive: Double
    let hasExpenses: Bool
    /// 固定支出和贷款：今天之后要扣的钱。没有时为空，自由天数和以前一分不差
    let loanPlan: LoanSchedule.Plan
    /// 固定支出和还没还清的贷款折成每天多少（每月 ÷ 30，和被动收入同一个折法）
    let dailyFixed: Double
    let now: Date

    var netWorth: Double { lockedAssets + cash }
    /// 画成金色格子、并算进自由天数的那部分资产。
    /// 没拆分：总开关关 → 不算；拆成多项：资产桶减去逐项关掉的那些。
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
    /// 被动收入能盖住多少开销：日常开销加上固定支出和月供。只比日常会在有房租、贷款时虚高
    var passiveRatio: Double {
        FreedomMath.passiveRatio(dailyPassive: dailyPassive,
                                 dailyBurn: dailyBurn.isFinite ? dailyBurn + dailyFixed : dailyBurn)
    }
    /// 有固定支出或贷款时按日历推演（见 `FreedomMath.freedomRun`），没有贷款时就是「钱 ÷ 每日净消耗」
    var freedomRun: FreedomMath.FreedomRun {
        FreedomMath.freedomRun(
            netWorth: freedomBase, dailyBurn: dailyBurn,
            dailyPassive: dailyPassive, hasExpenses: hasExpenses, loans: loanPlan
        )
    }
    var freedom: FreedomState { freedomRun.state }

    /// `assetItems` 只用来知道哪些项不计入；资产总数仍以 `assets.lockedAssets` 为准。
    /// 日均消费只算 `countsInBurn` 的支出：自动扣的房租、月供和确认过的旧记录扣了现金，但不算日常开销。
    init(expenses: [Expense], passiveSources: [PassiveSource], assets: UserAssets?,
         assetItems: [AssetItem] = [], loans: [Loan] = [], now: Date = .now,
         countsAssets: Bool = FreedomSettings.countsAssets) {
        self.countsAssets = assetItems.isEmpty ? countsAssets : true
        lockedAssets = assets?.lockedAssets ?? 0
        excludedItemAssets = FreedomSettings.excludedAmount(of: assetItems)
        cash = assets?.cash ?? 0
        burnEntries = FreedomMath.burnEntries(expenses)
        let burn = FreedomMath.burnEstimate(burnEntries, now: now)
        totalExpenses = burn.total
        firstExpenseDate = burn.firstDate
        trackDays = burn.trackDays
        dailyBurn = burn.dailyBurn
        spreadLumps = burn.spreadLumps
        dailyPassive = FreedomMath.dailyPassive(sources: passiveSources)
        hasExpenses = !burnEntries.isEmpty
        loanPlan = LoanSchedule.plan(loans: loans, payments: expenses, now: now)
        dailyFixed = LoanSchedule.monthlyTotal(loans: loans, payments: expenses, now: now) / 30
        self.now = now
    }
}
