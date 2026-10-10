// 支出选项的名称、顺序和可见性；不修改任何账目。
import Foundation

struct ExpenseCategoryOptions: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: String { name }
        let name: String
        var isHidden = false
    }

    enum ValidationError: Error, LocalizedError {
        case invalidName, duplicateName, lastVisible

        var errorDescription: String? {
            switch self {
            case .invalidName: return "分类名称请填写 1–20 个字，不包含换行。"
            case .duplicateName: return "这个分类已经存在，可以在列表中重新显示。"
            case .lastVisible: return "至少保留一个可选的支出分类。"
            }
        }
    }

    private(set) var items: [Item]
    static let defaults = ExpenseCategoryOptions(items: ExpenseCategory.canonical.map { Item(name: $0) })
    var visibleNames: [String] { items.filter { !$0.isHidden }.map(\.name) }
    var allNames: [String] { items.map(\.name) }

    /// 已使用的分类可从账本找回，已保存的隐藏状态和顺序优先。
    func including(_ recordedNames: [String]) -> Self {
        var result = self
        var known = Set(allNames)
        for name in Set(recordedNames).sorted() where !name.isEmpty {
            if known.insert(name).inserted { result.items.append(Item(name: name)) }
        }
        return result
    }

    mutating func add(_ input: String) throws {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 20,
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw ValidationError.invalidName
        }
        guard !allNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ValidationError.duplicateName
        }
        items.append(Item(name: name))
    }

    mutating func setHidden(_ hidden: Bool, name: String) throws {
        guard let index = items.firstIndex(where: { $0.name == name }) else { return }
        if hidden, !items[index].isHidden, visibleNames.count == 1 {
            throw ValidationError.lastVisible
        }
        items[index].isHidden = hidden
    }

    mutating func move(_ name: String, by distance: Int) {
        guard let index = items.firstIndex(where: { $0.name == name }),
              items.indices.contains(index + distance) else { return }
        items.swapAt(index, index + distance)
    }

    var isValid: Bool {
        !visibleNames.isEmpty && Set(allNames).count == items.count
            && allNames.allSatisfy { !$0.isEmpty && $0.count <= FinancialLimits.nameCharacters }
    }
}
