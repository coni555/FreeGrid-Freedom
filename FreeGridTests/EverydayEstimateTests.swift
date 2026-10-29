// 2.2 按月估算日常开销：不记账时日均 = 估算折成的每天；最后一笔之后超过 14 天的断档不再摊薄日均，
// 填了估算就按估算补那几天；备份带上这个数。规则见 AGENTS.md「2.2 按月估算日常开销」。
// 估算 3044 / 月按 30.44 天折成每天 100，下面的数都按这个算。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct EverydayEstimateTests {
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
        let burn = FreedomMath.burnEstimate([], monthlyEstimate: 3044, now: dayNumber(1))
        #expect(abs(burn.dailyBurn - 100) < 1e-9)
        #expect(burn.basis == .estimate)
        #expect(burn.trackDays == 0)
    }

    @Test func withoutRecordsOrEstimateThereIsNothingToSay() {
        let burn = FreedomMath.burnEstimate([], monthlyEstimate: nil, now: dayNumber(1))
        #expect(burn.dailyBurn.isNaN)
        #expect(FreedomMath.burnEstimate([], monthlyEstimate: 0, now: dayNumber(1)).dailyBurn.isNaN)
    }

    @Test func recordingPeopleIgnoreTheEstimate() {
        let burn = FreedomMath.burnEstimate(entries(daily(10)), monthlyEstimate: 9000, now: dayNumber(10))
        #expect(burn.dailyBurn == 60)
        #expect(burn.basis == .records && burn.gapDays == 0)
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
        let burn = FreedomMath.burnEstimate(entries(daily(30)), monthlyEstimate: 3044, now: dayNumber(50))
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
                                         now: dayNumber(1), countsAssets: true, monthlyEstimate: 3044)
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
                                         now: dayNumber(50), countsAssets: true, monthlyEstimate: 3044)
        #expect(abs(snapshot.dailyBurn - 48) < 1e-9)
        // 今天记一笔，断档就没了：(1800 + 60) / 50
        let impact = TransactionImpact(snapshot: snapshot, kind: .expense, amount: 60, date: dayNumber(50))
        #expect(abs(impact.newDailyBurn - 1860.0 / 50) < 1e-9)
    }

    @Test func theBackupCarriesTheEstimate() throws {
        let context = try TestSupport.makeContext()
        let data = try DataIO.exportJSON(context: context, everydayEstimate: 3000)
        #expect(try ImportValidator.validate(data: data).monthlyEverydayEstimate == 3000)
        let without = try DataIO.exportJSON(context: context)
        #expect(try ImportValidator.validate(data: without).monthlyEverydayEstimate == nil)
        #expect(String(decoding: without, as: UTF8.self).contains("monthly_everyday_estimate") == false)
    }
}
