// 新用户记满 7 天那天，首页弹一次「这一周的小结」（用户 2026-10-18 选的 N2）。
// 先给用户看自己这一周记下了什么，Pro 只在最后顺带一句；
// 新用户不在引导刚走完、也不在进 Settings 时被推 Pro（AGENTS「2.0 的 Pro 介绍」）。
// 7 天按记过账的日子算，不要求连续；记满那天没打开 App，下次打开时补弹。每台设备只弹一次。
// 这里只管判断和算数；屏幕上空不空、能不能弹，由 ContentView 看。

import Foundation

enum FirstWeekRecap {
    static let shownKey = "firstWeekRecapShown"
    static let requiredDays = 7

    /// 用户自己记的支出。自动扣的房租、月供，和确认过的「以前记的月供」不算：它们不是用户这一周在记账
    static func isLogged(_ expense: Expense) -> Bool {
        expense.loanID == nil && expense.countsInBurn
    }

    /// 记过账的天数：有自己记的支出的日子，不要求连续
    static func recordedDays(_ expenses: [Expense], calendar: Calendar = .current) -> Int {
        Set(expenses.filter(isLogged).map { calendar.startOfDay(for: $0.date) }).count
    }

    /// 只给新用户（老用户打开 2.0 时已经看过更新说明卡片），记满 7 天、还没弹过
    static func shouldShow(audience: ProIntro.Audience?, alreadyShown: Bool, recordedDays: Int) -> Bool {
        audience == .newcomer && !alreadyShown && recordedDays >= requiredDays
    }

    /// Pro 那一句只给没买、没开始过体验、读得到体验商品的人
    static func mentionsPro(ownsPro: Bool, hasStartedTrial: Bool, canStartTrial: Bool) -> Bool {
        !ownsPro && !hasStartedTrial && canStartTrial
    }

    struct Summary: Equatable {
        /// 这一周的 7 天，最早的在前，最后一天是今天
        let days: [Date]
        /// 每天自己记的支出合计，和 `days` 一一对应
        let dailyTotals: [Double]
        /// 首页 Daily 卡上的日均（日常 + 固定折算）
        let dailyCost: Double
        /// 首页大数字
        let freedom: FreedomState
        let mentionsPro: Bool

        var total: Double { dailyTotals.reduce(0, +) }
    }

    /// 截到今天的 7 天。日均和自由天数直接用首页的那份结果，卡片上的数字和首页一样
    static func summary(expenses: [Expense], snapshot: FinancialSnapshot, mentionsPro: Bool,
                        calendar: Calendar = .current) -> Summary {
        let today = calendar.startOfDay(for: snapshot.now)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        var totals = Dictionary(uniqueKeysWithValues: days.map { ($0, 0.0) })
        for expense in expenses where isLogged(expense) {
            let day = calendar.startOfDay(for: expense.date)
            if totals[day] != nil { totals[day, default: 0] += expense.amount }
        }
        return Summary(days: days, dailyTotals: days.map { totals[$0] ?? 0 }, dailyCost: snapshot.dailyCost,
                       freedom: snapshot.freedom, mentionsPro: mentionsPro)
    }
}
