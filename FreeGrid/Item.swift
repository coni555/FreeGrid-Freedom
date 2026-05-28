//
//  Item.swift
//  FreeGrid
//
//  数据模型层:lead-wealth 5 个核心 SwiftData 模型。
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
// 对应 lead-wealth web 版 expenses 数组里的每条记录
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
// 对应 lead-wealth web 版 incomes 数组
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
// 对应 lead-wealth web 版 devices 数组
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
// 对应 lead-wealth web 版 passive_sources 数组
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

    /// 首次启动升级: total → cash 一次性迁移
    func migrateIfNeeded() {
        if lockedAssets == 0 && cash == 0 && total > 0 {
            cash = total
        }
    }
}

// ============================================================================
// MARK: - FreedomMath (业务计算工具集)
// ============================================================================
// 设计动机:把 lead-wealth 的核心算法抽出来,供多个 View 共用,避免复制粘贴。
// 全部用 static func,无状态,便于测试 + 在 sheet 预览里也能调用。
// 命名故意和 lead-wealth web 版的函数名保持一致(getDailyBurn / getFreedomDays 等),
// 方便对照 web 版理解逻辑。

enum FreedomMath {

    // ===== 基础计量 =====

    /// 记录天数 = 今天 − firstRecordDate (最小 1)
    /// 没记过账时返回 1,避免后续除零
    static func trackDays(firstRecordDate: Date?) -> Int {
        guard let firstDate = firstRecordDate else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: firstDate, to: .now).day ?? 0
        return max(1, days + 1)  // +1 因为"今天也算一天"
    }

    /// 日均消费 = 总支出 ÷ 记录天数
    /// 对应 web 版的 getDailyBurn()
    static func dailyBurn(totalExpenses: Double, trackDays: Int) -> Double {
        guard trackDays > 0 else { return 0 }
        return totalExpenses / Double(trackDays)
    }

    /// 日均被动收入 = Σ(月被动收入 ÷ 30)
    static func dailyPassive(sources: [PassiveSource]) -> Double {
        sources.reduce(0) { $0 + $1.monthlyAmount / 30 }
    }

    /// 被动覆盖率 = 日均被动 ÷ 日均消费(≥ 1.0 即财务自由)
    static func passiveRatio(dailyPassive: Double, dailyBurn: Double) -> Double {
        guard dailyBurn > 0 else { return 0 }
        return dailyPassive / dailyBurn
    }

    // ===== 核心: 自由天数 =====

    /// 自由天数 = 净值 / 净每日消耗
    /// 净每日消耗 = max(0, 日均消费 − 日均被动收入)
    ///
    /// 设计动机: 被动收入是"不工作也有的钱", 它的本质就是让你不必动用净值。
    /// 当被动覆盖率 ≥ 100%, 净值不被消耗 → 自由天数 = ∞ (永远自由)。
    /// 把被动收入排除在自由天数之外, 等于让"被动覆盖率"沦为装饰指标, 跟核心数字脱钩。
    /// dailyPassive 默认 0, 旧 callsite 无需改动即可保持原静态消耗行为(但应尽快传入)。
    static func freedomDays(netWorth: Double, dailyBurn: Double, dailyPassive: Double = 0) -> Double {
        let netBurn = max(0, dailyBurn - dailyPassive)
        guard netBurn > 0 else { return .infinity }
        return max(0, netWorth) / netBurn
    }

    /// 自由天数格式化:三档无后缀(单位由 hero KickerLabel 承载)
    /// < 365 天    → 天数整数 "127"
    /// 365-3649 天 → 月数整数 "16" (= days / 30.44)
    /// ≥ 3650 天   → 年数 1 位小数 "38.1" (= days / 365.25)
    /// ∞ / NaN     → "∞"
    static func freedomDaysDisplay(_ value: Double) -> String {
        if value.isInfinite || value.isNaN { return "∞" }
        if value < 365 {
            return String(format: "%.0f", value)
        }
        if value < 3650 {
            return String(format: "%.0f", value / 30.44)
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
        if value.isInfinite || value.isNaN { return "∞" }
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
    enum GridUnit {
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
        guard dailyBurn > 0 else {
            return GridState(unit: .day, count: 0, blueDays: 0, yellowDays: 0, isOverflow: false)
        }

        let netWorth = max(0, lockedAssets) + max(0, cash)
        let netBurn = max(0, dailyBurn - dailyPassive)

        // 被动完全覆盖 (净每日消耗 = 0) → 年档满格 (永远自由)
        guard netBurn > 0 else {
            return GridState(unit: .year, count: 99, blueDays: 99 * 365,
                             yellowDays: 0, isOverflow: true)
        }

        let totalDays = netWorth / netBurn

        guard totalDays.isFinite else {
            return GridState(unit: .year, count: 99, blueDays: 99 * 365,
                             yellowDays: 0, isOverflow: true)
        }

        let unit: GridUnit
        let count: Int
        let isOverflow: Bool

        if totalDays < 365 {
            unit = .day
            count = Int(totalDays)
            isOverflow = false
        } else if totalDays < 3650 {
            unit = .month
            count = min(Int(totalDays / 30.44), GridUnit.month.maxCells)
            isOverflow = false
        } else {
            unit = .year
            let years = Int(totalDays / 365.25)
            count = min(years, GridUnit.year.maxCells)
            isOverflow = years > GridUnit.year.maxCells
        }

        // 双色分配: 蓝(资产)在前, 金(现金)在后
        let blueCells: Int
        let goldCells: Int
        if netWorth > 0 {
            blueCells = Int((Double(count) * max(0, lockedAssets) / netWorth).rounded())
            goldCells = count - blueCells
        } else {
            blueCells = 0
            goldCells = 0
        }

        return GridState(unit: unit, count: count,
                         blueDays: blueCells, yellowDays: goldCells,
                         isOverflow: isOverflow)
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
        guard let firstDate = firstRecordDate else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let trackedDays = cal.dateComponents([.day], from: firstDate, to: today).day ?? 0
        guard trackedDays >= 14 else { return [] }

        let availableWeeks = min(weeks, trackedDays / 7)
        var snapshots: [HistoryPoint] = []

        for i in (0...availableWeeks).reversed() {
            guard let weekEnd = cal.date(byAdding: .day, value: -7 * i, to: today) else { continue }
            if weekEnd < firstDate { continue }

            let trackDays_i = max(1, cal.dateComponents([.day], from: firstDate, to: weekEnd).day ?? 1)

            let expUntil = expenses.filter { $0.date <= weekEnd }.reduce(0) { $0 + $1.amount }
            let dailyBurn_i = expUntil / Double(trackDays_i)

            // 反推那时的净值 = 当前净值 + 之后支出 - 之后收入
            let expAfter = expenses.filter { $0.date > weekEnd }.reduce(0) { $0 + $1.amount }
            let incAfter = incomes.filter { $0.date > weekEnd }.reduce(0) { $0 + $1.amount }
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
        let s = Int(first.freedomDays.rounded())
        let e = Int(last.freedomDays.rounded())
        return (s, e, e - s)
    }

    /// 当前自由耗尽的预计日期 (今天 + freedomDays 天)
    /// 返回 nil 表示 ∞ 或没数据
    static func depleteDate(freedomDays: Double) -> Date? {
        guard !freedomDays.isInfinite, freedomDays > 0, freedomDays < 1825 * 5 else { return nil }
        let days = Int(freedomDays.rounded())
        return Calendar.current.date(byAdding: .day, value: days, to: .now)
    }
}


