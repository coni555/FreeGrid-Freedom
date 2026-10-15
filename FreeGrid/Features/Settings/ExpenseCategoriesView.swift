// Pro 支出选项管理；新增、排序和删除均只修改偏好，不改写旧账。
import SwiftUI
import SwiftData

struct ExpenseCategoriesView: View {
    @AppStorage(ExpenseCategoryStorage.key, store: AppPreferences.store) private var encodedOptions = ""
    @Query private var expenses: [Expense]
    @State private var name = ""
    @State private var saveError: String?
    @FocusState private var isNameFocused: Bool
    @State private var showingPro = false
    /// 等用户确认删除的分类名
    @State private var pendingDelete: String?

    private var options: ExpenseCategoryOptions {
        // 月供扣款的分类是贷款名，不当成支出分类补回来
        ExpenseCategoryStorage.decode(encodedOptions).including(expenses.filter { $0.loanID == nil }.map(\.category))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VaultCard {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "FREEGRID PRO")
                        Text("用你的方式记支出")
                            .font(.system(.title2, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Text(ProFeatures.canCustomizeExpenseCategories
                             ? "添加自己的分类，调整常用顺序，删除用不到的选项。"
                             : "自定义支出分类是 Pro 功能。现有的九个分类照常可用。")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        if !ProFeatures.canCustomizeExpenseCategories {
                            VaultButton(title: "了解 FreeGrid Pro", icon: "sparkles") { showingPro = true }
                                .padding(.top, Spacing.xs)
                                .accessibilityIdentifier("open-pro-from-categories")
                        }
                    }
                }
                if ProFeatures.canCustomizeExpenseCategories {
                    addCard
                    categoryList
                    Text("删除只影响记支出时的选项，已有的记录和统计保持原样；想找回，重新添加同名分类。排序和删除保存在此设备；账本备份保留已使用的分类名称。")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.horizontal, Spacing.sm)
                }
            }
            .padding()
        }
        .background(Color.paper)
        .navigationTitle("支出分类")
        .inlineNavTitle()
        .saveErrorAlert($saveError)
        .sheet(isPresented: $showingPro) { ProPaywallView() }
        .confirmationDialog("删除「\(pendingDelete ?? "")」？",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let name = pendingDelete { update { try $0.delete(name) } }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("记支出时不再出现这个选项。已有的记录不变。")
        }
    }

    private var addCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "新增分类")
                TextField("例如：房租、宠物、咖啡", text: $name)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .accessibilityIdentifier("new-expense-category")
                Hairline()
                VaultButton(title: "添加分类", icon: "plus", action: add)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("add-expense-category")
            }
        }
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                KickerLabel(text: "你的支出选项")
                Spacer()
                Text("\(options.activeItems.count) 个")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, Spacing.sm)
            VaultCard(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(options.activeItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Hairline().padding(.horizontal, Spacing.lg) }
                        categoryRow(item, index: index)
                    }
                }
            }
        }
    }

    private func categoryRow(_ item: ExpenseCategoryOptions.Item, index: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(item.name)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.ink)
            Spacer(minLength: 0)
            rowButton("arrow.up", label: "上移\(item.name)", id: "move-up-\(item.name)") {
                update { $0.move(item.name, by: -1) }
            }
            .disabled(index == 0)
            rowButton("arrow.down", label: "下移\(item.name)", id: "move-down-\(item.name)") {
                update { $0.move(item.name, by: 1) }
            }
            .disabled(index == options.activeItems.count - 1)
            rowButton("trash", label: "删除\(item.name)", id: "delete-\(item.name)", color: .flame) {
                pendingDelete = item.name
            }
            .disabled(options.activeItems.count == 1)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private func rowButton(_ icon: String, label: String, id: String, color: Color = .skyDeep,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func add() {
        update {
            try $0.add(name)
            name = ""
            isNameFocused = false
        }
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
