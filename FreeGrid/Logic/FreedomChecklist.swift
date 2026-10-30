// 由现有财务摘要计算自检结果，不保存额外状态。
// 2.1 起是三组里程碑：记录（记账满 30 / 90 / 365 天）、自由天数三级（和自由卡的材质同一套台阶）、现金流（每月有结余、被动收入两级）。
// 填了钱、有被动收入这类设置步骤不算分。

import Foundation

/// 自检的三组，顺序就是自检页上的顺序
enum FreedomCheckGroup: String, CaseIterable, Identifiable {
    case record, freedom, flow

    var id: String { rawValue }

    /// 组头的等宽小标签
    var kicker: String {
        switch self {
        case .record: return String(localized: "Record · 记录")
        case .freedom: return String(localized: "Freedom · 自由天数")
        case .flow: return String(localized: "Flow · 现金流")
        }
    }
}

/// 单项自检结果
struct FreedomCheckItem: Identifiable {
    let id: Int            // 1–3 自由天数、4 每月有结余、5–6 被动收入、7–9 记账天数；新加的往后排，不改旧编号
    let group: FreedomCheckGroup
    let title: String      // 完整标题
    let shortTitle: String // 「下一站」用的短名
    let done: Bool
    let progress: Double?  // 0...1；还判断不了时为 nil
    let detail: String     // "当前 49 / 180 天"；还判断不了时为 ""
    let hint: String       // 怎么前进
    /// 达成后「已达成」后面跟的一句；nil 时只写「已达成」
    var achievedNote: String? = nil
}

/// 自检汇总 — collapsed 卡用 doneCount/progress/nextStop, 子页用 groups
struct FreedomSummary {
    /// 按自检页上的顺序：记录、自由天数、现金流
    let items: [FreedomCheckItem]
    let doneCount: Int
    let total: Int
    let progress: Double         // doneCount / total
    let nextStopTitle: String?   // "自由天数 180 天" / item.shortTitle; 全达成 nil
    let remainText: String?      // "还差 131 天"; 仅自由天数的里程碑有

    func items(in group: FreedomCheckGroup) -> [FreedomCheckItem] { items.filter { $0.group == group } }
}

enum FreedomChecklist {
    /// 自由天数的三级，和自由卡银卡、香槟金、黑卡的门槛一致
    static let freedomMilestones = [30, 180, 365]
    /// 记账满多少天。90 天是日均不再把大额摊开估算的那一天（`FreedomMath.lumpSpreadDays`）
    static let recordMilestones = [30, FreedomMath.lumpSpreadDays, 365]

    /// 从已有记录反推自检 + 汇总。
    /// 自由天数相关的项和首页用同一个口径；「每月有结余」要知道收入，没有时还判断不了。
    static func evaluate(expenses: [Expense],
                         passiveSources: [PassiveSource],
                         assets: UserAssets?,
                         assetItems: [AssetItem] = [],
                         cashAccounts: [CashAccount] = [],
                         loans: [Loan] = [],
                         saving: MonthlySaving? = nil,
                         now: Date = .now,
                         countsAssets: Bool = FreedomSettings.countsAssets) -> FreedomSummary {
        evaluate(snapshot: FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assets,
                                             assetItems: assetItems, cashAccounts: cashAccounts, loans: loans,
                                             now: now, countsAssets: countsAssets),
                 saving: saving)
    }

    /// 已经算好 `FinancialSnapshot` 的页面直接用它，不再把整本账算一遍
    static func evaluate(snapshot: FinancialSnapshot, saving: MonthlySaving? = nil) -> FreedomSummary {
        let passiveRatio = snapshot.passiveRatio
        let finiteFreedom: Double?
        let covered: Bool
        switch snapshot.freedom {
        case .finite(let days):
            finiteFreedom = days
            covered = false
        case .covered:
            finiteFreedom = nil
            covered = true
        case .insufficientData, .invalidData:
            finiteFreedom = nil
            covered = false
        }
        let fShow = finiteFreedom.map { FinancialFormatting.wholeNumber($0.rounded(.down)) }
            ?? FreedomMath.freedomDaysDisplay(snapshot.freedom)
        let pct = FinancialFormatting.percentage(passiveRatio)

        func freedomItem(_ id: Int, _ target: Int) -> FreedomCheckItem {
            FreedomCheckItem(
                id: id, group: .freedom, title: String(localized: "自由天数超过 \(target) 天"), shortTitle: String(localized: "自由天数 \(target) 天"),
                done: covered || (finiteFreedom ?? 0) >= Double(target),
                progress: covered ? 1 : min(1, (finiteFreedom ?? 0) / Double(target)),
                detail: String(localized: "当前 \(fShow) / \(target) 天"),
                hint: snapshot.countsAssets ? String(localized: "增加可动用资产或降低日均消费")
                                            : String(localized: "提高现金或降低日均消费"))
        }

        // 记账天数从第一笔支出那天算，和首页「记账天数」同一个数；不要求连续，不花钱的日子本来就没有可记的
        let days = snapshot.trackDays
        func recordItem(_ id: Int, _ target: Int) -> FreedomCheckItem {
            FreedomCheckItem(
                id: id, group: .record, title: String(localized: "记账满 \(target) 天"), shortTitle: String(localized: "记账满 \(target) 天"),
                done: snapshot.hasRecords && days >= target,
                progress: snapshot.hasRecords ? min(1, Double(days) / Double(target)) : 0,
                detail: String(localized: "当前 \(String(snapshot.hasRecords ? days : 0)) / \(target) 天"),
                hint: snapshot.tracking.isMonthly ? String(localized: "用「每月一个数」时暂停更新")
                    : snapshot.hasRecords ? String(localized: "继续记下每天的花销")
                                           : String(localized: "记下第一笔支出，从那天开始算"),
                achievedNote: target == FreedomMath.lumpSpreadDays ? String(localized: "日均不再按大额摊开估算") : nil)
        }

        let freedom = freedomMilestones.enumerated().map { freedomItem($0.offset + 1, $0.element) }
        let flow: [FreedomCheckItem] = [
            savingItem(id: 4, saving: saving),
            FreedomCheckItem(
                id: 5, group: .flow, title: String(localized: "被动覆盖率超过 50%"), shortTitle: String(localized: "被动覆盖率 50%"),
                done: passiveRatio >= 0.5,
                progress: min(1, passiveRatio / 0.5),
                detail: String(localized: "当前 \(pct) / 50%"),
                hint: snapshot.dailyPassive > 0 ? String(localized: "提高被动收入或降低日均消费")
                                                : String(localized: "在钱包添加一项被动收入（租金、股息、利息…）")),
            FreedomCheckItem(
                id: 6, group: .flow, title: String(localized: "被动收入覆盖全部开销"), shortTitle: String(localized: "被动覆盖 100%"),
                done: passiveRatio >= 1.0,
                progress: min(1, passiveRatio),
                detail: String(localized: "当前 \(pct) / 100%"),
                hint: String(localized: "被动收入覆盖全部开销，就是财富自由")),
        ]
        let record = recordMilestones.enumerated().map { recordItem($0.offset + 7, $0.element) }
        let items = record + freedom + flow

        let doneCount = items.filter(\.done).count
        // 下一站：自由天数是主线，先看它；都达成了再看现金流，最后才是记账天数
        let next = (freedom + flow + record).first { !$0.done }
        var remainText: String?
        if let next, next.group == .freedom, let finiteFreedom,
           let fInt = FinancialFormatting.integer(finiteFreedom.rounded(.down)) {
            remainText = String(localized: "还差 \(freedomMilestones[next.id - 1] - fInt) 天")
        }

        return FreedomSummary(
            items: items,
            doneCount: doneCount,
            total: items.count,
            progress: Double(doneCount) / Double(items.count),
            nextStopTitle: next?.shortTitle,
            remainText: remainText)
    }

    /// 每月收入减开销为正。没填收入、记录也不够时还判断不了
    private static func savingItem(id: Int, saving: MonthlySaving?) -> FreedomCheckItem {
        let title = String(localized: "每月有结余")
        guard let saving else {
            return FreedomCheckItem(id: id, group: .flow, title: title, shortTitle: title, done: false, progress: nil,
                                    detail: "", hint: String(localized: "点这里填上每月到手收入"))
        }
        let amount = FinancialFormatting.wholeNumber(abs(saving.perMonth))
        let done = saving.perDay > 0
        let detail = done ? String(localized: "每月约存 ¥\(amount)") : String(localized: "每月约多花 ¥\(amount)")
        return FreedomCheckItem(
            id: id, group: .flow, title: title, shortTitle: title, done: done, progress: nil, detail: detail,
            hint: String(localized: "提高收入或降低日均消费"), achievedNote: done ? detail : nil)
    }
}
