// 分类配置是本机偏好；账目仍只保存原来的 category 字段。
import Foundation

enum ExpenseCategoryStorage {
    static let key = "expenseCategoryOptions"

    static func decode(_ text: String) -> ExpenseCategoryOptions {
        guard let data = text.data(using: .utf8),
              let options = try? JSONDecoder().decode(ExpenseCategoryOptions.self, from: data),
              options.isValid else { return .defaults }
        return options
    }

    /// 记支出、改一笔账时能选的分类。有 Pro 时把旧账里用过的也补回来；
    /// 没有 Pro 时就是存下的那份：体验期间设好的照常能选，只是不能改；从没改过的就是默认九类（用户 2026-10-18 定）
    static func pickable(_ text: String, recorded: [String], unlocked: Bool) -> [String] {
        let stored = decode(text)
        return (unlocked ? stored.including(recorded) : stored).visibleNames
    }

    /// 改过分类（加、删、改名、排序、换图标）。没改过的免费用户点「支出分类」直接看 Pro 介绍
    static func isCustomized(_ text: String) -> Bool { decode(text) != .defaults }

    static func encode(_ options: ExpenseCategoryOptions) throws -> String {
        let data = try JSONEncoder().encode(options)
        return String(decoding: data, as: UTF8.self)
    }
}
