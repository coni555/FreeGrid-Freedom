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
    /// 以 String 保存以兼容历史和 Pro 自定义分类；不因选项删除而改写记录。
    var category: String = ""

    /// 备注,可空
    var note: String = ""

    /// 消费日期(用户填的"什么时候花的")
    var date: Date = Date.now

    /// 记录时间(实际点保存按钮的时刻),用于审计
    var createdAt: Date = Date.now

    /// Pro 每月还款：到期自动扣的那一期指向它的贷款。手动记的支出是 nil。
    var loanID: UUID?

    /// 算不算进日均消费。自动扣的月供，和用户确认过「以前记的月供」都是 false；
    /// 它们照样扣过现金、照样出现在 History，只是不拿来估日常开销。旧库升级后全部为 true。
    var countsInBurn: Bool = true

    /// Pro 现金账户：这笔从哪个账户扣的。没拆账户时是 nil；账户后来删了也留着，撤销时退回第一个账户。
    var cashAccountID: UUID?

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

    /// Pro 现金账户：这笔进了哪个账户。没拆账户时是 nil
    var cashAccountID: UUID?

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
// MARK: - AssetItem (Pro 资产逐项记录)
// ============================================================================
// 把资产桶拆成一项一项：房、车、定期、基金…
// 不变量：只要存在资产项，`UserAssets.lockedAssets` 就等于各项金额之和（见 `AssetItemStore`）。
// 所以免费版的计算、旧备份和旧版本都只认 `lockedAssets`，不需要知道这张表。

@Model
final class AssetItem: Identifiable {
    var id: UUID = UUID()

    /// 1–20 个字符
    var name: String = ""

    /// 金额(元)，≥ 0
    var amount: Double = 0

    /// 列表里的顺序，新增的排在最后。备份按它还原顺序
    var sortOrder: Int = 0

    /// 这一项算不算进自由天数（Pro 逐项开关）。默认算；房、车这种卖不掉的可以关掉。
    /// 只影响自由天数，不影响资产总数和净值。旧库里已有的项升级后取默认值，也就是计入。
    var countsInFreedom: Bool = true

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(name: String, amount: Double, sortOrder: Int, countsInFreedom: Bool = true) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.sortOrder = sortOrder
        self.countsInFreedom = countsInFreedom
        self.createdAt = .now
        self.updatedAt = .now
    }
}

// ============================================================================
// MARK: - CashAccount (Pro 现金账户)
// ============================================================================
// 把现金拆成微信、支付宝、银行卡……
// 不变量：只要存在现金账户，`UserAssets.cash` 就等于各账户余额之和（见 `CashAccountStore`）。
// 账户的先后就是扣款顺序：记支出时从上往下，整笔扣第一个够付的账户。
// 每个账户自己决定算不算进自由天数（和资产项一样），默认算。

@Model
final class CashAccount: Identifiable {
    var id: UUID = UUID()

    /// 1–20 个字符
    var name: String = ""

    /// 余额(元)。正常 ≥ 0；现金不够时记的支出可以把它扣成负数
    var amount: Double = 0

    /// 扣款顺序，0 是第一个
    var sortOrder: Int = 0

    /// 这个账户算不算进自由天数（Pro 逐项开关）。默认算；留着不打算动的储蓄卡可以关掉。
    /// 只影响自由天数，不影响现金总数和净值。旧库里已有的账户升级后取默认值，也就是计入。
    var countsInFreedom: Bool = true

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(name: String, amount: Double, sortOrder: Int, countsInFreedom: Bool = true) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.sortOrder = sortOrder
        self.countsInFreedom = countsInFreedom
        self.createdAt = .now
        self.updatedAt = .now
    }
}

// ============================================================================
// MARK: - Loan (固定支出与贷款)
// ============================================================================
// 隔一段时间固定付一次的钱。两种：
// - 固定支出（`isOngoing`）：房租、保险、订阅，没有尽头，可以每 1/2/3/6/12 个月一次。免费。
// - 贷款：房贷、车贷、分期，每月一次、还剩几期（Pro）。只有贷款在首页格子上打孔。
// 到期那天自动从现金扣（扣款是一笔 `loanID` 指向它的支出），
// 自由天数按日历往后推：每天扣日常开销，到期日再扣这笔钱（见 `LoanSchedule`）。
// 还了几期、还剩几期、哪期没扣成，都由扣款记录推出来，不另存计数。
// 类型名沿用最早的「Loan」，SwiftData 和备份都认这个名字。

@Model
final class Loan: Identifiable {
    var id: UUID = UUID()

    /// 1–20 个字符，例如「房贷」
    var name: String = ""

    /// 每期付多少(元)，> 0。字段名是贷款时代留下的；固定支出每 3 个月一次时，这里是 3 个月付的那一笔
    var monthlyAmount: Double = 0

    /// 几号付，1–31。当月没有这一天时按月底
    var dueDay: Int = 1

    /// 贷款：从 `startDate` 之后算起一共几期（后来扣掉的也算在内）。还剩几期 = 它 − 已经还了的。固定支出是 0
    var periodsAtStart: Int = 0

    /// 固定支出：一直有，没有期数。旧库和旧备份里的都是贷款，升级后为 false
    var isOngoing: Bool = false

    /// 隔几个月付一次：1、2、3、6、12。贷款恒为 1
    var intervalMonths: Int = 1

    /// 这一天及以前的到期日都不归它管。贷款是添加（或改了还款日、期数）那天的零点；
    /// 固定支出是用户填的「下次哪天付」的前一天，所以可能在未来，到期日从那天往后每隔 `intervalMonths` 个月一次
    var startDate: Date = Date.now

    /// 自动扣款已经处理到的最后一个到期日。在它之后的到期日还没尝试过
    var processedThrough: Date?

    /// 用户说「从别处还的」那几期的到期日：算已还，但没动现金
    var settledDates: [Date] = []

    /// Pro 现金账户：月供固定从哪个账户扣（比如房贷绑的那张卡）。nil = 按扣款顺序找第一个够付的
    var cashAccountID: UUID?

    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    init(name: String, monthlyAmount: Double, dueDay: Int, periodsAtStart: Int,
         startDate: Date, sortOrder: Int, isOngoing: Bool = false, intervalMonths: Int = 1) {
        self.id = UUID()
        self.name = name
        self.monthlyAmount = monthlyAmount
        self.dueDay = dueDay
        self.periodsAtStart = periodsAtStart
        self.isOngoing = isOngoing
        self.intervalMonths = intervalMonths
        self.startDate = startDate
        self.processedThrough = startDate
        self.settledDates = []
        self.sortOrder = sortOrder
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
