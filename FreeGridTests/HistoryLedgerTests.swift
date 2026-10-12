// 历史页按月取数、筛选、搜索与按天分组的具体输入输出。
import Foundation
import Testing
@testable import FreeGrid

@MainActor
struct HistoryLedgerTests {
    private let october = HistoryMonth(year: 2026, month: 10)
    private var expenses: [Expense] {
        [
            Expense(amount: 22.8, category: "购物", note: "Clash", date: TestSupport.day("2026-10-10")),
            Expense(amount: 15.5, category: "午餐", date: TestSupport.day("2026-10-10")),
            Expense(amount: 13, category: "午餐", date: TestSupport.day("2026-10-09")),
            Expense(amount: -30, category: "购物", note: "退款", date: TestSupport.day("2026-10-01")),
            Expense(amount: 1234.5, category: "交通", note: "高铁票", date: TestSupport.day("2026-09-30")),
        ]
    }
    private var incomes: [Income] {
        [Income(amount: 2000, source: "工资", date: TestSupport.day("2026-10-09"))]
    }

    @Test func monthShiftCrossesYearsInBothDirections() {
        #expect(HistoryMonth(year: 2026, month: 1).shifted(by: -1) == HistoryMonth(year: 2025, month: 12))
        #expect(HistoryMonth(year: 2025, month: 12).shifted(by: 1) == HistoryMonth(year: 2026, month: 1))
        #expect(october.shifted(by: -22) == HistoryMonth(year: 2024, month: 12))
        #expect(october.label == "2026年10月")
    }

    @Test func monthScopeKeepsOnlyThatMonthAndSummaryNetsRefunds() {
        let month = HistoryLedger.transactions(expenses: expenses, incomes: incomes, scope: .month(october))
        #expect(month.count == 5)
        #expect(month.first?.date == TestSupport.day("2026-10-10"))
        let summary = HistoryLedger.summary(month)
        #expect(abs(summary.expense - 21.3) < 0.0001)   // 22.8 + 15.5 + 13 − 30
        #expect(summary.income == 2000)
        #expect(abs(summary.net - 1978.7) < 0.0001)
        #expect(HistoryLedger.transactions(expenses: expenses, incomes: incomes, scope: .allTime).count == 6)
        #expect(HistoryLedger.transactions(expenses: expenses, incomes: incomes,
                                           scope: .month(HistoryMonth(year: 2026, month: 8))).isEmpty)
    }

    @Test func categoryFilterDropsIncomeAndTotalsFollowTheScope() {
        let month = HistoryLedger.transactions(expenses: expenses, incomes: incomes, scope: .month(october))
        let lunch = HistoryLedger.filter(month, kind: .all, category: "午餐")
        #expect(lunch.map(\.cashChange) == [-15.5, -13])
        #expect(HistoryLedger.filter(month, kind: .income, category: nil).map(\.title) == ["工资"])
        #expect(HistoryLedger.filter(month, kind: .expense, category: nil).count == 4)
        let totals = HistoryLedger.categoryTotals(month)
        #expect(totals.map(\.category) == ["午餐", "购物"])
        #expect(totals.map(\.total) == [28.5, 22.8 - 30])
    }

    @Test func searchMatchesTitleNoteAndAmountIgnoringCase() {
        let all = HistoryLedger.transactions(expenses: expenses, incomes: incomes, scope: .allTime)
        #expect(HistoryLedger.search(all, query: "clash").map(\.note) == ["Clash"])
        #expect(HistoryLedger.search(all, query: "午餐 13").map(\.cashChange) == [-13])
        #expect(HistoryLedger.search(all, query: "1234.5").map(\.note) == ["高铁票"])
        #expect(HistoryLedger.search(all, query: "1,234").map(\.note) == ["高铁票"])
        #expect(HistoryLedger.search(all, query: "工资").count == 1)
        #expect(HistoryLedger.search(all, query: "不存在").isEmpty)
        #expect(HistoryLedger.search(all, query: "   ").count == all.count)
    }

    @Test func daysGroupNewestFirstWithDailyNet() {
        let month = HistoryLedger.transactions(expenses: expenses, incomes: incomes, scope: .month(october))
        let days = HistoryLedger.days(month)
        #expect(days.map(\.id) == ["2026-10-10", "2026-10-09", "2026-10-01"].map(TestSupport.day))
        #expect(days.map(\.transactions.count) == [2, 2, 1])
        #expect(abs(days[0].net + 38.3) < 0.0001)
        #expect(days[1].net == 1987)
        #expect(days[2].net == 30)   // 退款增加现金
        // 段头分开写支出和收入：9 日花 13、收 2000，不能合成 +1987 把支出盖住
        #expect(days[1].expense == 13)
        #expect(days[1].income == 2000)
        #expect(abs(days[0].expense - 38.3) < 0.0001)
        #expect(days[0].income == 0)
    }

    @Test func monthRangeCoversRecordsAndTheCurrentMonth() {
        let now = TestSupport.day("2026-10-11")
        let range = HistoryLedger.monthRange(expenses: expenses, incomes: incomes, now: now)
        #expect(range == HistoryMonth(year: 2026, month: 9)...october)
        #expect(HistoryLedger.monthRange(expenses: [], incomes: [], now: now) == october...october)
        // 记到未来的账也要能翻到
        let future = [Expense(amount: 1, category: "其他", date: TestSupport.day("2026-12-01"))]
        #expect(HistoryLedger.monthRange(expenses: future, incomes: [], now: now).upperBound
                == HistoryMonth(year: 2026, month: 12))
    }

    @Test func elapsedDaysCountsWholePastMonthsAndTheCurrentMonthToToday() {
        let now = TestSupport.day("2026-10-11")
        #expect(HistoryLedger.elapsedDays(in: october, now: now) == 11)
        #expect(HistoryLedger.elapsedDays(in: HistoryMonth(year: 2026, month: 9), now: now) == 30)
        #expect(HistoryLedger.elapsedDays(in: HistoryMonth(year: 2024, month: 2), now: now) == 29)
        #expect(HistoryLedger.elapsedDays(in: HistoryMonth(year: 2026, month: 11), now: now) == 0)
        #expect(HistoryLedger.elapsedDays(in: october, now: TestSupport.day("2026-10-01")) == 1)
        #expect(HistoryLedger.elapsedDays(in: october, now: TestSupport.day("2026-10-31")) == 31)
    }

    @Test func dayLabelNamesTodayYesterdayAndOtherYears() {
        let now = TestSupport.day("2026-10-11")
        #expect(HistoryLedger.dayLabel(TestSupport.day("2026-10-11"), now: now) == "今天 · 10月11日 周日")
        #expect(HistoryLedger.dayLabel(TestSupport.day("2026-10-10"), now: now) == "昨天 · 10月10日 周六")
        #expect(HistoryLedger.dayLabel(TestSupport.day("2026-10-07"), now: now) == "10月7日 周三")
        #expect(HistoryLedger.dayLabel(TestSupport.day("2025-12-31"), now: now) == "2025年12月31日 周三")
    }
}
