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

    static func encode(_ options: ExpenseCategoryOptions) throws -> String {
        let data = try JSONEncoder().encode(options)
        return String(decoding: data, as: UTF8.self)
    }
}
