import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct ObservationTests {
    private enum Failure: Error { case save }
    private func values(_ context: ModelContext) throws -> [ObservationValue] {
        try context.fetch(FetchDescriptor<FreedomObservation>(sortBy: [SortDescriptor(\.sequence)])).map(\.value)
    }

    @Test func savesBackfillUndoTransferAndPassiveChangesWithoutRewritingHistory() throws {
        let context = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: context) { $0.cash = 10000 }
        let before = try values(context)
        let expense = Expense(amount: 100, category: "午餐", date: TestSupport.day("2026-01-01"))
        try LedgerStore.add(.expense(expense), in: context)
        let afterExpense = try #require(try values(context).last)
        #expect(afterExpense.reason == .backfillExpense)
        #expect(afterExpense.effectiveDate == expense.date)
        #expect(afterExpense.cash == 9900 && afterExpense.totalExpenses == 100)
        #expect(Array(try values(context).prefix(before.count)) == before)
        try LedgerStore.undo(id: expense.id, kind: .expense, in: context)
        let undone = try #require(try values(context).last)
        #expect(undone.reason == .undo && undone.cash == 10000)
        #expect(undone.totalExpenses == 0 && !undone.hasExpenses && undone.trackDays == 0)
        try LedgerStore.updateAssets(in: context, reason: .transfer) { $0.cash -= 200; $0.lockedAssets += 200 }
        #expect(try values(context).last?.netWorth == 10000)
        #expect(try values(context).last?.reason == .transfer)
        try LedgerStore.savePassiveSource(nil, name: "利息", monthlyAmount: 300, in: context)
        #expect(try values(context).last?.dailyPassive == 10)
        let source = try #require(try context.fetch(FetchDescriptor<PassiveSource>()).first)
        try LedgerStore.perform(in: context, reason: .passiveChange) { context.delete(source) }
        #expect(try values(context).last?.dailyPassive == 0)
        #expect(try values(context).last?.netWorth == 10000)
    }

    @Test func failedSavesRollbackBaselineAndHistoryAlongWithLedger() throws {
        let context = try TestSupport.makeContext()
        #expect(throws: Failure.self) {
            try LedgerStore.add(.income(Income(amount: 100, source: "工资")), in: context) { _ in throw Failure.save }
        }
        #expect(try values(context).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Income>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UserAssets>()) == 0)
        try LedgerStore.updateAssets(in: context) { $0.cash = 100 }
        let before = try values(context)
        #expect(throws: Failure.self) {
            try LedgerStore.updateAssets(in: context, save: { _ in throw Failure.save }) { $0.cash = 90 }
        }
        #expect(try values(context) == before)
        #expect(try context.fetch(FetchDescriptor<UserAssets>()).first?.cash == 100)
        #expect(!context.hasChanges)
    }

    @Test func observationsSkipSameDayAndDoNotInventMissingDays() throws {
        let context = try TestSupport.makeContext()
        let day = TestSupport.day("2026-01-01")
        try ObservationStore.observe(in: context, now: day)
        try ObservationStore.observe(in: context, now: day.addingTimeInterval(3600))
        #expect(try values(context).count == 1)
        try ObservationStore.observe(in: context, now: day.addingTimeInterval(5 * 86400))
        #expect(try values(context).count == 2)
        #expect(try values(context).map(\.sequence) == [0, 1])
        #expect(ObservationHistory.dailyPoints(try values(context)).count == 2)
        let pending = Income(amount: 10, source: "未保存")
        context.insert(pending)
        #expect(throws: LedgerStore.StoreError.self) { try ObservationStore.observe(in: context) }
        #expect(context.hasChanges)
    }

    @Test func backupRestoresIndependentHistoryAndReimportIsIdempotent() throws {
        let source = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: source) { $0.cash = 10000 }
        try LedgerStore.add(.expense(Expense(amount: 30, category: "午餐")), in: source)
        let original = try values(source)
        let backup = try DataIO.exportJSON(context: source)
        #expect(try ImportValidator.validate(data: backup).schemaVersion == 4)
        let target = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: target) { $0.cash = 20 }
        let local = try values(target)
        _ = try DataIO.commitImport(preview: DataIO.previewJSON(data: backup, context: target), strategy: .replace, context: target)
        let rows = try target.fetch(FetchDescriptor<FreedomObservation>())
        #expect(rows.filter(\.isImported).map(\.value).sorted { $0.sequence < $1.sequence } == original)
        #expect(Set(rows.filter { !$0.isImported }.map(\.seriesID)) == Set(local.map(\.seriesID)))
        #expect(rows.filter { !$0.isImported }.max { $0.sequence < $1.sequence }?.reason == "backupImport")
        let before = try DataIO.exportJSON(context: target)
        _ = try DataIO.commitImport(preview: DataIO.previewJSON(data: backup, context: target), strategy: .skipAssets, context: target)
        #expect(try DataIO.exportJSON(context: target) == before)
        try DataIO.purgeAll(context: target)
        #expect(try values(target).isEmpty)
    }

    @Test func archiveRejectsConflictsMalformedFieldsAndResourceOverflow() throws {
        let source = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: source) { $0.cash = 10 }
        var entries = try values(source)
        #expect(throws: ImportValidationError.self) {
            try ObservationValidation.validate(entries, maximum: 1, now: .now)
        }
        entries[1].sequence = entries[0].sequence
        #expect(throws: ImportValidationError.invalidObservation) {
            try ObservationValidation.validate(entries, maximum: 100, now: .now)
        }
        entries = try values(source)
        entries[0].cash = 20
        #expect(throws: ImportValidationError.invalidObservation) {
            try ObservationStore.validateMerge(entries, in: source)
        }
        entries[0].cash = .nan
        #expect(throws: ImportValidationError.invalidObservation) {
            try ObservationValidation.validate(entries, maximum: 100, now: .now)
        }
        entries = try values(source)
        entries[0].calculationVersion = 2
        #expect(throws: ImportValidationError.invalidObservation) {
            try ObservationValidation.validate(entries, maximum: 100, now: .now)
        }
    }

    @Test func importedSnapshotConflictAndLocalObservationInvalidatePreview() throws {
        let context = try TestSupport.makeContext()
        let data = Data(#"{"schema_version":2,"assets":{"total":100}}"#.utf8)
        let preview = try DataIO.previewJSON(data: data, context: context)
        try ObservationStore.observe(in: context)
        #expect(throws: DataIO.DataIOError.stalePreview) {
            _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: context)
        }
    }

    @Test func netChangeReasonsReconcileAndNeverTreatTransferAsIncome() throws {
        let context = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: context) { $0.cash = 10000 }
        let start = try #require(try values(context).last)
        try LedgerStore.add(.income(Income(amount: 1500, source: "工资")), in: context)
        try LedgerStore.add(.expense(Expense(amount: 700, category: "购物")), in: context)
        try LedgerStore.updateAssets(in: context) { $0.lockedAssets = 300 }
        try LedgerStore.updateAssets(in: context, reason: .transfer) { $0.cash -= 200; $0.lockedAssets += 200 }
        let period = try values(context).filter { $0.sequence >= start.sequence }
        let changes = ObservationHistory.netChanges(period)
        #expect(changes.reduce(0) { $0 + $1.amount } == 1100)
        #expect(!changes.contains { $0.reason == .transfer })
        #expect(period.last?.netWorth == 11100)
    }
    @Test func fiveModelDiskStoreUpgradesWithoutChangingExistingData() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("legacy.store")
        let expenseID = try seedLegacyStore(at: url)
        let schema = StoreBootstrap.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<FreedomObservation>()) == 0)
        try ObservationStore.observe(in: context)
        #expect(try context.fetch(FetchDescriptor<Expense>()).first?.id == expenseID)
        #expect(try context.fetch(FetchDescriptor<UserAssets>()).first?.cash == 900)
        #expect(try values(context).count == 1)
        #expect(try values(context).first?.totalExpenses == 100)
        #expect(try context.fetchCount(FetchDescriptor<Income>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Device>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PassiveSource>()) == 1)
    }

    private func seedLegacyStore(at url: URL) throws -> UUID {
        let schema = Schema([Expense.self, Income.self, Device.self, PassiveSource.self, UserAssets.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        let expense = Expense(amount: 100, category: "午餐", date: TestSupport.day("2026-01-01"))
        context.insert(expense)
        context.insert(Income(amount: 50, source: "工资"))
        context.insert(Device(name: "电脑", category: "数码", price: 3000, purchaseDate: .now))
        context.insert(PassiveSource(name: "利息", monthlyAmount: 30))
        let assets = UserAssets(total: 0)
        assets.cash = 900
        context.insert(assets)
        try context.save()
        return expense.id
    }

}
