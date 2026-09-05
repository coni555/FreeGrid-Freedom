// 支出分类的唯一词表，供手动输入和导入共用。

import Foundation

enum ExpenseCategory {
    /// 权威分类(记账 Picker + 一切分析口径的唯一标准)
    static let canonical = ["早餐", "午餐", "晚餐", "购物", "交通", "娱乐",
                            "成长投资", "医疗", "其他"]

    /// 兜底分类(归一不出来时的默认)
    static let fallback = "其他"

    /// 外来标签 → canonical 的高置信别名表(只放"几乎不会错"的)。
    /// 英文 key 走小写匹配(早期 web 旧版分类键);中文 key 精确匹配。
    /// 拿不准的(food / 订阅 / 日用 / 人情 …)故意不放, 让它们落到 needs-review,
    /// 由用户在导入预览里手动归类 —— 这就是"稳"的含义。
    static let aliases: [String: String] = [
        "transport": "交通", "transportation": "交通",
        "shopping": "购物", "shop": "购物",
        "entertainment": "娱乐",
        "medical": "医疗", "health": "医疗",
        "other": "其他", "others": "其他", "misc": "其他",
        "growth": "成长投资", "investment": "成长投资",
        "数码": "购物",   // 经用户确认:电子产品并入购物
    ]

    /// 归一建议。已是 canonical → 原样(known);命中别名 → canonical(known);
    /// 都不命中 → fallback 但 known=false(需用户在预览里确认)。
    static func suggest(_ raw: String) -> (canonical: String, known: Bool) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonical.contains(t) { return (t, true) }
        if let mapped = aliases[t] ?? aliases[t.lowercased()] { return (mapped, true) }
        return (fallback, false)
    }
}
