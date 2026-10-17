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
        var id: String { title }
    }

    /// 只列已经做好的；新功能做完再加到这里。一屏放得下
    static let comparison: [Row] = [
        Row(title: "记账 · 历史 · 备份", free: .yes, pro: .yes),
        Row(title: "自由天数 · 格子 · 模拟", free: .yes, pro: .yes),
        Row(title: "支出分类", free: .text("默认九类"), pro: .text("随你定义"), topics: [.categories]),
        Row(title: "资产与现金", free: .text("一个总数"), pro: .text("拆成子账户"), topics: [.assets, .cash]),
        // 免费版只有资产总开关（整体算或不算），现金总是算；Pro 每个资产项、每个现金账户自己决定
        Row(title: "子账户计入自由", free: .text("整体开关"), pro: .text("逐个选择"), topics: [.freedomSwitch],
            info: Info(title: "按自己的方式算自由", body: [
                "不是每一笔钱都打算现在动用。",
                "资产和现金拆成子账户后，每一个都可以单独决定算不算进自由天数：日常花的钱照算，房子、车子、留给以后的储蓄可以不算。",
                "不算的那一个仍在净值里，只是不进自由天数。新加的子账户默认都算。免费版可以把资产整体算进或不算。",
            ])),
        Row(title: "资产视图", free: .text("经典"), pro: .text("钱与时间"), topics: [.assetsView]),
        // 给背着贷款的人：还款照常进行时，扣掉每期月供还剩多少自由天数（不是还清倒计时）
        Row(title: "负债与月供", free: .no, pro: .text("算进自由天数"), topics: [.loans],
            info: Info(title: "有负债，也能看见自由", body: [
                "房贷、车贷、分期按期数填进来，到还款日自动从现金扣。",
                "自由天数会先把每期月供留出来，算的是「还款照常进行时，你还能自由多久」，不是还清倒计时。",
                "房租、水电、会员这类没有期数的固定支出，免费版就能加。",
            ])),
        Row(title: "自由名片", free: .text("查看"), pro: .text("导出分享"), topics: [.freedomCard]),
    ]

    /// 设置页 Pro 卡头下面那一行：说人话讲能多做什么，不写价格（价格只在购买页出现）
    static let headline = "分类自己定，钱分账户记，房贷也算进去"

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
