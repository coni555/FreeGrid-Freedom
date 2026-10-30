// Pro：把一批支出移到另一个分类。合并（分类管理里「全部 N 笔移到…」）和拆分（明细搜索结果「把这 N 笔移到…」）
// 共用这一张表：先选移到哪，拆分时还能逐笔去掉勾选。真正的写入由打开它的页面做，移完给 5 秒撤销。

import SwiftUI

/// 要移到的分类：已有的，或者在表里新建的名字（移动时才真正加进分类列表）
struct CategoryMoveTarget: Equatable {
    let name: String
    let isNew: Bool
}

struct MoveExpensesSheet: View {
    /// 拆分时列出来的一笔
    struct Record: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let amount: Double
        let category: String
        let note: String
    }

    /// 当前的分类设置：列出能移到的分类和它们的图标
    let options: ExpenseCategoryOptions
    /// 合并时被搬空的分类，不出现在目标里；拆分时为 nil
    var source: String? = nil
    /// 合并时搬几笔（不逐笔列出）
    var sourceCount = 0
    /// 合并时：source 已经删掉了，搬完不用再问删不删
    var sourceIsDeleted = false
    /// 拆分时逐笔列出、默认全选；合并时为空
    var records: [Record] = []
    /// 选好的目标、勾上的记录（合并时为空，由页面按分类取）、搬完要不要删掉 source
    let onMove: (CategoryMoveTarget, Set<UUID>, Bool) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var target: CategoryMoveTarget?
    @State private var excluded: Set<UUID> = []
    @State private var removesSource = true
    @State private var naming = false
    @State private var newName = ""
    @State private var saveError: String?

    private var isMerge: Bool { source != nil }
    private var choices: [ExpenseCategoryOptions.Item] { options.activeItems.filter { $0.name != source } }
    private var selected: Set<UUID> { Set(records.map(\.id)).subtracting(excluded) }
    private var moveCount: Int { isMerge ? sourceCount : selected.count }
    private func shown(_ name: String) -> String { ExpenseCategory.displayName(name) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: String(localized: "移到"))
                            .padding(.horizontal, Spacing.sm)
                        VaultCard(padding: 0) { targetMenu }
                        if let target, target.isNew {
                            Text("会新建「\(target.name)」这个分类。")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.inkMuted)
                                .padding(.horizontal, Spacing.sm)
                        }
                    }
                    if let source, !sourceIsDeleted {
                        Toggle(isOn: $removesSource) {
                            Text("移完删掉「\(shown(source))」")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.ink)
                        }
                        .tint(Color.skyDeep)
                        .padding(.horizontal, Spacing.sm)
                        .accessibilityIdentifier("move-removes-source")
                    }
                    if !records.isEmpty { recordList }
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(isMerge ? "移走「\(shown(source ?? ""))」的 \(sourceCount) 笔" : "移到其他分类")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    let ready = target != nil && moveCount > 0
                    Button("移动") { move() }
                        .disabled(!ready)
                        .foregroundStyle(ready ? Color.skyDeep : Color.inkFaint)
                        .fontWeight(.medium)
                        .accessibilityIdentifier("confirm-move-expenses")
                }
            }
            .alert("新建分类", isPresented: $naming) {
                TextField("咖啡、宠物、房租…", text: $newName)
                Button("取消", role: .cancel) {}
                Button("好") { pickNewName() }
            }
        }
        .saveErrorAlert($saveError)
        .presentationDetents(records.isEmpty ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
    }

    /// 目标用菜单选，和记一笔表单里选分类同一种手感；菜单最后一项新建
    private var targetMenu: some View {
        Menu {
            ForEach(choices) { item in
                Button {
                    target = CategoryMoveTarget(name: item.name, isNew: false)
                } label: {
                    Label(shown(item.name), systemImage: options.icon(for: item.name))
                }
            }
            Divider()
            Button("新建分类…", systemImage: "plus") {
                newName = ""
                naming = true
            }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: target.map { options.icon(for: $0.name) } ?? "arrow.turn.down.right")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(target == nil ? Color.inkFaint : Color.skyDeep)
                    .frame(width: 24)
                Text(target.map { shown($0.name) } ?? String(localized: "选一个分类"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(target == nil ? Color.inkFaint : Color.ink)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, Spacing.lg)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("move-target-picker")
    }

    private var recordList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                KickerLabel(text: String(localized: "选中 \(selected.count) / \(records.count) 笔"))
                Spacer()
                Button(excluded.isEmpty ? "全不选" : "全选") {
                    excluded = excluded.isEmpty ? Set(records.map(\.id)) : []
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.skyDeep)
            }
            .padding(.horizontal, Spacing.sm)
            VaultCard(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { Hairline(color: .hairlineSoft).padding(.leading, 52) }
                        recordRow(record)
                    }
                }
            }
        }
    }

    private func recordRow(_ record: Record) -> some View {
        let checked = !excluded.contains(record.id)
        return Button {
            if checked { excluded.insert(record.id) } else { excluded.remove(record.id) }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(checked ? Color.skyDeep : Color.inkFaint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.note.isEmpty ? shown(record.category) : record.note)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(Self.dayLabel(record.date) + " · " + shown(record.category))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
                Spacer(minLength: Spacing.sm)
                Text(FinancialFormatting.yuan(record.amount))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(checked ? Color.ink : Color.inkFaint)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .accessibilityIdentifier("move-record-\(record.id.uuidString)")
    }

    /// 今年的只写月日，往年的带上年份
    private static func dayLabel(_ date: Date) -> String {
        Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(.dateTime.month().day())
            : date.formatted(.dateTime.year().month().day())
    }

    /// 输入的名字正好是已有分类（含英文界面下默认九类的英文名）时，直接选它，不重复新建
    private func pickNewName() {
        guard let typed = try? ExpenseCategoryOptions.cleanName(newName) else {
            saveError = ExpenseCategoryOptions.ValidationError.invalidName.localizedDescription
            return
        }
        if let existing = options.activeItems.first(where: {
            $0.name.caseInsensitiveCompare(typed) == .orderedSame
                || shown($0.name).caseInsensitiveCompare(typed) == .orderedSame
        }) {
            target = existing.name == source ? nil : CategoryMoveTarget(name: existing.name, isNew: false)
        } else {
            target = CategoryMoveTarget(name: typed, isNew: true)
        }
    }

    private func move() {
        guard let target else { return }
        do {
            try onMove(target, isMerge ? [] : selected, isMerge && !sourceIsDeleted && removesSource)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// 移动完成后的 5 秒撤销
struct CategoryMoveUndo: Identifiable, Equatable {
    let id = UUID()
    let message: String
    /// 每笔原来的分类
    let previous: [UUID: String]
    /// 移动前的分类设置（新建了分类、或删掉了被搬空的分类时，撤销要一起还原）
    let encodedOptions: String
}

extension View {
    /// 页面底部的撤销条，样子和首页记完一笔的撤销条一样
    func categoryMoveUndoBar(_ undo: Binding<CategoryMoveUndo?>, perform: @escaping (CategoryMoveUndo) -> Void) -> some View {
        safeAreaInset(edge: .bottom) {
            if let current = undo.wrappedValue {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.skyDeep)
                        .frame(width: 6, height: 6)
                    Text(current.message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Spacer()
                    Button("撤销") {
                        perform(current)
                        withAnimation(.easeOut(duration: 0.25)) { undo.wrappedValue = nil }
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.skyDeep)
                    .accessibilityIdentifier("undo-category-move")
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 10)
                .background(Capsule(style: .continuous).fill(Color.mist))
                .overlay(Capsule(style: .continuous).stroke(Color.hairlineSoft, lineWidth: 1))
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: current.id) {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.3)) { undo.wrappedValue = nil }
                }
            }
        }
    }
}
