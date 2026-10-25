// 离职 / GAP 倒计时：定一个离开的日期，算离那天还有几天、那天大约有多少天自由；可以再定一个「想撑多久」，看够不够。
// 目标存在本机偏好里，不进备份；「多少天自由」和首页的自由天数是同一个口径（计入的钱、固定支出按日历扣、被动收入抵开销）。

import Foundation

struct FreedomGoal: Equatable {
    /// 打算哪天走
    var leaveDate: Date
    /// 想撑多少天；nil 表示不设，只看那天有多少天自由
    var targetDays: Int?

    static let leaveDateKey = "gapLeaveDate"
    static let targetDaysKey = "gapTargetDays"
    /// 自己填的每月到手收入。和目标分开存：清掉目标不清收入，「每月有结余」那一项也用它
    static let incomeKey = "gapMonthlyIncome"

    /// 「想撑多久」的三档：半年、一年、两年
    static let targetChoices = [183, 365, 730]

    /// 从偏好里的两个值拼出目标；没设日期时是 nil
    init?(leaveDate: Double?, targetDays: Int) {
        guard let leaveDate else { return nil }
        self.init(leaveDate: Date(timeIntervalSince1970: leaveDate), targetDays: targetDays > 0 ? targetDays : nil)
    }

    init(leaveDate: Date, targetDays: Int? = nil) {
        self.leaveDate = leaveDate
        self.targetDays = targetDays
    }

    /// 「一年」「半年」这样的说法，卡上写「够撑一年」
    static func targetName(_ days: Int) -> String {
        switch days {
        case 183: return String(localized: "半年")
        case 365: return String(localized: "一年")
        case 730: return String(localized: "两年")
        default: return String(localized: "\(days) 天")
        }
    }
}

/// 每月到手收入从哪来
enum IncomeBasis: Equatable {
    /// 自己在目标面板里填的
    case entered
    /// 按近 90 天记下的收入推算
    case recorded
}

/// 每月能存下多少：收入加被动收入，减去界面上的日均消费（日常 + 固定支出折算）
struct MonthlySaving: Equatable {
    let income: Double
    let basis: IncomeBasis
    let perDay: Double
    var perMonth: Double { perDay * FreedomMath.GridUnit.month.daysPerCell }
}

enum FreedomGoalMath {
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

    /// 有多少计入的钱时能撑多少天；和首页一样按日历扣固定支出和贷款
    static func freedom(base: Double, snapshot: FinancialSnapshot) -> FreedomState {
        FreedomMath.freedomRun(netWorth: base, dailyBurn: snapshot.dailyBurn, dailyPassive: snapshot.dailyPassive,
                               hasExpenses: snapshot.hasExpenses, loans: snapshot.loanPlan).state
    }

    struct Result: Equatable {
        let goal: FreedomGoal
        /// 离那天还有几天；0 是今天，负数是已经过了
        let daysUntil: Int
        /// 那天大约有多少天自由。知道每月存多少时按它推到那天；不知道时就是现在的自由天数
        let freedom: FreedomState
        /// 有没有按每月存下的钱往后推；false 时卡上写「现在有」，并提示填收入
        let projected: Bool
        let saving: MonthlySaving?

        /// 那天的自由天数占目标多少，0...1；没设目标或算不出来时为 nil
        var progress: Double? {
            guard let target = goal.targetDays else { return nil }
            switch freedom {
            case .covered: return 1
            case .finite(let days): return min(1, max(0, days / Double(target)))
            case .insufficientData, .invalidData: return nil
            }
        }

        /// 够撑满目标；没设目标或算不出来时为 nil
        var enough: Bool? { progress.map { $0 >= 1 } }
    }

    /// 那天的钱 = 现在计入的钱 + 每天存下的 × 离那天的天数（存不下时往下减，最少到 0），再按首页同一套推演算能撑多久。
    /// 推演用的是现在的固定支出和还款计划，贷款快还完时会偏保守
    static func evaluate(goal: FreedomGoal, snapshot: FinancialSnapshot, saving: MonthlySaving?,
                         calendar: Calendar = .current) -> Result {
        let today = calendar.startOfDay(for: snapshot.now)
        let daysUntil = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: goal.leaveDate)).day ?? 0
        guard let saving, snapshot.hasExpenses else {
            return Result(goal: goal, daysUntil: daysUntil, freedom: snapshot.freedom, projected: false, saving: saving)
        }
        let base = max(0, snapshot.freedomBase + saving.perDay * Double(max(0, daysUntil)))
        return Result(goal: goal, daysUntil: daysUntil, freedom: freedom(base: base, snapshot: snapshot),
                      projected: true, saving: saving)
    }
}

// MARK: - 界面上的说法（自检页的卡、设置页那张卡、目标面板共用）

extension FreedomGoalMath {
    /// 按每月存多少推算的、收入是哪来的
    static func savingText(_ saving: MonthlySaving) -> String {
        let amount = FinancialFormatting.wholeNumber(abs(saving.perMonth))
        switch (saving.perDay > 0, saving.basis) {
        case (true, .entered): return String(localized: "按每月约存 ¥\(amount) 算 · 你填的收入")
        case (true, .recorded): return String(localized: "按每月约存 ¥\(amount) 算 · 近 90 天的收入记录")
        case (false, .entered): return String(localized: "按每月约多花 ¥\(amount) 算 · 你填的收入")
        case (false, .recorded): return String(localized: "按每月约多花 ¥\(amount) 算 · 近 90 天的收入记录")
        }
    }
}

extension FreedomGoalMath.Result {
    /// 那天的自由天数取整，是个大约的数，不写小数
    var freedomDaysText: String? {
        guard case .finite(let days) = freedom else { return nil }
        return FinancialFormatting.wholeNumber(max(0, days).rounded())
    }

    /// 卡上分隔线下那一句：那天大约有多少天自由
    var freedomLine: String {
        switch freedom {
        case .covered: return String(localized: "被动收入已经盖住开销")
        case .insufficientData, .invalidData: return String(localized: "记下支出、算出日均后才能算")
        case .finite:
            let days = freedomDaysText ?? "0"
            return projected ? String(localized: "那天大约有 \(days) 天自由") : String(localized: "现在有 \(days) 天自由")
        }
    }

    /// 进度条旁边：够撑满目标，或者还差几天自由（是自由天数差多少，不是离那天还有几天）
    var targetLine: String? {
        guard let target = goal.targetDays, let enough else { return nil }
        let name = FreedomGoal.targetName(target)
        if enough { return String(localized: "够撑\(name)") }
        guard case .finite(let days) = freedom else { return nil }
        let short = FinancialFormatting.wholeNumber((Double(target) - days).rounded(.up))
        return String(localized: "想撑\(name)，还差 \(short) 天自由")
    }

    /// 一句话的倒数：「GAP · 189 天后」，留给锁屏小组件这种只放得下一行的地方
    var countdownLine: String {
        if daysUntil > 0 { return String(localized: "GAP · \(daysUntil) 天后") }
        if daysUntil == 0 { return String(localized: "GAP · 就是今天") }
        return String(localized: "GAP · 这一天已经过了")
    }
}
