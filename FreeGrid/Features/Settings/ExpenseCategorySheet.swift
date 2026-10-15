// Pro：新增或编辑一个支出分类——名字和细线图标。编辑时可以改名（旧账一起改）和删除。

import SwiftUI

struct ExpenseCategorySheet: View {
    /// nil 表示新增
    let existingName: String?
    /// 编辑时这个分类原来的图标（用户选过的才有）
    var existingIcon: String? = nil
    /// 用这个分类的记录有几笔；改名时提示会一起改
    var recordCount = 0
    /// 只剩这一个可选分类时不能删
    var canDelete = true
    /// 名字和用户选的图标（没选过为 nil，按名字给默认图标）
    let onSave: (String, String?) throws -> Void
    var onDelete: (() throws -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var pickedIcon: String?
    @State private var saveError: String?
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { existingName != nil }
    private var shownIcon: String { pickedIcon ?? ExpenseCategoryIcons.defaultIcon(for: cleanedName ?? "") }
    private var cleanedName: String? { try? ExpenseCategoryOptions.cleanName(name) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "名称")
                        UnderlinedField(isFocused: nameFocused) {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: shownIcon)
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(Color.skyDeep)
                                    .frame(width: 28)
                                TextField("房租、宠物、咖啡…", text: $name)
                                    .font(.system(.title3, design: .rounded))
                                    .foregroundStyle(Color.ink)
                                    .focused($nameFocused)
                                    .submitLabel(.done)
                                    .accessibilityIdentifier("category-name-field")
                            }
                        }
                        if isEditing, recordCount > 0, let cleanedName, cleanedName != existingName {
                            Text("改名后，这个分类下的 \(recordCount) 笔记录一起改成「\(cleanedName)」。")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.inkMuted)
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        KickerLabel(text: "图标")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: Spacing.sm)],
                                  spacing: Spacing.sm) {
                            ForEach(ExpenseCategoryIcons.choices, id: \.self) { icon in
                                iconButton(icon)
                            }
                        }
                    }

                    if isEditing, onDelete != nil {
                        Button {
                            confirmingDelete = true
                        } label: {
                            Text("删除这个分类")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(canDelete ? Color.flame : Color.inkFaint)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canDelete)
                        .accessibilityIdentifier("delete-category")
                    }
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(isEditing ? "编辑分类" : "添加分类")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(cleanedName == nil)
                        .foregroundStyle(cleanedName == nil ? Color.inkFaint : Color.skyDeep)
                        .fontWeight(.medium)
                        .accessibilityIdentifier("save-category")
                }
            }
            .confirmationDialog("删除「\(existingName ?? "")」？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    do {
                        try onDelete?()
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("记支出时不再出现这个选项。已有的记录不变；想找回，重新添加同名分类。")
            }
            .onAppear {
                name = existingName ?? ""
                pickedIcon = existingIcon
                nameFocused = !isEditing
            }
        }
        .saveErrorAlert($saveError)
        .iosSheetDetents()
    }

    private func iconButton(_ icon: String) -> some View {
        let selected = icon == shownIcon
        return Button {
            pickedIcon = icon
            nameFocused = false
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(selected ? Color.skyDeep : Color.inkMuted)
                .frame(width: 44, height: 44)
                .background(Circle().stroke(selected ? Color.skyDeep : Color.clear, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        guard let cleanedName else { return }
        do {
            try onSave(cleanedName, pickedIcon)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
