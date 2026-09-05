// SwiftData 持久化模型。字段和类型名保持稳定，以兼容已有账本。

import Foundation
import SwiftData

@Model
final class Expense {
    /// 备份和去重使用的记录 ID，与 SwiftData 内部标识分开
    var id: UUID = UUID()

    /// 金额(元)。手动新增为正数；旧备份可能含退款负数和零元记录。
    var amount: Double = 0

    /// 分类:早餐/午餐/晚餐/购物/交通/娱乐/成长投资/医疗/其他
    /// 以 String 保存以兼容历史分类；新录入与导入映射使用 ExpenseCategory。
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
// 被动覆盖率由 PassiveSource 计算，单笔收入只增加现金。

@Model
final class Income {
    var id: UUID = UUID()

    var amount: Double = 0

    /// 来源:工资/投资/副业...(用户自由填)
    var source: String = ""

    /// 保留历史备份字段；不参与当前被动覆盖率计算，新录入为 false。
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
// 当前无设备编辑页面；完整保留导入/导出中的设备信息。
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
    /// 三种状态都在备份校验和往返中保留。
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
    // 旧版总额字段：启动迁移时读取一次，随后使用双桶，保留字段兼容旧库。
    var total: Double = 0

    /// 锁定资产(投资/定期):金色格子
    var lockedAssets: Double = 0

    /// 可花现金:蓝色格子
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
