import Foundation
import Testing
@testable import FreeGrid

/// 新用户记满 7 天时弹一次的「记账 7 天的小结」
struct FirstWeekRecapTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func expense(_ amount: Double, on day: String, at hour: Int = 12) -> Expense {
        let date = calendar.date(byAdding: .hour, value: hour, to: TestSupport.day(day))!
        return Expense(amount: amount, category: "午餐", date: date)
    }

    private func autoRent(on day: String) -> Expense {
        let rent = expense(3000, on: day)
        rent.loanID = UUID()
        rent.countsInBurn = false
        return rent
    }

    @Test func daysCountWhenTheUserLoggedSomethingNotNecessarilyInARow() {
        let expenses = [expense(10, on: "2026-10-01"), expense(20, on: "2026-10-01", at: 20),
                        expense(30, on: "2026-10-05"), expense(5, on: "2026-10-09")]
        #expect(FirstWeekRecap.recordedDays(expenses, calendar: calendar) == 3)
    }

    @Test func autoDeductedRentDoesNotCountAsADayOfLogging() {
        let expenses = [expense(10, on: "2026-10-01"), autoRent(on: "2026-10-02")]
        #expect(FirstWeekRecap.recordedDays(expenses, calendar: calendar) == 1)
    }

    @Test func onlyNewcomersWithSevenDaysSeeItOnce() {
        #expect(FirstWeekRecap.shouldShow(audience: .newcomer, alreadyShown: false, recordedDays: 7))
        #expect(!FirstWeekRecap.shouldShow(audience: .newcomer, alreadyShown: false, recordedDays: 6))
        #expect(!FirstWeekRecap.shouldShow(audience: .newcomer, alreadyShown: true, recordedDays: 30))
        #expect(!FirstWeekRecap.shouldShow(audience: .returning, alreadyShown: false, recordedDays: 30))
        #expect(!FirstWeekRecap.shouldShow(audience: nil, alreadyShown: false, recordedDays: 30))
    }

    @Test func proIsMentionedOnlyToPeopleWhoCanStillTryIt() {
        #expect(FirstWeekRecap.mentionsPro(ownsPro: false, hasStartedTrial: false, canStartTrial: true))
        #expect(!FirstWeekRecap.mentionsPro(ownsPro: true, hasStartedTrial: false, canStartTrial: true))
        #expect(!FirstWeekRecap.mentionsPro(ownsPro: false, hasStartedTrial: true, canStartTrial: true))
        #expect(!FirstWeekRecap.mentionsPro(ownsPro: false, hasStartedTrial: false, canStartTrial: false))
    }

    /// 零星记了三周才记满 7 天，过了几天才打开：画的还是记满的那 7 个记账日，没有空柱子
    @Test func theCardShowsTheFirstSevenLoggedDaysNotTheLastCalendarWeek() {
        let expenses = [expense(10, on: "2026-09-28"), expense(15, on: "2026-09-28", at: 19),
                        expense(40, on: "2026-10-01"), autoRent(on: "2026-10-02"),
                        expense(8, on: "2026-10-05"), expense(20, on: "2026-10-08"),
                        expense(30, on: "2026-10-11"), expense(5, on: "2026-10-14"),
                        expense(12, on: "2026-10-16"),
                        expense(99, on: "2026-10-17")]          // 第 8 个记账日，不画
        let assets = UserAssets(total: 0)
        assets.cash = 10_000
        let now = calendar.date(byAdding: .hour, value: 21, to: TestSupport.day("2026-10-20"))!
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: assets, now: now, countsAssets: true)
        let week = FirstWeekRecap.summary(expenses: expenses, snapshot: snapshot, mentionsPro: true, calendar: calendar)
        #expect(week.days.count == 7)
        #expect(week.days.first == TestSupport.day("2026-09-28"))
        #expect(week.days.last == TestSupport.day("2026-10-16"))
        #expect(week.dailyTotals == [25, 40, 8, 20, 30, 5, 12])
        #expect(week.total == 140)
        // 日均和自由天数就是首页那份
        #expect(week.dailyCost == snapshot.dailyCost)
        #expect(week.freedom == snapshot.freedom)
    }
}
