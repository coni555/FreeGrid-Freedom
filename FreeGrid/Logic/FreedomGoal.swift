// 自己的目标（Pro）：想要多少天自由，加一个可选的截止日；两项至少填一项，最多三个。
// 只填天数：看现在离目标还差多少、按现在的速度每月能多几天；只填日子：倒数，看那天大约有多少天自由；两项都填：那天够不够。
// 目标存在本机偏好里（JSON），不进备份；「多少天自由」和首页的自由天数是同一个口径（计入的钱、固定支出按日历扣、被动收入抵开销）。

import Foundation

struct FreedomGoal: Codable, Equatable, Identifiable {
    var id = UUID()
    /// 自己起的名字，可以空着
    var name: String = ""
    /// 想要多少天自由；nil 表示不设，只看那天
    var targetDays: Int?
    /// 在哪天之前；nil 表示不设日子
    var deadline: Date?

    /// 天数和日子至少有一项
    var isValid: Bool { (targetDays ?? 0) > 0 || deadline != nil }

    /// 没起名字时：只定了天数叫「攒够一年」，有日子的叫「我的目标」
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if deadline == nil, let targetDays { return String(localized: "攒够\(Self.targetName(targetDays))") }
        return String(localized: "我的目标")
    }

    /// 自己填的每月到手收入。和目标分开存：删掉目标不清收入，「每月有结余」那一项也用它。
    /// key 沿用 GAP 那一版的名字，分支上填过的收入不丢
    static let incomeKey = "gapMonthlyIncome"

    /// 「想要多少天自由」的三档：半年、一年、两年；也可以自己填
    static let targetChoices = [183, 365, 730]
    /// 名字的几个备选
    static var nameSuggestions: [String] {
        [String(localized: "应急金"), "GAP", String(localized: "辞职"), String(localized: "毕业旅行")]
    }

    /// 「一年」「半年」这样的说法，卡上写「够撑一年」；不是三档之一时写天数
    static func targetName(_ days: Int) -> String {
        switch days {
        case 183: return String(localized: "半年")
        case 365: return String(localized: "一年")
        case 730: return String(localized: "两年")
        default: return String(localized: "\(days) 天")
        }
    }
}

/// 几个目标存成一串 JSON，放在本机偏好里
enum FreedomGoalStore {
    static let key = "freedomGoals"
    /// 最多三个
    static let limit = 3

    /// 读不出来的、天数和日子都没有的跳过
    static func decode(_ stored: String) -> [FreedomGoal] {
        guard let data = stored.data(using: .utf8),
              let goals = try? JSONDecoder().decode([FreedomGoal].self, from: data) else { return [] }
        return Array(goals.filter(\.isValid).prefix(limit))
    }

    static func encode(_ goals: [FreedomGoal]) -> String {
        guard !goals.isEmpty, let data = try? JSONEncoder().encode(Array(goals.prefix(limit))) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// 改了就替换，新的加在最后
    static func saving(_ goal: FreedomGoal, into goals: [FreedomGoal]) -> [FreedomGoal] {
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            var result = goals
            result[index] = goal
            return result
        }
        return Array((goals + [goal]).prefix(limit))
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
        /// 离那天还有几天；0 是今天，负数是已经过了；没定日子时为 nil
        let daysUntil: Int?
        /// 有日子时是那天大约有多少天自由（知道每月存多少时推到那天，不知道时是现在的）；没日子时是现在的自由天数
        let freedom: FreedomState
        /// 有没有按每月存下的钱往后推；false 时写「现在有」，并提示填收入
        let projected: Bool
        let saving: MonthlySaving?
        /// 按现在的速度，每过一个月自由天数大约变多少（存不下钱时是负的）；不知道收入或算不出来时为 nil
        let monthlyGain: Double?

        /// 那天（或现在）的自由天数占目标多少，0...1；没设天数或算不出来时为 nil
        var progress: Double? {
            guard let target = goal.targetDays else { return nil }
            switch freedom {
            case .covered: return 1
            case .finite(let days): return min(1, max(0, days / Double(target)))
            case .insufficientData, .invalidData: return nil
            }
        }

        /// 够了；没设天数或算不出来时为 nil
        var enough: Bool? { progress.map { $0 >= 1 } }
    }

    /// 有日子时：那天的钱 = 现在计入的钱 + 每天存下的 × 离那天的天数（存不下时往下减，最少到 0），再按首页同一套推演算能撑多久。
    /// 推演用的是现在的固定支出和还款计划，贷款快还完时会偏保守。日子过了不再往后推
    static func evaluate(goal: FreedomGoal, snapshot: FinancialSnapshot, saving: MonthlySaving?,
                         calendar: Calendar = .current) -> Result {
        let today = calendar.startOfDay(for: snapshot.now)
        let daysUntil = goal.deadline.map {
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: $0)).day ?? 0
        }
        guard let saving, snapshot.hasExpenses else {
            return Result(goal: goal, daysUntil: daysUntil, freedom: snapshot.freedom, projected: false,
                          saving: saving, monthlyGain: nil)
        }
        let gain = monthlyGain(snapshot: snapshot, saving: saving)
        guard let daysUntil else {
            return Result(goal: goal, daysUntil: nil, freedom: snapshot.freedom, projected: false,
                          saving: saving, monthlyGain: gain)
        }
        let base = max(0, snapshot.freedomBase + saving.perDay * Double(max(0, daysUntil)))
        return Result(goal: goal, daysUntil: daysUntil, freedom: freedom(base: base, snapshot: snapshot),
                      projected: daysUntil > 0, saving: saving, monthlyGain: gain)
    }

    /// 多存（或多花）一个月的钱，自由天数变多少：同一套推演算两次相减
    static func monthlyGain(snapshot: FinancialSnapshot, saving: MonthlySaving) -> Double? {
        guard case .finite(let now) = freedom(base: snapshot.freedomBase, snapshot: snapshot),
              case .finite(let later) = freedom(base: max(0, snapshot.freedomBase + saving.perMonth), snapshot: snapshot)
        else { return nil }
        return later - now
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
    /// 自由天数取整，是个大约的数，不写小数
    var freedomDaysText: String? {
        guard case .finite(let days) = freedom else { return nil }
        return FinancialFormatting.wholeNumber(max(0, days).rounded())
    }

    /// 有日子时：那天大约有多少天自由；没日子时：现在多少 / 目标多少
    var freedomLine: String {
        switch freedom {
        case .covered: return String(localized: "被动收入已经盖住开销")
        case .insufficientData, .invalidData: return String(localized: "记下支出、算出日均后才能算")
        case .finite:
            let days = freedomDaysText ?? "0"
            if goal.deadline == nil, let target = goal.targetDays {
                return String(localized: "现在 \(days) / \(target) 天")
            }
            return projected ? String(localized: "那天大约有 \(days) 天自由") : String(localized: "现在有 \(days) 天自由")
        }
    }

    /// 进度条旁边：够了，或者还差几天自由（是自由天数差多少，不是离那天还有几天）
    var targetLine: String? {
        guard let target = goal.targetDays, let enough else { return nil }
        if enough {
            return goal.deadline == nil ? String(localized: "已达成") : String(localized: "够撑\(FreedomGoal.targetName(target))")
        }
        guard case .finite(let days) = freedom else { return nil }
        let short = FinancialFormatting.wholeNumber((Double(target) - days).rounded(.up))
        return String(localized: "还差 \(short) 天自由")
    }

    /// 最下面一行小字。有日子：按每月存多少推算的；只有天数：按现在的速度每月多几天；不知道收入时提示填上
    var footnote: String? {
        if let daysUntil {
            if let saving, projected { return FreedomGoalMath.savingText(saving) }
            if case .finite = freedom, daysUntil > 0 { return String(localized: "填上每月收入，算到那天会有多少") }
            return nil
        }
        if enough == true { return nil }
        guard let monthlyGain else {
            if case .finite = freedom { return String(localized: "填上每月收入，看每月能多几天") }
            return nil
        }
        let amount = FinancialFormatting.wholeNumber(abs(monthlyGain).rounded())
        return monthlyGain > 0 ? String(localized: "按现在的速度，每月约多 \(amount) 天自由")
                               : String(localized: "按现在的速度，每月约少 \(amount) 天自由")
    }

    /// 一句话的倒数：「GAP · 189 天后」，留给锁屏小组件这种只放得下一行的地方
    var countdownLine: String? {
        guard let daysUntil else { return nil }
        let name = goal.displayName
        if daysUntil > 0 { return String(localized: "\(name) · \(daysUntil) 天后") }
        if daysUntil == 0 { return String(localized: "\(name) · 就是今天") }
        return String(localized: "\(name) · 这一天已经过了")
    }
}
