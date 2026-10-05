import Foundation

nonisolated enum ObservationReason: String, Codable, Sendable, CaseIterable {
    case baseline, observation, expense, income, backfillExpense, backfillIncome
    case undo, assetAdjustment, transfer, passiveChange, backupImport

    var title: String {
        switch self {
        case .baseline: return "开始记录"
        case .observation: return "查看账本"
        case .expense: return "记录支出"
        case .income: return "记录收入"
        case .backfillExpense: return "补录支出"
        case .backfillIncome: return "补录收入"
        case .undo: return "撤销记录"
        case .assetAdjustment: return "资产调整"
        case .transfer: return "现金与资产调拨"
        case .passiveChange: return "调整被动收入"
        case .backupImport: return "导入备份"
        }
    }
}

// 备份使用同一份不可变值；日期按 JSONEncoder 的参考日期秒数无损保存。
nonisolated struct ObservationValue: Codable, Equatable, Identifiable, Sendable {
    // convertFromSnakeCase 将 series_id 转成 seriesId，显式映射缩写以保证往返。
    enum CodingKeys: String, CodingKey {
        case id, sequence, recordedAt, reason, effectiveDate, cash, lockedAssets
        case totalExpenses, trackDays, dailyPassive, hasExpenses, calculationVersion
        case seriesID = "seriesId"
    }
    var id: UUID
    var seriesID: UUID
    var sequence: Int
    var recordedAt: Date
    var reason: ObservationReason
    var effectiveDate: Date?
    var cash: Double
    var lockedAssets: Double
    var totalExpenses: Double
    var trackDays: Int
    var dailyPassive: Double
    var hasExpenses: Bool
    var calculationVersion: Int
}

extension ObservationValue {
    var netWorth: Double { cash + lockedAssets }
    var dailyBurn: Double { FreedomMath.dailyBurn(totalExpenses: totalExpenses, trackDays: trackDays) }
    var freedom: FreedomState {
        FreedomMath.freedomState(netWorth: netWorth, dailyBurn: dailyBurn,
                                dailyPassive: dailyPassive, hasExpenses: hasExpenses)
    }
    var freedomDescription: String {
        FreedomMath.HistoryPoint(date: recordedAt, state: freedom).description
    }

    func sameInputs(as other: Self) -> Bool {
        cash == other.cash && lockedAssets == other.lockedAssets && totalExpenses == other.totalExpenses
        && trackDays == other.trackDays && dailyPassive == other.dailyPassive && hasExpenses == other.hasExpenses
    }
}

nonisolated enum ObservationValidation {
    static func validate(_ values: [ObservationValue], maximum: Int, now: Date) throws {
        guard values.count <= maximum else {
            throw ImportValidationError.tooManyRecords(kind: "变化", count: values.count, maximum: maximum)
        }
        var ids = Set<UUID>()
        var sequences: [UUID: Set<Int>] = [:]
        for value in values {
            guard ids.insert(value.id).inserted,
                  sequences[value.seriesID, default: []].insert(value.sequence).inserted,
                  value.sequence >= 0, value.sequence < Int.max,
                  value.calculationVersion == 1,
                  (0...1_000_000).contains(value.trackDays),
                  value.cash.isFinite, abs(value.cash) <= FinancialLimits.maximumAmount,
                  value.lockedAssets.isFinite, value.lockedAssets >= 0,
                  value.lockedAssets <= FinancialLimits.maximumAmount,
                  value.totalExpenses.isFinite, value.dailyPassive.isFinite, value.dailyPassive >= 0,
                  value.recordedAt.timeIntervalSinceReferenceDate.isFinite,
                  value.recordedAt >= Date.distantPast,
                  value.recordedAt <= now.addingTimeInterval(86400),
                  value.hasExpenses || (value.trackDays == 0 && value.totalExpenses == 0)
            else { throw ImportValidationError.invalidObservation }
            if let date = value.effectiveDate {
                guard date.timeIntervalSinceReferenceDate.isFinite,
                      date >= Date.distantPast, date <= now.addingTimeInterval(86400)
                else { throw ImportValidationError.invalidObservation }
            }
        }
    }
}
