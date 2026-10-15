// Pro 每月还款：按日历推演的自由天数、格子打孔、到期自动扣、没扣成的那期、旧月供不计日均、备份往返。
// 期望数字由 `_local/plans/2026-10-15/expected-days.py` 独立算出。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct LoanTests {
    /// 2026-10-15 中午；明天是 10-16
    private let now = TestSupport.day("2026-10-15").addingTimeInterval(12 * 3600)

    private func at(_ day: String) -> Date { TestSupport.day(day).addingTimeInterval(12 * 3600) }

    private func assets(cash: Double, locked: Double = 0) -> UserAssets {
        let assets = UserAssets(total: 0)
        assets.cash = cash
        assets.lockedAssets = locked
        return assets
    }

    /// 日均 100：10 天里花了 1000，第一笔在 9 天前
    private var burn100: [Expense] {
        [Expense(amount: 1000, category: "午餐", date: Calendar.current.date(byAdding: .day, value: -9, to: now)!)]
    }

    private func loan(_ amount: Double = 3000, dueDay: Int = 14, periods: Int = 24) -> Loan {
        Loan(name: "房贷", monthlyAmount: amount, dueDay: dueDay, periodsAtStart: periods,
             startDate: TestSupport.day("2026-10-15"), sortOrder: 0)
    }

    private func snapshot(cash: Double = 20_000, locked: Double = 0, loans: [Loan],
                          passive: Double = 0, counts: Bool = true, extra: [Expense] = []) -> FinancialSnapshot {
        FinancialSnapshot(expenses: burn100 + extra,
                          passiveSources: passive > 0 ? [PassiveSource(name: "利息", monthlyAmount: passive)] : [],
                          assets: assets(cash: cash, locked: locked), loans: loans, now: now, countsAssets: counts)
    }

    private func days(_ snapshot: FinancialSnapshot) -> Double? {
        if case .finite(let days) = snapshot.freedom { return days }
        return nil
    }

    // MARK: - 期望表 A–K

    @Test func aBaseline() {
        let s = snapshot(loans: [loan()])
        #expect(s.dailyBurn == 100)
        #expect(days(s) == 110)
        #expect(s.freedomRun.paymentDays == [30, 60, 91])
    }

    @Test func bDueTomorrow() {
        #expect(days(snapshot(loans: [loan(dueDay: 16)])) == 92)
    }

    @Test func cOnlyTwoPeriodsLeft() {
        #expect(days(snapshot(loans: [loan(periods: 2)])) == 140)
    }

    @Test func dDueOn31stFallsToMonthEnd() {
        #expect(days(snapshot(loans: [loan(dueDay: 31)])) == 107)
        let dates = LoanSchedule.dueDates(after: TestSupport.day("2026-10-15"), dueDay: 31, count: 5)
        #expect(dates == ["2026-10-31", "2026-11-30", "2026-12-31", "2027-01-31", "2027-02-28"].map(TestSupport.day))
    }

    @Test func ePassiveIncomeOffsetsLivingCost() {
        #expect(days(snapshot(loans: [loan()], passive: 1500)) == 149)
    }

    @Test func fPassiveCoveringLivingCostStillRunsOutOnRepayments() {
        #expect(days(snapshot(loans: [loan()], passive: 3000)) == 210)
    }

    @Test func gPassiveCoveringEverythingIsCovered() {
        #expect(snapshot(loans: [loan()], passive: 6000).freedom == .covered)
    }

    @Test func hNotEnoughCashForTomorrowsRepayment() {
        #expect(days(snapshot(cash: 2500, loans: [loan(dueDay: 16)])) == 0)
    }

    @Test func iTwoLoans() {
        let car = Loan(name: "车贷", monthlyAmount: 1000, dueDay: 1, periodsAtStart: 6,
                       startDate: TestSupport.day("2026-10-15"), sortOrder: 1)
        #expect(days(snapshot(loans: [loan(), car])) == 90)
    }

    @Test func jCountedAssetsJoinTheRunAndTheSwitchStillWorks() {
        #expect(days(snapshot(locked: 10_000, loans: [loan()])) == 150)
        #expect(days(snapshot(locked: 10_000, loans: [loan()], counts: false)) == 110)
    }

    @Test func kNoLoanIsExactlyTheOldFormula() {
        let s = snapshot(loans: [])
        #expect(days(s) == 200)
        #expect(s.freedom == FreedomMath.freedomState(netWorth: 20_000, dailyBurn: 100, hasExpenses: true))
        #expect(s.freedomRun.paymentDays.isEmpty)
        // 已经还清的贷款也一样
        let paidOff = loan(periods: 0)
        #expect(snapshot(loans: [paidOff]).freedom == s.freedom)
    }

    // MARK: - 格子

    @Test func gridPunchesRepaymentDaysOnlyInDayCells() {
        let a = snapshot(loans: [loan()])
        let grid = FreedomMath.gridState(for: a.freedom, lockedAssets: 0, netWorth: a.freedomBase,
                                         paymentDays: a.freedomRun.paymentDays)
        #expect(grid.count == 110)
        #expect(grid.paymentCells == [29, 59, 90])

        let b = snapshot(loans: [loan(dueDay: 16)])
        let gridB = FreedomMath.gridState(for: b.freedom, lockedAssets: 0, netWorth: b.freedomBase,
                                          paymentDays: b.freedomRun.paymentDays)
        #expect(gridB.count == 92)
        #expect(gridB.paymentCells == [0, 31, 61])

        // 天数到了月格就不打孔
        let rich = snapshot(cash: 200_000, loans: [loan(periods: 2)])
        let monthGrid = FreedomMath.gridState(for: rich.freedom, lockedAssets: 0, netWorth: rich.freedomBase,
                                              paymentDays: rich.freedomRun.paymentDays)
        #expect(monthGrid.unit == .month)
        #expect(monthGrid.paymentCells.isEmpty)
    }

    // MARK: - 记一笔的预览和趋势用同一口径

    @Test func transactionPreviewRunsTheSameSchedule() {
        let a = snapshot(loans: [loan()])
        let impact = TransactionImpact(snapshot: a, kind: .income, amount: 3000)
        #expect(impact.newFreedom == .finite(days: 121))
    }

    @Test func trendEndsAtTheSameNumberAsTheHero() throws {
        let start = Calendar.current.date(byAdding: .day, value: -60, to: now)!
        let expenses = [Expense(amount: 6100, category: "午餐", date: start)]
        let s = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: assets(cash: 20_000),
                                  loans: [loan()], now: now, countsAssets: true)
        let history = FreedomMath.freedomDaysHistory(
            expenses: expenses, incomes: [], currentNetWorth: s.freedomBase,
            firstRecordDate: s.firstExpenseDate, loans: [loan()], now: now)
        #expect(history.count >= 3)
        #expect(history.last?.state == s.freedom)
    }

    // MARK: - 到期自动扣

    private func context(cash: Double) throws -> ModelContext {
        let context = try TestSupport.makeContext()
        context.insert(assets(cash: cash))
        try context.save()
        return context
    }

    private func cash(_ context: ModelContext) throws -> Double {
        try #require(try context.fetch(FetchDescriptor<UserAssets>()).first).cash
    }

    private func status(_ loan: Loan, _ context: ModelContext, on day: String) throws -> LoanSchedule.Status {
        LoanSchedule.status(of: loan, payments: try LoanStore.payments(in: context), now: at(day))
    }

    @Test func catchesUpMissedDueDatesOnceAndOnlyOnce() throws {
        let context = try context(cash: 20_000)
        let loan = try LoanStore.save(nil, name: "房贷", monthlyAmount: 3000, dueDay: 14, remaining: 24,
                                      now: now, in: context)
        #expect(try status(loan, context, on: "2026-10-15").remaining == 24)

        #expect(try LoanStore.processDue(now: at("2026-12-20"), in: context) == 2)
        let payments = try LoanStore.payments(in: context).sorted { $0.date < $1.date }
        #expect(payments.map(\.date) == [TestSupport.day("2026-11-14"), TestSupport.day("2026-12-14")])
        #expect(payments.allSatisfy { !$0.countsInBurn && $0.category == "房贷" && $0.amount == 3000 })
        #expect(try cash(context) == 14_000)
        #expect(try status(loan, context, on: "2026-12-20").remaining == 22)

        // 再打开一次不会重复扣
        #expect(try LoanStore.processDue(now: at("2026-12-20"), in: context) == 0)
        #expect(try cash(context) == 14_000)
    }

    @Test func undoingAPaymentLeavesThatPeriodPendingAndNotReDeducted() throws {
        let context = try context(cash: 20_000)
        let loan = try LoanStore.save(nil, name: "房贷", monthlyAmount: 3000, dueDay: 14, remaining: 24,
                                      now: now, in: context)
        try LoanStore.processDue(now: at("2026-12-20"), in: context)
        let december = try #require(try LoanStore.payments(in: context).first { $0.date == TestSupport.day("2026-12-14") })

        try LedgerStore.undo(id: december.id, kind: .expense, in: context)
        #expect(try cash(context) == 17_000)
        let afterUndo = try status(loan, context, on: "2026-12-20")
        #expect(afterUndo.remaining == 23)
        #expect(afterUndo.pending == [TestSupport.day("2026-12-14")])
        #expect(try LoanStore.processDue(now: at("2026-12-21"), in: context) == 0)
        #expect(try cash(context) == 17_000)

        try LoanStore.resolvePending(loan, dueDate: TestSupport.day("2026-12-14"), fromCash: true,
                                     now: at("2026-12-21"), in: context)
        #expect(try cash(context) == 14_000)
        #expect(try status(loan, context, on: "2026-12-21").remaining == 22)
        #expect(try status(loan, context, on: "2026-12-21").pending.isEmpty)
    }

    @Test func notEnoughCashLeavesThePeriodPendingUntilTheUserDecides() throws {
        let context = try context(cash: 2000)
        let loan = try LoanStore.save(nil, name: "房贷", monthlyAmount: 3000, dueDay: 14, remaining: 24,
                                      now: now, in: context)
        #expect(try LoanStore.processDue(now: at("2026-11-20"), in: context) == 0)
        #expect(try cash(context) == 2000)
        #expect(try status(loan, context, on: "2026-11-20").pending == [TestSupport.day("2026-11-14")])

        // 推演里这一期当作今天就要付：付不起就是 0 天
        let s = FinancialSnapshot(expenses: burn100 + (try LoanStore.payments(in: context)), passiveSources: [],
                                  assets: assets(cash: 2000), loans: [loan], now: at("2026-11-20"), countsAssets: true)
        #expect(s.freedom == .finite(days: 0))

        try LoanStore.resolvePending(loan, dueDate: TestSupport.day("2026-11-14"), fromCash: false,
                                     now: at("2026-11-20"), in: context)
        #expect(try cash(context) == 2000)
        let settled = try status(loan, context, on: "2026-11-20")
        #expect(settled.pending.isEmpty)
        #expect(settled.remaining == 23)
        #expect(throws: LoanError.notPending) {
            try LoanStore.resolvePending(loan, dueDate: TestSupport.day("2026-11-14"), fromCash: false,
                                         now: at("2026-11-20"), in: context)
        }
    }

    @Test func aLoanAddedOnItsDueDayStartsNextMonth() throws {
        let context = try context(cash: 20_000)
        let loan = try LoanStore.save(nil, name: "房贷", monthlyAmount: 3000, dueDay: 14, remaining: 2,
                                      now: at("2026-10-14"), in: context)
        #expect(try LoanStore.processDue(now: at("2026-10-14"), in: context) == 0)
        let s = try status(loan, context, on: "2026-10-14")
        #expect(s.upcoming == [TestSupport.day("2026-11-14"), TestSupport.day("2026-12-14")])
        #expect(s.lastDue == TestSupport.day("2026-12-14"))
    }

    @Test func editingPeriodsRestartsFromTodayButRenamingKeepsProgress() throws {
        let context = try context(cash: 20_000)
        let loan = try LoanStore.save(nil, name: "房贷", monthlyAmount: 3000, dueDay: 14, remaining: 24,
                                      now: now, in: context)
        try LoanStore.processDue(now: at("2026-11-20"), in: context)
        #expect(try status(loan, context, on: "2026-11-20").remaining == 23)

        try LoanStore.save(loan, name: "公积金房贷", monthlyAmount: 3000, dueDay: 14, remaining: 23,
                           now: at("2026-11-20"), in: context)
        #expect(loan.startDate == TestSupport.day("2026-10-15"))
        #expect(try status(loan, context, on: "2026-11-20").remaining == 23)

        try LoanStore.save(loan, name: "公积金房贷", monthlyAmount: 3000, dueDay: 14, remaining: 10,
                           now: at("2026-11-20"), in: context)
        #expect(loan.startDate == TestSupport.day("2026-11-20"))
        #expect(try status(loan, context, on: "2026-11-20").remaining == 10)
        #expect(try LoanStore.processDue(now: at("2026-11-20"), in: context) == 0)
    }

    @Test func rejectsInvalidInput() throws {
        let context = try context(cash: 0)
        #expect(throws: LoanError.invalidName) {
            try LoanStore.save(nil, name: "  ", monthlyAmount: 3000, dueDay: 14, remaining: 24, in: context)
        }
        #expect(throws: LoanError.invalidAmount) {
            try LoanStore.save(nil, name: "房贷", monthlyAmount: 0, dueDay: 14, remaining: 24, in: context)
        }
        #expect(throws: LoanError.invalidDueDay) {
            try LoanStore.save(nil, name: "房贷", monthlyAmount: 3000, dueDay: 32, remaining: 24, in: context)
        }
        #expect(throws: LoanError.invalidPeriods) {
            try LoanStore.save(nil, name: "房贷", monthlyAmount: 3000, dueDay: 14, remaining: 0, in: context)
        }
        #expect(try LoanStore.loans(in: context).isEmpty)
    }

    // MARK: - 以前记成支出的月供

    @Test func markingOldRepaymentsTakesThemOutOfDailyBurn() throws {
        let context = try context(cash: 20_000)
        let first = Calendar.current.date(byAdding: .day, value: -149, to: now)!
        context.insert(Expense(amount: 12_000, category: "其他", date: first))
        for month in 0..<6 {
            context.insert(Expense(amount: 3000, category: "其他", note: "房贷",
                                   date: Calendar.current.date(byAdding: .day, value: -25 * month, to: now)!))
        }
        try context.save()
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let before = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: assets(cash: 20_000),
                                       now: now, countsAssets: true)
        #expect(before.dailyBurn == 200)

        let candidates = LoanStore.pastRepaymentCandidates(monthlyAmount: 3000, in: expenses)
        #expect(candidates.count == 6)
        try LoanStore.save(nil, name: "房贷", monthlyAmount: 3000, dueDay: 14, remaining: 24,
                           pastRepayments: candidates, excludedFromBurn: Set(candidates.map(\.id)),
                           now: now, in: context)
        let after = FinancialSnapshot(expenses: try context.fetch(FetchDescriptor<Expense>()), passiveSources: [],
                                      assets: assets(cash: 20_000), now: now, countsAssets: true)
        #expect(after.dailyBurn == 80)
        #expect(after.trackDays == 150)
        // 记录本身还在
        #expect(try context.fetch(FetchDescriptor<Expense>()).count == 7)
    }

    // MARK: - 备份

    @Test func backupRoundTripKeepsLoansPaymentsAndBurnFlags() throws {
        let source = try context(cash: 7000)
        let old = Expense(amount: 3000, category: "其他", date: TestSupport.day("2026-05-14"))
        source.insert(old)
        try source.save()
        let loan = try LoanStore.save(nil, name: "房贷", monthlyAmount: 3000, dueDay: 14, remaining: 24,
                                      pastRepayments: [old], excludedFromBurn: [old.id],
                                      now: at("2026-06-15"), in: source)
        // 7、8 月扣成，9 月现金不够，用户说从别处还了
        #expect(try LoanStore.processDue(now: at("2026-09-20"), in: source) == 2)
        try LoanStore.resolvePending(loan, dueDate: TestSupport.day("2026-09-14"), fromCash: false,
                                     now: at("2026-09-20"), in: source)
        let before = try status(loan, source, on: "2026-09-20")
        #expect(before.remaining == 21)

        let data = try DataIO.exportJSON(context: source)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"loans\""))
        #expect(text.contains("\"loan_id\""))
        #expect(text.contains("\"counts_in_burn\" : false"))

        let target = try TestSupport.makeContext()
        let preview = try DataIO.previewJSON(data: data, context: target)
        #expect(preview.loansNew.count == 1)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)

        let restored = try #require(try LoanStore.loans(in: target).first)
        #expect(restored.id == loan.id)
        #expect(restored.name == "房贷" && restored.monthlyAmount == 3000 && restored.dueDay == 14)
        #expect(restored.periodsAtStart == 24)
        #expect(restored.startDate == TestSupport.day("2026-06-15"))
        #expect(restored.processedThrough == TestSupport.day("2026-09-14"))
        #expect(restored.settledDates == [TestSupport.day("2026-09-14")])
        #expect(try status(restored, target, on: "2026-09-20") == before)
        let expenses = try target.fetch(FetchDescriptor<Expense>())
        #expect(expenses.filter { $0.loanID == loan.id }.count == 2)
        #expect(expenses.first { $0.id == old.id }?.countsInBurn == false)
        #expect(expenses.filter(\.countsInBurn).isEmpty)

        // 同一份再导一次不会多出一笔贷款
        let again = try DataIO.previewJSON(data: data, context: target)
        #expect(again.loansNew.isEmpty)
    }

    @Test func aLedgerWithoutLoansExportsNoLoanFields() throws {
        let context = try context(cash: 1000)
        context.insert(Expense(amount: 30, category: "午餐", date: TestSupport.day("2026-10-01")))
        try context.save()
        let text = String(decoding: try DataIO.exportJSON(context: context), as: UTF8.self)
        #expect(!text.contains("loan"))
        #expect(!text.contains("counts_in_burn"))
    }

    @Test func purgeRemovesLoans() throws {
        let context = try context(cash: 1000)
        try LoanStore.save(nil, name: "房贷", monthlyAmount: 3000, dueDay: 14, remaining: 24, now: now, in: context)
        try DataIO.purgeAll(context: context)
        #expect(try LoanStore.loans(in: context).isEmpty)
    }
}
