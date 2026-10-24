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
        Row(title: String(localized: "记账 · 固定支出 · 备份"), free: .yes, pro: .yes),
        Row(title: String(localized: "自由天数 · 格子 · 模拟"), free: .yes, pro: .yes),
        Row(title: String(localized: "支出分类"), free: .text(String(localized: "默认九类")), pro: .text(String(localized: "随你定义")), topics: [.categories]),
        Row(title: String(localized: "资产与现金"), free: .text(String(localized: "一个总数")), pro: .text(String(localized: "拆成子账户")), topics: [.assets, .cash]),
        // 免费版只有资产总开关（整体算或不算），现金总是算；Pro 每个资产项、每个现金账户自己决定
        Row(title: String(localized: "计入自由天数"), free: .text(String(localized: "资产整体选")), pro: .text(String(localized: "逐个选")), topics: [.freedomSwitch],
            info: Info(title: String(localized: "按自己的方式算自由"), body: [
                String(localized: "不是每一笔钱都打算现在动用。"),
                String(localized: "资产和现金拆成子账户后，每一个都能单独选计不计入自由天数。"),
                String(localized: "日常花的钱照常计入；房子、车子、留给以后的储蓄可以不计入。"),
                String(localized: "不计入的仍在净值里，只是不进自由天数。新加的子账户默认计入。免费版只能整体选资产计不计入，现金总是计入。"),
            ])),
        Row(title: String(localized: "资产视图"), free: .text(String(localized: "经典")), pro: .text(String(localized: "钱与时间")), topics: [.assetsView]),
        // 给背着贷款的人：还款照常进行时，扣掉每期月供还剩多少自由天数（不是还清倒计时）
        Row(title: String(localized: "贷款与分期"), free: .no, pro: .text(String(localized: "按还款计划算")), topics: [.loans],
            info: Info(title: String(localized: "有负债，也能看见自由"), body: [
                String(localized: "房贷、车贷，或是其他每月还款，都可以纳入自由天数测算。"),
                String(localized: "即使肩负还款责任，也能更清楚地了解自己的财务状况，以及当下真正拥有多少自由。"),
            ])),
        Row(title: String(localized: "自由卡"), free: .text(String(localized: "查看")), pro: .text(String(localized: "导出分享")), topics: [.freedomCard]),
    ]

    /// 设置页 Pro 卡头下面那一行，用户 2026-10-17 定的原话。不写价格（价格只在购买页出现）
    static let headline = String(localized: "管理更细致，自由更清晰")

    static var canCustomizeExpenseCategories: Bool { ProStore.shared.isUnlocked }
    /// 增、删、改资产项。已经拆好的项不管有没有 Pro 都看得到。
    static var canManageAssetItems: Bool { ProStore.shared.isUnlocked }
    /// 增、改、用贷款。没有 Pro 时已经加的贷款停用：照常显示、能删，但不自动扣、不算进自由天数（见 `LoanSchedule.inEffect`）
    static var canManageLoans: Bool { ProStore.shared.isUnlocked }
    /// 算自由天数、日均、首页格子时用的贷款：没有 Pro 时去掉停用的那些
    static func loansInEffect(_ loans: [Loan]) -> [Loan] {
        LoanSchedule.inEffect(loans, proUnlocked: canManageLoans)
    }
    /// 增、删、改现金账户和扣款顺序。已经拆好的账户不管有没有 Pro 都照常显示、照常按顺序扣。
    static var canManageCashAccounts: Bool { ProStore.shared.isUnlocked }
    /// Assets 的「钱与时间」视图。没有 Pro 时一律显示经典版
    static var canUseMoneyTimeAssets: Bool { ProStore.shared.isUnlocked }
    /// 把自由卡导出成图分享。看卡不要 Pro
    static var canShareFreedomCard: Bool { ProStore.shared.isUnlocked }
}
