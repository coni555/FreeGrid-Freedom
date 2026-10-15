// 支出分类的图标：细线 SF Symbols，和卡片的 1 像素描边同一种语言，不用实心或彩色。
import Foundation

enum ExpenseCategoryIcons {
    /// 编辑分类时可选的图标，按用途大致排好
    static let choices = [
        "cup.and.saucer", "fork.knife", "takeoutbag.and.cup.and.straw", "wineglass", "birthday.cake",
        "cart", "bag", "tshirt", "gift", "sparkles",
        "house", "bolt", "drop", "wifi", "iphone",
        "tram", "car", "bicycle", "airplane", "fuelpump",
        "gamecontroller", "film", "music.note", "book", "graduationcap",
        "cross.case", "pills", "heart", "pawprint", "figure.walk",
        "briefcase", "creditcard", "wrench.and.screwdriver", "scissors", "leaf",
        "person.2", "tag", "ellipsis",
    ]

    /// 免费版九个分类的默认图标
    private static let canonical: [String: String] = [
        "早餐": "cup.and.saucer", "午餐": "fork.knife", "晚餐": "takeoutbag.and.cup.and.straw",
        "购物": "bag", "交通": "tram", "娱乐": "gamecontroller",
        "成长投资": "book", "医疗": "cross.case", "其他": "ellipsis",
    ]

    /// 自定义分类按名字里的关键词猜一个，猜不到用标签
    private static let keywords: [(words: [String], icon: String)] = [
        (["房租", "租房", "房贷", "物业"], "house"),
        (["水电", "电费", "燃气", "煤气"], "bolt"),
        (["水费"], "drop"),
        (["话费", "手机", "宽带", "网费"], "iphone"),
        (["咖啡", "奶茶", "茶"], "cup.and.saucer"),
        (["饭", "餐", "外卖", "食"], "fork.knife"),
        (["酒", "聚会"], "wineglass"),
        (["零食", "甜品", "蛋糕"], "birthday.cake"),
        (["超市", "日用", "买菜"], "cart"),
        (["衣", "服饰", "鞋"], "tshirt"),
        (["礼物", "红包", "人情"], "gift"),
        (["美妆", "护肤", "化妆"], "sparkles"),
        (["地铁", "公交", "火车", "高铁"], "tram"),
        (["打车", "停车", "车"], "car"),
        (["加油", "油费"], "fuelpump"),
        (["机票", "旅行", "旅游"], "airplane"),
        (["游戏"], "gamecontroller"),
        (["电影", "视频", "会员", "订阅"], "film"),
        (["音乐"], "music.note"),
        (["书", "学习", "课程"], "book"),
        (["学费", "培训"], "graduationcap"),
        (["药"], "pills"),
        (["医", "看病"], "cross.case"),
        (["健身", "运动"], "figure.walk"),
        (["宠物", "猫", "狗"], "pawprint"),
        (["工作", "办公"], "briefcase"),
        (["理发", "美发"], "scissors"),
        (["维修", "装修"], "wrench.and.screwdriver"),
    ]

    static func defaultIcon(for name: String) -> String {
        if let icon = canonical[name] { return icon }
        return keywords.first { entry in entry.words.contains { name.contains($0) } }?.icon ?? "tag"
    }
}
