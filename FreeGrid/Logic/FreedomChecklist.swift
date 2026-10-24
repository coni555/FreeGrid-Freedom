// 由现有财务摘要计算自检结果，不保存额外状态。
// 2.1 起只留里程碑：自由天数三级（和自由卡的材质同一套台阶）、每月有结余、被动收入两级。
// 记账满 N 天、填了钱、有被动收入这类设置步骤不再算分，记账天数改成清单下面一行提示。

import Foundation

/// 单项自检结果
struct FreedomCheckItem: Identifiable {
    let id: Int            // 1...6
    let title: String      // 完整标题
    let shortTitle: String // 「下一站」用的短名
    let done: Bool
    let progress: Double?  // 0...1；还判断不了时为 nil
    let detail: String     // "当前 49 / 180 天"；还判断不了时为 ""
    let hint: String       // 怎么前进
}

/// 自检汇总 — collapsed 卡用 doneCount/progress/nextStop, 子页用 items
struct FreedomSummary {
    let items: [FreedomCheckItem]
    let doneCount: Int
    let total: Int
    let progress: Double         // doneCount / total
    let nextStopTitle: String?   // "自由天数 180 天" / item.shortTitle; 全达成 nil
    let remainText: String?      // "还差 131 天"; 仅自由天数的里程碑有
    /// 清单下面那行：记账不满 90 天时说再记多久日均就稳了；还没记账时说从哪开始。不计分
    let dataNote: String?
}

enum FreedomChecklist {
    /// 自由天数的三级，和自由卡银卡、香槟金、黑卡的门槛一致
    static let freedomMilestones = [30, 180, 365]

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
                id: id, title: String(localized: "自由天数超过 \(target) 天"), shortTitle: String(localized: "自由天数 \(target) 天"),
                done: covered || (finiteFreedom ?? 0) >= Double(target),
                progress: covered ? 1 : min(1, (finiteFreedom ?? 0) / Double(target)),
                detail: String(localized: "当前 \(fShow) / \(target) 天"),
                hint: snapshot.countsAssets ? String(localized: "增加可动用资产或降低日均消费")
                                            : String(localized: "提高现金或降低日均消费"))
        }

        let items: [FreedomCheckItem] = freedomMilestones.enumerated().map { freedomItem($0.offset + 1, $0.element) } + [
            savingItem(id: 4, saving: saving),
            FreedomCheckItem(
                id: 5, title: String(localized: "被动覆盖率超过 50%"), shortTitle: String(localized: "被动覆盖率 50%"),
                done: passiveRatio >= 0.5,
                progress: min(1, passiveRatio / 0.5),
                detail: String(localized: "当前 \(pct) / 50%"),
                hint: snapshot.dailyPassive > 0 ? String(localized: "提高被动收入或降低日均消费")
                                                : String(localized: "在钱包添加一项被动收入（租金、股息、利息…）")),
            FreedomCheckItem(
                id: 6, title: String(localized: "被动收入覆盖全部开销"), shortTitle: String(localized: "被动覆盖 100%"),
                done: passiveRatio >= 1.0,
                progress: min(1, passiveRatio),
                detail: String(localized: "当前 \(pct) / 100%"),
                hint: String(localized: "被动收入覆盖全部开销，就是财富自由")),
        ]

        let doneCount = items.filter(\.done).count
        // 下一站：清单里第一个没达成的；是自由天数那几级时再写还差几天
        let next = items.first { !$0.done }
        var remainText: String?
        if let next, next.id <= freedomMilestones.count, let finiteFreedom,
           let fInt = FinancialFormatting.integer(finiteFreedom.rounded(.down)) {
            remainText = String(localized: "还差 \(freedomMilestones[next.id - 1] - fInt) 天")
        }

        let dataNote: String?
        if !snapshot.hasExpenses {
            dataNote = String(localized: "记下第一笔支出后开始判断")
        } else if snapshot.trackDays < FreedomMath.lumpSpreadDays {
            dataNote = String(localized: "再记录 \(FreedomMath.lumpSpreadDays - snapshot.trackDays) 天，日均趋势会更清晰")
        } else {
            dataNote = nil
        }

        return FreedomSummary(
            items: items,
            doneCount: doneCount,
            total: items.count,
            progress: Double(doneCount) / Double(items.count),
            nextStopTitle: next?.shortTitle,
            remainText: remainText,
            dataNote: dataNote)
    }

    /// 每月收入减开销为正。没填收入、记录也不够时还判断不了
    private static func savingItem(id: Int, saving: MonthlySaving?) -> FreedomCheckItem {
        let title = String(localized: "每月有结余")
        guard let saving else {
            return FreedomCheckItem(id: id, title: title, shortTitle: title, done: false, progress: nil, detail: "",
                                    hint: String(localized: "在上面的 GAP 里填上每月到手收入"))
        }
        let amount = FinancialFormatting.wholeNumber(abs(saving.perMonth))
        let done = saving.perDay > 0
        return FreedomCheckItem(
            id: id, title: title, shortTitle: title, done: done, progress: nil,
            detail: done ? String(localized: "每月约存 ¥\(amount)") : String(localized: "每月约多花 ¥\(amount)"),
            hint: String(localized: "提高收入或降低日均消费"))
    }
}
