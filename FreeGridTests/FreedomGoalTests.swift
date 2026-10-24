// 离职 / GAP 目标：要多少钱、还要几天、定的日期那天够不够、收入从哪来，以及「每月有结余」那一项。
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

    @Test func requiredMoneyIsTargetDaysTimesDailyNetCost() throws {
        let s = snapshot()
        let required = try #require(FreedomGoalMath.requiredBase(days: 12 * month, snapshot: s))
        #expect(abs(required - 12 * month * 120) < 0.01)
    }

    @Test func countsDownWithMonthlySaving() throws {
        let s = snapshot()
        let goal = FreedomGoal(months: 12)
        let result = FreedomGoalMath.evaluate(goal: goal, snapshot: s, saving: saving(perDay: 100, in: s))
        // 还差 12 × 30.44 × 120 − 36,000 = 7,833.6，每天存 100 → 79 天
        guard case .onTheWay(let days, let ready) = result.status else {
            Issue.record("应该在路上：\(result.status)"); return
        }
        #expect(days == 79)
        #expect(Calendar.current.isDate(ready, inSameDayAs: day(79)))
        #expect(abs(result.progress - 36_000 / (12 * month * 120)) < 0.0001)
        #expect(result.statusLine == "还要 79 天")
    }

    @Test func reachedWhenMoneyAlreadyLastsTheTarget() {
        let s = snapshot()
        let result = FreedomGoalMath.evaluate(goal: FreedomGoal(months: 6), snapshot: s, saving: nil)
        #expect(result.status == .reached)
        #expect(result.progress == 1)
        #expect(result.statusLine == "现在的钱已经够撑 6 个月")
    }

    @Test func passiveIncomeCoveringCostsMeansReached() {
        let s = snapshot(cash: 0, passive: 120 * month)
        let result = FreedomGoalMath.evaluate(goal: FreedomGoal(months: 24), snapshot: s, saving: nil)
        #expect(result.status == .reached)
    }

    @Test func unreachableWhenSpendingMoreThanEarning() {
        let s = snapshot()
        let result = FreedomGoalMath.evaluate(goal: FreedomGoal(months: 12), snapshot: s, saving: saving(perDay: -10, in: s))
        #expect(result.status == .unreachable)
        #expect(result.statusLine == "按现在的结余攒不到")
    }

    @Test func needsIncomeOrDataWhenItCannotCount() {
        let s = snapshot()
        #expect(FreedomGoalMath.evaluate(goal: FreedomGoal(months: 12), snapshot: s, saving: nil).status == .needsIncome)
        let empty = snapshot(expenses: [])
        #expect(FreedomGoalMath.saving(snapshot: empty, enteredIncome: 8_000, recordedIncome: nil) == nil)
        #expect(FreedomGoalMath.evaluate(goal: FreedomGoal(months: 12), snapshot: empty, saving: nil).status == .needsData)
    }

    @Test func leaveDateShowsWhetherThatDayIsEnough() throws {
        let s = snapshot()
        let perDay = saving(perDay: 100, in: s)
        // 100 天后：36,000 + 10,000 = 46,000 → 383 天，够 12 个月
        let later = FreedomGoalMath.evaluate(goal: FreedomGoal(months: 12, leaveDate: day(100)), snapshot: s, saving: perDay)
        let leave = try #require(later.leave)
        #expect(leave.daysUntil == 100)
        #expect(leave.enough == true)
        #expect(later.leaveLine?.hasSuffix("够了") == true)
        // 50 天后：41,000 → 约 341.7 天，差约 0.8 个月
        let sooner = FreedomGoalMath.evaluate(goal: FreedomGoal(months: 12, leaveDate: day(50)), snapshot: s, saving: perDay)
        #expect(sooner.leave?.enough == false)
        #expect(sooner.leaveLine?.contains("还差 0.8 个月") == true)
        // 没有收入：推不到那天
        let unknown = FreedomGoalMath.evaluate(goal: FreedomGoal(months: 12, leaveDate: day(50)), snapshot: s, saving: nil)
        #expect(unknown.leave?.projected == nil)
        #expect(unknown.leaveLine?.hasSuffix("填上收入才能算那天够不够") == true)
    }

    @Test func requiredMoneyWithRentLastsExactlyTheTarget() throws {
        let due = TestSupport.day("2026-07-05")
        let rent = Loan(name: "房租", monthlyAmount: 2_500, dueDay: 5, periodsAtStart: 0,
                        startDate: Calendar.current.date(byAdding: .day, value: -1, to: due)!,
                        sortOrder: 0, isOngoing: true)
        let s = snapshot(loans: [rent])
        let target = 6 * month
        let required = try #require(FreedomGoalMath.requiredBase(days: target, snapshot: s))
        func days(_ base: Double) -> Double {
            if case .finite(let d) = FreedomGoalMath.freedom(base: base, snapshot: s) { return d }
            return .infinity
        }
        #expect(days(required) >= target)
        #expect(days(required - 2) < target)
        // 房租让要的钱比只按日常算多
        #expect(required > target * 120)
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

    @Test func checklistHasSixMilestonesAndADataNote() {
        let summary = FreedomChecklist.evaluate(snapshot: snapshot())
        #expect(summary.total == 6)
        #expect(summary.items.map(\.id) == [1, 2, 3, 4, 5, 6])
        #expect(summary.dataNote == "再记录 80 天，日均趋势会更清晰")
        #expect(FreedomChecklist.evaluate(snapshot: snapshot(expenses: [])).dataNote == "记下第一笔支出后开始判断")
    }
}
