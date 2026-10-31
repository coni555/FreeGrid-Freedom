// Pro 支出分类管理：拖动排序、左滑删除、点一行改名换图标，或把它的旧账全部移到别的分类（合并）。改名和移动会改写旧账。
// 删掉的分类如果还有旧账，单独列在下面，可以把旧账移走或放回列表。
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
    @State private var undoMove: CategoryMoveUndo?

    /// 打开分类表单：新增、编辑某一个，或把一个已删除分类的旧账移走
    private enum EditTarget: Identifiable {
        case new
        case existing(String)
        case moveDeleted(String)
        var id: String {
            switch self {
            case .new: return "+new"
            case .existing(let name): return name
            case .moveDeleted(let name): return "-" + name
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
                    Text("长按拖动调整顺序，左滑删除。点一个分类可以改名，或把它的账全部移到别的分类。删除分类不影响已记的账。")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.horizontal, Spacing.sm)
                    deletedWithRecords
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
        .categoryMoveUndoBar($undoMove) { undo($0) }
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
                    onDelete: { try delete(name) },
                    moveOptions: options,
                    onMoveAll: { target, removesSource in try moveAll(from: name, to: target, removingSource: removesSource) }
                )
            case .moveDeleted(let name):
                MoveExpensesSheet(options: options, source: name, sourceCount: recordCounts[name, default: 0],
                                  sourceIsDeleted: true) { target, _, _ in
                    try moveAll(from: name, to: target, removingSource: true)
                }
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
                VaultButton(title: String(localized: "了解 FreeGrid Pro"), icon: "sparkles") { showingPro = true }
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
            VaultButton(title: String(localized: "解锁 Pro"), icon: "sparkles") { showingPro = true }
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
                KickerLabel(text: String(localized: "你的支出分类"))
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
                Text(ExpenseCategory.displayName(item.name))
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

    /// 删掉了、但账本里还有记录用着的分类。以前删了就再也够不着这些旧账
    @ViewBuilder
    private var deletedWithRecords: some View {
        let counts = recordCounts
        let deleted = options.items.filter { $0.isDeleted && counts[$0.name, default: 0] > 0 }
        if !deleted.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                KickerLabel(text: String(localized: "已删除，还有旧账"))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, Spacing.md)
                VaultCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(deleted.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Hairline().padding(.leading, Spacing.lg) }
                            deletedRow(item, count: counts[item.name, default: 0])
                        }
                    }
                }
                Text("记支出时不会出现。可以把它们的账移到别的分类，或者放回列表。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .padding(.horizontal, Spacing.sm)
            }
        }
    }

    private func deletedRow(_ item: ExpenseCategoryOptions.Item, count: Int) -> some View {
        Menu {
            Button("全部 \(count) 笔移到…", systemImage: "arrow.turn.down.right") { editing = .moveDeleted(item.name) }
            Button("放回列表", systemImage: "arrow.uturn.backward") { update { try $0.add(item.name) } }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: options.icon(for: item.name))
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Color.inkFaint)
                    .frame(width: 24)
                Text(ExpenseCategory.displayName(item.name))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                Spacer(minLength: Spacing.sm)
                Text("\(count) 笔")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, Spacing.lg)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("deleted-category-row-\(item.name)")
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

    /// 合并：`source` 的账全部移到 `target`（可以是当场新建的，放在 source 的位置）。
    /// 先改账再存偏好；偏好存不进去时把账改回来，分类名和旧账始终对得上。
    private func moveAll(from source: String, to target: CategoryMoveTarget, removingSource: Bool) throws {
        let before = encodedOptions
        var next = options
        let name = target.isNew ? try next.add(target.name, before: source) : target.name
        if removingSource { next.merge(source, into: name) }
        let encoded = try ExpenseCategoryStorage.encode(next)
        let ids = Set(expenses.filter { $0.loanID == nil && $0.category == source }.map(\.id))
        let previous = try LedgerStore.moveExpenses(ids, to: name, in: modelContext)
        encodedOptions = encoded
        withAnimation(.spring(duration: 0.3)) {
            undoMove = CategoryMoveUndo(
                message: String(localized: "\(previous.count) 笔已移到「\(ExpenseCategory.displayName(name))」"),
                previous: previous, encodedOptions: before)
        }
    }

    private func undo(_ move: CategoryMoveUndo) {
        do {
            try LedgerStore.restoreCategories(move.previous, in: modelContext)
            encodedOptions = move.encodedOptions
        } catch { saveError = error.localizedDescription }
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
