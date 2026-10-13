// 「资产计入自由天数」开关：开关开时和原来一样，关掉后只按现金算，净值不变。
// 所有用例都显式传 countsAssets，不读本机偏好。
import Foundation
import Testing
@testable import FreeGrid

@MainActor
struct FreedomAssetSwitchTests {
    private let now = TestSupport.day("2026-06-10")

    private func assets(locked: Double, cash: Double) -> UserAssets {
        let assets = UserAssets(total: 0)
        assets.lockedAssets = locked
        assets.cash = cash
        return assets
    }

    /// 日均消费 120：10 天里共花 1200，第一笔在 9 天前
    private var burn120: [Expense] {
        [Expense(amount: 1200, category: "午餐", date: Calendar.current.date(byAdding: .day, value: -9, to: now)!)]
    }

    private func snapshot(locked: Double = 22_000, cash: Double = 14_000, counts: Bool,
                          passive: [PassiveSource] = []) -> FinancialSnapshot {
        FinancialSnapshot(expenses: burn120, passiveSources: passive,
                          assets: assets(locked: locked, cash: cash), now: now, countsAssets: counts)
    }

    // MARK: - 天数

    @Test func switchOnCountsAssetsAndCash() {
        let on = snapshot(counts: true)
        #expect(on.dailyBurn == 120)
        #expect(on.freedomBase == 36_000)
        #expect(on.countedAssets == 22_000)
        #expect(on.freedom == .finite(days: 300))
    }

    @Test func switchOffCountsCashOnlyAndKeepsNetWorth() {
        let off = snapshot(counts: false)
        #expect(off.netWorth == 36_000)
        #expect(off.freedomBase == 14_000)
        #expect(off.countedAssets == 0)
        #expect(off.freedom == .finite(days: 14_000.0 / 120))
        #expect(FreedomMath.freedomDaysDisplay(off.freedom) == "116")
        #expect(FreedomMath.freedomDaysDisplay(snapshot(counts: true).freedom) == "300")
    }

    @Test func switchOffDrawsOnlyCashCells() {
        let off = snapshot(counts: false)
        let grid = FreedomMath.gridState(for: off.freedom, lockedAssets: off.countedAssets, netWorth: off.freedomBase)
        #expect(grid.count == 116)
        #expect(grid.assetCells == 0)
        #expect(grid.cashCells == 116)

        let on = snapshot(counts: true)
        let onGrid = FreedomMath.gridState(for: on.freedom, lockedAssets: on.countedAssets, netWorth: on.freedomBase)
        #expect(onGrid.count == 300)
        #expect(onGrid.assetCells > 0)
        #expect(onGrid.assetCells + onGrid.cashCells == 300)
    }

    @Test func noAssetsMeansTheSwitchChangesNothing() {
        let on = snapshot(locked: 0, counts: true)
        let off = snapshot(locked: 0, counts: false)
        #expect(on.freedom == off.freedom)
        #expect(on.freedomBase == off.freedomBase)
        #expect(on.netWorth == off.netWorth)
        #expect(on.countedAssets == 0 && off.countedAssets == 0)
    }

    @Test func passiveIncomeCoveringSpendingIsCoveredEitherWay() {
        let passive = [PassiveSource(name: "利息", monthlyAmount: 3_600)]   // 120 / 天
        #expect(snapshot(counts: true, passive: passive).freedom == .covered)
        #expect(snapshot(counts: false, passive: passive).freedom == .covered)
    }

    // MARK: - 记一笔的预览

    @Test func expensePreviewUsesTheCurrentSwitchBasis() {
        // 再花 1200：总支出 2400 / 10 天 = 240
        let on = TransactionImpact(snapshot: snapshot(counts: true), kind: .expense, amount: 1_200)
        #expect(on.newFreedomBase == 34_800)
        #expect(on.newNetWorth == 34_800)
        #expect(on.newDailyBurn == 240)
        #expect(on.newFreedom == .finite(days: 145))

        let off = TransactionImpact(snapshot: snapshot(counts: false), kind: .expense, amount: 1_200)
        #expect(off.newFreedomBase == 12_800)
        #expect(off.newNetWorth == 34_800)          // 净值照样减少
        #expect(off.newFreedom == .finite(days: 12_800.0 / 240))
        // 现金口径：116.67 → 53.33
        #expect(abs((off.freedomChange ?? 0) - (12_800.0 / 240 - 14_000.0 / 120)) < 1e-9)
    }

    @Test func incomePreviewUsesTheCurrentSwitchBasis() {
        let off = TransactionImpact(snapshot: snapshot(counts: false), kind: .income, amount: 1_200)
        #expect(off.newFreedomBase == 15_200)
        #expect(off.newNetWorth == 37_200)
        #expect(off.freedomChange == 1_200.0 / 120)

        let on = TransactionImpact(snapshot: snapshot(counts: true), kind: .income, amount: 1_200)
        #expect(on.newFreedomBase == 37_200)
        #expect(on.freedomChange == 1_200.0 / 120)
    }

    // MARK: - 开关本身

    @Test func switchDefaultsToOnAndFollowsTheStoredPreference() throws {
        let suite = "FreedomAssetSwitchTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(defaults.object(forKey: FreedomSettings.countsAssetsKey) == nil)
        #expect(FreedomSettings.isOn(in: defaults))
        defaults.set(false, forKey: FreedomSettings.countsAssetsKey)
        #expect(!FreedomSettings.isOn(in: defaults))
        defaults.set(true, forKey: FreedomSettings.countsAssetsKey)
        #expect(FreedomSettings.isOn(in: defaults))
    }

    // MARK: - 自检

    @Test func checklistFreedomItemsFollowTheSwitchButNetWorthItemDoesNot() throws {
        let ledger = assets(locked: 22_000, cash: 14_000)
        func item(_ id: Int, _ summary: FreedomSummary) throws -> FreedomCheckItem {
            try #require(summary.items.first { $0.id == id })
        }
        let on = FreedomChecklist.evaluate(expenses: burn120, passiveSources: [], assets: ledger,
                                           now: now, countsAssets: true)
        let off = FreedomChecklist.evaluate(expenses: burn120, passiveSources: [], assets: ledger,
                                            now: now, countsAssets: false)
        // 开：300 天，过 180 但没到 365
        #expect(try item(4, on).done)
        #expect(try !item(5, on).done)
        #expect(try item(4, on).detail == "当前 300 / 180 天")
        #expect(on.nextStopTitle == "自由天数 365 天")
        #expect(on.remainText == "还差 65 天")
        // 关：116 天，两项都没过，数字和首页同一个
        #expect(try !item(4, off).done)
        #expect(try item(4, off).detail == "当前 116 / 180 天")
        #expect(try item(5, off).detail == "当前 116 / 365 天")
        #expect(off.nextStopTitle == "自由天数 180 天")
        #expect(off.remainText == "还差 64 天")
        // 「记录了可变现资产」看净值，不跟开关
        #expect(try item(3, on).done)
        #expect(try item(3, off).done)
        // 只有现金为 0、资产有钱：净值项仍达成，自由天数项归零
        let onlyAssets = FreedomChecklist.evaluate(expenses: burn120, passiveSources: [],
                                                   assets: assets(locked: 22_000, cash: 0),
                                                   now: now, countsAssets: false)
        #expect(try item(3, onlyAssets).done)
        #expect(try item(4, onlyAssets).detail == "当前 0 / 180 天")
    }

    // MARK: - 趋势

    @Test func trendHidesAFlooredStartOnlyWhenAskedTo() {
        let first = Calendar.current.date(byAdding: .day, value: -28, to: now)!
        let expenses = [Expense(amount: 2_800, category: "午餐", date: first)]
        // 现金 14000，但 3 周前之后进过 20000 的收入：往回推 14000 − 20000 < 0
        let incomes = [Income(amount: 20_000, source: "工资", date: Calendar.current.date(byAdding: .day, value: -7, to: now)!)]
        let history = FreedomMath.freedomDaysHistory(expenses: expenses, incomes: incomes, currentNetWorth: 14_000,
                                                     firstRecordDate: first, weeks: 4, now: now)
        let start = history.first!
        let end = history.last!
        #expect(start.isFloored)
        #expect(start.description == "0 天")
        #expect(!end.isFloored)

        #expect(FreedomMath.trendSummaryText(first: start, last: end, hidesFlooredStart: true) == end.description)
        #expect(FreedomMath.trendSummaryText(first: start, last: end, hidesFlooredStart: false)
                == "0 天 → \(end.description)")
    }

    @Test func trendKeepsBothEndsWhenNothingWasFloored() {
        let first = Calendar.current.date(byAdding: .day, value: -28, to: now)!
        let expenses = [Expense(amount: 2_800, category: "午餐", date: first)]
        let history = FreedomMath.freedomDaysHistory(expenses: expenses, incomes: [], currentNetWorth: 14_000,
                                                     firstRecordDate: first, weeks: 4, now: now)
        #expect(history.allSatisfy { !$0.isFloored })
        let text = FreedomMath.trendSummaryText(first: history.first!, last: history.last!, hidesFlooredStart: true)
        #expect(text == "\(history.first!.description) → \(history.last!.description)")
    }

    @Test func trendWithAssetsCountedIsUnchangedByTheFlag() {
        // 同一份账目，用净值 36000 往回推时起点是正的：开关开时摘要完全不变
        let first = Calendar.current.date(byAdding: .day, value: -28, to: now)!
        let expenses = [Expense(amount: 2_800, category: "午餐", date: first)]
        let incomes = [Income(amount: 20_000, source: "工资", date: Calendar.current.date(byAdding: .day, value: -7, to: now)!)]
        let withAssets = FreedomMath.freedomDaysHistory(expenses: expenses, incomes: incomes, currentNetWorth: 36_000,
                                                        firstRecordDate: first, weeks: 4, now: now)
        #expect(withAssets.allSatisfy { !$0.isFloored })
        #expect(withAssets.first!.state != .finite(days: 0))
    }
}
