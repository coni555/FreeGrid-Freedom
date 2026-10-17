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

    /// Pro 现金账户的逐个开关：不计入的那些账户余额之和。扣成负数的账户不算（不计入的钱不会让自由天数变多）。
    static func excludedCash(of accounts: [CashAccount]) -> Double {
        accounts.reduce(0) { $1.countsInFreedom ? $0 : $0 + max(0, $1.amount) }
    }
}

struct FinancialSnapshot {
    /// 实际生效的总开关：有资产项时恒为开，由各项自己决定算不算
    let countsAssets: Bool
    let lockedAssets: Double
    /// Pro 逐项开关：关掉「计入自由天数」的那些资产项金额之和。没有资产项时是 0。
    let excludedItemAssets: Double
    let cash: Double
    /// Pro 现金账户：关掉「计入自由天数」的那些账户余额之和。没有账户或都计入时是 0。
    let excludedCash: Double
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
    /// 画成蓝色格子、并算进自由天数的现金
    var countedCash: Double { cash - excludedCash }
    /// 用来算自由天数的钱：计入的现金加计入的资产。都计入时就是净值，和以前一分不差
    var freedomBase: Double {
        let base = countsAssets && excludedItemAssets == 0 ? netWorth : cash + countedAssets
        return excludedCash == 0 ? base : base - excludedCash
    }
    /// 首页图例旁的说明：都计入时没有；资产一点没计入是「资产未计入」，只算了一部分是「部分资产未计入」；
    /// 有现金账户没计入时是「部分现金未计入」；两样都有时合成一句
    var uncountedAssetsNote: String? {
        let assetNote = uncountedAssets > 0 ? (countedAssets > 0 ? "部分资产" : "资产") : nil
        let cashNote = excludedCash > 0 ? (countedCash > 0 ? "部分现金" : "现金") : nil
        switch (assetNote, cashNote) {
        case (nil, nil): return nil
        case (let asset?, nil): return asset + "未计入"
        case (nil, let cash?): return cash + "未计入"
        case (_?, _?): return "部分资金未计入"
        }
    }
    /// 有不计入自由天数的钱（资产或现金）。趋势往回推时这部分算不清，早期的 0 不写出来
    var hasUncountedMoney: Bool { !countsAssets || uncountedAssets > 0 || excludedCash > 0 }
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

    /// `assetItems`、`cashAccounts` 只用来知道哪些项不计入；资产、现金总数仍以 `assets` 为准。
    /// 日均消费只算 `countsInBurn` 的支出：自动扣的房租、月供和确认过的旧记录扣了现金，但不算日常开销。
    init(expenses: [Expense], passiveSources: [PassiveSource], assets: UserAssets?,
         assetItems: [AssetItem] = [], cashAccounts: [CashAccount] = [], loans: [Loan] = [], now: Date = .now,
         countsAssets: Bool = FreedomSettings.countsAssets) {
        self.countsAssets = assetItems.isEmpty ? countsAssets : true
        lockedAssets = assets?.lockedAssets ?? 0
        excludedItemAssets = FreedomSettings.excludedAmount(of: assetItems)
        cash = assets?.cash ?? 0
        excludedCash = FreedomSettings.excludedCash(of: cashAccounts)
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
