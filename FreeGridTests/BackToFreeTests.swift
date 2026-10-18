// 「回到免费版」：Pro 失效只报一次、哪些人要弹引导、合并后资产总开关和自由天数怎么变。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
@Suite(.serialized)
struct BackToFreeTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "BackToFreeTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    // MARK: - Pro 失效

    @Test func trialEndingIsReportedOnceAndAFreshInstallNever() {
        withDefaults { defaults in
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            #expect(!ProStore(defaults: defaults).takeLapse())   // 从没体验过、刚装 2.0 的老用户

            defaults.set(start, forKey: ProStore.trialStartedKey)
            let during = ProStore(defaults: defaults, clock: { start.addingTimeInterval(3 * 86_400) })
            #expect(!during.takeLapse())                          // 体验中记下「能用」

            let after = ProStore(defaults: defaults, clock: { start.addingTimeInterval(8 * 86_400) })
            #expect(after.takeLapse())                            // 到期后第一次看到：弹
            #expect(!after.takeLapse())                           // 同一次到期不再弹
            #expect(!ProStore(defaults: defaults, clock: { start.addingTimeInterval(9 * 86_400) }).takeLapse())
        }
    }

    @Test func refundAfterBuyingIsALapseToo() {
        withDefaults { defaults in
            defaults.set(true, forKey: ProStore.unlockedKey)
            #expect(!ProStore(defaults: defaults).takeLapse())
            defaults.set(false, forKey: ProStore.unlockedKey)    // App Store 核对后撤销了买断
            #expect(ProStore(defaults: defaults).takeLapse())
        }
    }

    // MARK: - 要不要弹

    @Test func onlyAssetItemsCashAccountsAndTermLoansNeedTheGuide() {
        let rent = Loan(name: "房租", monthlyAmount: 2500, dueDay: 5, periodsAtStart: 0, startDate: .now,
                        sortOrder: 0, isOngoing: true)
        let car = Loan(name: "车贷", monthlyAmount: 1200, dueDay: 25, periodsAtStart: 18, startDate: .now, sortOrder: 1)
        #expect(!BackToFreePlan(assetItems: [], cashAccounts: [], loans: []).hasProContent)
        #expect(!BackToFreePlan(assetItems: [], cashAccounts: [], loans: [rent]).hasProContent)   // 固定支出是免费的
        #expect(BackToFreePlan(assetItems: [], cashAccounts: [], loans: [rent, car]).loans == ["车贷"])

        let plan = BackToFreePlan(
            assetItems: [AssetItem(name: "房", amount: 1_200_000, sortOrder: 0, countsInFreedom: false),
                         AssetItem(name: "基金", amount: 7000, sortOrder: 1)],
            cashAccounts: [CashAccount(name: "微信", amount: 320, sortOrder: 0)], loans: [])
        #expect(plan.hasProContent)
        #expect(plan.excludedAssets == ["房"])
        #expect(plan.excludedCash.isEmpty)
    }

    // MARK: - 合并

    @Test func mergingTurnsTheAssetSwitchOnWhenAnyItemCounted() {
        let house = AssetItem(name: "房", amount: 1_200_000, sortOrder: 0, countsInFreedom: false)
        let fund = AssetItem(name: "基金", amount: 7000, sortOrder: 1)
        #expect(AssetItemStore.switchAfterMerging([house, fund]))
        #expect(!AssetItemStore.switchAfterMerging([house]))
        #expect(AssetItemStore.switchAfterMerging([]))
    }

    @Test func mergeKeepsTheTotalAndWritesTheSwitch() throws {
        try withDefaults { defaults in
            let context = try TestSupport.makeContext()
            let assets = UserAssets(total: 0)
            context.insert(assets)
            try context.save()
            _ = try AssetItemStore.save(nil, name: "房", amount: 100_000, countsInFreedom: false, in: context)
            _ = try AssetItemStore.save(nil, name: "基金", amount: 8000, in: context)
            defaults.set(false, forKey: FreedomSettings.countsAssetsKey)

            try AssetItemStore.mergeIntoTotalKeepingSwitch(in: context, defaults: defaults)
            #expect(try AssetItemStore.items(in: context).isEmpty)
            #expect(assets.lockedAssets == 108_000)
            #expect(FreedomSettings.isOn(in: defaults))
        }
    }

    /// 房子不计入时自由天数只算现金和基金；合并后房子也算进去，引导里要先写出来
    @Test func previewShowsTheJumpWhenAnExcludedHouseJoins() {
        let now = TestSupport.day("2026-10-15").addingTimeInterval(12 * 3600)
        let expenses = [Expense(amount: 1000, category: "午餐", date: Calendar.current.date(byAdding: .day, value: -9, to: now)!)]
        let assets = UserAssets(total: 0)
        assets.cash = 2000
        assets.lockedAssets = 108_000
        let items = [AssetItem(name: "房", amount: 100_000, sortOrder: 0, countsInFreedom: false),
                     AssetItem(name: "基金", amount: 8000, sortOrder: 1)]
        let before = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: assets, assetItems: items,
                                       now: now).freedom
        let after = BackToFreePlan.freedomAfterMerging(assets: true, cash: false, expenses: expenses, passiveSources: [],
                                                       assets: assets, assetItems: items, cashAccounts: [], loans: [],
                                                       now: now)
        #expect(before == .finite(days: 100))     // (2000 + 8000) ÷ 100
        #expect(after == .finite(days: 1100))     // (2000 + 108000) ÷ 100
    }
}
