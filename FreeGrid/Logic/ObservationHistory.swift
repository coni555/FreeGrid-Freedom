import Foundation

enum ObservationHistory {
    // 同日只用最后一次实际记录作为图上的点，详情仍保留当日每次变化。
    static func dailyPoints(_ values: [ObservationValue], calendar: Calendar = .current) -> [ObservationValue] {
        let groups = Dictionary(grouping: values) { calendar.startOfDay(for: $0.recordedAt) }
        return groups.keys.sorted().compactMap { day in groups[day]?.max { $0.sequence < $1.sequence } }
    }

    static func netChanges(_ values: [ObservationValue]) -> [(reason: ObservationReason, amount: Double)] {
        guard values.count > 1 else { return [] }
        let ordered = values.sorted { $0.sequence < $1.sequence }
        var totals: [ObservationReason: Double] = [:]
        for (before, after) in zip(ordered, ordered.dropFirst()) where before.seriesID == after.seriesID {
            totals[after.reason, default: 0] += after.netWorth - before.netWorth
        }
        return ObservationReason.allCases.compactMap { reason in
            guard let amount = totals[reason], amount != 0 else { return nil }
            return (reason, amount)
        }
    }
}
