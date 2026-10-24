// 首页三张数字小卡：默认放哪三个、换和挪之后的顺序、本月 / 结余率 / 下次固定支出算出来的数。
import Foundation
import Testing
@testable import FreeGrid

@MainActor
struct HomeStatTests {
    /// 2026-10-24 中午
    private let now = TestSupport.day("2026-10-24").addingTimeInterval(12 * 3600)

    private func at(_ day: String) -> Date { TestSupport.day(day).addingTimeInterval(12 * 3600) }

    private func snapshot(_ expenses: [Expense], cash: Double = 10_000) -> FinancialSnapshot {
        let assets = UserAssets(total: 0)
        assets.cash = cash
        return FinancialSnapshot(expenses: expenses, passiveSources: [], assets: assets, loans: [],
                                 now: now, countsAssets: true)
    }

    private func inputs(expenses: [Expense], incomes: [Income] = [], loans: [Loan] = []) -> HomeStat.Inputs {
        HomeStat.Inputs(snapshot: snapshot(expenses), expenses: expenses, incomes: incomes, loans: loans)
    }

    @Test func defaultsMatchTheOldCardsAndFillTheHiddenPassiveSlot() {
        #expect(HomeStat.slots(stored: "", hasPassive: true) == [.daily, .passive, .track])
        #expect(HomeStat.slots(stored: "", hasPassive: false) == [.daily, .month, .track])
        // 存坏了（重复、不认识、数量不对）都回到默认
        #expect(HomeStat.slots(stored: "daily,daily,track", hasPassive: false) == [.daily, .month, .track])
        #expect(HomeStat.slots(stored: "daily,weekly,track", hasPassive: false) == [.daily, .month, .track])
        #expect(HomeStat.slots(stored: "next,saved,base", hasPassive: false) == [.next, .saved, .base])
    }

    @Test func replacingWithACardAlreadyShownSwapsThem() {
        let slots: [HomeStat] = [.daily, .passive, .track]
        #expect(HomeStat.replacing(slots, at: 1, with: .month) == [.daily, .month, .track])
        #expect(HomeStat.replacing(slots, at: 0, with: .track) == [.track, .passive, .daily])
        #expect(HomeStat.moving(slots, from: 2, to: 1) == [.daily, .track, .passive])
        // 第一张拖到最后，中间两张各往左让一格
        #expect(HomeStat.moving(slots, from: 0, to: 2) == [.passive, .track, .daily])
        #expect(HomeStat.moving(slots, from: 0, to: 3) == slots)
        #expect(HomeStat.encode([.next, .saved, .base]) == "next,saved,base")
    }

    @Test func monthComparesWithTheSameSpanOfLastMonth() {
        let expenses = [
            Expense(amount: 300, category: "午餐", date: at("2026-10-03")),
            Expense(amount: 100, category: "午餐", date: at("2026-10-24")),
            // 上个月 1–24 号 500，25 号以后的不算进同期
            Expense(amount: 500, category: "午餐", date: at("2026-09-10")),
            Expense(amount: 900, category: "购物", date: at("2026-09-28")),
        ]
        let display = HomeStat.month.display(inputs(expenses: expenses))
        #expect(display == .init(value: "400", unit: "比上月同期少 20%"))

        let firstMonth = HomeStat.month.display(inputs(expenses: [Expense(amount: 80, category: "午餐", date: at("2026-10-02"))]))
        #expect(firstMonth == .init(value: "80", unit: "元 · 本月已花"))
    }

    @Test func savedRateUsesThisMonthsIncome() {
        let expenses = [Expense(amount: 3_100, category: "购物", date: at("2026-10-10"))]
        let incomes = [Income(amount: 5_000, source: "工资", date: at("2026-10-05")),
                       Income(amount: 9_000, source: "工资", date: at("2026-09-05"))]
        #expect(HomeStat.saved.display(inputs(expenses: expenses, incomes: incomes)) == .init(value: "38%", unit: "本月收入留下"))
        #expect(HomeStat.saved.display(inputs(expenses: expenses)) == .init(value: "—", unit: "本月还没记收入"))
        let over = [Income(amount: 2_000, source: "工资", date: at("2026-10-05"))]
        #expect(HomeStat.saved.display(inputs(expenses: expenses, incomes: over)) == .init(value: "−55%", unit: "本月花得比挣得多"))
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
