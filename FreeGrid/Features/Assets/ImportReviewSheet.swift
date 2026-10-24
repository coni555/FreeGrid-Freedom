// 导入前确认新增记录、分类与资产处理策略。

import SwiftUI

struct ImportReviewSheet: View {
    let preview: DataIO.ImportPreview
    let onCommit: (DataIO.AssetsImportStrategy, [String: String], Set<Int>) throws -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?
    @State private var entries: [DataIO.CategoryMapEntry]
    @State private var strategy: DataIO.AssetsImportStrategy = .skipAssets
    @State private var skippedSuspectedExpenses: Set<Int> = []

    init(preview: DataIO.ImportPreview,
         onCommit: @escaping (DataIO.AssetsImportStrategy, [String: String], Set<Int>) throws -> Void,
         onCancel: @escaping () -> Void) {
        self.preview = preview
        self.onCommit = onCommit
        self.onCancel = onCancel
        _entries = State(initialValue: preview.categoryEntries)
    }

    private var reviewCount: Int { entries.filter { $0.needsReview }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    summaryCard
                    if !preview.suspectedExpenseIndices.isEmpty { suspectedDuplicatesCard }
                    if !entries.isEmpty { categoryCard }
                    strategyCard
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("导入预览")
            .inlineNavTitle()
            .saveErrorAlert($saveError)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel(); dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        let map = Dictionary(uniqueKeysWithValues: entries.map { ($0.raw, $0.canonical) })
                        do {
                            try onCommit(strategy, map, skippedSuspectedExpenses)
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                    .fontWeight(.medium)
                    .foregroundStyle(Color.skyDeep)
                }
            }
        }
    }

    // ===== 摘要 =====
    private var summaryCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                KickerLabel(text: String(localized: "导入预览"))
                summaryRow(String(localized: "新增支出"), String(localized: "\(preview.expensesNew.count - skippedSuspectedExpenses.count) 笔"))
                summaryRow(String(localized: "新增收入"), String(localized: "\(preview.incomesNew.count) 笔"))
                if preview.devicesNew.count > 0 {
                    summaryRow(String(localized: "新增设备"), String(localized: "\(preview.devicesNew.count) 个"))
                }
                if preview.passiveSourcesNew.count > 0 {
                    summaryRow(String(localized: "新增被动收入"), String(localized: "\(preview.passiveSourcesNew.count) 个"))
                }
                let existingDuplicates = preview.expenseDuplicates.existing
                    + preview.incomeDuplicates.existing
                    + preview.deviceDuplicates.existing
                    + preview.passiveSourceDuplicates.existing
                let fileDuplicates = preview.expenseDuplicates.inFile
                    + preview.incomeDuplicates.inFile
                    + preview.deviceDuplicates.inFile
                    + preview.passiveSourceDuplicates.inFile
                if existingDuplicates > 0 {
                    summaryRow(String(localized: "账本里已有，跳过"), String(localized: "\(existingDuplicates) 条"))
                }
                if fileDuplicates > 0 {
                    summaryRow(String(localized: "备份里重复，跳过"), String(localized: "\(fileDuplicates) 条"))
                }
            }
        }
    }

    private var suspectedDuplicatesCard: some View {
        VaultCard {
            LazyVStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: String(localized: "可能重复 · 请核对"))
                Text("这几笔可能已经导入过。是同一笔的，关掉它的开关。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                ForEach(preview.suspectedExpenseIndices, id: \.self) { index in
                    let record = preview.expensesNew[index]
                    Toggle(isOn: Binding(
                        get: { !skippedSuspectedExpenses.contains(index) },
                        set: { keep in
                            if keep { skippedSuspectedExpenses.remove(index) }
                            else { skippedSuspectedExpenses.insert(index) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("保留 · \(ExpenseCategory.displayName(record.category)) · ¥\(money(record.amount))")
                            Text(record.date, format: .dateTime.year().month().day())
                            Text(record.note).lineLimit(2)
                        }
                        .font(.system(.caption, design: .rounded))
                    }
                    .accessibilityIdentifier("keep-suspected-expense-\(index)")
                }
                summaryRow(String(localized: "手动跳过"), String(localized: "\(skippedSuspectedExpenses.count) 笔"))
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color.inkMuted)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Color.ink)
        }
    }

    // ===== 分类对齐 =====
    private var categoryCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: String(localized: "分类对齐"))
                    Spacer()
                    if reviewCount > 0 {
                        Text("\(reviewCount) 个待确认")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.flame)
                    }
                }
                Text("备份中的自定义分类可以保留原名，也可以归入已有分类。标橙的旧分类请确认。")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)

                ForEach($entries) { $entry in
                    Hairline()
                    categoryRow($entry)
                }
            }
        }
    }

    private func categoryRow(_ entry: Binding<DataIO.CategoryMapEntry>) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if entry.wrappedValue.needsReview {
                        Circle().fill(Color.flame).frame(width: 6, height: 6)
                    }
                    Text(ExpenseCategory.displayName(entry.wrappedValue.raw))
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                }
                Text("\(entry.wrappedValue.count) 笔 · ¥\(FinancialFormatting.wholeNumber(entry.wrappedValue.total))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkGhost)
            Picker("", selection: entry.canonical) {
                if !preview.categoryNames.contains(entry.wrappedValue.raw) {
                    Text("保留：\(entry.wrappedValue.raw)").tag(entry.wrappedValue.raw)
                }
                ForEach(preview.categoryNames, id: \.self) { c in
                    Text(ExpenseCategory.displayName(c)).tag(c)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.skyDeep)
        }
    }

    // ===== 净值策略 =====
    private var strategyCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: String(localized: "资产和现金怎么办"))
                summaryRow(String(localized: "备份里的资产"), "¥\(money(preview.importedAssets.lockedAssets))")
                summaryRow(String(localized: "备份里的现金"), "¥\(money(preview.importedAssets.cash))")
                summaryRow(String(localized: "备份里的净值"), "¥\(money(preview.importedAssets.total))")
                Hairline()
                strategyOption(.skipAssets, String(localized: "只导入收支记录"), String(localized: "现在的资产和现金不变"))
                Hairline()
                strategyOption(
                    .replace,
                    String(localized: "换成备份里的"),
                    String(localized: "资产 ¥\(money(preview.importedAssets.lockedAssets)) + 现金 ¥\(money(preview.importedAssets.cash))") + replaceItemsNote
                )
                Hairline()
                strategyOption(
                    .addToCash,
                    String(localized: "加进现金"),
                    String(localized: "现金 +¥\(money(preview.importedAssets.total))")
                )
            }
        }
    }

    private func money(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// 资产项跟着资产桶一起被替换：备份里有就恢复，没有而现在有就合并成总数
    private var replaceItemsNote: String {
        if !preview.importedAssetItems.isEmpty {
            return String(localized: "，含 \(preview.importedAssetItems.count) 个资产项")
        }
        if preview.currentAssetItemCount > 0 {
            return String(localized: "；现有 \(preview.currentAssetItemCount) 个资产项会并成一个总数")
        }
        return ""
    }

    private func strategyOption(_ s: DataIO.AssetsImportStrategy, _ title: String, _ desc: String) -> some View {
        Button {
            strategy = s
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: strategy == s ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(strategy == s ? Color.skyDeep : Color.inkGhost)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                    Text(desc)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
