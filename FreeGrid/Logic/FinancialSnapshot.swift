// 从原始账目得到当前财务摘要。它只是计算结果，不是另一份数据库或缓存。

import Foundation

struct FinancialSnapshot {
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
    var passiveRatio: Double {
        FreedomMath.passiveRatio(dailyPassive: dailyPassive, dailyBurn: dailyBurn)
    }
    var freedom: FreedomState {
        FreedomMath.freedomState(
            netWorth: netWorth, dailyBurn: dailyBurn,
            dailyPassive: dailyPassive, hasExpenses: hasExpenses
        )
    }

    init(expenses: [Expense], passiveSources: [PassiveSource], assets: UserAssets?, now: Date = .now) {
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
