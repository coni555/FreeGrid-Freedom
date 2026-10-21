import Foundation

/// 只按使用程度和请求间隔判断，不根据金额、Pro 状态或满意度筛选用户。
nonisolated enum ReviewInvitation {
    static let requiredDays = 10
    static let intervalDays = 90
    static let opportunityLifetime: TimeInterval = 120

    static func shouldRequest(recordedDays: Int, lastRequestedAt: Date?, now: Date,
                              calendar: Calendar = .current) -> Bool {
        guard recordedDays >= requiredDays else { return false }
        guard let lastRequestedAt else { return true }
        guard let next = calendar.date(byAdding: .day, value: intervalDays, to: lastRequestedAt) else { return false }
        return now >= next
    }
}
