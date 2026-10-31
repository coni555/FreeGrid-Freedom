// 支出选项的名称、图标、顺序和删除。本身不改账目；改名时旧账由 `LedgerStore.renameCategory` 一起改。
import Foundation

struct ExpenseCategoryOptions: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: String { name }
        var name: String
        /// 删掉的选项留一条记号：账本里还有用这个名字的旧账，没有记号它会被当成新分类补回来
        var isDeleted = false
        /// 用户选的 SF Symbol；nil 时按名字给默认图标（见 `ExpenseCategoryIcons`）
        var icon: String?

        // 早期版本把这个状态叫「隐藏」，偏好里沿用旧字段名
        private enum CodingKeys: String, CodingKey {
            case name
            case isDeleted = "isHidden"
            case icon
        }
    }

    enum ValidationError: Error, LocalizedError {
        case invalidName, duplicateName, lastVisible

        var errorDescription: String? {
            switch self {
            case .invalidName: return String(localized: "分类名称请填写 1–20 个字，不包含换行。")
            case .duplicateName: return String(localized: "这个分类已经存在。")
            case .lastVisible: return String(localized: "至少保留一个可选的支出分类。")
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

    /// 返回存进去的名字：重新添加删掉过的分类时沿用原来的写法
    @discardableResult
    mutating func add(_ input: String) throws -> String {
        let name = try Self.cleanName(input)
        if let index = items.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            guard items[index].isDeleted else { throw ValidationError.duplicateName }
            // 重新添加删掉过的名字：沿用原来的写法，旧账才对得上；排到最后
            let restored = items.remove(at: index)
            items.append(Item(name: restored.name, icon: restored.icon))
            return restored.name
        }
        items.append(Item(name: name))
        return name
    }

    /// 新建分类放在 `anchor` 的位置：把早午晚餐并成「餐饮」时，新的一类顶替原来那一项，不跑到最后
    @discardableResult
    mutating func add(_ input: String, before anchor: String?) throws -> String {
        let name = try add(input)
        guard let anchor, anchor != name,
              let from = items.firstIndex(where: { $0.name == name }),
              let to = items.firstIndex(where: { $0.name == anchor }), to < from else { return name }
        items.insert(items.remove(at: from), at: to)
        return name
    }

    /// 清理并校验用户输入的名称：去首尾空白，1–20 字，不含换行等控制字符
    static func cleanName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 20,
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw ValidationError.invalidName
        }
        return name
    }

    /// 改名，返回清理后的新名字。和别的分类重名（不分大小写）时拒绝；
    /// 新名字正好是删掉过的分类，就把那条删除记号拿掉，两边的旧账从此都叫这个名字。
    @discardableResult
    mutating func rename(_ old: String, to input: String) throws -> String {
        var name = try Self.cleanName(input)
        guard let index = items.firstIndex(where: { $0.name == old }) else { return name }
        guard name != old else { return name }
        if let other = items.firstIndex(where: { $0.name != old && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            guard items[other].isDeleted else { throw ValidationError.duplicateName }
            // 沿用删掉那条的写法，旧账才合得上
            name = items[other].name
            items.remove(at: other)
        }
        let target = items.firstIndex(where: { $0.name == old }) ?? index
        items[target].name = name
        return name
    }

    /// 列出来的分类里，和输入同名（不分大小写）的另一个分类；改名成它就是合并
    func mergeTarget(for input: String, excluding old: String) -> String? {
        guard let name = try? Self.cleanName(input) else { return nil }
        return activeItems.first { $0.name != old && $0.name.caseInsensitiveCompare(name) == .orderedSame }?.name
    }

    /// 合并：`old` 从列表里拿掉，旧账由 `LedgerStore.renameCategory` 改到 `target` 名下。
    /// 留下的是 `target` 的位置和图标。
    mutating func merge(_ old: String, into target: String) {
        guard old != target, items.contains(where: { $0.name == target && !$0.isDeleted }) else { return }
        items.removeAll { $0.name == old }
    }

    mutating func setIcon(_ icon: String?, for name: String) {
        guard let index = items.firstIndex(where: { $0.name == name }) else { return }
        items[index].icon = icon
    }

    /// 这个分类显示的图标：用户选过的优先，否则按名字给默认的
    func icon(for name: String) -> String {
        items.first { $0.name == name }?.icon ?? ExpenseCategoryIcons.defaultIcon(for: name)
    }

    /// 列表里拖动排序：`offsets` 和 `destination` 都是在列出来的选项里的位置，已删除项留在原地不参与
    mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let active = items.indices.filter { !items[$0].isDeleted }
        var reordered = active.map { items[$0] }
        let moving = offsets.filter { reordered.indices.contains($0) }
        let picked = moving.map { reordered[$0] }
        for index in moving.reversed() { reordered.remove(at: index) }
        let insertAt = min(max(0, destination - moving.filter { $0 < destination }.count), reordered.count)
        reordered.insert(contentsOf: picked, at: insertAt)
        for (slot, item) in zip(active, reordered) { items[slot] = item }
    }

    /// 从备份恢复分类设置。`replacing` 为真（整份恢复）时以备份为准；
    /// 否则保留本机的顺序和图标，只把备份里有、本机没有的分类接到后面。
    func merging(_ backup: ExpenseCategoryOptions, replacing: Bool) -> ExpenseCategoryOptions {
        guard backup.isValid else { return self }
        if replacing { return backup.including(allNames) }
        var result = self
        var known = Set(allNames.map { $0.lowercased() })
        for item in backup.items where known.insert(item.name.lowercased()).inserted {
            result.items.append(item)
        }
        return result.isValid ? result : self
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
