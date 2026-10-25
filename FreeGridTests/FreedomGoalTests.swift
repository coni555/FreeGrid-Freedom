// 自己的目标：存取、只定天数时还差多少和每月多几天、定了日子时离那天几天和那天的自由天数、够不够、收入从哪来，以及自检清单。
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
        FreedomGoalMath.saving(snapshot: s, enteredIncome: (120 + perDay) * month, recordedIncome: nil)
    }

    @Test func goalsRoundTripThroughPreferences() {
        let gap = FreedomGoal(name: "GAP", targetDays: 730, deadline: day(189))
        let fund = FreedomGoal(name: "", targetDays: 365)
        let stored = FreedomGoalStore.encode([gap, fund])
        #expect(FreedomGoalStore.decode(stored) == [gap, fund])
        #expect(FreedomGoalStore.decode("") == [])
        #expect(FreedomGoalStore.decode("not json") == [])
        // 天数和日子都没有的不算；最多三个
        #expect(!FreedomGoal(name: "空的").isValid)
        let four = (0..<4).map { FreedomGoal(targetDays: 100 + $0) }
        #expect(FreedomGoalStore.decode(FreedomGoalStore.encode(four)).count == 3)
        // 改了替换、新的加在最后
        var edited = gap
        edited.targetDays = 365
        #expect(FreedomGoalStore.saving(edited, into: [gap, fund]) == [edited, fund])
        #expect(FreedomGoalStore.saving(FreedomGoal(targetDays: 30), into: [gap, fund, fund]).count == 3)
        // 没起名字：只有天数叫「攒够一年」，有日子的叫「我的目标」
        #expect(fund.displayName == "攒够一年")
        #expect(FreedomGoal(deadline: day(10)).displayName == "我的目标")
        #expect(gap.displayName == "GAP")
    }

    @Test func projectsFreedomToTheDeadline() throws {
        let s = snapshot()
        let perDay = saving(perDay: 100, in: s)
        // 100 天后：36,000 + 10,000 = 46,000 → 383 天，够撑一年
        let later = FreedomGoalMath.evaluate(goal: FreedomGoal(name: "GAP", targetDays: 365, deadline: day(100)), snapshot: s, saving: perDay)
        #expect(later.daysUntil == 100)
        #expect(later.projected)
        #expect(later.freedomLine == "那天大约有 383 天自由")
        #expect(later.enough == true)
        #expect(later.targetLine == "够撑一年")
        #expect(later.countdownLine == "GAP · 100 天后")
        #expect(FreedomGoalSheet.summary(later) == "那天约 383 天自由，够了")
        // 50 天后：41,000 → 341.7 天，还差 24 天自由
        let sooner = FreedomGoalMath.evaluate(goal: FreedomGoal(targetDays: 365, deadline: day(50)), snapshot: s, saving: perDay)
        #expect(sooner.enough == false)
        #expect(try abs(#require(sooner.progress) - 41_000.0 / 120 / 365) < 0.0001)
        #expect(sooner.targetLine == "还差 24 天自由")
        #expect(FreedomGoalSheet.summary(sooner) == "那天约 342 天自由，还差 24 天")
        // 只定日子：没有进度条
        let noTarget = FreedomGoalMath.evaluate(goal: FreedomGoal(deadline: day(50)), snapshot: s, saving: perDay)
        #expect(noTarget.progress == nil)
        #expect(noTarget.targetLine == nil)
        #expect(noTarget.footnote == "按每月约存 ¥3,044 算 · 你填的收入")
    }

    @Test func daysOnlyGoalShowsShortfallAndMonthlyGain() {
        let s = snapshot()
        // 现在 300 天；每天多存 100 → 每月多 3,044 → 约多 25 天
        let goal = FreedomGoal(name: "应急金", targetDays: 365)
        let result = FreedomGoalMath.evaluate(goal: goal, snapshot: s, saving: saving(perDay: 100, in: s))
        #expect(result.daysUntil == nil)
        #expect(!result.projected)
        #expect(result.freedomLine == "现在 300 / 365 天")
        #expect(result.targetLine == "还差 65 天自由")
        #expect(result.footnote == "按现在的速度，每月约多 25 天自由")
        #expect(result.countdownLine == nil)
        #expect(FreedomGoalSheet.summary(result) == "现在 300 天自由，还差 65 天")
        // 存不下钱：每月少几天
        let shrinking = FreedomGoalMath.evaluate(goal: goal, snapshot: s, saving: saving(perDay: -10, in: s))
        #expect(shrinking.footnote == "按现在的速度，每月约少 3 天自由")
        // 不知道收入：提示填上
        #expect(FreedomGoalMath.evaluate(goal: goal, snapshot: s, saving: nil).footnote == "填上每月收入，看每月能多几天")
        // 已经够了：写「已达成」，不再写速度
        let done = FreedomGoalMath.evaluate(goal: FreedomGoal(targetDays: 183), snapshot: s, saving: saving(perDay: 100, in: s))
        #expect(done.targetLine == "已达成")
        #expect(done.footnote == nil)
    }

    @Test func spendingMoreThanEarningShrinksThatDay() {
        let s = snapshot()
        let result = FreedomGoalMath.evaluate(goal: FreedomGoal(deadline: day(100)), snapshot: s, saving: saving(perDay: -10, in: s))
        // 36,000 − 1,000 = 35,000 → 291.7 天
        #expect(result.freedomLine == "那天大约有 292 天自由")
    }

    @Test func withoutIncomeShowsTodaysFreedom() {
        let s = snapshot()
        let result = FreedomGoalMath.evaluate(goal: FreedomGoal(targetDays: 183, deadline: day(100)), snapshot: s, saving: nil)
        #expect(!result.projected)
        #expect(result.freedomLine == "现在有 300 天自由")
        #expect(result.targetLine == "够撑半年")
    }

    @Test func coveredAndMissingDataHaveTheirOwnLines() {
        let covered = FreedomGoalMath.evaluate(goal: FreedomGoal(targetDays: 730, deadline: day(10)),
                                               snapshot: snapshot(cash: 0, passive: 120 * month), saving: nil)
        #expect(covered.freedomLine == "被动收入已经盖住开销")
        #expect(covered.enough == true)
        let empty = snapshot(expenses: [])
        #expect(FreedomGoalMath.saving(snapshot: empty, enteredIncome: 8_000, recordedIncome: nil) == nil)
        let none = FreedomGoalMath.evaluate(goal: FreedomGoal(targetDays: 365, deadline: day(10)), snapshot: empty, saving: nil)
        #expect(none.freedomLine == "记下支出、算出日均后才能算")
        #expect(none.progress == nil)
    }

    @Test func countdownLineForTodayAndPastDays() {
        let s = snapshot()
        #expect(FreedomGoalMath.evaluate(goal: FreedomGoal(name: "GAP", deadline: now), snapshot: s, saving: nil).countdownLine == "GAP · 就是今天")
        let past = FreedomGoalMath.evaluate(goal: FreedomGoal(name: "GAP", deadline: day(-3)), snapshot: s, saving: saving(perDay: 100, in: s))
        #expect(past.daysUntil == -3)
        #expect(past.countdownLine == "GAP · 这一天已经过了")
        // 已经过了的日子不再往后推钱
        #expect(past.freedom == .finite(days: 300))
    }

    @Test func rentIsDeductedOnTheWayToo() throws {
        let due = TestSupport.day("2026-07-05")
        let rent = Loan(name: "房租", monthlyAmount: 2_500, dueDay: 5, periodsAtStart: 0,
                        startDate: Calendar.current.date(byAdding: .day, value: -1, to: due)!,
                        sortOrder: 0, isOngoing: true)
        let s = snapshot(loans: [rent])
        let result = FreedomGoalMath.evaluate(goal: FreedomGoal(deadline: day(100)), snapshot: s, saving: saving(perDay: 100, in: s))
        // 房租也算进开销，每天存下的变少；那天的钱再按首页同一套推演扣房租
        let perDay = try #require(result.saving).perDay
        #expect(abs(perDay - (100 - s.dailyFixed)) < 0.0001)
        #expect(result.freedom == FreedomGoalMath.freedom(base: 36_000 + perDay * 100, snapshot: s))
        guard case .finite(let days) = result.freedom else { Issue.record("应该是有限天数"); return }
        #expect(days < (36_000 + perDay * 100) / 120)
    }

    @Test func recordedIncomeUsesActiveIncomeOverTheLast90Days() throws {
        let salaries = [-80, -50, -20].map { Income(amount: 9_000, source: "工资", date: day($0)) }
        let passive = Income(amount: 500, source: "利息", isPassive: true, date: day(-10))
        let monthly = try #require(FreedomGoalMath.recordedMonthlyIncome(salaries + [passive], now: now))
        #expect(abs(monthly - 27_000 / 80 * month) < 0.01)
        // 收入记录不满 60 天：不推算
        let recent = [-40, -10].map { Income(amount: 9_000, source: "工资", date: day($0)) }
        #expect(FreedomGoalMath.recordedMonthlyIncome(recent, now: now) == nil)
        // 填过就用填的
        let s = snapshot()
        let picked = try #require(FreedomGoalMath.saving(snapshot: s, enteredIncome: 0, recordedIncome: monthly))
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
        #expect(FreedomGoalSection.dateLine(TestSupport.day("2026-06-20"), target: nil, now: now) == "6月20日")
        #expect(FreedomGoalSection.dateLine(TestSupport.day("2027-05-01"), target: 730, now: now) == "2027年5月1日 · 想撑两年")
    }
}
