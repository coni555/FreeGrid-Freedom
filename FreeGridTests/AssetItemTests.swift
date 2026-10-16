// Pro 资产逐项记录：总数永远等于各项之和，迁移不丢钱，失败整体回滚，备份往返不丢项。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct AssetItemTests {
    private enum Failure: Error { case save }
    private let failingSave: LedgerStore.SaveAction = { _ in throw Failure.save }
    private let today = TestSupport.day("2026-06-10")

    // MARK: - 夹具

    private func ledger(locked: Double = 0, cash: Double = 0) throws -> ModelContext {
        let context = try TestSupport.makeContext()
        let assets = UserAssets(total: 0)
        assets.lockedAssets = locked
        assets.cash = cash
        context.insert(assets)
        try context.save()
        return context
    }

    private func assets(_ context: ModelContext) throws -> UserAssets {
        try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
    }

    private func items(_ context: ModelContext) throws -> [AssetItem] {
        try AssetItemStore.items(in: context)
    }

    private struct State: Equatable {
        let cash: Double
        let locked: Double
        let items: [String]
    }

    private func state(_ context: ModelContext) throws -> State {
        let assets = try assets(context)
        return State(cash: assets.cash, locked: assets.lockedAssets,
                     items: try items(context).map { "\($0.id)|\($0.name)|\($0.amount)|\($0.sortOrder)|\($0.countsInFreedom)" })
    }

    /// 房 100000 / 定期 30000 / 基金 5000，现金 14000
    private func threeItems() throws -> ModelContext {
        let context = try ledger(cash: 14_000)
        for (name, amount) in [("房", 100_000.0), ("定期", 30_000), ("基金", 5_000)] {
            try AssetItemStore.save(nil, name: name, amount: amount, in: context)
        }
        return context
    }

    // MARK: - 迁移

    @Test func firstVisitTurnsTheOldTotalIntoOneItemWithoutChangingNetWorthOrFreedom() throws {
        let context = try ledger(locked: 22_000, cash: 14_000)
        let expenses = [Expense(amount: 1_200, category: "午餐", date: Calendar.current.date(byAdding: .day, value: -9, to: today)!)]
        func snapshot() throws -> FinancialSnapshot {
            FinancialSnapshot(expenses: expenses, passiveSources: [], assets: try assets(context), now: today, countsAssets: true)
        }
        let before = try snapshot()

        #expect(try AssetItemStore.migrateIfNeeded(in: context) != nil)
        let migrated = try items(context)
        #expect(migrated.count == 1)
        #expect(migrated[0].name == "资产")
        #expect(migrated[0].amount == 22_000)
        let after = try snapshot()
        #expect(after.netWorth == before.netWorth && after.netWorth == 36_000)
        #expect(after.freedom == before.freedom && after.freedom == .finite(days: 300))
        #expect(try assets(context).lockedAssets == 22_000)

        // 再进一次不会再生成
        #expect(try AssetItemStore.migrateIfNeeded(in: context) == nil)
        #expect(try items(context).count == 1)
    }

    @Test func nothingToMigrateWhenTheTotalIsZeroOrThereIsNoLedger() throws {
        let empty = try ledger(locked: 0, cash: 500)
        #expect(try AssetItemStore.migrateIfNeeded(in: empty) == nil)
        #expect(try items(empty).isEmpty)
        let none = try TestSupport.makeContext()
        #expect(try AssetItemStore.migrateIfNeeded(in: none) == nil)
    }

    @Test func addingTheFirstItemKeepsTheOldTotalAsItsOwnItem() throws {
        // 没经过明细页的迁移就直接加一项：原来的 22000 不能被新的一项顶掉
        let context = try ledger(locked: 22_000, cash: 14_000)
        try AssetItemStore.save(nil, name: "车", amount: 30_000, in: context)
        #expect(try items(context).map(\.name) == ["资产", "车"])
        #expect(try assets(context).lockedAssets == 52_000)
        #expect(try assets(context).cash == 14_000)
    }

    @Test func splittingWithTheSwitchOffKeepsTheOldTotalUncounted() throws {
        // 拆分前总开关关着：拆出来的那一项「资产」也不算，自由天数和拆分前一样
        let context = try ledger(locked: 22_000, cash: 14_000)
        let expenses = [Expense(amount: 1_200, category: "午餐", date: Calendar.current.date(byAdding: .day, value: -9, to: today)!)]
        let before = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: try assets(context),
                                       now: today, countsAssets: false)
        try AssetItemStore.save(nil, name: "基金", amount: 8_000, source: .unsplitTotal, totalCounts: false, in: context)
        let all = try items(context)
        #expect(all.map(\.name) == ["资产", "基金"])
        #expect(all.map(\.countsInFreedom) == [false, true])
        // 拆分之后总开关不再参与：传开传关都一样，只按各项算
        for switchState in [true, false] {
            let after = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: try assets(context),
                                          assetItems: all, now: today, countsAssets: switchState)
            #expect(after.freedomBase == 14_000 + 8_000)
        }
        #expect(before.freedomBase == 14_000)
    }

    // MARK: - 从已有一项里拆出来

    @Test func carvingFromTheUnsplitTotalKeepsTheTotal() throws {
        let context = try ledger(locked: 22_000, cash: 14_000)
        try AssetItemStore.save(nil, name: "基金", amount: 8_000, source: .unsplitTotal, in: context)
        #expect(try items(context).map(\.name) == ["资产", "基金"])
        #expect(try items(context).map(\.amount) == [14_000, 8_000])
        #expect(try assets(context).lockedAssets == 22_000)
        #expect(try assets(context).cash == 14_000)
    }

    @Test func carvingFromAnItemMovesTheAmountAndCanTakeItAll() throws {
        let context = try threeItems()
        let deposit = try items(context)[1]
        try AssetItemStore.save(nil, name: "国债", amount: 30_000, source: .item(deposit.id), in: context)
        #expect(deposit.amount == 0)
        #expect(try items(context).last?.name == "国债")
        #expect(try assets(context).lockedAssets == 135_000)
    }

    @Test func carvingMoreThanTheSourceHasChangesNothing() throws {
        let context = try threeItems()
        let fund = try items(context)[2]
        let before = try state(context)
        #expect(throws: AssetItemError.notEnough(name: "基金", available: 5_000)) {
            try AssetItemStore.save(nil, name: "股票", amount: 6_000, source: .item(fund.id), in: context)
        }
        #expect(try state(context) == before)
    }

    @Test func carvingRollsTheSourceBackWhenSavingFails() throws {
        let context = try threeItems()
        let house = try items(context)[0]
        let before = try state(context)
        #expect(throws: Failure.self) {
            try AssetItemStore.save(nil, name: "车位", amount: 20_000, source: .item(house.id), in: context, save: failingSave)
        }
        #expect(try state(context) == before)
        #expect(house.amount == 100_000)
    }

    // MARK: - 排序

    @Test func movingAnItemChangesOnlyTheOrder() throws {
        let context = try threeItems()
        try AssetItemStore.move(try items(context)[2], to: 0, in: context)
        #expect(try items(context).map(\.name) == ["基金", "房", "定期"])
        #expect(try assets(context).lockedAssets == 135_000)

        let before = try state(context)
        #expect(throws: Failure.self) {
            try AssetItemStore.move(try items(context)[0], to: 2, in: context, save: failingSave)
        }
        #expect(try state(context) == before)
    }

    // MARK: - 逐项开关

    @Test func togglingOneItemLeavesTheOthersAndTheTotalAlone() throws {
        let context = try threeItems()
        let all = try items(context)
        try AssetItemStore.setCountsInFreedom(false, for: all[0], in: context)
        #expect(try items(context).map(\.countsInFreedom) == [false, true, true])
        #expect(try assets(context).lockedAssets == 135_000)

        let before = try state(context)
        #expect(throws: Failure.self) {
            try AssetItemStore.setCountsInFreedom(true, for: all[0], in: context, save: failingSave)
        }
        #expect(try state(context) == before)
    }

    @Test func oldSwitchOffIsHandedToEveryItem() throws {
        let context = try threeItems()
        #expect(try AssetItemStore.adoptSwitchOff(in: context))
        #expect(try items(context).allSatisfy { !$0.countsInFreedom })
        #expect(try !AssetItemStore.adoptSwitchOff(in: try ledger(locked: 100)))
    }

    // MARK: - 总数 = 各项之和

    @Test func threeItemsSumToTheBucketAndDriveNetWorthAndFreedom() throws {
        let context = try threeItems()
        let assets = try assets(context)
        #expect(assets.lockedAssets == 135_000)
        #expect(assets.netWorth == 149_000)
        let expenses = [Expense(amount: 1_200, category: "午餐", date: Calendar.current.date(byAdding: .day, value: -9, to: today)!)]
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: [], assets: assets, now: today, countsAssets: true)
        #expect(snapshot.freedom == .finite(days: 149_000.0 / 120))
        #expect(try items(context).map(\.name) == ["房", "定期", "基金"])
    }

    @Test func editingOneItemMovesTheTotalAndLeavesTheOthersAlone() throws {
        let context = try threeItems()
        let before = try items(context)
        let others = before.dropFirst().map { "\($0.id)|\($0.amount)" }
        try AssetItemStore.save(before[0], name: " 房产 ", amount: 120_000, in: context)
        let after = try items(context)
        #expect(after[0].name == "房产")
        #expect(after[0].amount == 120_000)
        #expect(after.dropFirst().map { "\($0.id)|\($0.amount)" } == others)
        #expect(try assets(context).lockedAssets == 155_000)
        #expect(after.map(\.id) == before.map(\.id))
    }

    @Test func deletingAnItemRemovesExactlyItsAmount() throws {
        let context = try threeItems()
        let all = try items(context)
        try AssetItemStore.delete(all[1], in: context)
        #expect(try items(context).map(\.name) == ["房", "基金"])
        #expect(try assets(context).lockedAssets == 105_000)
        #expect(try assets(context).cash == 14_000)
        // 删到没有：总数归零，不留下没有来源的数
        try AssetItemStore.delete(try items(context)[0], in: context)
        try AssetItemStore.delete(try items(context)[0], in: context)
        #expect(try items(context).isEmpty)
        #expect(try assets(context).lockedAssets == 0)
    }

    @Test func newItemsAreAppendedInOrderEvenAfterADeletion() throws {
        let context = try threeItems()
        try AssetItemStore.delete(try items(context)[1], in: context)
        try AssetItemStore.save(nil, name: "车", amount: 1, in: context)
        #expect(try items(context).map(\.name) == ["房", "基金", "车"])
    }

    @Test func mergingKeepsTheTotalAndDropsTheItems() throws {
        let context = try threeItems()
        try AssetItemStore.mergeIntoTotal(in: context)
        #expect(try items(context).isEmpty)
        #expect(try assets(context).lockedAssets == 135_000)
        #expect(try assets(context).netWorth == 149_000)
    }

    // MARK: - 校验

    @Test func namesAreOneToTwentyCharactersWithoutControlCharacters() throws {
        let context = try ledger()
        for bad in ["", "   ", "\n", String(repeating: "资", count: 21), "房\n子"] {
            #expect(throws: AssetItemError.invalidName) {
                try AssetItemStore.save(nil, name: bad, amount: 1, in: context)
            }
        }
        try AssetItemStore.save(nil, name: String(repeating: "资", count: 20), amount: 1, in: context)
        try AssetItemStore.save(nil, name: "房", amount: 0, in: context)
        #expect(try items(context).count == 2)
    }

    @Test func amountsMustBeFiniteNonNegativeAndInRange() throws {
        let context = try ledger()
        for bad in [-1, .nan, .infinity, -.infinity, FinancialLimits.maximumAmount + 1] {
            #expect(throws: AssetItemError.invalidAmount) {
                try AssetItemStore.save(nil, name: "房", amount: bad, in: context)
            }
        }
        #expect(try items(context).isEmpty)
        #expect(try assets(context).lockedAssets == 0)
    }

    @Test func aSumBeyondTheLimitIsRejectedAndNothingChanges() throws {
        let context = try ledger()
        try AssetItemStore.save(nil, name: "甲", amount: FinancialLimits.maximumAmount, in: context)
        let before = try state(context)
        #expect(throws: (any Error).self) {
            try AssetItemStore.save(nil, name: "乙", amount: 1, in: context)
        }
        #expect(try state(context) == before)
        #expect(!context.hasChanges)
    }

    // MARK: - 调拨

    @Test func transferMovesMoneyBetweenCashAndTheChosenItem() throws {
        let context = try ledger(cash: 1_000)
        try AssetItemStore.save(nil, name: "定期", amount: 500, in: context)
        try AssetItemStore.save(nil, name: "基金", amount: 200, in: context)
        let all = try items(context)

        #expect(try AssetItemStore.transfer(.cashToItem, amount: 300, item: all[1], in: context) == 300)
        #expect(try assets(context).cash == 700)
        #expect(all[1].amount == 500 && all[0].amount == 500)
        #expect(try assets(context).lockedAssets == 1_000)

        // 超过来源里有的：只调走有的
        #expect(try AssetItemStore.transfer(.itemToCash, amount: 9_999, item: all[0], in: context) == 500)
        #expect(all[0].amount == 0 && all[1].amount == 500)
        #expect(try assets(context).cash == 1_200)
        #expect(try assets(context).lockedAssets == 500)
        #expect(try assets(context).netWorth == 1_700)

        #expect(throws: AssetItemError.invalidAmount) {
            try AssetItemStore.transfer(.cashToItem, amount: 0, item: all[0], in: context)
        }
    }

    @Test func transferBetweenCashAndUncountedItemMovesMoneyAndPreservesFlag() throws {
        let context = try ledger(cash: 14_000)
        let house = try AssetItemStore.save(nil, name: "房", amount: 100_000, countsInFreedom: false, in: context)
        // 现金调入未计入的项 4000
        let moved = try AssetItemStore.transfer(.cashToItem, amount: 4_000, item: house, in: context)
        #expect(moved == 4_000)
        #expect(try assets(context).cash == 10_000)
        #expect(try assets(context).lockedAssets == 104_000)
        #expect(house.amount == 104_000)
        #expect(house.countsInFreedom == false)

        // 再调回 2000
        let movedBack = try AssetItemStore.transfer(.itemToCash, amount: 2_000, item: house, in: context)
        #expect(movedBack == 2_000)
        #expect(try assets(context).cash == 12_000)
        #expect(try assets(context).lockedAssets == 102_000)
        #expect(house.amount == 102_000)
        #expect(house.countsInFreedom == false)
    }

    // MARK: - 失败回滚

    @Test func everyWriteRestoresCashItemsAndTotalWhenSavingFails() throws {
        let context = try threeItems()
        let all = try items(context)
        let before = try state(context)

        func expectUnchanged(_ action: () throws -> Void) throws {
            #expect(throws: Failure.self) { try action() }
            #expect(try state(context) == before)
            #expect(!context.hasChanges)
        }
        try expectUnchanged { try AssetItemStore.save(nil, name: "车", amount: 9, in: context, save: failingSave) }
        try expectUnchanged { try AssetItemStore.save(all[0], name: "改", amount: 1, in: context, save: failingSave) }
        try expectUnchanged { try AssetItemStore.delete(all[1], in: context, save: failingSave) }
        try expectUnchanged { try AssetItemStore.mergeIntoTotal(in: context, save: failingSave) }
        try expectUnchanged { try AssetItemStore.transfer(.cashToItem, amount: 100, item: all[2], in: context, save: failingSave) }
        try expectUnchanged { try AssetItemStore.transfer(.itemToCash, amount: 100, item: all[0], in: context, save: failingSave) }

        let old = try ledger(locked: 22_000, cash: 14_000)
        let oldBefore = try state(old)
        #expect(throws: Failure.self) { try AssetItemStore.migrateIfNeeded(in: old, save: failingSave) }
        #expect(try state(old) == oldBefore)
        #expect(try items(old).isEmpty)
    }

    // MARK: - 备份

    private func backup(from context: ModelContext) throws -> Data { try DataIO.exportJSON(context: context) }

    @Test func exportWithoutItemsHasNoItemsKeyAndKeepsTheSchemaVersion() throws {
        let context = try ledger(locked: 100, cash: 50)
        let json = try #require(String(data: backup(from: context), encoding: .utf8))
        #expect(!json.contains("asset_items"))
        #expect(json.contains("\"schema_version\" : 2"))
    }

    @Test func itemsRoundTripWithNamesAmountsAndOrderIntact() throws {
        let source = try ledger(cash: 14_000)
        for (name, amount) in [("车", 30_000.0), ("房", 100_000), ("基金", 5_000)] {
            try AssetItemStore.save(nil, name: name, amount: amount, in: source)
        }
        let original = try items(source)
        let data = try backup(from: source)

        let target = try TestSupport.makeContext()
        let preview = try DataIO.previewJSON(data: data, context: target)
        #expect(preview.importedAssetItems.count == 3)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)

        let restored = try items(target)
        #expect(restored.map(\.name) == ["车", "房", "基金"])
        #expect(restored.map(\.amount) == [30_000, 100_000, 5_000])
        #expect(restored.map(\.id) == original.map(\.id))
        #expect(restored.map(\.sortOrder) == [0, 1, 2])
        #expect(restored.map(\.countsInFreedom) == [true, true, true])
        #expect(try assets(target).lockedAssets == 135_000)
        #expect(try assets(target).cash == 14_000)
    }

    @Test func countsInFreedomRoundTripPreservesBothStates() throws {
        let source = try ledger(cash: 14_000)
        try AssetItemStore.save(nil, name: "房", amount: 100_000, countsInFreedom: false, in: source)
        try AssetItemStore.save(nil, name: "定期", amount: 30_000, countsInFreedom: true, in: source)
        try AssetItemStore.save(nil, name: "基金", amount: 5_000, countsInFreedom: true, in: source)

        let data = try backup(from: source)
        let target = try TestSupport.makeContext()
        let preview = try DataIO.previewJSON(data: data, context: target)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)

        let restored = try items(target)
        #expect(restored.count == 3)
        #expect(restored.map(\.name) == ["房", "定期", "基金"])
        #expect(restored.map(\.countsInFreedom) == [false, true, true])
    }

    @Test func importBackupWithoutCountsInFreedomDefaultsToCounted() throws {
        let target = try TestSupport.makeContext()
        // 阶段 2 导出的备份，没有 counts_in_freedom 字段
        let data = json(items: #"[{"name":"房","amount":100000},{"name":"定期","amount":30000}]"#, locked: 130_000)
        let preview = try DataIO.previewJSON(data: data, context: target)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)

        let restored = try items(target)
        #expect(restored.count == 2)
        #expect(restored.allSatisfy { $0.countsInFreedom })
    }

    @Test func importingSameBackupTwiceKeepsCountsInFreedom() throws {
        let source = try ledger(cash: 14_000)
        try AssetItemStore.save(nil, name: "房", amount: 100_000, countsInFreedom: false, in: source)
        try AssetItemStore.save(nil, name: "定期", amount: 30_000, countsInFreedom: true, in: source)
        let data = try backup(from: source)

        let target = try TestSupport.makeContext()
        for _ in 0..<2 {
            let preview = try DataIO.previewJSON(data: data, context: target)
            _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)
        }
        let restored = try items(target)
        #expect(restored.count == 2)
        #expect(restored.map(\.countsInFreedom) == [false, true])
    }

    @Test func importingTheSameBackupTwiceDoesNotDuplicateItems() throws {
        let source = try threeItems()
        let data = try backup(from: source)
        let target = try TestSupport.makeContext()
        for _ in 0..<2 {
            let preview = try DataIO.previewJSON(data: data, context: target)
            _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)
        }
        #expect(try items(target).count == 3)
        #expect(try assets(target).lockedAssets == 135_000)
        // 再导回原来的账本也一样
        let again = try DataIO.previewJSON(data: data, context: source)
        _ = try DataIO.commitImport(preview: again, strategy: .replace, context: source)
        #expect(try items(source).count == 3)
        #expect(try assets(source).lockedAssets == 135_000)
    }

    @Test func otherStrategiesLeaveExistingItemsAlone() throws {
        let source = try threeItems()
        let data = try backup(from: source)
        let target = try ledger(cash: 10)
        try AssetItemStore.save(nil, name: "已有", amount: 40, in: target)
        let before = try state(target)
        let skip = try DataIO.previewJSON(data: data, context: target)
        _ = try DataIO.commitImport(preview: skip, strategy: .skipAssets, context: target)
        #expect(try state(target) == before)
        let add = try DataIO.previewJSON(data: data, context: target)
        _ = try DataIO.commitImport(preview: add, strategy: .addToCash, context: target)
        #expect(try items(target).map(\.name) == ["已有"])
        #expect(try assets(target).lockedAssets == 40)
        #expect(try assets(target).cash == 10 + 149_000)
    }

    @Test(arguments: [0, 1, 2, 3])
    func oldBackupVersionsImportAsATotalAndFoldExistingItemsBackIntoOne(version: Int) throws {
        let json: String
        switch version {
        case 0: json = #"{"assets":{"total":900},"expenses":[{"amount":30,"category":"午餐","date":"2026-01-01"}]}"#
        case 1: json = #"{"schema_version":1,"assets":{"total":900},"expenses":[{"amount":30,"category":"午餐","date":"2026-01-01"}]}"#
        default: json = #"{"schema_version":\#(version),"assets":{"total":900,"locked_assets":600,"cash":300},"expenses":[{"amount":30,"category":"午餐","date":"2026-01-01"}]}"#
        }
        let target = try threeItems()
        let preview = try DataIO.previewJSON(data: Data(json.utf8), context: target)
        #expect(preview.importedAssetItems.isEmpty)
        #expect(preview.currentAssetItemCount == 3)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)
        #expect(try items(target).isEmpty)
        #expect(try assets(target).lockedAssets == (version >= 2 ? 600 : 0))
        #expect(try assets(target).netWorth == 900)
    }

    @Test func staleItemsInThePreviewRejectTheCommit() throws {
        let source = try threeItems()
        let data = try backup(from: source)
        let target = try ledger(locked: 7, cash: 0)
        let preview = try DataIO.previewJSON(data: data, context: target)
        try AssetItemStore.save(nil, name: "新", amount: 1, in: target)
        #expect(throws: DataIO.DataIOError.stalePreview) {
            _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)
        }
    }

    @Test func failedReplaceRestoresItemsAndTotal() throws {
        let source = try threeItems()
        let data = try backup(from: source)
        let target = try ledger(cash: 10)
        try AssetItemStore.save(nil, name: "已有", amount: 40, in: target)
        let before = try state(target)
        let plan = try DataIO.makeImportPlan(preview: DataIO.previewJSON(data: data, context: target), strategy: .replace)
        #expect(throws: Failure.self) {
            _ = try DataIO.commitImport(plan: plan, context: target) { _ in throw Failure.save }
        }
        #expect(try state(target) == before)
        #expect(!target.hasChanges)
    }

    @Test func purgeAllAlsoRemovesItems() throws {
        let context = try threeItems()
        try DataIO.purgeAll(context: context)
        #expect(try items(context).isEmpty)
    }

    // MARK: - 备份校验

    private func json(items: String, locked: Double = 100) -> Data {
        Data("""
        {"schema_version":2,"assets":{"total":\(locked),"locked_assets":\(locked),"cash":0},"asset_items":\(items)}
        """.utf8)
    }

    @Test func itemsMustAddUpToTheAssetBucket() throws {
        let ok = try ImportValidator.validate(data: json(items: #"[{"name":"房","amount":60},{"name":"车","amount":40}]"#))
        #expect(ok.assetItems.count == 2)
        #expect(throws: ImportValidationError.assetItemsTotalMismatch) {
            try ImportValidator.validate(data: json(items: #"[{"name":"房","amount":60}]"#))
        }
        // 没有资产桶时，资产项没有可核对的总数
        #expect(throws: ImportValidationError.assetItemsTotalMismatch) {
            try ImportValidator.validate(data: Data(#"{"schema_version":2,"asset_items":[{"name":"房","amount":1}]}"#.utf8))
        }
        // 导出自校验不卡这一条：导出是逃生舱
        let lenient = try ImportValidator.validate(data: json(items: #"[{"name":"房","amount":60}]"#),
                                                   policy: .exportSelfCheck)
        #expect(lenient.assetItems.count == 1)
    }

    @Test func itemFieldsAreValidatedLikeEveryOtherImportedField() throws {
        func rejects(_ items: String, _ error: ImportValidationError) {
            #expect(throws: error) { try ImportValidator.validate(data: json(items: items, locked: 0)) }
        }
        rejects(#"[{"name":"","amount":0}]"#, .emptyText(field: "资产项名称"))
        rejects(#"[{"name":"\#(String(repeating: "资", count: 21))","amount":0}]"#,
                .textTooLong(field: "资产项名称", maximum: 20))
        rejects(#"[{"name":"房","amount":-1}]"#, .amountOutOfRange(field: "资产项"))
        rejects(#"[{"id":"nope","name":"房","amount":0}]"#, .invalidUUID(field: "资产项"))
        let id = UUID().uuidString
        rejects(#"[{"id":"\#(id)","name":"房","amount":0},{"id":"\#(id)","name":"车","amount":0}]"#, .duplicateAssetItemID)
        #expect(throws: ImportValidationError.self) {
            try ImportValidator.validate(data: json(items: #"[{"name":"房","amount":0,"created_at":"2999-01-01T00:00:00Z"}]"#, locked: 0))
        }
    }

    @Test func tooManyItemsAreRefusedForAnOutsideFile() throws {
        let many = "[" + (0..<(FinancialLimits.assetItemRecords + 1)).map { _ in #"{"name":"项","amount":0}"# }.joined(separator: ",") + "]"
        #expect(throws: ImportValidationError.self) { try ImportValidator.validate(data: json(items: many, locked: 0)) }
    }

    @Test func itemsWithoutASortOrderKeepTheirOrderInTheFile() throws {
        let target = try TestSupport.makeContext()
        let data = json(items: #"[{"name":"丙","amount":1},{"name":"乙","amount":2},{"name":"甲","amount":3}]"#, locked: 6)
        _ = try DataIO.commitImport(preview: DataIO.previewJSON(data: data, context: target), strategy: .replace, context: target)
        #expect(try items(target).map(\.name) == ["丙", "乙", "甲"])
    }

    // MARK: - 磁盘迁移

    @Test func aVersion15StoreOpensWithTheNewSchemaWithoutLosingAnythingOrReachingRecovery() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.store")

        // 1.5 的库：只有五个模型
        let oldSchema = Schema([Expense.self, Income.self, Device.self, PassiveSource.self, UserAssets.self])
        do {
            let container = try ModelContainer(for: oldSchema, configurations: [ModelConfiguration(schema: oldSchema, url: url)])
            let context = ModelContext(container)
            let assets = UserAssets(total: 0)
            assets.lockedAssets = 22_000
            assets.cash = 14_000
            context.insert(assets)
            context.insert(Expense(amount: 30, category: "午餐", date: today))
            context.insert(Income(amount: 800, source: "工资", date: today))
            context.insert(PassiveSource(name: "利息", monthlyAmount: 420))
            try context.save()
        }

        let newSchema = StoreBootstrap.schema
        let bootstrap = StoreBootstrap(factory: {
            try ModelContainer(for: newSchema, configurations: [ModelConfiguration(schema: newSchema, url: url)])
        })
        guard case .ready(let container) = bootstrap.state else {
            Issue.record("升级后进了恢复页")
            return
        }
        let context = ModelContext(container)
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(assets.lockedAssets == 22_000 && assets.cash == 14_000)
        #expect(try context.fetch(FetchDescriptor<Expense>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Income>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<PassiveSource>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AssetItem>()).isEmpty)

        // 升级后第一次进逐项管理：总数变成一项，净值不变
        try AssetItemStore.migrateIfNeeded(in: context)
        #expect(try AssetItemStore.items(in: context).map(\.amount) == [22_000])
        #expect(assets.netWorth == 36_000)
    }

    @Test func aPhase2StoreWithAssetItemsOpensWithAllItemsCounted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ledger.store")

        // 阶段 2 数据库：有资产项，升级到阶段 3
        let schema = StoreBootstrap.schema
        do {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(container)
            let assets = UserAssets(total: 0)
            assets.lockedAssets = 135_000
            assets.cash = 14_000
            context.insert(assets)
            context.insert(AssetItem(name: "房", amount: 100_000, sortOrder: 0))
            context.insert(AssetItem(name: "定期", amount: 35_000, sortOrder: 1))
            try context.save()
        }

        let bootstrap = StoreBootstrap(factory: {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        })
        guard case .ready(let container) = bootstrap.state else {
            Issue.record("阶段 2 数据库升级后进了恢复页")
            return
        }
        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<AssetItem>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.countsInFreedom })
        #expect(try context.fetch(FetchDescriptor<UserAssets>()).first?.netWorth == 149_000)
    }
}
