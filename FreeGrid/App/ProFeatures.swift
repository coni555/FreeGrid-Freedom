// 哪些功能属于 Pro。是否已解锁由 ProStore 根据 App Store 的购买记录决定。
import Foundation

enum ProFeatures {
    struct Benefit: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    /// 购买页只列已经做好的权益；新功能做完再加到这里
    static let benefits: [Benefit] = [
        Benefit(icon: "list.bullet",
                title: "自定义支出分类",
                detail: "添加自己的分类，调整常用顺序，删除用不到的选项。"),
        Benefit(icon: "square.stack.3d.up",
                title: "资产和现金分账户",
                detail: "资产拆成房、车、定期、基金，现金拆成微信、支付宝、银行卡；记支出按你排的顺序扣。"),
        Benefit(icon: "slider.horizontal.3",
                title: "自由天数逐项开关",
                detail: "房子、车等难以变现的资产可以单独排除，自由天数只算真正能用的钱。"),
        Benefit(icon: "calendar",
                title: "每月还款",
                detail: "填上房贷车贷，自由天数在按时还款的前提下算，还款日在格子上一眼可见。"),
        Benefit(icon: "creditcard",
                title: "分享自由卡",
                detail: "把自由天数做成一张卡，材质随天数升级。默认不露金额，导出卡片或海报。"),
    ]

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
