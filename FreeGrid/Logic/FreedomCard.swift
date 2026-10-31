// Pro 第五项权益「自由卡」要用到的数：卡的材质（随自由天数升级）、卡面上写什么、什么时候在首页提示一次「升级了」。
// 卡上只写天数和比例，从不写金额：用户 2026-10-17「我不希望我的用户去炫富」。

import Foundation

/// 卡的材质。按自由天数从低到高；被动收入盖住全部开销时是 ∞ 卡
enum FreedomCardTier: Int, CaseIterable, Comparable {
    case paper, silver, champagne, obsidian, infinite

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 不到 30 天纸卡，30 天起银卡，180 天起香槟金，365 天起黑卡；还算不出来时也是纸卡
    static func tier(for state: FreedomState) -> FreedomCardTier {
        switch state {
        case .covered: return .infinite
        case .finite(let days):
            switch days {
            case 365...: return .obsidian
            case 180...: return .champagne
            case 30...: return .silver
            default: return .paper
            }
        case .insufficientData, .invalidData: return .paper
        }
    }

    /// 卡面右上角的等级字样
    var label: String {
        switch self {
        case .paper: return "PAPER"
        case .silver: return "SILVER"
        case .champagne: return "CHAMPAGNE"
        case .obsidian: return "OBSIDIAN"
        case .infinite: return "FREE"
        }
    }

    var name: String {
        switch self {
        case .paper: return String(localized: "纸卡")
        case .silver: return String(localized: "银卡")
        case .champagne: return String(localized: "香槟金卡")
        case .obsidian: return String(localized: "黑卡")
        case .infinite: return String(localized: "∞ 卡")
        }
    }

    /// 等级表里的一句：多少天起
    var threshold: String {
        switch self {
        case .paper: return String(localized: "起步")
        case .silver: return String(localized: "30 天")
        case .champagne: return String(localized: "180 天")
        case .obsidian: return String(localized: "1 年")
        case .infinite: return String(localized: "被动收入覆盖开销")
        }
    }
}

/// 卡面上的全部内容。从财务摘要和自检里取，不另存
struct FreedomCardData: Equatable {
    let freedom: FreedomState
    let tier: FreedomCardTier
    /// 记账天数
    let trackDays: Int
    let passiveRatio: Double
    let milestonesDone: Int
    let milestonesTotal: Int
    /// 第一笔账的日期
    let since: Date?
    /// 卡面格子里金色（资产）占多少，其余是蓝色（现金）
    let assetShare: Double

    init(snapshot: FinancialSnapshot, summary: FreedomSummary) {
        freedom = snapshot.freedom
        tier = FreedomCardTier.tier(for: snapshot.freedom)
        trackDays = snapshot.hasRecords ? snapshot.trackDays : 0
        passiveRatio = snapshot.passiveRatio
        milestonesDone = summary.doneCount
        milestonesTotal = summary.total
        since = snapshot.firstExpenseDate
        assetShare = snapshot.freedomBase > 0 ? min(1, max(0, snapshot.countedAssets / snapshot.freedomBase)) : 0
    }

    /// 大数字：整天，带千分位；∞；还算不出来时是一条横线
    var daysText: String {
        switch freedom {
        case .finite(let days): return Int(max(0, days).rounded(.down)).formatted(.number)
        case .covered: return "∞"
        case .insufficientData, .invalidData: return "—"
        }
    }

    /// 海报上的一句话
    var posterLine: String {
        switch freedom {
        case .finite: return String(localized: "我的自由\n还能撑 \(daysText) 天")
        case .covered: return String(localized: "我的被动收入\n已经覆盖了全部开销")
        case .insufficientData, .invalidData: return String(localized: "我在用 FreeGrid\n数我的自由")
        }
    }

    /// 卡面格子：一共 `total` 格里亮几格。天数越多亮得越满，一年铺到九成；∞ 卡全亮
    func litCells(of total: Int) -> Int {
        switch freedom {
        case .covered: return total
        case .finite(let days):
            return min(total, Int((min(1, max(0, days) / 365) * Double(total) * 0.9).rounded()) + total / 30)
        case .insufficientData, .invalidData: return total / 30
        }
    }
}

/// 首页那一行「自由卡升级了」：只在卡第一次达到某个更高的等级时出现一次，点开看过就不再出现
enum FreedomCardPrompt {
    /// 看过的最高等级（rawValue），本机偏好；没看过是 -1
    static let highestSeenKey = "freedomCardHighestSeen"

    /// 纸卡是起点，不值得提示；从银卡开始
    static func text(current: FreedomCardTier, highestSeen: Int, hasFreedomNumber: Bool) -> String? {
        guard hasFreedomNumber, current > .paper, current.rawValue > highestSeen else { return nil }
        return highestSeen < 0 ? String(localized: "你有一张\(current.name)了") : String(localized: "自由卡升级成了\(current.name)")
    }
}
