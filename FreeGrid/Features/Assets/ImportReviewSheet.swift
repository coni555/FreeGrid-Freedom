// 导入前确认新增记录、分类与资产处理策略。

import SwiftUI

struct ImportReviewSheet: View {
    let preview: DataIO.ImportPreview
    let onCommit: (DataIO.AssetsImportStrategy, [String: String]) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DataIO.CategoryMapEntry]
    @State private var strategy: DataIO.AssetsImportStrategy = .skipAssets

    init(preview: DataIO.ImportPreview,
         onCommit: @escaping (DataIO.AssetsImportStrategy, [String: String]) -> Void,
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
                    if !entries.isEmpty { categoryCard }
                    strategyCard
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("导入预览")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel(); dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        let map = Dictionary(uniqueKeysWithValues: entries.map { ($0.raw, $0.canonical) })
                        onCommit(strategy, map)
                        dismiss()
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
                KickerLabel(text: "导入预览")
                summaryRow("新增支出", "\(preview.expensesNew.count) 笔")
                summaryRow("新增收入", "\(preview.incomesNew.count) 笔")
                if preview.devicesNew.count > 0 {
                    summaryRow("新增设备", "\(preview.devicesNew.count) 个")
                }
                if preview.passiveSourcesNew.count > 0 {
                    summaryRow("新增被动源", "\(preview.passiveSourcesNew.count) 个")
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
                    summaryRow("库内重复", "\(existingDuplicates) 条")
                }
                if fileDuplicates > 0 {
                    summaryRow("文件内重复", "\(fileDuplicates) 条")
                }
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
                    KickerLabel(text: "分类对齐")
                    Spacer()
                    if reviewCount > 0 {
                        Text("\(reviewCount) 个待确认")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.flame)
                    }
                }
                Text("这些分类不在你的标准分类里(导入数据带来的)。已自动归类的可改,标橙的请确认。")
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
                    Text(entry.wrappedValue.raw)
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
                ForEach(ExpenseCategory.canonical, id: \.self) { c in
                    Text(c).tag(c)
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
                KickerLabel(text: "净值处理")
                summaryRow("备份资产桶", "¥\(money(preview.importedAssets.lockedAssets))")
                summaryRow("备份现金桶", "¥\(money(preview.importedAssets.cash))")
                summaryRow("备份净值", "¥\(money(preview.importedAssets.total))")
                Hairline()
                strategyOption(.skipAssets, "只导入交易", "不动现有现金 / 资产桶")
                Hairline()
                strategyOption(
                    .replace,
                    "替换双桶",
                    "资产 ¥\(money(preview.importedAssets.lockedAssets)) + 现金 ¥\(money(preview.importedAssets.cash))"
                )
                Hairline()
                strategyOption(
                    .addToCash,
                    "加到现金",
                    "现金桶 +¥\(money(preview.importedAssets.total))"
                )
            }
        }
    }

    private func money(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
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
