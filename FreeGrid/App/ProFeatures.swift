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
                detail: "添加自己的分类，调整常用顺序，隐藏用不到的选项。"),
    ]

    static var canCustomizeExpenseCategories: Bool { ProStore.shared.isUnlocked }
}
