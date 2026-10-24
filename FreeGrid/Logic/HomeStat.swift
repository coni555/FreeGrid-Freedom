// 首页底部的三张数字小卡：固定三张，点一张可以换成下面任意一个指标（免费），按住拖动换位置。
// 这里决定有哪些指标、默认放哪三个、换了以后怎么排，以及每个指标显示什么。

import Foundation

enum HomeStat: String, CaseIterable, Identifiable {
    case daily, month, saved, next, passive, base, track

    var id: String { rawValue }

    /// 卡上等宽大写的小标签
    var kicker: String {
        switch self {
        case .daily: return "Daily"
        case .month: return "Month"
        case .saved: return "Saved"
        case .next: return "Next"
        case .passive: return "Passive"
        case .base: return "Funds"
        case .track: return "Track"
        }
    }

    /// 长按菜单里的名字
    var title: String {
        switch self {
        case .daily: return "日均消费"
        case .month: return "本月花销"
        case .saved: return "本月结余率"
        case .next: return "下次固定支出"
        case .passive: return "被动收入覆盖"
        case .base: return "可动用资产"
        case .track: return "记账天数"
        }
    }

    // MARK: - 放哪三个

    static let slotsKey = "homeStatSlots"
    static let slotCount = 3

    /// 存的是三个 rawValue 用逗号连起来。没换过（或存的不对）时用默认：和 2.0 一样的日均、被动覆盖、记账天数；
    /// 没有被动收入的人 2.0 里那张是藏起来的，这里补成本月花销，三张始终都在
    static func slots(stored: String, hasPassive: Bool) -> [HomeStat] {
        let parsed = stored.split(separator: ",").compactMap { HomeStat(rawValue: String($0)) }
        if parsed.count == slotCount, Set(parsed).count == slotCount { return parsed }
        return [.daily, hasPassive ? .passive : .month, .track]
    }

    static func encode(_ slots: [HomeStat]) -> String {
        slots.map(\.rawValue).joined(separator: ",")
    }

    /// 第 `index` 张换成 `stat`。它已经在别的位置时两张对调，三张不会重复
    static func replacing(_ slots: [HomeStat], at index: Int, with stat: HomeStat) -> [HomeStat] {
        guard slots.indices.contains(index) else { return slots }
        var result = slots
        if let other = result.firstIndex(of: stat) {
            result.swapAt(index, other)
        } else {
            result[index] = stat
        }
        return result
    }

    /// 把第 `from` 张拖到第 `to` 格，中间的往旁边让
    static func moving(_ slots: [HomeStat], from: Int, to: Int) -> [HomeStat] {
        guard slots.indices.contains(from), slots.indices.contains(to) else { return slots }
        var result = slots
        result.insert(result.remove(at: from), at: to)
        return result
    }

    // MARK: - 显示什么

    struct Display: Equatable {
        let value: String
        let unit: String
    }

    func display(_ inputs: Inputs) -> Display {
        let snapshot = inputs.snapshot
        switch self {
        case .daily:
            // 日均含固定支出折成的每天；有固定支出时小字拆开写，和下面只比日常的 Today 对得上
            return Display(
                value: snapshot.dailyCost.isFinite ? String(format: "%.1f", snapshot.dailyCost) : "—",
                unit: snapshot.dailyFixed > 0 && snapshot.dailyBurn.isFinite
                    ? "日常 \(FinancialFormatting.wholeNumber(snapshot.dailyBurn)) · 固定 \(FinancialFormatting.wholeNumber(snapshot.dailyFixed))"
                    : "元/天")
        case .month:
            return Display(value: FinancialFormatting.wholeNumber(inputs.monthSpent),
                           unit: Self.monthComparison(spent: inputs.monthSpent, lastMonth: inputs.lastMonthSameSpan))
        case .saved:
            guard inputs.monthIncome > 0 else { return Display(value: "—", unit: "本月还没记收入") }
            let rate = (inputs.monthIncome - inputs.monthSpent) / inputs.monthIncome
            if rate < 0 {
                return Display(value: "−" + FinancialFormatting.percentage(-rate), unit: "本月花得比挣得多")
            }
            return Display(value: FinancialFormatting.percentage(rate), unit: "本月收入留下")
        case .next:
            guard let next = inputs.nextFixed else { return Display(value: "—", unit: "没有固定支出") }
            return Display(value: "\(next.daysAway)",
                           unit: "天后 · \(next.name) \(FinancialFormatting.yuan(next.amount, precision: 0))")
        case .passive:
            return Display(value: FinancialFormatting.percentage(snapshot.passiveRatio),
                           unit: snapshot.dailyPassive > 0 ? "被动收入覆盖" : "还没有被动收入")
        case .base:
            return Display(value: FinancialFormatting.wholeNumber(snapshot.freedomBase), unit: "元 · 可动用资产")
        case .track:
            return Display(value: "\(snapshot.trackDays)", unit: "天记账")
        }
    }

    /// 本月到今天花的和上个月同一段（1 号到同一天）比。上个月这段没有记录时只写「本月已花」
    static func monthComparison(spent: Double, lastMonth: Double?) -> String {
        guard let lastMonth, lastMonth > 0 else { return "元 · 本月已花" }
        let change = (spent - lastMonth) / lastMonth
        if abs(change) < 0.01 { return "和上月同期差不多" }
        let pct = FinancialFormatting.percentage(abs(change), maximum: 999)
        return change > 0 ? "比上月同期多 \(pct)" : "比上月同期少 \(pct)"
    }

    // MARK: - 算这些指标要的数

    struct NextFixed: Equatable {
        let name: String
        let amount: Double
        let daysAway: Int
    }

    /// 除了 `FinancialSnapshot` 以外，几个新指标要的数。账本变了才重算，和首页其他数字一起
    struct Inputs {
        let snapshot: FinancialSnapshot
        /// 本月 1 号到现在的全部支出，自动扣的房租、月供也算
        let monthSpent: Double
        /// 上个月 1 号到同一天的支出；上个月整月一笔都没有时为 nil
        let lastMonthSameSpan: Double?
        /// 本月记的收入
        let monthIncome: Double
        /// 最近一笔还没付的固定支出或月供
        let nextFixed: NextFixed?

        init(snapshot: FinancialSnapshot, monthSpent: Double, lastMonthSameSpan: Double?,
             monthIncome: Double, nextFixed: NextFixed?) {
            self.snapshot = snapshot
            self.monthSpent = monthSpent
            self.lastMonthSameSpan = lastMonthSameSpan
            self.monthIncome = monthIncome
            self.nextFixed = nextFixed
        }

        /// `loans` 传起作用的那些（`ProFeatures.loansInEffect`）：贷款停用时不显示它的下次还款
        init(snapshot: FinancialSnapshot, expenses: [Expense], incomes: [Income], loans: [Loan],
             calendar: Calendar = .current) {
            let now = snapshot.now
            let today = calendar.startOfDay(for: now)
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? today
            let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
            // 上个月的同一天（上个月没有这一天时到月底），包含那一整天
            let dayOfMonth = calendar.component(.day, from: now)
            let lastMonthDays = calendar.range(of: .day, in: .month, for: lastMonthStart)?.count ?? 28
            let lastSpanEnd = calendar.date(byAdding: .day, value: min(dayOfMonth, lastMonthDays), to: lastMonthStart)
                ?? monthStart
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now

            var monthSpent = 0.0, lastSpan = 0.0, lastMonthAny = false
            for expense in expenses {
                let date = expense.date
                if date >= monthStart, date < tomorrow {
                    monthSpent += expense.amount
                } else if date >= lastMonthStart, date < monthStart {
                    lastMonthAny = true
                    if date < lastSpanEnd { lastSpan += expense.amount }
                }
            }
            let monthIncome = incomes.reduce(0) { sum, income in
                income.date >= monthStart && income.date < tomorrow ? sum + income.amount : sum
            }

            let payments = expenses.filter { $0.loanID != nil }
            let next = loans.compactMap { loan -> (Loan, Date)? in
                guard loan.monthlyAmount.isFinite, loan.monthlyAmount > 0,
                      let due = LoanSchedule.status(of: loan, payments: payments, now: now, calendar: calendar).nextDue
                else { return nil }
                return (loan, due)
            }
            .min { $0.1 < $1.1 }

            self.init(snapshot: snapshot, monthSpent: monthSpent,
                      lastMonthSameSpan: lastMonthAny ? lastSpan : nil,
                      monthIncome: monthIncome,
                      nextFixed: next.map { loan, due in
                          NextFixed(name: loan.name, amount: loan.monthlyAmount,
                                    daysAway: calendar.dateComponents([.day], from: today,
                                                                      to: calendar.startOfDay(for: due)).day ?? 0)
                      })
        }
    }
}
