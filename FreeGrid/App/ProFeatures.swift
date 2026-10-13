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
                title: "资产逐项记录",
                detail: "把资产拆成房、车、定期、基金…一项一项记，总数自动相加。"),
        Benefit(icon: "slider.horizontal.3",
                title: "自由天数逐项开关",
                detail: "房子、车等难以变现的资产可以单独排除，自由天数只算真正能用的钱。"),
    ]

    static var canCustomizeExpenseCategories: Bool { ProStore.shared.isUnlocked }
    /// 增、删、改资产项。已经拆好的项不管有没有 Pro 都看得到。
    static var canManageAssetItems: Bool { ProStore.shared.isUnlocked }
}
