// 一笔交易会怎样改变净值、日均消费和自由天数。
// 真实表单与模拟页共用这里；这个类型不会保存或修改任何模型。

import Foundation

enum TransactionKind: CaseIterable, Hashable {
    case expense, income

    func cashChange(amount: Double) -> Double {
        self == .expense ? -amount : amount
    }
}

struct TransactionImpact {
    let before: FinancialSnapshot
    let kind: TransactionKind
    let cashChange: Double
    let newNetWorth: Double
    /// 这笔之后用来算自由天数的钱；资产不计入时和净值不是一个数
    let newFreedomBase: Double
    let newDailyBurn: Double
    let newFreedom: FreedomState
    let changesTrackingStart: Bool

    var freedomChange: Double? {
        guard case .finite(let oldDays) = before.freedom,
              case .finite(let newDays) = newFreedom else { return nil }
        return newDays - oldDays
    }

    /// `countsInFreedom`：这笔从（或进）的现金账户算不算进自由天数。不算时净值照变，自由天数里的钱不变，
    /// 支出仍然算进日均。
    init(snapshot: FinancialSnapshot, kind: TransactionKind, amount: Double, date: Date? = nil,
         countsInFreedom: Bool = true) {
        before = snapshot
        self.kind = kind
        cashChange = kind.cashChange(amount: amount)
        newNetWorth = snapshot.netWorth + cashChange
        newFreedomBase = countsInFreedom ? snapshot.freedomBase + cashChange : snapshot.freedomBase

        if kind == .expense {
            let entry = FreedomMath.BurnEntry(date: date ?? snapshot.now, amount: amount)
            let burn = FreedomMath.burnEstimate(snapshot.burnEntries + [entry], now: snapshot.now)
            newDailyBurn = burn.dailyBurn
            changesTrackingStart = snapshot.hasExpenses && burn.trackDays != snapshot.trackDays
        } else {
            newDailyBurn = snapshot.dailyBurn
            changesTrackingStart = false
        }
        newFreedom = FreedomMath.freedomRun(
            netWorth: newFreedomBase, dailyBurn: newDailyBurn,
            dailyPassive: snapshot.dailyPassive,
            hasExpenses: snapshot.hasExpenses || kind == .expense,
            loans: snapshot.loanPlan
        ).state
    }
}
