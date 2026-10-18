// 哪些功能属于 Pro。是否已解锁由 ProStore 根据 App Store 的购买记录决定。
import Foundation

enum ProFeatures {
    /// 从哪个功能进的购买页：对照表上那一行淡淡地标出来
    enum Topic {
        case categories, assets, cash, freedomSwitch, assetsView, loans, freedomCard
    }

    /// 对照表一格：打勾、横杠（没有）、或者一个短词
    enum Cell {
        case yes, no
        case text(String)
    }

    /// 一行旁边的 ⓘ：点开是一段说明。只给一眼看不懂的行
    struct Info: Equatable {
        let title: String
        let body: [String]
    }

    /// 购买页对照表的一行。前两行两边都有，告诉人免费版本来就够用；往下左边变少，右边一直是满的
    struct Row: Identifiable {
        let title: String
        let free: Cell
        let pro: Cell
        var topics: [Topic] = []
        var info: Info? = nil
        /// 老用户的 Pro 介绍里，这一行配的图标和一句卖点；两边都有的行不进介绍
        var symbol: String? = nil
        var pitch: String? = nil
        var id: String { title }
    }

    /// 只列已经做好的；新功能做完再加到这里。一屏放得下
    static let comparison: [Row] = [
        Row(title: "记账 · 固定支出 · 备份", free: .yes, pro: .yes),
        Row(title: "自由天数 · 格子 · 模拟", free: .yes, pro: .yes),
        Row(title: "支出分类", free: .text("默认九类"), pro: .text("随你定义"), topics: [.categories],
            symbol: "tag", pitch: "名字、图标和顺序，都由你来定。"),
        Row(title: "资产与现金", free: .text("一个总数"), pro: .text("拆成子账户"), topics: [.assets, .cash],
            symbol: "square.split.2x1", pitch: "银行卡、基金、支付宝，各记各的。"),
        // 免费版只有资产总开关（整体算或不算），现金总是算；Pro 每个资产项、每个现金账户自己决定
        Row(title: "计入自由天数", free: .text("资产整体选"), pro: .text("逐个选"), topics: [.freedomSwitch],
            info: Info(title: "按自己的方式算自由", body: [
                "不是每一笔钱都打算现在动用。",
                "资产和现金拆成子账户后，每一个都能单独选计不计入自由天数。",
                "日常花的钱照常计入；房子、车子、留给以后的储蓄可以不计入。",
                "不计入的仍在净值里，只是不进自由天数。新加的子账户默认计入。免费版只能整体选资产计不计入，现金总是计入。",
            ]),
            symbol: "checkmark.square", pitch: "每个账户，单独决定算不算进去。"),
        Row(title: "资产视图", free: .text("经典"), pro: .text("钱与时间"), topics: [.assetsView],
            symbol: "clock", pitch: "把金额换算成够日常花几天。"),
        // 给背着贷款的人：还款照常进行时，扣掉每期月供还剩多少自由天数（不是还清倒计时）
        Row(title: "贷款与分期", free: .no, pro: .text("按还款计划算"), topics: [.loans],
            info: Info(title: "有负债，也能看见自由", body: [
                "房贷、车贷，或是其他每月还款，都可以纳入自由天数测算。",
                "即使肩负还款责任，也能更清楚地了解自己的财务状况，以及当下真正拥有多少自由。",
            ]),
            symbol: "calendar", pitch: "背着房贷车贷，也看得见自由。"),
        Row(title: "自由卡", free: .text("查看"), pro: .text("导出分享"), topics: [.freedomCard],
            symbol: "creditcard", pitch: "把你的自由天数，做成一张卡。"),
    ]

    /// 设置页 Pro 卡头下面那一行，用户 2026-10-17 定的原话。不写价格（价格只在购买页出现）
    static let headline = "管理更细致，自由更清晰"

    static var canCustomizeExpenseCategories: Bool { ProStore.shared.isUnlocked }
    /// 增、删、改资产项。已经拆好的项不管有没有 Pro 都看得到。
    static var canManageAssetItems: Bool { ProStore.shared.isUnlocked }
    /// 增、改每月还款。已经加过的不管有没有 Pro 都照常显示、照常到期自动扣，也能删和处理没扣成的那期。
    static var canManageLoans: Bool { ProStore.shared.isUnlocked }
    /// 增、删、改现金账户和扣款顺序。已经拆好的账户不管有没有 Pro 都照常显示、照常按顺序扣。
    static var canManageCashAccounts: Bool { ProStore.shared.isUnlocked }
    /// Assets 的「钱与时间」视图。没有 Pro 时一律显示经典版
    static var canUseMoneyTimeAssets: Bool { ProStore.shared.isUnlocked }
    /// 把自由卡导出成图分享。看卡不要 Pro
    static var canShareFreedomCard: Bool { ProStore.shared.isUnlocked }
}
