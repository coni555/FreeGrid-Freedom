// 2.2 按月估算：每月花销含固定支出，算日均时扣掉；不记账时日均 = 日常部分折成的每天；开始记账后 30 天里慢慢过渡到记录；
// 最后一笔之后超过 14 天的断档不再摊薄日均，填了每月花销就按它补那几天；备份带上这个数。
// 规则见 AGENTS.md「2.2 按月估算」。3044 / 月按 30.44 天折成每天 100，下面的数都按这个算。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct MonthlySpendingTests {
    /// 第 n 天的中午（第 1 天是 2026-10-01）
    private func dayNumber(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n - 1, to: TestSupport.day("2026-10-01"))!
            .addingTimeInterval(12 * 3600)
    }

    private func entries(_ pairs: [(Int, Double)]) -> [FreedomMath.BurnEntry] {
        pairs.map { FreedomMath.BurnEntry(date: dayNumber($0.0), amount: $0.1) }
    }

    /// 第 1 天到第 n 天每天 60
    private func daily(_ n: Int) -> [(Int, Double)] { (1...n).map { ($0, 60) } }

    @Test func withoutRecordsTheEstimateIsTheDailyBurn() {
        let burn = FreedomMath.burnEstimate([], everydayEstimate: 3044, now: dayNumber(1))
        #expect(abs(burn.dailyBurn - 100) < 1e-9)
        #expect(burn.basis == .estimate)
        #expect(burn.trackDays == 0)
    }

    @Test func withoutRecordsOrEstimateThereIsNothingToSay() {
        let burn = FreedomMath.burnEstimate([], everydayEstimate: nil, now: dayNumber(1))
        #expect(burn.dailyBurn.isNaN)
    }

    @Test func afterThirtyDaysOfRecordsTheEstimateIsIgnored() {
        let burn = FreedomMath.burnEstimate(entries(daily(30)), everydayEstimate: 9000, now: dayNumber(30))
        #expect(burn.dailyBurn == 60)
        #expect(burn.basis == .records && burn.gapDays == 0)
    }

    @Test func theFirstEntryDoesNotJump() {
        // 每天 100 的估算，第一天记一笔 20：(20 + 29 × 100) / 30，不是直接变成 20
        let burn = FreedomMath.burnEstimate(entries([(1, 20)]), everydayEstimate: 3044, now: dayNumber(1))
        #expect(abs(burn.dailyBurn - (20.0 + 29 * 100) / 30) < 1e-9)
        #expect(burn.basis == .recordsAndEstimate)
        #expect(burn.trackDays == 1)
    }

    @Test func theBurnMovesTowardsTheRecordsDayByDay() {
        // 每天记 60，估算每天 100：从 100 一路慢慢落到 60，每天只动一小步，第 30 天正好是 60
        var previous = 100.0
        for day in 1...30 {
            let burn = FreedomMath.burnEstimate(entries(daily(day)), everydayEstimate: 3044, now: dayNumber(day)).dailyBurn
            #expect(burn < previous)
            #expect(previous - burn < 2)
            previous = burn
        }
        #expect(abs(previous - 60) < 1e-9)
    }

    @Test func aLoneEntryFromAMonthAgoDoesNotHalveTheEstimate() {
        // 第 1 天记一笔 20 就没再记，第 31 天填每天 100 的估算：(20 + 30 × 100) / 31，中间的空天不算一分没花
        let burn = FreedomMath.burnEstimate(entries([(1, 20)]), everydayEstimate: 3044, now: dayNumber(31))
        #expect(abs(burn.dailyBurn - (20.0 + 30 * 100) / 31) < 1e-9)
        #expect(burn.basis == .recordsAndEstimate)
        #expect(burn.gapDays == 16)
        // 第 10 天看也一样：还没记到的 29 天都按估算
        let early = FreedomMath.burnEstimate(entries([(1, 20)]), everydayEstimate: 3044, now: dayNumber(10))
        #expect(abs(early.dailyBurn - (20.0 + 29 * 100) / 30) < 1e-9)
    }

    @Test func withoutAnEstimateRecordsWorkAsBefore() {
        let burn = FreedomMath.burnEstimate(entries(daily(10)), now: dayNumber(10))
        #expect(burn.dailyBurn == 60)
        #expect(burn.basis == .records)
    }

    @Test func theDailyCardSaysItIsBlending() {
        let expenses = [Expense(amount: 20, category: "午餐", date: dayNumber(1))]
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: cash(10_000),
                                         now: dayNumber(1), countsAssets: true, monthlySpending: 3044)
        #expect(HomeStat.dailyNote(snapshot) == String(localized: "按估算和记账"))
    }

    @Test func fourteenQuietDaysStillCount() {
        // 记了 30 天、每天 60，第 44 天看：最后一笔之后 14 天，照常摊
        let burn = FreedomMath.burnEstimate(entries(daily(30)), now: dayNumber(44))
        #expect(burn.gapDays == 0)
        #expect(burn.dailyBurn == 1800.0 / 44)
    }

    @Test func aLongerGapStopsTheBurnFromFalling() {
        // 第 50 天：最后一笔之后 20 天，多出的 6 天不进分母，停在第 44 天的数
        let burn = FreedomMath.burnEstimate(entries(daily(30)), now: dayNumber(50))
        #expect(burn.trackDays == 50)
        #expect(burn.gapDays == 6)
        #expect(burn.dailyBurn == 1800.0 / 44)
        #expect(burn.basis == .records)
        // 第 45 天和第 44 天一样：慢慢停下，不跳
        #expect(FreedomMath.burnEstimate(entries(daily(30)), now: dayNumber(45)).dailyBurn == 1800.0 / 44)
    }

    @Test func theEstimateFillsTheGap() {
        // 前 44 天按记录（共 1800），后 6 天每天按估算 100：(1800 + 600) / 50 = 48
        let burn = FreedomMath.burnEstimate(entries(daily(30)), everydayEstimate: 3044, now: dayNumber(50))
        #expect(abs(burn.dailyBurn - 48) < 1e-9)
        #expect(burn.basis == .recordsAndEstimate)
    }

    @Test func monthlyLoggersAreNotCutShort() {
        // 每月记一次总账：第 1、31 天各 1800。第 46 天离上一笔 15 天，只停 1 天：3600 / 45
        let burn = FreedomMath.burnEstimate(entries([(1, 1800), (31, 1800)]), now: dayNumber(46))
        #expect(burn.gapDays == 1)
        #expect(burn.dailyBurn == 3600.0 / 45)
        // 中间那 29 天空着不算断档
        #expect(FreedomMath.burnEstimate(entries([(1, 1800), (31, 1800)]), now: dayNumber(31)).dailyBurn == 3600.0 / 31)
    }

    @Test func lumpsAreSpreadOverTheRecordedSpan() {
        // 记了 7 天、第 7 天买电脑 6000，第 40 天看：记录段 7 + 14 = 21 天，不满 90 天，电脑按 90 天摊
        let burn = FreedomMath.burnEstimate(entries(daily(7) + [(7, 6000)]), now: dayNumber(40))
        #expect(burn.gapDays == 19)
        #expect(burn.spreadLumps == 6000)
        #expect(abs(burn.dailyBurn - (420.0 / 21 + 6000.0 / 90)) < 1e-9)
    }

    @Test func freedomDaysWithoutAnyRecords() {
        let assets = UserAssets(total: 0)
        assets.cash = 10_000
        let snapshot = FinancialSnapshot(expenses: [], passiveSources: [], assets: assets,
                                         now: dayNumber(1), countsAssets: true, monthlySpending: 3044)
        #expect(snapshot.hasExpenses && !snapshot.hasRecords)
        #expect(snapshot.burnBasis == .estimate)
        guard case .finite(let days) = snapshot.freedom else { Issue.record("应该算得出自由天数"); return }
        #expect(abs(days - 100) < 1e-6)
        // 记账里程碑不因为估算而开始
        #expect(FreedomChecklist.evaluate(snapshot: snapshot).items.first { $0.group == .record }?.progress == 0)
    }

    @Test func thePreviewKeepsUsingTheEstimateForTheGap() {
        let expenses = daily(30).map { Expense(amount: $0.1, category: "午餐", date: dayNumber($0.0)) }
        let assets = UserAssets(total: 0)
        assets.cash = 10_000
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: assets,
                                         now: dayNumber(50), countsAssets: true, monthlySpending: 3044)
        #expect(abs(snapshot.dailyBurn - 48) < 1e-9)
        // 今天记一笔，断档就没了：(1800 + 60) / 50
        let impact = TransactionImpact(snapshot: snapshot, kind: .expense, amount: 60, date: dayNumber(50))
        #expect(abs(impact.newDailyBurn - 1860.0 / 50) < 1e-9)
    }

    // MARK: - 每月花销含固定支出

    private func rent(_ amount: Double) -> Loan {
        Loan(name: "房租", monthlyAmount: amount, dueDay: 5, periodsAtStart: 0,
             startDate: dayNumber(1), sortOrder: 0, isOngoing: true)
    }

    private func cash(_ amount: Double) -> UserAssets {
        let assets = UserAssets(total: 0)
        assets.cash = amount
        return assets
    }

    @Test func fixedExpensesAreInsideTheMonthlyNumber() {
        // 填 3044、房租 1000：日常 2044；首页写的日均还是 3044 折成的 100，没有多算一遍
        let snapshot = FinancialSnapshot(expenses: [], passiveSources: [], assets: cash(10_000), loans: [rent(1000)],
                                         now: dayNumber(1), countsAssets: true, monthlySpending: 3044)
        #expect(snapshot.everydayEstimate == 2044)
        #expect(abs(snapshot.dailyBurn - 2044 / 30.44) < 1e-9)
        #expect(abs(snapshot.dailyCost - 100) < 1e-9)
        #expect(snapshot.burnBasis == .estimate)
    }

    @Test func addingAFixedExpenseBarelyMovesFreedomDays() {
        // 同样每月花 3044：不管有没有把房租单列出来，都是一百来天
        let plain = FinancialSnapshot(expenses: [], passiveSources: [], assets: cash(10_000),
                                      now: dayNumber(1), countsAssets: true, monthlySpending: 3044)
        let withRent = FinancialSnapshot(expenses: [], passiveSources: [], assets: cash(10_000), loans: [rent(1000)],
                                         now: dayNumber(1), countsAssets: true, monthlySpending: 3044)
        guard case .finite(let a) = plain.freedom, case .finite(let b) = withRent.freedom else {
            Issue.record("都应该算得出自由天数"); return
        }
        #expect(abs(a - 100) < 1e-6)
        #expect(abs(a - b) < 31)
    }

    @Test func fixedExpensesOverTheMonthlyNumberAreNotABadData() {
        // 房租比填的数还多：日常 0，只按日历扣房租，不提示「有一笔金额不对」
        let snapshot = FinancialSnapshot(expenses: [], passiveSources: [], assets: cash(10_000), loans: [rent(2000)],
                                         now: dayNumber(1), countsAssets: true, monthlySpending: 1000)
        #expect(snapshot.dailyBurn == 0)
        guard case .finite(let days) = snapshot.freedom else { Issue.record("应该算得出自由天数"); return }
        // 10000 付得起 5 个月房租，第 6 次到期的前一天停住
        #expect(days > 120 && days < 170)
        // 记收入的预览也不报错
        let impact = TransactionImpact(snapshot: snapshot, kind: .income, amount: 100, date: dayNumber(1))
        guard case .finite = impact.newFreedom else { Issue.record("预览应该算得出"); return }
    }

    @Test func recordingAZeroAmountIsStillBadData() {
        // 真的记过账、日均却是 0：这才是数据有问题，放宽只给每月花销
        let run = FreedomMath.freedomRun(netWorth: 1000, dailyBurn: 0, hasExpenses: true,
                                         loans: LoanSchedule.plan(loans: [rent(100)], payments: [], now: dayNumber(1)))
        #expect(run.state == .invalidData)
    }

    @Test func theGapIsFilledWithTheEverydayPartOnly() {
        // 记了 30 天、每天 60；第 50 天看，房租 1000 不进空档：(1800 + 6 × 2044/30.44) / 50
        let expenses = daily(30).map { Expense(amount: $0.1, category: "午餐", date: dayNumber($0.0)) }
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: cash(10_000), loans: [rent(1000)],
                                         now: dayNumber(50), countsAssets: true, monthlySpending: 3044)
        #expect(abs(snapshot.dailyBurn - (1800 + 6 * 2044 / 30.44) / 50) < 1e-9)
        #expect(snapshot.burnBasis == .recordsAndEstimate)
    }

    @Test func theDailyCardAlwaysSaysEstimate() {
        let snapshot = FinancialSnapshot(expenses: [], passiveSources: [], assets: cash(10_000), loans: [rent(1000)],
                                         now: dayNumber(1), countsAssets: true, monthlySpending: 3044)
        #expect(HomeStat.dailyNote(snapshot) == String(localized: "按每月估算"))
    }

    @Test func theTrackCardDoesNotNagPeopleWhoDoNotRecord() {
        let snapshot = FinancialSnapshot(expenses: [], passiveSources: [], assets: cash(10_000),
                                         now: dayNumber(1), countsAssets: true, monthlySpending: 3044)
        let inputs = HomeStat.Inputs(snapshot: snapshot, monthSpent: 0, lastMonthSameSpan: nil, todaySpending: 0, nextFixed: nil)
        #expect(HomeStat.track.display(inputs).unit == String(localized: "天记账"))
    }

    @Test func theWalletRowIsForPeopleWhoNeedIt() {
        #expect(MonthlySpending.showsRow(monthly: nil, hasRecords: false, gapDays: 0))     // 没记过账
        #expect(MonthlySpending.showsRow(monthly: 3000, hasRecords: true, gapDays: 0))     // 已经填过
        #expect(MonthlySpending.showsRow(monthly: nil, hasRecords: true, gapDays: 9))      // 断档
        #expect(!MonthlySpending.showsRow(monthly: nil, hasRecords: true, gapDays: 0))     // 天天记账
    }

    @Test func theBackupCarriesTheEstimate() throws {
        let context = try TestSupport.makeContext()
        let data = try DataIO.exportJSON(context: context, monthlySpending: 3000)
        #expect(try ImportValidator.validate(data: data).monthlySpending == 3000)
        let without = try DataIO.exportJSON(context: context)
        #expect(try ImportValidator.validate(data: without).monthlySpending == nil)
        #expect(String(decoding: without, as: UTF8.self).contains("monthly_spending") == false)
    }
}
