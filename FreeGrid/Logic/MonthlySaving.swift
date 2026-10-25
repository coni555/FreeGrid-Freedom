// 每月能存下多少：自检里「每月有结余」那一项用（免费）。收入优先用自己填的，没填按近 90 天的收入记录推算。
// 自己填的收入存在本机偏好里，不进备份。

import Foundation

/// 每月到手收入从哪来
enum IncomeBasis: Equatable {
    /// 自己在「每月有结余」那一行填的
    case entered
    /// 按近 90 天记下的收入推算
    case recorded
}

/// 每月能存下多少：收入加被动收入，减去界面上的日均消费（日常 + 固定支出折算）
struct MonthlySaving: Equatable {
    /// 自己填的每月到手收入。key 沿用 GAP 那一版的名字，分支上填过的收入不丢
    static let incomeKey = "gapMonthlyIncome"

    let income: Double
    let basis: IncomeBasis
    let perDay: Double
    var perMonth: Double { perDay * FreedomMath.GridUnit.month.daysPerCell }
}

enum SavingMath {
    /// 用记录推算收入，至少要有这么多天的收入记录，太短的一两笔工资会把每月算偏
    static let recordedIncomeMinDays = 60
    static let recordedIncomeWindow = 90

    /// 近 90 天记下的上班收入折成每月。被动收入不算，它已经按「被动收入」那一栏抵了开销
    static func recordedMonthlyIncome(_ incomes: [Income], now: Date = .now, calendar: Calendar = .current) -> Double? {
        let active = incomes.filter { !$0.isPassive && $0.amount > 0 }
        guard let first = active.map(\.date).min() else { return nil }
        let today = calendar.startOfDay(for: now)
        let span = calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: today).day ?? 0
        guard span >= recordedIncomeMinDays,
              let windowStart = calendar.date(byAdding: .day, value: -recordedIncomeWindow, to: today) else { return nil }
        let days = min(span, recordedIncomeWindow)
        let total = active.filter { $0.date >= windowStart && $0.date <= now }.reduce(0) { $0 + $1.amount }
        return total / Double(days) * FreedomMath.GridUnit.month.daysPerCell
    }

    /// 填过就用填的，没填按记录；两样都没有时算不出来
    static func saving(snapshot: FinancialSnapshot, enteredIncome: Double?, recordedIncome: Double?) -> MonthlySaving? {
        guard snapshot.hasExpenses, snapshot.dailyCost.isFinite else { return nil }
        let pick: (Double, IncomeBasis)?
        if let enteredIncome, enteredIncome.isFinite, enteredIncome >= 0 {
            pick = (enteredIncome, .entered)
        } else if let recordedIncome {
            pick = (recordedIncome, .recorded)
        } else {
            pick = nil
        }
        guard let (income, basis) = pick else { return nil }
        let perDay = income / FreedomMath.GridUnit.month.daysPerCell + snapshot.dailyPassive - snapshot.dailyCost
        return MonthlySaving(income: income, basis: basis, perDay: perDay)
    }
}
