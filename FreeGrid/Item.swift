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

    /// 分类:早餐/午餐/晚餐/购物/交通/娱乐/成长投资/医疗/人情/日用/其他
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
final class PassiveSource {
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
// MARK: - UserAssets (用户资产 - 单例)
// ============================================================================
// 对应 lead-wealth web 版 assets 对象
// 设计动机: assets.total 是戴维斯三杀 KILL 1 的基准,必须用户手动维护的"真实储蓄"
// 不是从 expenses/incomes 推算的——外部充值/转账系统不知道,只有用户自己知道
//
// 注: SwiftData 没有"单例 @Model"的官方支持,我们约定 UserAssets 全表只有 1 行
// 第一次启动或保存时如果不存在就 insert,后续永远更新这一行

@Model
final class UserAssets {
    /// 当前可变现资产总额(元)。存款 + 余额宝 + 货币基金等"随时能用的钱"
    var total: Double = 0

    /// 上次更新时间。展示 "上次更新: 5 分钟前" 用
    var updatedAt: Date = Date.now

    /// 首次记账日期。用来算 trackDays = 今天 - firstRecordDate
    /// 如果用户从来没记过账,这个字段是 nil,dailyBurn 计算时返回 0
    var firstRecordDate: Date?

    init(total: Double = 0, firstRecordDate: Date? = nil) {
        self.total = total
        self.updatedAt = .now
        self.firstRecordDate = firstRecordDate
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

    /// 自由天数 = (资产 + max(净储蓄, 0)) ÷ 日均消费
    /// 设计动机: 净储蓄为负不算(透支不能让你更自由),取 max(0, _)。
    /// 没记账时返回 ∞ (没有消费数据,自由是无限的)。
    /// 对应 web 版的 getFreedomDays()
    static func freedomDays(assets: Double, netSavings: Double, dailyBurn: Double) -> Double {
        guard dailyBurn > 0 else { return .infinity }
        let assetDays = max(0, assets) / dailyBurn   // 负资产不算,防止 Freedom Days 负数
        let incomeDays = max(0, netSavings) / dailyBurn
        return assetDays + incomeDays
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

    /// 网格状态:档位 + 应绘格数 + 资产/收入分配(双色阶段使用)
    struct GridState {
        /// 当前档位
        let unit: GridUnit
        /// 该绘制多少格(按 unit 颗粒度)
        let count: Int
        /// 资产对应的"天"数 (raw, 双色阶段使用)
        let blueDays: Int
        /// 收入对应的"天"数 (raw, 双色阶段使用)
        let yellowDays: Int
        /// 是否超过年档上限(99 年)
        let isOverflow: Bool
    }

    /// 根据当前财务状态,计算 grid 档位 + 应绘格数
    static func gridState(assets: Double, netSavings: Double, dailyBurn: Double) -> GridState {
        // 没记账时:零格(归入 day 档,展示 emptyGridHint)
        guard dailyBurn > 0 else {
            return GridState(unit: .day, count: 0, blueDays: 0, yellowDays: 0, isOverflow: false)
        }

        // 资产 / 净储蓄能撑的天数。负数(透支)= 0
        let assetRaw = max(0, assets / dailyBurn)
        let incomeRaw = max(0, netSavings / dailyBurn)
        let totalDays = assetRaw + incomeRaw

        // ∞ 兜底:dailyBurn 上面已经 guard,但 assets 极大时浮点除可能溢出
        guard totalDays.isFinite else {
            return GridState(unit: .year, count: 99, blueDays: 99 * 365,
                             yellowDays: 0, isOverflow: true)
        }

        // 资产/收入按天颗粒度分配(future 双色用)
        let assetDays = Int(assetRaw)
        let incomeDays = Int(incomeRaw)

        // 决定档位 + 格数
        let unit: GridUnit
        let count: Int
        let isOverflow: Bool

        if totalDays < 365 {
            unit = .day
            count = Int(totalDays)
            isOverflow = false
        } else if totalDays < 3650 {
            unit = .month
            // 30.44 ≈ 平均月长 (365.25 / 12),让月数 = 12 时正好对应 1 年
            count = min(Int(totalDays / 30.44), GridUnit.month.maxCells)
            isOverflow = false
        } else {
            unit = .year
            // 365.25 ≈ 平均年长,处理闰年
            let years = Int(totalDays / 365.25)
            count = min(years, GridUnit.year.maxCells)
            isOverflow = years > GridUnit.year.maxCells
        }

        return GridState(unit: unit, count: count,
                         blueDays: assetDays, yellowDays: incomeDays,
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
    /// - weeks: 取多少个 weekly snapshot (默认 12)
    /// - 返回时间升序(老的在前,新的在后),最后一个是今天
    static func freedomDaysHistory(
        expenses: [Expense],
        incomes: [Income],
        currentAssets: Double,
        firstRecordDate: Date?,
        weeks: Int = 12
    ) -> [HistoryPoint] {
        guard let firstDate = firstRecordDate else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let trackedDays = cal.dateComponents([.day], from: firstDate, to: today).day ?? 0
        guard trackedDays >= 14 else { return [] }   // < 2 周数据,不画

        // 决定要回看多少周
        let availableWeeks = min(weeks, trackedDays / 7)
        var snapshots: [HistoryPoint] = []

        for i in (0...availableWeeks).reversed() {
            guard let weekEnd = cal.date(byAdding: .day, value: -7 * i, to: today) else { continue }
            if weekEnd < firstDate { continue }

            let trackDays_i = max(1, cal.dateComponents([.day], from: firstDate, to: weekEnd).day ?? 1)

            let expUntil = expenses.filter { $0.date <= weekEnd }.reduce(0) { $0 + $1.amount }
            let incUntil = incomes.filter { $0.date <= weekEnd }.reduce(0) { $0 + $1.amount }
            let netSavings_i = incUntil - expUntil
            let dailyBurn_i = expUntil / Double(trackDays_i)

            // 反推那时的 assets:
            // assets_i = currentAssets + (expensesAfter_i - incomesAfter_i)
            // 因为 expensesAfter 都从 assets 扣了 → assets_i 当时更多
            let expAfter = expenses.filter { $0.date > weekEnd }.reduce(0) { $0 + $1.amount }
            let incAfter = incomes.filter { $0.date > weekEnd }.reduce(0) { $0 + $1.amount }
            let assets_i = currentAssets + expAfter - incAfter

            let days_i: Double
            if dailyBurn_i > 0 {
                days_i = max(0, assets_i) / dailyBurn_i + max(0, netSavings_i) / dailyBurn_i
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


