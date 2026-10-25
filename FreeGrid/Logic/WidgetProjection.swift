// 小组件那份数怎么算：和首页同一套规则（FinancialSnapshot、HomeStat、FreedomGoalProgress），从今天起每天各算一份。
// 往后的日子假设不再记账：日均的分母照常一天天变大，到期还没扣的房租、月供在推演里当天扣掉，
// 自由天数和那天打开 App 时首页上的一样；只有「本月花销」不含还没扣的房租，打开 App 补扣后才算进去。
// 字按 App 当前的界面语言写好，小组件不再翻译。

import Foundation

enum WidgetProjection {
    /// 看板小组件能选的几项：首页的小卡，今日对比长条和目标卡不算
    static let stats: [HomeStat] = [.daily, .month, .today, .track, .base, .passive, .next]

    /// 算一天要的全部账目。`loans` 传起作用的那些（`ProFeatures.loansInEffect`）
    struct Ledger {
        var expenses: [Expense]
        var passiveSources: [PassiveSource]
        var assets: UserAssets?
        var assetItems: [AssetItem] = []
        var cashAccounts: [CashAccount] = []
        var loans: [Loan] = []
        var countsAssets: Bool = true
    }

    /// `goals` 只在 Pro 生效时用：没有 Pro 时小组件里没有目标
    static func snapshot(ledger: Ledger, goals: [FreedomGoal], proActive: Bool, now: Date = .now,
                         days: Int = WidgetSnapshot.projectedDays, calendar: Calendar = .current) -> WidgetSnapshot {
        let today = calendar.startOfDay(for: now)
        // 第一份从现在起，之后每天零点换一份
        let dates = [now] + (1..<max(1, days)).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let shownGoals = proActive ? goals : []
        return WidgetSnapshot(
            generatedAt: now,
            proActive: proActive,
            days: dates.map { day(ledger: ledger, goals: shownGoals, at: $0, calendar: calendar) },
            text: text)
    }

    static func day(ledger: Ledger, goals: [FreedomGoal], at date: Date,
                    calendar: Calendar = .current) -> WidgetSnapshot.Day {
        let snapshot = FinancialSnapshot(expenses: ledger.expenses, passiveSources: ledger.passiveSources,
                                         assets: ledger.assets, assetItems: ledger.assetItems,
                                         cashAccounts: ledger.cashAccounts, loans: ledger.loans, now: date,
                                         countsAssets: ledger.countsAssets)
        let inputs = HomeStat.Inputs(snapshot: snapshot, expenses: ledger.expenses, loans: ledger.loans,
                                     calendar: calendar)
        var stats: [String: WidgetSnapshot.Stat] = [:]
        for stat in self.stats {
            let display = stat.display(inputs)
            stats[stat.rawValue] = WidgetSnapshot.Stat(kicker: stat.kicker, title: stat.title,
                                                       value: display.value, unit: display.unit)
        }
        return WidgetSnapshot.Day(
            date: date,
            freedom: freedom(snapshot),
            stats: stats,
            goals: goals.map { goal(FreedomGoalProgress(goal: $0, snapshot: snapshot, calendar: calendar), now: date) })
    }

    /// 首页大数字卡上的那几样：数字、上面的小标签、下面一行
    static func freedom(_ snapshot: FinancialSnapshot) -> WidgetSnapshot.Freedom {
        let unit = FreedomMath.gridUnit(for: snapshot.freedom)
        let state: WidgetSnapshot.Freedom.State
        let kicker: String
        let caption: String
        switch snapshot.freedom {
        case .finite:
            state = .finite
            switch unit {
            case .day: kicker = "Freedom Days"; caption = String(localized: "还能撑这么多天")
            case .month: kicker = "Freedom Months"; caption = String(localized: "还能撑这么多月")
            case .year: kicker = "Freedom Years"; caption = String(localized: "还能撑这么多年")
            }
        case .covered:
            state = .covered
            kicker = "Freedom"
            caption = plain(String(localized: "你已*财富*自由"))
        case .insufficientData:
            state = .pending
            kicker = "Freedom Pending"
            caption = snapshot.netWorth == 0 ? plain(String(localized: "先记下*你有多少钱*"))
                                             : plain(String(localized: "再记*一笔支出*"))
        case .invalidData:
            state = .invalid
            kicker = "Data Check"
            caption = plain(String(localized: "检查*财务数据*"))
        }
        let short = FreedomMath.freedomDescription(snapshot.freedom)
        return WidgetSnapshot.Freedom(
            state: state,
            value: FreedomMath.freedomDaysDisplay(snapshot.freedom),
            kicker: kicker,
            caption: caption,
            short: short,
            unit: state == .finite ? unit.label : "",
            inline: String(localized: "自由 \(short)"),
            dailyCost: snapshot.dailyCost.isFinite ? snapshot.dailyCost : nil)
    }

    static func goal(_ progress: FreedomGoalProgress, now: Date) -> WidgetSnapshot.Goal {
        WidgetSnapshot.Goal(
            id: progress.goal.id,
            name: progress.goal.displayName,
            targetDays: progress.goal.targetDays,
            deadline: progress.goal.deadline,
            deadlineText: progress.goal.deadline.map { FreedomGoalSection.dateLine($0, now: now) },
            daysUntil: progress.daysUntil,
            progress: progress.progress,
            enough: progress.enough == true,
            freedomDays: progress.freedomDaysText,
            freedomLine: progress.freedomLine,
            targetLine: progress.targetLine,
            countdownLine: progress.countdownLine)
    }

    /// 首页标题里用星号标出强调的那几个字；小组件上没有强调，去掉星号
    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "*", with: "")
    }

    static var text: WidgetSnapshot.Text {
        WidgetSnapshot.Text(
            proTitle: String(localized: "Pro 小组件"),
            proBody: String(localized: "看板和目标小组件属于 Pro，点一下了解。"),
            noGoal: String(localized: "在自检里加一个目标，这里就会显示。"),
            stale: String(localized: "打开 FreeGrid 更新"),
            daysLater: String(localized: "天后"),
            today: String(localized: "就是今天"),
            passed: String(localized: "已经过了"),
            target: String(localized: "目标"),
            now: String(localized: "现在"))
    }
}
