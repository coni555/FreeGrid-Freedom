// 由现有财务摘要计算自检结果，不保存额外状态。

import Foundation

/// 单项自检结果
struct FreedomCheckItem: Identifiable {
    let id: Int            // 1...8
    let title: String      // 完整标题
    let shortTitle: String // 「下一站」用的短名
    let done: Bool
    let progress: Double?  // 0...1, 量化项(1/4/5/7/8)有; 二元项(2/3/6)为 nil
    let detail: String     // "当前 49 / 180 天"; 二元项为 ""
    let hint: String       // 怎么前进
}

/// 自检汇总 — collapsed 卡用 doneCount/progress/nextStop, 子页用 items
struct FreedomSummary {
    let items: [FreedomCheckItem]
    let doneCount: Int
    let total: Int
    let progress: Double         // doneCount / total
    let nextStopTitle: String?   // "自由天数 180 天" / item.shortTitle; 全达成 nil
    let remainText: String?      // "还差 131 天"; 仅 freedom-day 里程碑有
}

enum FreedomChecklist {
    /// 从已有记录反推 8 项自检 + 汇总。incomes 不参与(跟原 CheckView 一致)。
    static func evaluate(expenses: [Expense],
                         passiveSources: [PassiveSource],
                         assets: UserAssets?) -> FreedomSummary {
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assets)
        let days = snapshot.trackDays
        let dailyBurn = snapshot.dailyBurn
        let netWorth = snapshot.netWorth
        let passiveRatio = snapshot.passiveRatio
        let freedomState = snapshot.freedom
        let finiteFreedom: Double?
        let freedomMilestonesComplete: Bool
        switch freedomState {
        case .finite(let days):
            finiteFreedom = days
            freedomMilestonesComplete = false
        case .covered:
            finiteFreedom = nil
            freedomMilestonesComplete = true
        case .insufficientData, .invalidData:
            finiteFreedom = nil
            freedomMilestonesComplete = false
        }
        let fInt = finiteFreedom.flatMap { FinancialFormatting.integer($0.rounded(.down)) }
        let fShow = finiteFreedom.map { FinancialFormatting.wholeNumber($0.rounded(.down)) }
            ?? FreedomMath.freedomDaysDisplay(freedomState)
        let pct = FinancialFormatting.percentage(passiveRatio)

        let items: [FreedomCheckItem] = [
            FreedomCheckItem(
                id: 1, title: "记录天数超过 30 天", shortTitle: "记录满 30 天",
                done: days >= 30,
                progress: min(1, Double(days) / 30),
                detail: "当前 \(days) / 30 天",
                hint: "继续每天记账,还差 \(max(0, 30 - days)) 天"),
            FreedomCheckItem(
                id: 2, title: "了解自己的日均消费", shortTitle: "了解日均消费",
                done: days >= 7 && dailyBurn > 0,
                progress: nil, detail: "",
                hint: "记满 7 天且有支出记录后自动达成"),
            FreedomCheckItem(
                id: 3, title: "记录了可变现资产", shortTitle: "记录可变现资产",
                done: netWorth > 0,
                progress: nil, detail: "",
                hint: "去 Assets 填入你的现金 / 可变现资产"),
            FreedomCheckItem(
                id: 4, title: "自由天数超过 180 天", shortTitle: "自由天数 180 天",
                done: freedomMilestonesComplete || (finiteFreedom ?? 0) >= 180,
                progress: freedomMilestonesComplete ? 1 : min(1, (finiteFreedom ?? 0) / 180),
                detail: "当前 \(fShow) / 180 天",
                hint: "提高净值或降低日均消费"),
            FreedomCheckItem(
                id: 5, title: "自由天数超过 365 天", shortTitle: "自由天数 365 天",
                done: freedomMilestonesComplete || (finiteFreedom ?? 0) >= 365,
                progress: freedomMilestonesComplete ? 1 : min(1, (finiteFreedom ?? 0) / 365),
                detail: "当前 \(fShow) / 365 天",
                hint: "继续积累净值或被动收入"),
            FreedomCheckItem(
                id: 6, title: "有被动收入来源", shortTitle: "添加被动收入",
                done: !passiveSources.isEmpty,
                progress: nil, detail: "",
                hint: "在 Assets 添加一个被动收入源(房租 / 股息 / 利息…)"),
            FreedomCheckItem(
                id: 7, title: "被动覆盖率超过 50%", shortTitle: "被动覆盖率 50%",
                done: passiveRatio >= 0.5,
                progress: min(1, passiveRatio / 0.5),
                detail: "当前 \(pct) / 50%",
                hint: "提高被动收入或降低日均消费"),
            FreedomCheckItem(
                id: 8, title: "被动收入覆盖日常消费 (≥100%)", shortTitle: "被动覆盖 100%",
                done: passiveRatio >= 1.0,
                progress: min(1, passiveRatio),
                detail: "当前 \(pct) / 100%",
                hint: "被动收入覆盖全部日常消费即财务自由"),
        ]

        let doneCount = items.filter(\.done).count

        // 下一站: 优先 freedom-day 里程碑(180 → 365), 都达成则指向下一个未达成项, 全达成 nil
        let nextStopTitle: String?
        let remainText: String?
        if let fInt, fInt < 180 {
            nextStopTitle = "自由天数 180 天"
            remainText = "还差 \(180 - fInt) 天"
        } else if let fInt, fInt < 365 {
            nextStopTitle = "自由天数 365 天"
            remainText = "还差 \(365 - fInt) 天"
        } else if let nextUnmet = items.first(where: { !$0.done }) {
            nextStopTitle = nextUnmet.shortTitle
            remainText = nil
        } else {
            nextStopTitle = nil
            remainText = nil
        }

        return FreedomSummary(
            items: items,
            doneCount: doneCount,
            total: items.count,
            progress: Double(doneCount) / Double(items.count),
            nextStopTitle: nextStopTitle,
            remainText: remainText)
    }
}
