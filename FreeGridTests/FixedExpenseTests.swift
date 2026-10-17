// 固定支出（房租、保险、订阅）和日均里的大额支出摊开：
// 到期日与周期、按日历推演、交租当天只少一天、不打孔、被动收入覆盖的判定、写入与校验、备份往返；
// 记账不满 90 天时单笔大额按 90 天摊。
// 期望天数由 `_local/plans/2026-10-17/fixed-expenses-expected.py` 独立算出。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct FixedExpenseTests {
    /// 2026-10-15 中午；明天是 10-16
    private let now = TestSupport.day("2026-10-15").addingTimeInterval(12 * 3600)

    private func at(_ day: String) -> Date { TestSupport.day(day).addingTimeInterval(12 * 3600) }

    private func assets(cash: Double) -> UserAssets {
        let assets = UserAssets(total: 0)
        assets.cash = cash
        return assets
    }

    /// 日均 100：10 天里花了 1000，第一笔在 9 天前
    private var burn100: [Expense] {
        [Expense(amount: 1000, category: "午餐", date: Calendar.current.date(byAdding: .day, value: -9, to: now)!)]
    }

    /// 下次 `nextDue` 付，之后每 `interval` 个月一次
    private func rent(_ amount: Double = 2500, nextDue: String = "2026-11-05", interval: Int = 1) -> Loan {
        let due = TestSupport.day(nextDue)
        return Loan(name: "房租", monthlyAmount: amount, dueDay: Calendar.current.component(.day, from: due),
                    periodsAtStart: 0, startDate: Calendar.current.date(byAdding: .day, value: -1, to: due)!,
                    sortOrder: 0, isOngoing: true, intervalMonths: interval)
    }

    private func snapshot(cash: Double = 20_000, loans: [Loan], passive: Double = 0,
                          at date: Date? = nil) -> FinancialSnapshot {
        FinancialSnapshot(expenses: burn100,
                          passiveSources: passive > 0 ? [PassiveSource(name: "利息", monthlyAmount: passive)] : [],
                          assets: assets(cash: cash), loans: loans, now: date ?? now, countsAssets: true)
    }

    private func days(_ state: FreedomState) -> Double? {
        if case .finite(let days) = state { return days }
        return nil
    }

    // MARK: - 到期日

    @Test func everyThreeMonthsStartsFromTheNextDueDate() {
        let dates = LoanSchedule.dueDates(after: TestSupport.day("2026-11-04"), dueDay: 5, intervalMonths: 3, count: 4)
        #expect(dates == ["2026-11-05", "2027-02-05", "2027-05-05", "2027-08-05"].map(TestSupport.day))
    }

    @Test func anOngoingScheduleHasNoLastPeriod() {
        let status = LoanSchedule.status(of: rent(), payments: [], now: now)
        #expect(status.nextDue == TestSupport.day("2026-11-05"))
        #expect(!status.isPaidOff)
        // 从起算日（11-04）往后看 400 天：2026-11-05 到 2027-12-05 一共 14 期
        #expect(status.upcoming.count == 14)
        let far = LoanSchedule.status(of: rent(), payments: [], now: at("2040-03-01"))
        #expect(far.overdue.count > 150 && !far.upcoming.isEmpty)
    }

    // MARK: - 推演

    @Test func rentIsPlannedOnItsDueDays() {
        let s = snapshot(loans: [rent()])
        #expect(s.dailyBurn == 100)
        #expect(days(s.freedom) == 112)
        // 房租不打孔，也不在最后一格后面补淡孔
        #expect(s.freedomRun.paymentDays.isEmpty)
        #expect(s.freedomRun.missedPaymentDay == nil)
    }

    @Test func everyThreeMonthsIsPlannedToo() {
        #expect(days(snapshot(cash: 30_000, loans: [rent(7500, interval: 3)]).freedom) == 150)
        #expect(days(snapshot(cash: 30_000, loans: [rent()]).freedom) == 171)
    }

    /// 交租当天：钱少了一大笔，计划里也少了这一期，天数照常只少 1 天
    @Test func payingRentTakesOnlyOneDay() {
        let loan = rent(nextDue: "2026-11-05")
        let before = LoanSchedule.plan(loans: [loan], payments: [], now: at("2026-11-04"))
        let payment = Expense(amount: 2500, category: "房租", date: TestSupport.day("2026-11-05"))
        payment.loanID = loan.id
        payment.countsInBurn = false
        let after = LoanSchedule.plan(loans: [loan], payments: [payment], now: at("2026-11-05"))
        let dayBefore = FreedomMath.freedomRun(netWorth: 20_000, dailyBurn: 100, hasExpenses: true, loans: before)
        let rentDay = FreedomMath.freedomRun(netWorth: 20_000 - 100 - 2500, dailyBurn: 100, hasExpenses: true, loans: after)
        #expect(days(dayBefore.state)! - days(rentDay.state)! == 1)
    }

    @Test func loansStillPunchButRentOnTheSameDayDoesNot() {
        let loan = Loan(name: "车贷", monthlyAmount: 1000, dueDay: 5, periodsAtStart: 2,
                        startDate: TestSupport.day("2026-10-15"), sortOrder: 1)
        let run = snapshot(cash: 50_000, loans: [rent(), loan]).freedomRun
        // 11-05、12-05 两天都有车贷，打孔；之后只剩房租，不打
        #expect(run.paymentDays == [21, 51])
    }

    @Test func passiveCoveringDailyCostStillRunsOutOnRent() {
        // 被动 3000/月 = 每天 100，正好盖住日常；房租每月 2500 一直在扣，第 9 次交不上
        let s = snapshot(loans: [rent()], passive: 3000)
        #expect(days(s.freedom) == 262)
    }

    /// 推演超过 400 天后，固定支出按需往后展开，周期和月底规则照旧
    @Test func theScheduleKeepsItsIntervalBeyondWhatStatusLists() {
        #expect(days(snapshot(cash: 60_000, loans: [rent(7500, interval: 3)], passive: 3000).freedom) == 751)
        #expect(days(snapshot(cash: 40_000, loans: [rent(3000, nextDue: "2026-10-31", interval: 2)],
                              passive: 3000).freedom) == 807)
    }

    @Test func passiveCoveringRentToo_isCovered() {
        #expect(snapshot(loans: [rent()], passive: 6000).freedom == .covered)
    }

    @Test func passiveRatioCountsFixedCosts() {
        // 日常 100/天 + 房租 2500/月（≈ 83.3/天）；被动 3000/月 = 100/天
        let s = snapshot(loans: [rent()], passive: 3000)
        #expect(abs(s.passiveRatio - 100 / (100 + 2500.0 / 30)) < 1e-9)
    }

    /// 首页写的日均含固定支出折成的每天（押一付三按每月折）；推演用的日常日均不变，房租仍在到期日另扣
    @Test func displayedDailyCostAddsFixedCosts() {
        let s = snapshot(loans: [rent(7500, interval: 3)])
        #expect(s.dailyBurn == 100)
        #expect(abs(s.dailyCost - (100 + 2500.0 / 30)) < 1e-9)
        #expect(snapshot(loans: []).dailyCost == 100)
    }

    // MARK: - 写入

    private func context(cash: Double) throws -> ModelContext {
        let context = try TestSupport.makeContext()
        context.insert(assets(cash: cash))
        try context.save()
        return context
    }

    private func cash(_ context: ModelContext) throws -> Double {
        try #require(try context.fetch(FetchDescriptor<UserAssets>()).first).cash
    }

    @Test func rentIsDeductedOnItsDueDayAndStaysOutOfDailyBurn() throws {
        let context = try context(cash: 10_000)
        let loan = try LoanStore.saveFixed(nil, name: "房租", amount: 2500, intervalMonths: 1,
                                           nextDue: TestSupport.day("2026-10-20"), now: now, in: context)
        #expect(loan.isOngoing && loan.dueDay == 20 && loan.periodsAtStart == 0)
        #expect(try LoanStore.processDue(now: at("2026-10-19"), in: context) == 0)
        #expect(try LoanStore.processDue(now: at("2026-11-21"), in: context) == 2)
        #expect(try cash(context) == 5000)
        let payments = try LoanStore.payments(in: context)
        #expect(payments.count == 2 && payments.allSatisfy { !$0.countsInBurn && $0.category == "房租" })
    }

    @Test func changingTheNextDueDateRestartsButRenamingDoesNot() throws {
        let context = try context(cash: 10_000)
        let loan = try LoanStore.saveFixed(nil, name: "房租", amount: 2500, intervalMonths: 1,
                                           nextDue: TestSupport.day("2026-10-20"), now: now, in: context)
        try LoanStore.saveFixed(loan, name: "公寓", amount: 2600, intervalMonths: 1,
                                nextDue: TestSupport.day("2026-10-20"), now: now, in: context)
        #expect(loan.name == "公寓" && loan.monthlyAmount == 2600 && loan.startDate == TestSupport.day("2026-10-19"))
        try LoanStore.saveFixed(loan, name: "公寓", amount: 2600, intervalMonths: 3,
                                nextDue: TestSupport.day("2026-11-01"), now: now, in: context)
        #expect(loan.intervalMonths == 3 && loan.dueDay == 1 && loan.startDate == TestSupport.day("2026-10-31"))
        let status = LoanSchedule.status(of: loan, payments: [], now: now)
        #expect(Array(status.upcoming.prefix(2)) == ["2026-11-01", "2027-02-01"].map(TestSupport.day))
    }

    @Test func rejectsInvalidFixedInput() throws {
        let context = try context(cash: 1000)
        #expect(throws: LoanError.invalidNextDue) {
            try LoanStore.saveFixed(nil, name: "房租", amount: 2500, intervalMonths: 1,
                                    nextDue: TestSupport.day("2026-10-15"), now: now, in: context)
        }
        #expect(throws: LoanError.invalidNextDue) {
            try LoanStore.saveFixed(nil, name: "房租", amount: 2500, intervalMonths: 1,
                                    nextDue: TestSupport.day("2027-10-16"), now: now, in: context)
        }
        #expect(throws: LoanError.invalidInterval) {
            try LoanStore.saveFixed(nil, name: "房租", amount: 2500, intervalMonths: 4,
                                    nextDue: TestSupport.day("2026-11-05"), now: now, in: context)
        }
        #expect(try LoanStore.loans(in: context).isEmpty)
    }

    @Test func backupRoundTripKeepsFixedExpenses() throws {
        let source = try context(cash: 1000)
        // 用真实的今天：导入校验拿真实时间比较未来日期
        let today = Calendar.current.startOfDay(for: .now)
        let nextDue = Calendar.current.date(byAdding: .day, value: 20, to: today)!
        let loan = try LoanStore.saveFixed(nil, name: "保险", amount: 3600, intervalMonths: 12,
                                           nextDue: nextDue, in: source)
        let text = String(decoding: try DataIO.exportJSON(context: source), as: UTF8.self)
        #expect(text.contains("\"is_ongoing\" : true"))
        #expect(text.contains("\"interval_months\" : 12"))

        let target = try TestSupport.makeContext()
        let preview = try DataIO.previewJSON(data: Data(text.utf8), context: target)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)
        let restored = try #require(try LoanStore.loans(in: target).first)
        #expect(restored.id == loan.id && restored.isOngoing && restored.intervalMonths == 12)
        #expect(restored.startDate == loan.startDate && restored.dueDay == loan.dueDay)
    }

    // MARK: - 日均：大额摊开

    private func entries(_ pairs: [(Int, Double)]) -> [FreedomMath.BurnEntry] {
        pairs.map { FreedomMath.BurnEntry(date: Calendar.current.date(byAdding: .day, value: $0.0 - 1,
                                                                         to: TestSupport.day("2026-10-01"))!,
                                          amount: $0.1) }
    }

    /// 第 1 天到第 n 天每天 60
    private func daily(_ n: Int) -> [(Int, Double)] { (1...n).map { ($0, 60) } }

    private func dayNumber(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n - 1, to: TestSupport.day("2026-10-01"))!
            .addingTimeInterval(12 * 3600)
    }

    @Test func aLaptopInTheFirstWeekIsSpreadOverNinetyDays() {
        let burn = FreedomMath.burnEstimate(entries(daily(7) + [(7, 6000)]), now: dayNumber(7))
        #expect(burn.trackDays == 7)
        #expect(burn.spreadLumps == 6000)
        #expect(abs(burn.dailyBurn - (60 + 6000.0 / 90)) < 1e-9)
    }

    @Test func afterNinetyDaysItIsPlainTotalOverDays() {
        let all = entries(daily(90) + [(30, 6000)])
        let burn = FreedomMath.burnEstimate(all, now: dayNumber(90))
        #expect(burn.spreadLumps == 0)
        #expect(burn.dailyBurn == all.reduce(0) { $0 + $1.amount } / 90)
    }

    @Test func peopleWhoLogOnceAMonthAreNotSpread() {
        let burn = FreedomMath.burnEstimate(entries([(1, 1800), (31, 1800)]), now: dayNumber(31))
        #expect(burn.spreadLumps == 0)
        #expect(burn.dailyBurn == 3600.0 / 31)
    }

    @Test func aSingleFirstExpenseIsNeverALump() {
        let burn = FreedomMath.burnEstimate(entries([(1, 6000)]), now: dayNumber(1))
        #expect(burn.spreadLumps == 0 && burn.dailyBurn == 6000)
    }

    @Test func withOnlyTwoDaysNothingIsALump() {
        // 一天 1 块、一天 100：只有两天的账，看不出哪笔不寻常
        let burn = FreedomMath.burnEstimate(entries([(1, 1), (10, 100)]), now: dayNumber(10))
        #expect(burn.spreadLumps == 0 && burn.dailyBurn == 101.0 / 10)
    }

    /// 房租没设成固定支出、当普通支出记（日常 60，第 7、37、67 天各 2500）：日均一步步涨到真实的 143，不来回跳。
    /// 期望值见 `_local/plans/2026-10-17/rent-recorded-as-expense.py`
    @Test func rentRecordedAsAnExpenseClimbsSmoothly() {
        func ledger(_ t: Int) -> [FreedomMath.BurnEntry] {
            entries(daily(t) + [7, 37, 67].filter { $0 <= t }.map { ($0, 2500.0) })
        }
        func burn(_ t: Int) -> Double { FreedomMath.burnEstimate(ledger(t), now: dayNumber(t)).dailyBurn }
        #expect(abs(burn(7) - (60 + 2500.0 / 90)) < 1e-9)
        #expect(abs(burn(36) - (60 + 2500.0 / 90)) < 1e-9)
        #expect(abs(burn(37) - (60 + 5000.0 / 90)) < 1e-9)
        #expect(abs(burn(67) - (60 + 7500.0 / 90)) < 1e-9)
        #expect(burn(90) == (90 * 60 + 7500.0) / 90)
    }

    @Test func smallerPurchasesStayAsTheyAre() {
        // 1000 不到平常一天（60）的 30 倍，照实算
        let burn = FreedomMath.burnEstimate(entries(daily(7) + [(7, 1000)]), now: dayNumber(7))
        #expect(burn.spreadLumps == 0 && burn.dailyBurn == 1420.0 / 7)
    }

    @Test func thePreviewSpreadsTheSameWay() {
        let expenses = daily(6).map { Expense(amount: $0.1, category: "午餐", date: dayNumber($0.0)) }
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: assets(cash: 20_000),
                                         now: dayNumber(7), countsAssets: true)
        let impact = TransactionImpact(snapshot: snapshot, kind: .expense, amount: 6000, date: dayNumber(7))
        #expect(abs(impact.newDailyBurn - (360.0 / 7 + 6000.0 / 90)) < 1e-9)
    }
}
