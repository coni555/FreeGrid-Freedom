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
    let newDailyBurn: Double
    let newFreedom: FreedomState
    let changesTrackingStart: Bool

    var freedomChange: Double? {
        guard case .finite(let oldDays) = before.freedom,
              case .finite(let newDays) = newFreedom else { return nil }
        return newDays - oldDays
    }

    init(snapshot: FinancialSnapshot, kind: TransactionKind, amount: Double, date: Date? = nil) {
        before = snapshot
        self.kind = kind
        cashChange = kind.cashChange(amount: amount)
        newNetWorth = snapshot.netWorth + cashChange

        if kind == .expense {
            let transactionDate = date ?? snapshot.now
            let firstDate = min(snapshot.firstExpenseDate ?? transactionDate, transactionDate)
            let newDays = FreedomMath.trackDays(firstRecordDate: firstDate, now: snapshot.now)
            newDailyBurn = FreedomMath.dailyBurn(
                totalExpenses: snapshot.totalExpenses + amount, trackDays: newDays
            )
            changesTrackingStart = snapshot.hasExpenses && newDays != snapshot.trackDays
        } else {
            newDailyBurn = snapshot.dailyBurn
            changesTrackingStart = false
        }
        newFreedom = FreedomMath.freedomState(
            netWorth: newNetWorth, dailyBurn: newDailyBurn,
            dailyPassive: snapshot.dailyPassive,
            hasExpenses: snapshot.hasExpenses || kind == .expense
        )
    }
}
