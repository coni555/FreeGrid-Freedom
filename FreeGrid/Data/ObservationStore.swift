import Foundation
import SwiftData

@MainActor
enum ObservationStore {
    static func latest(in context: ModelContext) throws -> FreedomObservation? {
        var query = FetchDescriptor<FreedomObservation>(predicate: #Predicate { !$0.isImported },
                                                       sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        query.fetchLimit = 1
        return try context.fetch(query).first
    }

    static func capture(in context: ModelContext, reason: ObservationReason, effectiveDate: Date?,
                        now: Date, previous: FreedomObservation?) throws -> ObservationValue {
        let snapshot = FinancialSnapshot(
            expenses: try context.fetch(FetchDescriptor<Expense>()).filter { !$0.isDeleted },
            passiveSources: try context.fetch(FetchDescriptor<PassiveSource>()).filter { !$0.isDeleted },
            assets: try context.fetch(FetchDescriptor<UserAssets>()).first, now: now)
        let value = ObservationValue(id: UUID(), seriesID: previous?.seriesID ?? UUID(),
            sequence: (previous?.sequence ?? -1) + 1, recordedAt: now, reason: reason,
            effectiveDate: effectiveDate, cash: snapshot.cash, lockedAssets: snapshot.lockedAssets,
            totalExpenses: snapshot.totalExpenses, trackDays: snapshot.trackDays,
            dailyPassive: snapshot.dailyPassive, hasExpenses: snapshot.hasExpenses, calculationVersion: 1)
        try ObservationValidation.validate([value], maximum: 1, now: .distantFuture)
        return value
    }

    // 由保存事务调用；第一次业务操作先留下操作前起点，失败会一起回滚。
    static func begin(in context: ModelContext, now: Date) throws -> FreedomObservation {
        if let previous = try latest(in: context) { return previous }
        let value = try capture(in: context, reason: .baseline, effectiveDate: nil, now: now, previous: nil)
        let entry = FreedomObservation(value)
        context.insert(entry)
        return entry
    }

    static func append(in context: ModelContext, previous: FreedomObservation,
                       reason: ObservationReason, effectiveDate: Date?, now: Date) throws {
        let value = try capture(in: context, reason: reason, effectiveDate: effectiveDate, now: now, previous: previous)
        if !value.sameInputs(as: previous.value) { context.insert(FreedomObservation(value)) }
    }

    // 只在启动、回到前台或前台跨日时观察，不声称后台每天记录了收盘值。
    static func observe(in context: ModelContext, now: Date = .now,
                        save: LedgerStore.SaveAction = { try $0.save() }) throws {
        guard !context.hasChanges else { throw LedgerStore.StoreError.pendingChanges }
        let previous = try latest(in: context)
        let value = try capture(in: context, reason: previous == nil ? .baseline : .observation,
                                effectiveDate: nil, now: now, previous: previous)
        if let previous, Calendar.current.isDate(previous.recordedAt, inSameDayAs: now),
           value.sameInputs(as: previous.value) { return }
        try LedgerStore.perform(in: context, save: save) { context.insert(FreedomObservation(value)) }
    }

    static func validateMerge(_ values: [ObservationValue], in context: ModelContext) throws {
        let rows = try context.fetch(FetchDescriptor<FreedomObservation>())
        let activeSeries = Set(rows.filter { !$0.isImported }.map(\.seriesID))
        let existing = rows.map(\.value)
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for value in values {
            if let old = byID[value.id] {
                guard old == value else { throw ImportValidationError.invalidObservation }
            } else if activeSeries.contains(value.seriesID) {
                // 本机连续记录不能混入同源但不同进度的副本，否则下一次序号会冲突。
                throw ImportValidationError.invalidObservation
            }
        }
        let combined = existing + values.filter { byID[$0.id] == nil }
        try ObservationValidation.validate(combined, maximum: .max, now: .distantFuture)
    }

    static func importArchive(_ values: [ObservationValue], in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<FreedomObservation>())
        let byID = Dictionary(existing.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
        for value in values {
            if let old = byID[value.id] {
                guard old == value else { throw ImportValidationError.invalidObservation }
            } else {
                // 不将来自另一份账本的历史当作本机的连续增长。
                context.insert(FreedomObservation(value, isImported: true))
            }
        }
    }
}
