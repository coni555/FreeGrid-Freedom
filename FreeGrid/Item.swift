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

    /// 自由天数格式化:∞ 或具体整数
    static func freedomDaysDisplay(_ value: Double) -> String {
        if value.isInfinite { return "∞" }
        return String(format: "%.0f", value)
    }

    // ============================================================================
    // MARK: - 1825 格生命网格
    // ============================================================================
    // 设计动机: 把"自由天数"这个抽象数字,可视化为格子。
    // 5 年 = 1825 天 = 1825 格(产品上限),每格 1 天自由。
    // 蓝格 = 资产能撑的天数;金格 = 净储蓄能撑的天数(在蓝格之后).
    // 对应 lead-wealth web 版的 getGridState() + renderFreedomGrid()

    /// 1825 格的上限(5 年 × 365 天)
    static let maxGridCells = 1825

    /// 网格状态:多少蓝格、多少金格、是否溢出 1825
    struct GridState {
        /// 蓝格数:资产能撑天数
        let blueDays: Int
        /// 金格数:净储蓄能撑天数(在蓝格之后绘制)
        let yellowDays: Int
        /// 总点亮格数 = blueDays + yellowDays,封顶 1825
        let totalLit: Int
        /// 是否超出 5 年上限(用于提示"已超 1825,不再增加")
        let isOverflow: Bool
    }

    /// 根据当前财务状态,计算应该亮多少格
    /// 对应 web 版的 getGridState()
    static func gridState(assets: Double, netSavings: Double, dailyBurn: Double) -> GridState {
        // 没记账时:零格
        guard dailyBurn > 0 else {
            return GridState(blueDays: 0, yellowDays: 0, totalLit: 0, isOverflow: false)
        }

        // 资产能撑的天数。资产为负数 = 0 格(透支不算自由)
        let rawAsset = max(0, assets / dailyBurn)
        let assetDays = rawAsset.isInfinite ? maxGridCells : Int(rawAsset)

        // 净储蓄能撑的天数。负数(透支)= 0 格
        let incomeDays = max(0, Int(netSavings / dailyBurn))

        let rawTotal = assetDays + incomeDays
        let totalLit = min(rawTotal, maxGridCells)
        let blueDays = min(assetDays, totalLit)
        let yellowDays = totalLit - blueDays

        return GridState(blueDays: blueDays, yellowDays: yellowDays,
                         totalLit: totalLit, isOverflow: rawTotal > maxGridCells)
    }
}


