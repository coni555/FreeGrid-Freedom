// 首页数字小卡：没改过时放哪几张、存下来的顺序、每行几张，以及本月 / 今日 / 记账天数 / 可动用资产 / 下次固定支出算出来的数。
import Foundation
import Testing
@testable import FreeGrid

@MainActor
struct HomeStatTests {
    /// 2026-10-24 中午
    private let now = TestSupport.day("2026-10-24").addingTimeInterval(12 * 3600)

    private func at(_ day: String) -> Date { TestSupport.day(day).addingTimeInterval(12 * 3600) }

    private func snapshot(_ expenses: [Expense], cash: Double = 10_000, locked: Double = 0) -> FinancialSnapshot {
        let assets = UserAssets(total: 0)
        assets.cash = cash
        assets.lockedAssets = locked
        return FinancialSnapshot(expenses: expenses, passiveSources: [], assets: assets, loans: [],
                                 now: now, countsAssets: true)
    }

    private func inputs(expenses: [Expense], loans: [Loan] = []) -> HomeStat.Inputs {
        HomeStat.Inputs(snapshot: snapshot(expenses), expenses: expenses, loans: loans)
    }

    @Test func defaultsMatchTheOldCardsAndStoredListsKeepTheirOrder() {
        #expect(HomeStat.slots(stored: "", hasPassive: true) == [.daily, .passive, .track, .todayBar])
        #expect(HomeStat.slots(stored: "", hasPassive: false) == [.daily, .month, .track, .todayBar])
        // 拿掉的「本月结余率」、认不出的、重复的都跳过，其余按存的顺序
        #expect(HomeStat.slots(stored: "saved,daily,daily,weekly,next", hasPassive: false) == [.daily, .next])
        #expect(HomeStat.slots(stored: "base,today,month,track,daily", hasPassive: false)
                == [.base, .today, .month, .track, .daily])
        // 全都移除了也记得，不回到默认
        #expect(HomeStat.encode([]) == "none")
        #expect(HomeStat.slots(stored: HomeStat.encode([]), hasPassive: true).isEmpty)
    }

    @Test func rowsHoldAtMostThreeAndNeverLeaveOneAlone() {
        #expect(HomeStat.rowSizes(count: 0) == [])
        #expect(HomeStat.rowSizes(count: 1) == [1])
        #expect(HomeStat.rowSizes(count: 3) == [3])
        #expect(HomeStat.rowSizes(count: 4) == [2, 2])
        #expect(HomeStat.rowSizes(count: 5) == [3, 2])
        #expect(HomeStat.rowSizes(count: 7) == [3, 2, 2])
    }

    @Test func theTodayBarAlwaysTakesARowOfItsOwn() {
        #expect(HomeStat.rows([.daily, .month, .track, .todayBar]) == [[.daily, .month, .track], [.todayBar]])
        // 长条夹在中间：前后的小卡各自分行
        #expect(HomeStat.rows([.daily, .todayBar, .month, .today, .track, .base])
                == [[.daily], [.todayBar], [.month, .today], [.track, .base]])
        #expect(HomeStat.rows([.todayBar]) == [[.todayBar]])
        #expect(HomeStat.rows([]) == [])
    }

    @Test func monthComparesWithTheSameSpanOfLastMonth() {
        let expenses = [
            Expense(amount: 300, category: "午餐", date: at("2026-10-03")),
            Expense(amount: 100, category: "午餐", date: at("2026-10-24")),
            // 上个月 1–24 号 500，25 号以后的不算进同期
            Expense(amount: 500, category: "午餐", date: at("2026-09-10")),
            Expense(amount: 900, category: "购物", date: at("2026-09-28")),
        ]
        #expect(HomeStat.month.display(inputs(expenses: expenses)) == .init(value: "400", unit: "比上月同期少 20%"))
        let firstMonth = HomeStat.month.display(inputs(expenses: [Expense(amount: 80, category: "午餐", date: at("2026-10-02"))]))
        #expect(firstMonth == .init(value: "80", unit: "元 · 本月已花"))
    }

    @Test func todayComparesTheDaysSpendingWithTheUsualDay() {
        #expect(HomeStat.todayComparison(today: 0, dailyBurn: 100, routine: false) == "今天还没花")
        #expect(HomeStat.todayComparison(today: 120, dailyBurn: 100, routine: false) == "比日均高 20%")
        #expect(HomeStat.todayComparison(today: 75, dailyBurn: 100, routine: true) == "比日常低 25%")
        #expect(HomeStat.todayComparison(today: -30, dailyBurn: 100, routine: false) == "今天净退款")
        // 今天的数只算今天的日常支出
        let expenses = [Expense(amount: 40, category: "午餐", date: at("2026-10-24")),
                        Expense(amount: 60, category: "晚餐", date: at("2026-10-23"))]
        #expect(inputs(expenses: expenses).todaySpending == 40)
    }

    @Test func trackTellsHowLongUntilTheDailyAverageSettles() {
        // 第一笔在 9 天前：记了 10 天，再记 80 天
        let young = HomeStat.track.display(inputs(expenses: [Expense(amount: 30, category: "午餐", date: at("2026-10-15"))]))
        #expect(young == .init(value: "10", unit: "再记录 80 天，日均趋势会更清晰"))
        let settled = HomeStat.track.display(inputs(expenses: [Expense(amount: 30, category: "午餐", date: at("2026-01-01"))]))
        #expect(settled.unit == "天记账")
    }

    @Test func baseSplitAddsUpToAHundred() {
        #expect(HomeStat.baseSplit(assets: 22_000, cash: 14_000) == "资产 61% · 现金 39%")
        #expect(HomeStat.baseSplit(assets: 0, cash: 5_000) == "全是现金")
        #expect(HomeStat.baseSplit(assets: 5_000, cash: 0) == "全是资产")
        #expect(HomeStat.baseSplit(assets: 0, cash: 0) == "元 · 可动用资产")
        // 极小的一边也至少写 1%
        #expect(HomeStat.baseSplit(assets: 1, cash: 9_999) == "资产 1% · 现金 99%")
    }

    @Test func nextShowsTheSoonestFixedExpense() {
        func fixed(_ name: String, _ amount: Double, nextDue: String) -> Loan {
            let due = TestSupport.day(nextDue)
            return Loan(name: name, monthlyAmount: amount, dueDay: Calendar.current.component(.day, from: due),
                        periodsAtStart: 0, startDate: Calendar.current.date(byAdding: .day, value: -1, to: due)!,
                        sortOrder: 0, isOngoing: true)
        }
        let expenses = [Expense(amount: 50, category: "午餐", date: at("2026-10-20"))]
        let loans = [fixed("房租", 3_000, nextDue: "2026-11-05"), fixed("会员", 25, nextDue: "2026-10-29")]
        #expect(HomeStat.next.display(inputs(expenses: expenses, loans: loans)) == .init(value: "5", unit: "天后 · 会员 ¥25"))
        #expect(HomeStat.next.display(inputs(expenses: expenses)) == .init(value: "—", unit: "没有固定支出"))
    }
}
