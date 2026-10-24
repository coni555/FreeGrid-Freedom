// 离职 / GAP 目标：攒够能撑几个月再走、打算哪天走。按每月能存下的钱，算还要多少天、那天够不够。
// 目标存在本机偏好里，不进备份；「撑多久」和首页的自由天数是同一个口径（计入的钱、固定支出按日历扣、被动收入抵开销）。

import Foundation

struct FreedomGoal: Equatable {
    /// 想攒够能撑几个月
    var months: Int
    /// 打算哪天走；nil 表示只看还要多久
    var leaveDate: Date?

    static let monthsRange = 1...120
    static let monthsKey = "gapGoalMonths"
    static let leaveDateKey = "gapGoalLeaveDate"
    /// 自己填的每月到手收入。和目标分开存：清掉目标不清收入，「每月有结余」那一项也用它
    static let incomeKey = "gapMonthlyIncome"

    /// 目标折成天数，一个月按 30.44 天，和首页按月显示的格子一致
    var targetDays: Double { Double(months) * FreedomMath.GridUnit.month.daysPerCell }
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

    /// 撑满 `days` 天至少要多少计入的钱。没有固定支出时就是天数 × 每日净消耗；
    /// 有的话扣款日不均匀，按推演二分找。被动收入已经盖住开销时是 0
    static func requiredBase(days: Double, snapshot: FinancialSnapshot) -> Double? {
        let net = snapshot.dailyBurn - snapshot.dailyPassive
        guard snapshot.hasExpenses, net.isFinite else { return nil }
        if case .covered = freedom(base: 0, snapshot: snapshot) { return 0 }
        guard net > 0 || !snapshot.loanPlan.isEmpty else { return 0 }
        if snapshot.loanPlan.isEmpty { return days * net }

        func lasts(_ base: Double) -> Bool {
            switch freedom(base: base, snapshot: snapshot) {
            case .covered: return true
            case .finite(let d): return d >= days
            case .insufficientData, .invalidData: return false
            }
        }
        var high = max(1, days * (net + snapshot.dailyFixed))
        var grow = 0
        while !lasts(high) {
            high *= 2
            grow += 1
            if grow > 40 { return nil }
        }
        var low = 0.0
        // 精确到一块钱就够了
        while high - low > 1 {
            let mid = (low + high) / 2
            if lasts(mid) { high = mid } else { low = mid }
        }
        return high.rounded(.up)
    }

    struct LeaveCheck: Equatable {
        let date: Date
        let daysUntil: Int
        /// 那天能撑多久；nil 表示没填收入，推不到那天
        let projected: FreedomState?
        let enough: Bool?
    }

    enum Status: Equatable {
        /// 还没记支出，日均算不出来
        case needsData
        /// 现在的钱已经够撑满目标
        case reached
        /// 每月能存下钱：还要多少天、哪天够
        case onTheWay(daysLeft: Int, readyDate: Date)
        /// 每月存不下钱，按现在的速度攒不到
        case unreachable
        /// 没填收入、收入记录也不够，算不出还要多久
        case needsIncome
    }

    struct Result: Equatable {
        let goal: FreedomGoal
        let status: Status
        /// 现在的钱占「撑满目标要的钱」多少，0...1
        let progress: Double
        let required: Double?
        let saving: MonthlySaving?
        let leave: LeaveCheck?
    }

    static func evaluate(goal: FreedomGoal, snapshot: FinancialSnapshot, saving: MonthlySaving?,
                         calendar: Calendar = .current) -> Result {
        let base = snapshot.freedomBase
        guard snapshot.hasExpenses, let required = requiredBase(days: goal.targetDays, snapshot: snapshot) else {
            return Result(goal: goal, status: .needsData, progress: 0, required: nil, saving: nil, leave: nil)
        }
        let progress = required <= 0 ? 1 : min(1, max(0, base / required))
        let status: Status
        if base >= required {
            status = .reached
        } else if let saving {
            if saving.perDay > 0 {
                let left = Int(((required - base) / saving.perDay).rounded(.up))
                let today = calendar.startOfDay(for: snapshot.now)
                let ready = calendar.date(byAdding: .day, value: left, to: today) ?? today
                status = .onTheWay(daysLeft: left, readyDate: ready)
            } else {
                status = .unreachable
            }
        } else {
            status = .needsIncome
        }
        return Result(goal: goal, status: status, progress: progress, required: required, saving: saving,
                      leave: leaveCheck(goal: goal, snapshot: snapshot, saving: saving, calendar: calendar))
    }

    /// 定了日期：按每月能存下的钱推到那天，看那天的钱能撑多久
    private static func leaveCheck(goal: FreedomGoal, snapshot: FinancialSnapshot, saving: MonthlySaving?,
                                   calendar: Calendar) -> LeaveCheck? {
        guard let date = goal.leaveDate else { return nil }
        let today = calendar.startOfDay(for: snapshot.now)
        let daysUntil = max(0, calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0)
        guard let saving else { return LeaveCheck(date: date, daysUntil: daysUntil, projected: nil, enough: nil) }
        let projectedBase = max(0, snapshot.freedomBase + saving.perDay * Double(daysUntil))
        let projected = freedom(base: projectedBase, snapshot: snapshot)
        let enough: Bool
        switch projected {
        case .covered: enough = true
        case .finite(let days): enough = days >= goal.targetDays
        case .insufficientData, .invalidData: enough = false
        }
        return LeaveCheck(date: date, daysUntil: daysUntil, projected: projected, enough: enough)
    }
}

// MARK: - 界面上的说法（自检页、设置页那张卡、目标面板共用）

extension FreedomGoalMath {
    /// 天数折成「x.x 个月」，和目标的单位一致
    static func monthsText(days: Double) -> String {
        let months = max(0, days) / FreedomMath.GridUnit.month.daysPerCell
        return String(localized: "\(String(format: "%.1f", months)) 个月")
    }

    /// 能存下钱时每月存多少、按什么算的收入
    static func savingText(_ saving: MonthlySaving) -> String {
        let amount = FinancialFormatting.wholeNumber(abs(saving.perMonth))
        switch (saving.perDay > 0, saving.basis) {
        case (true, .entered): return String(localized: "每月约存 ¥\(amount) · 按你填的收入")
        case (true, .recorded): return String(localized: "每月约存 ¥\(amount) · 按近 90 天的收入记录")
        case (false, .entered): return String(localized: "每月约多花 ¥\(amount) · 按你填的收入")
        case (false, .recorded): return String(localized: "每月约多花 ¥\(amount) · 按近 90 天的收入记录")
        }
    }
}

extension FreedomGoalMath.Result {
    /// 设置页卡上那一行、目标面板底下的预览：一句结论
    var statusLine: String {
        switch status {
        case .needsData: return String(localized: "记下支出、算出日均后才能算")
        case .reached: return String(localized: "现在的钱已经够撑 \(goal.months) 个月")
        case .onTheWay(let days, _): return String(localized: "还要 \(days) 天")
        case .unreachable: return String(localized: "按现在的结余攒不到")
        case .needsIncome: return String(localized: "填上每月收入，就能算还要多久")
        }
    }

    /// 定了日期时那一行：那天能撑多久、够不够
    var leaveLine: String? {
        guard let leave else { return nil }
        let date = FreedomMath.depleteDateText(leave.date)
        guard let projected = leave.projected, let enough = leave.enough else {
            return String(localized: "\(date)走：填上收入才能算那天够不够")
        }
        switch projected {
        case .covered:
            return String(localized: "\(date)走：被动收入已经盖住开销")
        case .finite(let days):
            let can = FreedomGoalMath.monthsText(days: days)
            if enough { return String(localized: "\(date)走：那天能撑 \(can)，够了") }
            let short = FreedomGoalMath.monthsText(days: goal.targetDays - days)
            return String(localized: "\(date)走：那天能撑 \(can)，还差 \(short)")
        case .insufficientData, .invalidData:
            return String(localized: "\(date)走：记下支出后才能算")
        }
    }
}
