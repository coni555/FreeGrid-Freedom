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

    /// 已经和 App Store 核对过的 store：takeLapse 只在核对后才判断
    private func checked(_ store: ProStore) -> ProStore {
        store.hasCheckedEntitlements = true
        return store
    }

    @Test func trialEndingIsReportedOnceAndAFreshInstallNever() {
        withDefaults { defaults in
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            #expect(!checked(ProStore(defaults: defaults)).takeLapse())   // 从没体验过、刚装 2.0 的老用户

            defaults.set(start, forKey: ProStore.trialStartedKey)
            let during = checked(ProStore(defaults: defaults, clock: { start.addingTimeInterval(3 * 86_400) }))
            #expect(!during.takeLapse())                          // 体验中记下「能用」

            let after = checked(ProStore(defaults: defaults, clock: { start.addingTimeInterval(8 * 86_400) }))
            #expect(after.takeLapse())                            // 到期后第一次看到：弹
            #expect(!after.takeLapse())                           // 同一次到期不再弹
            #expect(!checked(ProStore(defaults: defaults, clock: { start.addingTimeInterval(9 * 86_400) })).takeLapse())
            #expect(!after.lapsedFromPurchase)
        }
    }

    @Test func refundAfterBuyingIsALapseToo() {
        withDefaults { defaults in
            defaults.set(true, forKey: ProStore.unlockedKey)
            #expect(!checked(ProStore(defaults: defaults)).takeLapse())
            defaults.set(false, forKey: ProStore.unlockedKey)    // App Store 核对后撤销了买断
            let refunded = checked(ProStore(defaults: defaults))
            #expect(refunded.takeLapse())
            #expect(refunded.lapsedFromPurchase)                  // 标题写「Pro 已失效」
        }
    }

    /// 体验期间就买断了：体验到期时 Pro 没断过，不弹
    @Test func buyingDuringTheTrialNeverLapses() {
        withDefaults { defaults in
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            defaults.set(start, forKey: ProStore.trialStartedKey)
            #expect(!checked(ProStore(defaults: defaults, clock: { start.addingTimeInterval(2 * 86_400) })).takeLapse())
            defaults.set(true, forKey: ProStore.unlockedKey)
            #expect(!checked(ProStore(defaults: defaults, clock: { start.addingTimeInterval(30 * 86_400) })).takeLapse())
        }
    }

    /// 还没和 App Store 核对过（比如别的设备上买了、这台还没同步）：先不判断，也不记下「不能用」
    @Test func lapseWaitsForTheEntitlementCheck() {
        withDefaults { defaults in
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            defaults.set(start, forKey: ProStore.trialStartedKey)
            let during = checked(ProStore(defaults: defaults, clock: { start.addingTimeInterval(2 * 86_400) }))
            let duringLapse = during.takeLapse()
            let unchecked = ProStore(defaults: defaults, clock: { start.addingTimeInterval(8 * 86_400) })
            let beforeCheck = unchecked.takeLapse()
            unchecked.hasCheckedEntitlements = true
            let afterCheck = unchecked.takeLapse()
            #expect(during.isUnlocked && !duringLapse)
            #expect(!unchecked.isUnlocked)
            #expect(defaults.bool(forKey: ProStore.wasUnlockedKey) == false)
            #expect(!beforeCheck)
            #expect(afterCheck)
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
        #expect(plan.assetsCountAfterMerging)
        #expect(plan.excludedCash.isEmpty)
        // 一项都没算：合并后资产整体不计入，引导里不能写「统一计入」
        let allExcluded = BackToFreePlan(
            assetItems: [AssetItem(name: "房", amount: 1_200_000, sortOrder: 0, countsInFreedom: false)],
            cashAccounts: [], loans: [])
        #expect(!allExcluded.assetsCountAfterMerging)
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

    // MARK: - 没有 Pro 时贷款停用

    @Test func pausedLoansStopCountingButFixedCostsStay() {
        let rent = Loan(name: "房租", monthlyAmount: 2500, dueDay: 5, periodsAtStart: 0, startDate: .now,
                        sortOrder: 0, isOngoing: true)
        let car = Loan(name: "车贷", monthlyAmount: 1200, dueDay: 25, periodsAtStart: 18, startDate: .now, sortOrder: 1)
        #expect(LoanSchedule.inEffect([rent, car], proUnlocked: true).map(\.name) == ["房租", "车贷"])
        #expect(LoanSchedule.inEffect([rent, car], proUnlocked: false).map(\.name) == ["房租"])
    }

    /// 停用期间到期的两期不扣钱，记成没扣成；重新解锁后由用户逐期处理，不会一下子扣掉
    @Test func pausedLoanIsNotDeductedAndItsPeriodsWaitForTheUser() throws {
        let now = TestSupport.day("2026-10-15").addingTimeInterval(12 * 3600)
        let context = try TestSupport.makeContext()
        let assets = UserAssets(total: 0)
        assets.cash = 10_000
        context.insert(assets)
        try context.save()
        let loan = try LoanStore.save(nil, name: "车贷", monthlyAmount: 1200, dueDay: 20, remaining: 12,
                                      now: now, in: context)
        let later = TestSupport.day("2026-12-01").addingTimeInterval(12 * 3600)
        #expect(try LoanStore.processDue(now: later, pausesTermLoans: true, in: context) == 0)
        #expect(assets.cash == 10_000)
        let status = LoanSchedule.status(of: loan, payments: try LoanStore.payments(in: context), now: later)
        #expect(status.pending.count == 2)
        // 解锁后再处理一次也不会补扣：那两期已经交给用户选
        #expect(try LoanStore.processDue(now: later, in: context) == 0)
        #expect(assets.cash == 10_000)
    }

    /// 删停用的贷款要么全删、要么一笔不删
    @Test func deletingSeveralLoansIsAllOrNothing() throws {
        enum Failure: Error { case save }
        let context = try TestSupport.makeContext()
        context.insert(UserAssets(total: 0))
        try context.save()
        let now = TestSupport.day("2026-10-15").addingTimeInterval(12 * 3600)
        let car = try LoanStore.save(nil, name: "车贷", monthlyAmount: 1200, dueDay: 20, remaining: 12, now: now, in: context)
        let phone = try LoanStore.save(nil, name: "手机", monthlyAmount: 300, dueDay: 25, remaining: 8, now: now, in: context)

        #expect(throws: Failure.self) {
            try LoanStore.delete([car, phone], in: context) { _ in throw Failure.save }
        }
        #expect(try LoanStore.loans(in: context).count == 2)
        try LoanStore.delete([car, phone], in: context)
        #expect(try LoanStore.loans(in: context).isEmpty)
    }

    // MARK: - 支出分类

    @Test func customCategoriesStayPickableWithoutPro() throws {
        var options = ExpenseCategoryOptions.defaults
        try options.add("咖啡")
        try options.delete("娱乐")
        let encoded = try ExpenseCategoryStorage.encode(options)
        #expect(ExpenseCategoryStorage.isCustomized(encoded))
        #expect(!ExpenseCategoryStorage.isCustomized(""))

        let locked = ExpenseCategoryStorage.pickable(encoded, recorded: ["猫粮"], unlocked: false)
        #expect(locked.contains("咖啡") && !locked.contains("娱乐") && !locked.contains("猫粮"))
        #expect(ExpenseCategoryStorage.pickable(encoded, recorded: ["猫粮"], unlocked: true).contains("猫粮"))
        #expect(ExpenseCategoryStorage.pickable("", recorded: ["猫粮"], unlocked: false) == ExpenseCategory.canonical)
    }
}
