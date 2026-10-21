import Foundation
import Observation

/// 只保存「尝试请求」时间；系统不提供是否展示、是否评分的回调。
@MainActor
@Observable
final class ReviewInvitationStore {
    static let shared = ReviewInvitationStore(defaults: AppPreferences.store)
    static let lastRequestedKey = "reviewLastRequestedAt"

    struct Opportunity: Equatable {
        let id = UUID()
        let transactionID: UUID
        let savedAt: Date
    }

    private(set) var opportunity: Opportunity?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    static var isSuppressedForTesting: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UseInMemoryStore") && !args.contains("-reviewInvitation")
        #else
        return false
        #endif
    }

    var lastRequestedAt: Date? {
        let raw = defaults.object(forKey: Self.lastRequestedKey)
        // 启动参数域可能以字符串覆盖测试偏好中的数值，二者都按同一个时间戳读取。
        let timestamp = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init)
        guard let timestamp, timestamp.isFinite else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// 仅由添加收支的表单在保存成功后调用，不接数据库的通用变化通知。
    func didSave(transactionID: UUID, now: Date = .now) {
        opportunity = Opportunity(transactionID: transactionID, savedAt: now)
    }

    /// 开始下一笔输入就结束上一笔的邀请，不能在取消新表单时补弹。
    func didBeginEntry() { opportunity = nil }

    func discard(_ id: UUID) {
        if opportunity?.id == id { opportunity = nil }
    }

    func didUndo(transactionID: UUID) {
        if opportunity?.transactionID == transactionID { opportunity = nil }
    }

    @discardableResult
    func requestIfEligible(_ id: UUID, recordedDays: Int, now: Date = .now,
                           calendar: Calendar = .current, request: () -> Void) -> Bool {
        guard let candidate = opportunity, candidate.id == id else { return false }
        opportunity = nil
        let age = now.timeIntervalSince(candidate.savedAt)
        guard age >= 0, age < ReviewInvitation.opportunityLifetime,
              ReviewInvitation.shouldRequest(recordedDays: recordedDays, lastRequestedAt: lastRequestedAt,
                                             now: now, calendar: calendar) else { return false }
        // 在调用前落盘，多个窗口或连续记账也不会重复请求；没展示也不追着用户再弹。
        defaults.set(now.timeIntervalSince1970, forKey: Self.lastRequestedKey)
        request()
        return true
    }

    #if DEBUG
    /// UI 回归只记录请求次数，不依赖 StoreKit 是否决定显示，也不提交评价。
    static var usesRequestProbe: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-UseInMemoryStore") && args.contains("-ReviewRequestProbe")
    }

    private static var probeCount = 0

    static func recordRequestProbe() {
        let args = ProcessInfo.processInfo.arguments
        guard usesRequestProbe, let flag = args.firstIndex(of: "-ReviewRequestProbeFile"),
              args.indices.contains(flag + 1) else { return }
        probeCount += 1
        let data = try? JSONEncoder().encode(["requests": probeCount])
        try? data?.write(to: URL(fileURLWithPath: args[flag + 1]), options: .atomic)
    }
    #endif
}
