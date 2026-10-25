// 自己的目标：存取、和首页自由天数比的进度和还差多少、离那天几天；「每月有结余」的收入从哪来，以及自检清单。
import Foundation
import Testing
@testable import FreeGrid

@MainActor
struct FreedomGoalTests {
    private let now = TestSupport.day("2026-06-10")
    private let month = FreedomMath.GridUnit.month.daysPerCell

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: now)!
    }

    /// 日均 120：10 天里共花 1200；现金 36,000 → 自由 300 天
    private func snapshot(cash: Double = 36_000, passive: Double = 0, loans: [Loan] = [],
                          expenses: [Expense]? = nil) -> FinancialSnapshot {
        let assets = UserAssets(total: 0)
        assets.cash = cash
        return FinancialSnapshot(expenses: expenses ?? [Expense(amount: 1200, category: "午餐", date: day(-9))],
                                 passiveSources: passive > 0 ? [PassiveSource(name: "利息", monthlyAmount: passive)] : [],
                                 assets: assets, loans: loans, now: now, countsAssets: true)
    }

    /// 每天正好存下 `perDay`：收入折成每天 = 日均 120 + perDay
    private func saving(perDay: Double, in s: FinancialSnapshot) -> MonthlySaving? {
        SavingMath.saving(snapshot: s, enteredIncome: (120 + perDay) * month, recordedIncome: nil)
    }

    @Test func goalsRoundTripThroughPreferences() {
        let gap = FreedomGoal(name: "GAP", targetDays: 730, deadline: day(189))
        let fund = FreedomGoal(name: "", targetDays: 365)
        let stored = FreedomGoalStore.encode([gap, fund])
        #expect(FreedomGoalStore.decode(stored) == [gap, fund])
        #expect(FreedomGoalStore.decode("") == [])
        #expect(FreedomGoalStore.decode("not json") == [])
        // 天数不对的不算；个数不限
        #expect(!FreedomGoal(name: "空的", targetDays: 0).isValid)
        let many = (0..<8).map { FreedomGoal(targetDays: 100 + $0) }
        #expect(FreedomGoalStore.decode(FreedomGoalStore.encode(many)).count == 8)
        // 改了替换、新的加在最后
        var edited = gap
        edited.targetDays = 365
        #expect(FreedomGoalStore.saving(edited, into: [gap, fund]) == [edited, fund])
        #expect(FreedomGoalStore.saving(FreedomGoal(targetDays: 30), into: [gap, fund]).count == 3)
        // 没起名字叫「攒够一年」
        #expect(fund.displayName == "攒够一年")
        #expect(FreedomGoal(targetDays: 100).displayName == "攒够 100 天")
        #expect(gap.displayName == "GAP")
    }

    @Test func comparesWithTheHomeFreedomDays() {
        // 现在 300 天：和首页同一个数，不按收入往后推
        let s = snapshot()
        let fund = FreedomGoalProgress(goal: FreedomGoal(name: "应急金", targetDays: 365), snapshot: s)
        #expect(fund.freedom == s.freedom)
        #expect(fund.daysUntil == nil)
        #expect(fund.freedomLine == "现在 300 / 365 天")
        #expect(fund.targetLine == "还差 65 天自由")
        #expect(abs((fund.progress ?? 0) - 300.0 / 365) < 0.0001)
        #expect(FreedomGoalSheet.summary(fund) == "现在 300 天自由，还差 65 天")
        // 定了日子：多一个倒数，数还是现在的
        let gap = FreedomGoalProgress(goal: FreedomGoal(name: "GAP", targetDays: 730, deadline: day(100)), snapshot: s)
        #expect(gap.daysUntil == 100)
        #expect(gap.freedomLine == "现在 300 / 730 天")
        #expect(gap.targetLine == "还差 430 天自由")
        #expect(gap.countdownLine == "GAP · 100 天后")
        // 够了
        let done = FreedomGoalProgress(goal: FreedomGoal(targetDays: 183), snapshot: s)
        #expect(done.enough == true)
        #expect(done.targetLine == "已达成")
        #expect(done.shortText == nil)
        #expect(FreedomGoalSheet.summary(done) == "现在 300 天自由，够了")
    }

    @Test func coveredAndMissingDataHaveTheirOwnLines() {
        let covered = FreedomGoalProgress(goal: FreedomGoal(targetDays: 730),
                                          snapshot: snapshot(cash: 0, passive: 120 * month))
        #expect(covered.freedomLine == "被动收入已经盖住开销")
        #expect(covered.enough == true)
        #expect(covered.targetLine == "已达成")
        let none = FreedomGoalProgress(goal: FreedomGoal(targetDays: 365), snapshot: snapshot(expenses: []))
        #expect(none.freedomLine == "记下支出、算出日均后才能算")
        #expect(none.progress == nil)
        #expect(none.targetLine == nil)
        #expect(SavingMath.saving(snapshot: snapshot(expenses: []), enteredIncome: 8_000, recordedIncome: nil) == nil)
    }

    @Test func countdownLineForTodayAndPastDays() {
        let s = snapshot()
        #expect(FreedomGoalProgress(goal: FreedomGoal(name: "GAP", targetDays: 365, deadline: now), snapshot: s).countdownLine == "GAP · 就是今天")
        let past = FreedomGoalProgress(goal: FreedomGoal(name: "GAP", targetDays: 365, deadline: day(-3)), snapshot: s)
        #expect(past.daysUntil == -3)
        #expect(past.countdownLine == "GAP · 这一天已经过了")
    }

    @Test func recordedIncomeUsesActiveIncomeOverTheLast90Days() throws {
        let salaries = [-80, -50, -20].map { Income(amount: 9_000, source: "工资", date: day($0)) }
        let passive = Income(amount: 500, source: "利息", isPassive: true, date: day(-10))
        let monthly = try #require(SavingMath.recordedMonthlyIncome(salaries + [passive], now: now))
        #expect(abs(monthly - 27_000 / 80 * month) < 0.01)
        // 收入记录不满 60 天：不推算
        let recent = [-40, -10].map { Income(amount: 9_000, source: "工资", date: day($0)) }
        #expect(SavingMath.recordedMonthlyIncome(recent, now: now) == nil)
        // 填过就用填的
        let s = snapshot()
        let picked = try #require(SavingMath.saving(snapshot: s, enteredIncome: 0, recordedIncome: monthly))
        #expect(picked.basis == .entered)
        #expect(picked.perDay == -120)
    }

    @Test func savingMilestoneNeedsIncome() throws {
        let s = snapshot()
        func savingItem(_ saving: MonthlySaving?) throws -> FreedomCheckItem {
            try #require(FreedomChecklist.evaluate(snapshot: s, saving: saving).items.first { $0.id == 4 })
        }
        let unknown = try savingItem(nil)
        #expect(!unknown.done)
        #expect(unknown.detail.isEmpty)
        let saves = try savingItem(saving(perDay: 100, in: s))
        #expect(saves.done)
        #expect(saves.detail == "每月约存 ¥3,044")
        #expect(try !savingItem(saving(perDay: -10, in: s)).done)
    }

    @Test func checklistHasNineMilestonesInThreeGroups() throws {
        let summary = FreedomChecklist.evaluate(snapshot: snapshot())
        #expect(summary.total == 9)
        // 记录、自由天数、现金流；旧的编号不变，记账天数排在最前、编号 7–9
        #expect(summary.items.map(\.id) == [7, 8, 9, 1, 2, 3, 4, 5, 6])
        #expect(FreedomCheckGroup.allCases.map { summary.items(in: $0).count } == [3, 3, 3])
        // 第一笔在 9 天前：记了 10 天
        let thirty = try #require(summary.items.first { $0.id == 7 })
        #expect(thirty.title == "记账满 30 天")
        #expect(!thirty.done)
        #expect(thirty.detail == "当前 10 / 30 天")
        #expect(thirty.hint == "继续记下每天的花销")
        // 记账天数没满不抢「下一站」：自由天数 300，下一站还是 365 天
        #expect(summary.nextStopTitle == "自由天数 365 天")
        #expect(summary.remainText == "还差 65 天")
    }

    @Test func recordMilestonesCountDaysSinceTheFirstExpense() throws {
        // 89 天前第一笔：记满 90 天；中间不花钱的日子不断档
        let s = snapshot(expenses: [Expense(amount: 9_000, category: "房租", date: day(-89)),
                                    Expense(amount: 1_800, category: "午餐", date: day(-3))])
        let summary = FreedomChecklist.evaluate(snapshot: s)
        let record = summary.items(in: .record)
        #expect(record.map(\.done) == [true, true, false])
        #expect(record[1].achievedNote == "日均不再按大额摊开估算")
        #expect(record[2].detail == "当前 90 / 365 天")

        let empty = FreedomChecklist.evaluate(snapshot: snapshot(expenses: [])).items(in: .record)
        #expect(empty.allSatisfy { !$0.done })
        #expect(empty[0].detail == "当前 0 / 30 天")
        #expect(empty[0].hint == "记下第一笔支出，从那天开始算")
    }

    @Test func savingRowAsksForIncomeWhenUnknown() throws {
        let s = snapshot()
        let unknown = try #require(FreedomChecklist.evaluate(snapshot: s, saving: nil).items.first { $0.id == 4 })
        #expect(unknown.hint == "点这里填上每月到手收入")
        let saves = try #require(FreedomChecklist.evaluate(snapshot: s, saving: saving(perDay: 100, in: s)).items.first { $0.id == 4 })
        #expect(saves.achievedNote == "每月约存 ¥3,044")
    }

    @Test func goalRowDateCarriesTheYearOnlyWhenItIsNotThisYear() {
        #expect(FreedomGoalSection.dateLine(TestSupport.day("2026-06-20"), now: now) == "6月20日")
        #expect(FreedomGoalSection.dateLine(TestSupport.day("2027-05-01"), now: now) == "2027年5月1日")
    }
}
