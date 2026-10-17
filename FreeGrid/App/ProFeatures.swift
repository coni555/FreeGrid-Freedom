// 哪些功能属于 Pro。是否已解锁由 ProStore 根据 App Store 的购买记录决定。
import Foundation

enum ProFeatures {
    /// 从哪个功能进的购买页：对照表上那一行淡淡地标出来
    enum Topic {
        case categories, assets, cash, freedomSwitch, assetsView, loans, freedomCard
    }

    /// 购买页对照表的一行：名字、一句说明，免费版有没有。Pro 一列永远是有
    struct Row: Identifiable {
        let title: String
        let detail: String
        let inFree: Bool
        var topics: [Topic] = []
        var id: String { title }
    }

    /// Pro 专属，排在前面。文案是用户 2026-10-17 定的；新功能做完再加到这里
    static let proRows: [Row] = [
        Row(title: "自定义支出分类", detail: "按自己的习惯，整理每一笔开销。", inFree: false,
            topics: [.categories]),
        Row(title: "资产与现金设立子账户", detail: "自由拆分，逐项决定是否计入自由天数。", inFree: false,
            topics: [.assets, .cash, .freedomSwitch]),
        Row(title: "全新资产视图", detail: "在「金钱与时间」之间切换，经典界面随时可回。", inFree: false,
            topics: [.assetsView]),
        Row(title: "每月还款管理", detail: "把负债安排在内，看还款后还剩多少自由。", inFree: false,
            topics: [.loans]),
        Row(title: "专属自由名片", detail: "把你的自由状态，做成一张值得分享的卡片，支持导出。", inFree: false,
            topics: [.freedomCard]),
    ]

    /// 免费就有，两列都打勾：告诉人免费版本来就够用
    static let freeRows: [Row] = [
        Row(title: "自由可视化", detail: "自由天数、每日格子与变化趋势。", inFree: true),
        Row(title: "完整收支记账", detail: "默认支出分类、历史查询与月度汇总。", inFree: true),
        Row(title: "基础资产管理", detail: "资产、现金总额与被动收入。", inFree: true),
        Row(title: "消费模拟与自检", detail: "预览消费影响，了解自由状态。", inFree: true),
        Row(title: "离线使用与备份", detail: "无需注册，支持账本导入导出。", inFree: true),
    ]

    /// 设置页 Pro 卡头下面那一行
    static let headline = "全新资产视图 · 子账户 · 每月还款"

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
