// Pro 支出分类管理：拖动排序、左滑删除、点一行改名换图标。只有改名会改写旧账（一起改成新名字）。
// 没有 Pro、但体验期间改过分类的人：列表照常显示、记账照常能选，只是不能改。
import SwiftUI
import SwiftData

struct ExpenseCategoriesView: View {
    @AppStorage(ExpenseCategoryStorage.key, store: AppPreferences.store) private var encodedOptions = ""
    @Environment(\.modelContext) private var modelContext
    @Query private var expenses: [Expense]
    @State private var saveError: String?
    @State private var showingPro = false
    @State private var editing: EditTarget?

    /// 打开分类表单：新增，或编辑某一个
    private enum EditTarget: Identifiable {
        case new
        case existing(String)
        var id: String {
            switch self {
            case .new: return "+new"
            case .existing(let name): return name
            }
        }
    }

    /// 一行的高度。列表放在卡片里不滚动，高度按行数算
    private static let rowHeight: CGFloat = 56

    private var options: ExpenseCategoryOptions {
        // 月供扣款的分类是贷款名，不当成支出分类补回来
        ExpenseCategoryStorage.decode(encodedOptions).including(expenses.filter { $0.loanID == nil }.map(\.category))
    }

    /// 每个分类下有几笔支出
    private var recordCounts: [String: Int] {
        expenses.reduce(into: [:]) { counts, expense in
            if expense.loanID == nil { counts[expense.category, default: 0] += 1 }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if ProFeatures.canCustomizeExpenseCategories {
                    categoryList
                    Text("长按拖动调整顺序，左滑删除。删除分类不影响已记的账，改名会一起改。")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.horizontal, Spacing.sm)
                } else if ExpenseCategoryStorage.isCustomized(encodedOptions) {
                    categoryList
                    readOnlyNote
                } else {
                    lockedCard
                }
            }
            .padding()
        }
        .background(Color.paper)
        .navigationTitle("支出分类")
        .inlineNavTitle()
        .saveErrorAlert($saveError)
        .proPaywall(isPresented: $showingPro, topic: .categories)
        .sheet(item: $editing) { target in
            switch target {
            case .new:
                ExpenseCategorySheet(existingName: nil) { name, icon in try add(name, icon: icon) }
            case .existing(let name):
                ExpenseCategorySheet(
                    existingName: name,
                    existingIcon: options.items.first { $0.name == name }?.icon,
                    recordCount: recordCounts[name, default: 0],
                    canDelete: options.activeItems.count > 1,
                    otherNames: options.activeItems.map(\.name).filter { $0 != name },
                    onSave: { newName, icon in try edit(name, to: newName, icon: icon) },
                    onDelete: { try delete(name) }
                )
            }
        }
    }

    private var lockedCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                KickerLabel(text: "FREEGRID PRO")
                Text("用你的方式记支出")
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(Color.ink)
                Text("自定义支出分类是 Pro 功能：添加自己的分类、配图标、改名、拖动排序。现有的九个分类照常可用。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                VaultButton(title: "了解 FreeGrid Pro", icon: "sparkles") { showingPro = true }
                    .padding(.top, Spacing.xs)
                    .accessibilityIdentifier("open-pro-from-categories")
            }
        }
    }

    /// 体验结束后：分类继续可用，修改要 Pro
    private var readOnlyNote: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("这些分类继续可用。修改分类需要 Pro。")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .padding(.horizontal, Spacing.sm)
            VaultButton(title: "解锁 Pro", icon: "sparkles") { showingPro = true }
                .accessibilityIdentifier("open-pro-from-categories")
        }
    }

    private var categoryList: some View {
        let canEdit = ProFeatures.canCustomizeExpenseCategories
        // 没有 Pro 时只看存下的那份，和记支出时能选的一样
        let items = canEdit ? options.activeItems : ExpenseCategoryStorage.decode(encodedOptions).activeItems
        let counts = recordCounts
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                KickerLabel(text: "你的支出分类")
                Spacer()
                Text("\(items.count) 个")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, Spacing.sm)
            VaultCard(padding: 0) {
                List {
                    ForEach(items) { item in
                        categoryRow(item, count: counts[item.name, default: 0])
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if canEdit && items.count > 1 {
                                    Button("删除") { update { try $0.delete(item.name) } }
                                        .tint(Color.flame)
                                }
                            }
                    }
                    .onMove(perform: canEdit ? { offsets, destination in
                        update { $0.move(fromOffsets: offsets, toOffset: destination) }
                    } : nil)
                    if canEdit {
                        addRow
                            .moveDisabled(true)
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, Self.rowHeight)
                .frame(height: Self.rowHeight * CGFloat(items.count + (canEdit ? 1 : 0)))
            }
        }
    }

    private func categoryRow(_ item: ExpenseCategoryOptions.Item, count: Int) -> some View {
        Button {
            if ProFeatures.canCustomizeExpenseCategories { editing = .existing(item.name) } else { showingPro = true }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: options.icon(for: item.name))
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Color.inkMuted)
                    .frame(width: 24)
                Text(item.name)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.ink)
                Spacer(minLength: Spacing.sm)
                if count > 0 {
                    Text("\(count) 笔")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.hairline)
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: 0, trailing: Spacing.lg))
        .accessibilityIdentifier("category-row-\(item.name)")
    }

    private var addRow: some View {
        Button {
            editing = .new
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 24)
                Text("添加分类")
                    .font(.system(.body, design: .rounded))
                Spacer()
            }
            .foregroundStyle(Color.skyDeep)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden, edges: .bottom)
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: 0, trailing: Spacing.lg))
        .accessibilityIdentifier("add-expense-category")
    }

    // MARK: - 写入

    private func add(_ name: String, icon: String?) throws {
        var next = options
        let stored = try next.add(name)
        if let icon { next.setIcon(icon, for: stored) }
        encodedOptions = try ExpenseCategoryStorage.encode(next)
    }

    /// 先改旧账再存偏好：账改失败时偏好不动，分类名和旧账始终对得上。
    /// 改成另一个已有分类的名字就是合并：旧账并过去，这个分类从列表里拿掉（表单里已经确认过）。
    private func edit(_ old: String, to input: String, icon: String?) throws {
        var next = options
        if let target = next.mergeTarget(for: input, excluding: old) {
            try LedgerStore.renameCategory(from: old, to: target, in: modelContext)
            next.merge(old, into: target)
            encodedOptions = try ExpenseCategoryStorage.encode(next)
            return
        }
        let name = try next.rename(old, to: input)
        if let icon { next.setIcon(icon, for: name) }
        if name != old { try LedgerStore.renameCategory(from: old, to: name, in: modelContext) }
        encodedOptions = try ExpenseCategoryStorage.encode(next)
    }

    private func delete(_ name: String) throws {
        var next = options
        try next.delete(name)
        encodedOptions = try ExpenseCategoryStorage.encode(next)
    }

    private func update(_ mutation: (inout ExpenseCategoryOptions) throws -> Void) {
        guard ProFeatures.canCustomizeExpenseCategories else { return }
        do {
            var next = options
            try mutation(&next)
            encodedOptions = try ExpenseCategoryStorage.encode(next)
        } catch { saveError = error.localizedDescription }
    }
}
