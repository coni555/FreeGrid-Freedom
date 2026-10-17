// 哪些功能属于 Pro。是否已解锁由 ProStore 根据 App Store 的购买记录决定。
import Foundation

enum ProFeatures {
    /// 从哪个功能进的购买页：对照表上那一行淡淡地标出来
    enum Topic {
        case categories, assets, cash, freedomSwitch, loans, freedomCard
    }

    /// 对照表一格：打勾、横杠（没有）、或者一个短词
    enum Cell {
        case yes, no
        case text(String)
    }

    /// 购买页对照表的一行。前两行两边都有，告诉人免费版本来就够用；往下左边变少，右边一直是满的
    struct Row: Identifiable {
        let title: String
        let free: Cell
        let pro: Cell
        var topic: Topic?
        var id: String { title }
    }

    /// 只列已经做好的；新功能做完再加到这里
    static let comparison: [Row] = [
        Row(title: "记账 · 历史 · 备份", free: .yes, pro: .yes),
        Row(title: "自由天数 · 格子 · 模拟", free: .yes, pro: .yes),
        Row(title: "支出分类", free: .text("固定"), pro: .text("自定义"), topic: .categories),
        Row(title: "资产", free: .text("一个总数"), pro: .text("逐项拆分"), topic: .assets),
        Row(title: "现金", free: .text("一个总数"), pro: .text("分账户"), topic: .cash),
        Row(title: "资产计入自由天数", free: .text("整体开关"), pro: .text("逐项开关"), topic: .freedomSwitch),
        Row(title: "每月还款", free: .no, pro: .yes, topic: .loans),
        Row(title: "自由卡", free: .text("查看"), pro: .text("导出分享"), topic: .freedomCard),
    ]

    /// 设置页 Pro 卡头下面那一行
    static let headline = "分账户 · 每月还款 · 分享自由卡"

    static var canCustomizeExpenseCategories: Bool { ProStore.shared.isUnlocked }
    /// 增、删、改资产项。已经拆好的项不管有没有 Pro 都看得到。
    static var canManageAssetItems: Bool { ProStore.shared.isUnlocked }
    /// 增、改每月还款。已经加过的不管有没有 Pro 都照常显示、照常到期自动扣，也能删和处理没扣成的那期。
    static var canManageLoans: Bool { ProStore.shared.isUnlocked }
    /// 增、删、改现金账户和扣款顺序。已经拆好的账户不管有没有 Pro 都照常显示、照常按顺序扣。
    static var canManageCashAccounts: Bool { ProStore.shared.isUnlocked }
    /// 把自由卡导出成图分享。看卡不要 Pro
    static var canShareFreedomCard: Bool { ProStore.shared.isUnlocked }
}
