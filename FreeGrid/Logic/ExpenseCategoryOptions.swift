// 支出选项的名称、顺序和删除；不修改任何账目。
import Foundation

struct ExpenseCategoryOptions: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: String { name }
        let name: String
        /// 删掉的选项留一条记号：账本里还有用这个名字的旧账，没有记号它会被当成新分类补回来
        var isDeleted = false

        // 早期版本把这个状态叫「隐藏」，偏好里沿用旧字段名
        private enum CodingKeys: String, CodingKey {
            case name
            case isDeleted = "isHidden"
        }
    }

    enum ValidationError: Error, LocalizedError {
        case invalidName, duplicateName, lastVisible

        var errorDescription: String? {
            switch self {
            case .invalidName: return "分类名称请填写 1–20 个字，不包含换行。"
            case .duplicateName: return "这个分类已经存在。"
            case .lastVisible: return "至少保留一个可选的支出分类。"
            }
        }
    }

    private(set) var items: [Item]
    static let defaults = ExpenseCategoryOptions(items: ExpenseCategory.canonical.map { Item(name: $0) })
    /// 记支出时能选的，也是管理页列出来的
    var activeItems: [Item] { items.filter { !$0.isDeleted } }
    var visibleNames: [String] { activeItems.map(\.name) }
    /// 包含已删除的名字；导入旧账时这些名字仍然算认识的分类
    var allNames: [String] { items.map(\.name) }

    /// 已使用的分类可从账本找回；已保存的顺序优先，删掉的不会被补回来。
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
        if let index = items.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            guard items[index].isDeleted else { throw ValidationError.duplicateName }
            // 重新添加删掉过的名字：沿用原来的写法，旧账才对得上；排到最后
            let restored = items.remove(at: index)
            items.append(Item(name: restored.name))
            return
        }
        items.append(Item(name: name))
    }

    /// 删除只是让它不再出现在选项里，用过这个分类的旧账不变
    mutating func delete(_ name: String) throws {
        guard let index = items.firstIndex(where: { $0.name == name }), !items[index].isDeleted else { return }
        guard visibleNames.count > 1 else { throw ValidationError.lastVisible }
        items[index].isDeleted = true
    }

    /// 在列出来的选项之间挪一位；中间夹着的已删除项不占位置
    mutating func move(_ name: String, by distance: Int) {
        let active = items.indices.filter { !items[$0].isDeleted }
        guard let position = active.firstIndex(where: { items[$0].name == name }),
              active.indices.contains(position + distance) else { return }
        items.swapAt(active[position], active[position + distance])
    }

    var isValid: Bool {
        !visibleNames.isEmpty && Set(allNames).count == items.count
            && allNames.allSatisfy { !$0.isEmpty && $0.count <= FinancialLimits.nameCharacters }
    }
}
