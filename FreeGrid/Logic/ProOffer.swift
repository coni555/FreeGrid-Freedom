// Pro 试用和试用专属价的时间规则（用户 2026-10-17 定）：
// 每个人自己点「开始试用」，从那一刻起 7 天 Pro 全开；从同一刻起 14 天内买断用专属价，过了用原价。
// 还没开始试用的人也按专属价：直接买的人不该比先试用的人付得多。
// 只管按时间算，不碰 App Store；试用从哪一刻开始由 ProStore 从购买记录里读出来。

import Foundation

struct ProOffer: Equatable {
    static let trialDays = 7
    static let specialPriceDays = 14

    /// 试用那笔 ¥0 交易的时间；还没开始试用为 nil
    var trialStartedAt: Date?

    var trialEndsAt: Date? {
        trialStartedAt.map { $0.addingTimeInterval(Self.days(Self.trialDays)) }
    }

    var specialPriceEndsAt: Date? {
        trialStartedAt.map { $0.addingTimeInterval(Self.days(Self.specialPriceDays)) }
    }

    var hasStartedTrial: Bool { trialStartedAt != nil }

    func isTrialActive(at now: Date) -> Bool {
        guard let start = trialStartedAt, let end = trialEndsAt else { return false }
        return start <= now && now < end
    }

    /// 买断现在该用专属价还是原价
    func hasSpecialPrice(at now: Date) -> Bool {
        guard let end = specialPriceEndsAt else { return true }
        return now < end
    }

    /// 下一个会让界面变样的时刻（试用结束、专属价结束），都过了为 nil
    func nextChange(after now: Date) -> Date? {
        [trialEndsAt, specialPriceEndsAt].compactMap { $0 }.filter { $0 > now }.min()
    }

    /// 「还剩 N 天」：不足一天也算一天，到点前一直至少显示 1
    static func daysLeft(until end: Date, from now: Date) -> Int {
        max(0, Int((end.timeIntervalSince(now) / days(1)).rounded(.up)))
    }

    private static func days(_ count: Int) -> TimeInterval { TimeInterval(count) * 24 * 60 * 60 }
}
