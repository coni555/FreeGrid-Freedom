// 保存当时实际显示的输入，不用今天的资产或后来补录的数据改写过去。
import Foundation
import SwiftData

@Model
final class FreedomObservation {
    var id: UUID = UUID()
    var seriesID: UUID = UUID()
    var sequence: Int = 0
    var recordedAt: Date = Date.now
    var reason: String = "baseline"
    var effectiveDate: Date?
    var cash: Double = 0
    var lockedAssets: Double = 0
    var totalExpenses: Double = 0
    var trackDays: Int = 0
    var dailyPassive: Double = 0
    var hasExpenses: Bool = false
    var calculationVersion: Int = 1
    var isImported: Bool = false

    init(_ value: ObservationValue, isImported: Bool = false) {
        id = value.id
        seriesID = value.seriesID
        sequence = value.sequence
        recordedAt = value.recordedAt
        reason = value.reason.rawValue
        effectiveDate = value.effectiveDate
        cash = value.cash
        lockedAssets = value.lockedAssets
        totalExpenses = value.totalExpenses
        trackDays = value.trackDays
        dailyPassive = value.dailyPassive
        hasExpenses = value.hasExpenses
        calculationVersion = value.calculationVersion
        self.isImported = isImported
    }

    var value: ObservationValue {
        ObservationValue(id: id, seriesID: seriesID, sequence: sequence, recordedAt: recordedAt,
                         reason: ObservationReason(rawValue: reason) ?? .observation,
                         effectiveDate: effectiveDate, cash: cash, lockedAssets: lockedAssets,
                         totalExpenses: totalExpenses, trackDays: trackDays, dailyPassive: dailyPassive,
                         hasExpenses: hasExpenses, calculationVersion: calculationVersion)
    }
}
