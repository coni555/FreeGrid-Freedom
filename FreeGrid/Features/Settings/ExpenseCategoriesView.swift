// Pro 支出选项管理；新增、排序和隐藏均只修改偏好，不改写旧账。
import SwiftUI
import SwiftData

struct ExpenseCategoriesView: View {
    @AppStorage(ExpenseCategoryStorage.key) private var encodedOptions = ""
    @Query private var expenses: [Expense]
    @State private var name = ""
    @State private var saveError: String?
    @FocusState private var isNameFocused: Bool

    private var options: ExpenseCategoryOptions {
        ExpenseCategoryStorage.decode(encodedOptions).including(expenses.map(\.category))
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
                             ? "添加自己的分类，调整常用顺序，隐藏用不到的选项。"
                             : "自定义支出分类是 Pro 功能，正式上线后可购买解锁。")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                    }
                }
                if ProFeatures.canCustomizeExpenseCategories {
                    addCard
                    categoryList
                    Text("隐藏只影响记支出时的选项，历史记录和统计保持原样。排序与隐藏设置保存在此设备；账本备份保留已使用的分类名称。")
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
                Text("\(options.visibleNames.count) 个显示")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, Spacing.sm)
            VaultCard(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(options.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Hairline().padding(.horizontal, Spacing.lg) }
                        categoryRow(item, index: index)
                    }
                }
            }
        }
    }

    private func categoryRow(_ item: ExpenseCategoryOptions.Item, index: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(item.isHidden ? Color.inkFaint : Color.ink)
                Text(item.isHidden ? "已隐藏" : "记支出时显示")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
            Spacer(minLength: 0)
            rowButton("arrow.up", label: "上移\(item.name)", id: "move-up-\(item.name)") {
                update { $0.move(item.name, by: -1) }
            }
            .disabled(index == 0)
            rowButton("arrow.down", label: "下移\(item.name)", id: "move-down-\(item.name)") {
                update { $0.move(item.name, by: 1) }
            }
            .disabled(index == options.items.count - 1)
            rowButton(item.isHidden ? "eye.slash" : "eye",
                      label: item.isHidden ? "显示\(item.name)" : "隐藏\(item.name)",
                      id: "visibility-\(item.name)") {
                update { try $0.setHidden(!item.isHidden, name: item.name) }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private func rowButton(_ icon: String, label: String, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.skyDeep)
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
