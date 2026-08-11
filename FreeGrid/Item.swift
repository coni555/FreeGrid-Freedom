//
//  Item.swift
//  FreeGrid
//
//  数据模型层:早期 web 版 5 个核心 SwiftData 模型。
//  原 Xcode 模板自带的 Item 类已删除,替换为业务实体。
//
//  设计原则:
//  - 字段都给默认值(为以后接 CloudKit 留兼容空间)
//  - 不用 @Attribute(.unique),CloudKit 兼容
//  - 关系字段(目前没有)未来用 optional
//

import Foundation
import SwiftData

// ============================================================================
// MARK: - Expense (支出)
// ============================================================================
// 对应 早期 web 版 expenses 数组里的每条记录
// 关键字段: amount + category + date,其他可选

@Model
final class Expense {
    /// 唯一标识符。SwiftData 自带 PersistentIdentifier,但我们额外存 UUID 方便同步合并
    var id: UUID = UUID()

    /// 金额(元),正数
    var amount: Double = 0

    /// 分类:早餐/午餐/晚餐/购物/交通/娱乐/成长投资/医疗/其他
    /// 注:用 String 而不是 enum,方便未来用户自定义分类
    var category: String = ""

    /// 备注,可空
    var note: String = ""

    /// 消费日期(用户填的"什么时候花的")
    var date: Date = Date.now

    /// 记录时间(实际点保存按钮的时刻),用于审计
    var createdAt: Date = Date.now

    init(amount: Double, category: String, note: String = "", date: Date = .now) {
        self.id = UUID()
        self.amount = amount
        self.category = category
        self.note = note
        self.date = date
        self.createdAt = .now
    }
}

// ============================================================================
// MARK: - Income (收入)
// ============================================================================
// 对应 早期 web 版 incomes 数组
// isPassive 字段决定这笔收入是否纳入"被动收入源"统计

@Model
final class Income {
    var id: UUID = UUID()

    var amount: Double = 0

    /// 来源:工资/投资/副业...(用户自由填)
    var source: String = ""

    /// 是否被动收入。设计动机: 区分"主动赚的"和"睡后收入"
    /// 被动覆盖率 = 日均被动收入 ÷ 日均消费,≥1 即财务自由
    var isPassive: Bool = false

    var note: String = ""
    var date: Date = Date.now
    var createdAt: Date = Date.now

    init(amount: Double, source: String, isPassive: Bool = false, note: String = "", date: Date = .now) {
        self.id = UUID()
        self.amount = amount
        self.source = source
        self.isPassive = isPassive
        self.note = note
        self.date = date
        self.createdAt = .now
    }
}

// ============================================================================
// MARK: - Device (持有物 / 设备)
// ============================================================================
// 对应 早期 web 版 devices 数组
// 核心用途: 算"日均使用成本",看一件物品到底每天花你多少钱
// 注意: 设备账独立于会计层,不影响 daily burn / assets

@Model
final class Device {
    var id: UUID = UUID()

    var name: String = ""

    /// 分类:数码/家电/家具/服饰/工具/交通/其他
    var category: String = "数码"

    /// 购买价格(元)
    var price: Double = 0

    /// 购买日期。日均成本 = price ÷ (今天 − purchaseDate) 天数
    var purchaseDate: Date = Date.now

    /// 状态:active / retired / sold
    /// MVP 阶段只用 active,sold 字段先留着不实现
    var status: String = "active"

    /// 卖出价格(可空,只有 status=sold 时有意义)
    var soldPrice: Double?

    /// 卖出日期
    var soldDate: Date?

    var note: String = ""
    var createdAt: Date = Date.now

    init(name: String, category: String, price: Double, purchaseDate: Date, note: String = "") {
        self.id = UUID()
        self.name = name
        self.category = category
        self.price = price
        self.purchaseDate = purchaseDate
        self.status = "active"
        self.note = note
        self.createdAt = .now
    }
}

// ============================================================================
// MARK: - PassiveSource (被动收入源)
// ============================================================================
// 对应 早期 web 版 passive_sources 数组
// 例: 房租收入 / 股息 / 版税 / 利息 / 副业稳定流水

@Model
final class PassiveSource: Identifiable {
    var id: UUID = UUID()

    var name: String = ""

    /// 月均收入(元/月)。日均换算: monthlyAmount ÷ 30
    var monthlyAmount: Double = 0

    var createdAt: Date = Date.now

    init(name: String, monthlyAmount: Double) {
        self.id = UUID()
        self.name = name
        self.monthlyAmount = monthlyAmount
        self.createdAt = .now
    }
}

// ============================================================================
// MARK: - UserAssets (用户净值 - 单例)
// ============================================================================
// 净值 = 资产(锁定/投资) + 现金(可花)
// 收入默认进现金,用户可在 AssetsView 手动调拨到资产
// 支出从现金扣
//
// 注: SwiftData 没有"单例 @Model"的官方支持,我们约定 UserAssets 全表只有 1 行

@Model
final class UserAssets {
    // legacy — 保留给 CloudKit 轻量迁移,新逻辑不读写
    var total: Double = 0

    /// 锁定资产(投资/定期):蓝色格子
    var lockedAssets: Double = 0

    /// 可花现金:金色格子
    var cash: Double = 0

    /// 净值 = 资产 + 现金 (计算属性)
    var netWorth: Double { lockedAssets + cash }

    var updatedAt: Date = Date.now
    var firstRecordDate: Date?

    init(total: Double = 0, firstRecordDate: Date? = nil) {
        self.total = total
        self.updatedAt = .now
        self.firstRecordDate = firstRecordDate
    }
}

enum FreedomState: Equatable {
    case insufficientData
    case covered
    case finite(days: Double)
    case invalidData
}

// ============================================================================
// MARK: - FreedomMath (业务计算工具集)
// ============================================================================
// 设计动机:把 早期 web 版的核心算法抽出来,供多个 View 共用,避免复制粘贴。
// 全部用 static func,无状态,便于测试 + 在 sheet 预览里也能调用。
// 命名故意和 早期 web 版的函数名保持一致(getDailyBurn / getFreedomDays 等),
// 方便对照 web 版理解逻辑。

enum FreedomMath {

    // ===== 基础计量 =====

    /// 最早支出日期是追踪基线；收入和资产录入不启动自由天数计算。
    static func earliestExpenseDate(_ expenses: [Expense]) -> Date? {
        expenses.map(\.date).min()
    }

    /// 记录天数 = 今天 − 最早支出日期 + 1。没有支出或基线在未来时返回 0。
    static func trackDays(firstRecordDate: Date?, now: Date = .now) -> Int {
        guard let firstDate = firstRecordDate else { return 0 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: firstDate)
        let end = calendar.startOfDay(for: now)
        guard let days = calendar.dateComponents([.day], from: start, to: end).day,
              days >= 0 else {
            return 0
        }
        return days + 1
    }

    /// 日均消费 = 总支出 ÷ 记录天数
    /// 对应 web 版的 getDailyBurn()
    static func dailyBurn(totalExpenses: Double, trackDays: Int) -> Double {
        guard totalExpenses.isFinite, totalExpenses >= 0, trackDays > 0 else { return .nan }
        return totalExpenses / Double(trackDays)
    }

    /// 日均被动收入 = Σ(月被动收入 ÷ 30)
    static func dailyPassive(sources: [PassiveSource]) -> Double {
        sources.reduce(0) { $0 + $1.monthlyAmount / 30 }
    }

    /// 被动覆盖率 = 日均被动 ÷ 日均消费(≥ 1.0 即财务自由)
    static func passiveRatio(dailyPassive: Double, dailyBurn: Double) -> Double {
        guard dailyPassive.isFinite, dailyPassive >= 0,
              dailyBurn.isFinite, dailyBurn > 0 else { return 0 }
        let ratio = dailyPassive / dailyBurn
        return ratio.isFinite ? ratio : 0
    }

    // ===== 核心: 自由天数 =====

    /// 自由天数 = 净值 / 净每日消耗
    /// 净每日消耗 = max(0, 日均消费 − 日均被动收入)
    ///
    /// 设计动机: 被动收入是"不工作也有的钱", 它的本质就是让你不必动用净值。
    /// 当被动覆盖率 ≥ 100%, 净值不被消耗 → 自由天数 = ∞ (永远自由)。
    /// 把被动收入排除在自由天数之外, 等于让"被动覆盖率"沦为装饰指标, 跟核心数字脱钩。
    /// dailyPassive 默认 0, 旧 callsite 无需改动即可保持原静态消耗行为(但应尽快传入)。
    static func freedomState(
        netWorth: Double,
        dailyBurn: Double,
        dailyPassive: Double = 0,
        hasExpenses: Bool
    ) -> FreedomState {
        guard hasExpenses else { return .insufficientData }
        guard netWorth.isFinite, dailyBurn.isFinite, dailyPassive.isFinite,
              dailyBurn >= 0, dailyPassive >= 0 else {
            return .invalidData
        }
        guard dailyBurn > 0 else { return .invalidData }
        guard dailyPassive < dailyBurn else { return .covered }

        let days = max(0, netWorth) / (dailyBurn - dailyPassive)
        guard days.isFinite else { return .invalidData }
        return .finite(days: days)
    }

    /// 仅供历史趋势和模拟中的有限数学使用；业务 UI 应优先读取 FreedomState。
    static func freedomDays(netWorth: Double, dailyBurn: Double, dailyPassive: Double = 0) -> Double {
        guard netWorth.isFinite, dailyBurn.isFinite, dailyPassive.isFinite,
              dailyBurn >= 0, dailyPassive >= 0 else { return .nan }
        let netBurn = max(0, dailyBurn - dailyPassive)
        guard netBurn > 0 else { return .infinity }
        let days = max(0, netWorth) / netBurn
        return days.isFinite ? days : .nan
    }

    /// 自由天数格式化:三档无后缀(单位由 hero KickerLabel 承载)
    static func freedomDaysDisplay(_ state: FreedomState) -> String {
        switch state {
        case .insufficientData, .invalidData:
            return "—"
        case .covered:
            return "∞"
        case .finite(let days):
            return freedomDaysDisplay(days)
        }
    }

    static func freedomDaysDisplay(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return value.isInfinite ? "∞" : "—" }
        if value < 365 {
            return FinancialFormatting.wholeNumber(value.rounded(.down))
        }
        if value < 3650 {
            return FinancialFormatting.wholeNumber((value / 30.44).rounded(.down))
        }
        return String(format: "%.1f", value / 365.25)
    }

    /// 自由天数档位枚举 — sheet 里 from/to/delta 需要强制对齐到同一档位时用
    enum FreedomUnit { case day, month, year }

    /// 按 value 自身大小决定档位(三档规则跟 freedomDaysDisplay 一致)
    static func freedomDaysUnit(_ value: Double) -> FreedomUnit {
        if value.isInfinite || value.isNaN { return .day }
        if value < 365 { return .day }
        if value < 3650 { return .month }
        return .year
    }

    /// 按指定档位格式化(给 sheet 里 to/delta 用,把它们对齐到 from 的档位)
    /// delta 用 abs 值,符号由调用方加
    static func freedomDaysFormatted(_ value: Double, unit: FreedomUnit) -> String {
        if value.isInfinite { return "∞" }
        guard value.isFinite, value >= 0 else { return "—" }
        switch unit {
        case .day:   return String(format: "%.0f", value)
        case .month: return String(format: "%.0f", value / 30.44)
        case .year:  return String(format: "%.1f", value / 365.25)
        }
    }

    /// 档位的中文单位标签
    static func freedomUnitLabel(_ unit: FreedomUnit) -> String {
        switch unit {
        case .day: return "天"
        case .month: return "月"
        case .year: return "年"
        }
    }

    // ============================================================================
    // MARK: - 生命网格(自适应单位:日/月/年)
    // ============================================================================
    // 设计动机: 把"自由天数"这个抽象数字,可视化为格子。
    // 颗粒度随自由度自适应升级——
    //   < 1 年 (< 365 天):   日格 (每格 1 天, 最多 365)
    //   1-10 年 (365-3649): 月格 (每格 1 月, 最多 120 = 10 年)
    //   ≥ 10 年 (≥ 3650):   年格 (每格 1 年, 最多 99)
    // 跟 hero 数字单位切换同步,UI 在数字 + grid 两层一起做维度提升。

    /// Grid 颗粒度档位
    enum GridUnit: Equatable {
        case day, month, year

        /// 每格视觉尺寸 (pt)
        var cellSize: CGFloat {
            switch self {
            case .day: return 9
            case .month: return 12
            case .year: return 16
            }
        }

        /// 格子间距 (pt) — 跟随 cellSize 比例
        var spacing: CGFloat {
            switch self {
            case .day: return 2.5
            case .month: return 3
            case .year: return 3.5
            }
        }

        /// 单档上限(超过即升档,或在年档 cap 99)
        var maxCells: Int {
            switch self {
            case .day: return 365
            case .month: return 120     // 10 年
            case .year: return 99
            }
        }

        /// 中文单位标签
        var label: String {
            switch self {
            case .day: return "天"
            case .month: return "月"
            case .year: return "年"
            }
        }
    }

    struct GridState {
        let unit: GridUnit
        let count: Int
        /// 蓝色格子数(锁定资产)
        let blueDays: Int
        /// 金色格子数(现金)
        let yellowDays: Int
        let isOverflow: Bool
    }

    /// 根据当前财务状态,计算 grid 档位 + 应绘格数 + 双色分配
    /// dailyPassive: 日均被动收入。被动覆盖率 ≥ 100% 时净每日消耗为 0, grid 上限化(年档 99 满格)
    static func gridState(lockedAssets: Double, cash: Double, dailyBurn: Double, dailyPassive: Double = 0) -> GridState {
        guard lockedAssets.isFinite, cash.isFinite, dailyBurn.isFinite, dailyPassive.isFinite,
              dailyBurn > 0, dailyPassive >= 0 else {
            return GridState(unit: .day, count: 0, blueDays: 0, yellowDays: 0, isOverflow: false)
        }

        let netWorth = max(0, lockedAssets + cash)
        let netBurn = max(0, dailyBurn - dailyPassive)

        if netBurn == 0 {
            let count = GridUnit.year.maxCells
            let split = FinancialFormatting.assetCellSplit(
                count: count,
                lockedAssets: lockedAssets,
                netWorth: netWorth
            )
            return GridState(
                unit: .year,
                count: count,
                blueDays: split.blue,
                yellowDays: split.gold,
                isOverflow: true
            )
        }

        let totalDays = netWorth / netBurn
        guard totalDays.isFinite, totalDays >= 0 else {
            return GridState(unit: .day, count: 0, blueDays: 0, yellowDays: 0, isOverflow: false)
        }

        let unit: GridUnit
        let count: Int
        let isOverflow: Bool
        if totalDays < 365 {
            unit = .day
            count = FinancialFormatting.gridCount(days: totalDays, divisor: 1, maximum: unit.maxCells)
            isOverflow = false
        } else if totalDays < 3650 {
            unit = .month
            count = FinancialFormatting.gridCount(days: totalDays, divisor: 30.44, maximum: unit.maxCells)
            isOverflow = false
        } else {
            unit = .year
            count = FinancialFormatting.gridCount(days: totalDays, divisor: 365.25, maximum: unit.maxCells)
            isOverflow = totalDays / 365.25 > Double(unit.maxCells)
        }

        let split = FinancialFormatting.assetCellSplit(
            count: count,
            lockedAssets: lockedAssets,
            netWorth: netWorth
        )
        return GridState(
            unit: unit,
            count: count,
            blueDays: split.blue,
            yellowDays: split.gold,
            isOverflow: isOverflow
        )
    }

    // ============================================================================
    // MARK: - 历史趋势 (sparkline + delta + 见底日期)
    // ============================================================================
    // 设计动机: hero card 里展示"过去 12 周自由天数走势"——一条 sparkline +
    // delta badge (▲ +22d) + 见底日期。让用户看到自己是在"赎回自由"
    // 还是"消耗自由",而不只看今天的数字。
    //
    // 数据反推:
    // - 当前没有存 freedomDays 的历史 snapshot。
    // - 反向计算: 取每周末日期,反推那时的 expenses / incomes / assets
    //   (assets 用 current + 后续 net 变动反推, 假设 dataset 完整且 user
    //    没手动调过 assets baseline——足够 sparkline 视觉趋势准确)
    //
    // 边界:
    // - 如果 trackDays < 14 天,数据不够,返回空
    // - 如果 trackDays 在 14~84 天之间,返回 trackDays/7 个点
    // - 如果 ≥ 84 天 (12 周),返回 12 个点

    /// 单个历史 snapshot
    struct HistoryPoint {
        let date: Date
        let freedomDays: Double
    }

    /// 反推过去 N 周末日的 freedomDays
    /// currentNetWorth = lockedAssets + cash
    /// dailyPassive: 当前被动收入日均。历史快照都用当前值近似 — PassiveSource 没存历史
    /// 时间戳, 简化模型 "假设当时也有这些被动"。被动覆盖时 sparkline 都会显示 0 或满,
    /// 反而把"净值是否在涨"暴露得更直观。
    static func freedomDaysHistory(
        expenses: [Expense],
        incomes: [Income],
        currentNetWorth: Double,
        firstRecordDate: Date?,
        dailyPassive: Double = 0,
        weeks: Int = 12
    ) -> [HistoryPoint] {
        guard let firstDate = firstRecordDate,
              currentNetWorth.isFinite,
              dailyPassive.isFinite,
              dailyPassive >= 0,
              // 只挡非有限数。旧账本的退款/冲正是合法负数支出(schema v3 会原样承接),
              // 用 >= 0 挡会让这类用户的走势图整块消失,而不是显示净额趋势。
              expenses.allSatisfy({ $0.amount.isFinite }),
              incomes.allSatisfy({ $0.amount.isFinite }) else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let trackedDays = cal.dateComponents([.day], from: firstDate, to: today).day ?? 0
        guard trackedDays >= 14 else { return [] }

        let availableWeeks = min(weeks, trackedDays / 7)
        var snapshots: [HistoryPoint] = []

        for i in (0...availableWeeks).reversed() {
            guard let weekEnd = cal.date(byAdding: .day, value: -7 * i, to: today) else { continue }
            if weekEnd < firstDate { continue }

            // +1 跟 Hero 的 trackDays(today − first + 1)同口径 —— 含端点当天,
            // 否则分母少 1 天、dailyBurn 微高, sparkline 终点会比 Hero 大数字少 1。
            let trackDays_i = max(1, (cal.dateComponents([.day], from: firstDate, to: weekEnd).day ?? 1) + 1)

            // 关键:交易按"自然日"归属, 不看具体时间戳。
            // weekEnd 是某天的 00:00;若用裸 date 比较, 当天白天发生的交易(时间戳 > 00:00)
            // 会被误判成"weekEnd 之后", 在终点(weekEnd = 今天)那步, 今天到账的收入被当成
            // "今天之后"从 incAfter 减掉 → 终点净值塌陷, sparkline 终点 ≠ Hero 大数字。
            // 用 startOfDay 比较, 把"今天"完整算进 expUntil/此刻净值, 终点就跟 Hero 对齐。
            let dayOf: (Date) -> Date = { cal.startOfDay(for: $0) }
            let expUntil = expenses.filter { dayOf($0.date) <= weekEnd }.reduce(0) { $0 + $1.amount }
            let dailyBurn_i = expUntil / Double(trackDays_i)

            // 反推那时的净值 = 当前净值 + 之后支出 - 之后收入(均按自然日)
            let expAfter = expenses.filter { dayOf($0.date) > weekEnd }.reduce(0) { $0 + $1.amount }
            let incAfter = incomes.filter { dayOf($0.date) > weekEnd }.reduce(0) { $0 + $1.amount }
            let netWorth_i = currentNetWorth + expAfter - incAfter

            let netBurn_i = max(0, dailyBurn_i - dailyPassive)
            let days_i: Double
            if netBurn_i > 0 {
                days_i = max(0, netWorth_i) / netBurn_i
            } else if dailyBurn_i > 0 {
                // 被动覆盖, 显示 cap 数字让 sparkline 不爆掉(用 1825 = 5 年作 upper bound)
                days_i = 1825
            } else {
                days_i = 0
            }

            snapshots.append(HistoryPoint(date: weekEnd, freedomDays: days_i))
        }

        return snapshots
    }

    /// 给定 history,算 12-week-ago vs 当前的 delta
    /// 返回 (起点天数, 终点天数, delta 天数)
    static func deltaSummary(history: [HistoryPoint]) -> (start: Int, end: Int, delta: Int)? {
        guard let first = history.first, let last = history.last,
              history.count >= 2 else { return nil }
        // 向下取整, 跟 Hero freedomDaysDisplay / Grid 一致(避免 sparkline 起终点又四舍五入裂开)
        guard let s = FinancialFormatting.integer(first.freedomDays.rounded(.down)),
              let e = FinancialFormatting.integer(last.freedomDays.rounded(.down)) else {
            return nil
        }
        return (s, e, e - s)
    }

    /// 当前自由耗尽的预计日期 (今天 + freedomDays 天)
    /// 返回 nil 表示 ∞ 或没数据
    static func depleteDate(freedomDays: Double) -> Date? {
        guard freedomDays.isFinite, freedomDays > 0, freedomDays < 1825 * 5,
              let days = FinancialFormatting.integer(
                freedomDays,
                rounded: .toNearestOrAwayFromZero
              ) else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: .now)
    }
}

// ============================================================================
// MARK: - FreedomChecklist (财富自由自检 — 8 项评估器)
// ============================================================================
// 设计动机: collapsed 自检卡(Settings 顶部)和完整自检子页两处共用同一套评估,
// 避免重复推导。阈值与顺序完全沿用早期 web 版 / 原 CheckView.items。
// 全部从已有记录自动反推, 不需手动勾选。

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
        let firstDate = FreedomMath.earliestExpenseDate(expenses)
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)
        let totalExp = expenses.reduce(0) { $0 + $1.amount }
        let dailyBurn = FreedomMath.dailyBurn(totalExpenses: totalExp, trackDays: days)
        let netWorth = (assets?.lockedAssets ?? 0) + (assets?.cash ?? 0)
        let dailyPassive = FreedomMath.dailyPassive(sources: passiveSources)
        let passiveRatio = FreedomMath.passiveRatio(dailyPassive: dailyPassive, dailyBurn: dailyBurn)
        let freedomState = FreedomMath.freedomState(
            netWorth: netWorth,
            dailyBurn: dailyBurn,
            dailyPassive: dailyPassive,
            hasExpenses: !expenses.isEmpty
        )
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
        let fShow = FreedomMath.freedomDaysDisplay(freedomState)
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


