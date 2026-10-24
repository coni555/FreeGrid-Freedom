// 新增或编辑一项资产（名称 + 金额 + 算不算进自由天数）；保存由父页面处理。
// 新增时可以选这笔钱从哪来：新增的钱让总数变大，从已有一项里拆出来则总数不变。

import SwiftUI

struct AssetItemSheet: View {

    /// 新增时可以从这里拆出来的一项
    typealias SourceOption = MoneySourcePicker<AssetItemStore.Source>.Option

    let existing: AssetItem?
    /// 新增时可选的来源；为空时不显示这一行
    var sources: [SourceOption] = []
    /// 现在的总数，写「保存后总数变成多少」用
    var total: Double = 0
    /// 打开时默认选中的来源（拆分时是原来的总数）
    var initialSource: AssetItemStore.Source? = nil
    let onSave: (String, Double, Bool, AssetItemStore.Source?) throws -> Void
    /// 编辑时才有：删除这一项
    var onDelete: (() throws -> Void)? = nil

    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var amount: String = ""
    @State private var countsInFreedom: Bool = true
    @State private var source: AssetItemStore.Source?
    @State private var confirmingDelete = false
    private enum Field { case name, amount }
    @FocusState private var focus: Field?

    private var isEditing: Bool { existing != nil }
    private var title: String { isEditing ? String(localized: "编辑资产项") : String(localized: "添加资产项") }
    private var pickedSource: SourceOption? { sources.first { $0.source == source } }
    private var enteredAmount: Double? {
        Double(amount).flatMap { FinancialFormatting.validAmount($0, allowsZero: true) ? $0 : nil }
    }
    /// 从某一项拆出来、但填的比那一项还多
    private var exceedsSource: Bool {
        guard let pickedSource, let enteredAmount else { return false }
        return enteredAmount > pickedSource.amount + FinancialLimits.assetChecksumTolerance
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: String(localized: "名称"))
                        UnderlinedField(isFocused: focus == .name) {
                            TextField("房、车、定期、基金…", text: $name)
                                .font(.system(.title3, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .amount }
                                .accessibilityIdentifier("asset-item-name-field")
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: String(localized: "金额"))
                        UnderlinedField(isFocused: focus == .amount, accent: .assetGold) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("¥")
                                    .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                                    .foregroundStyle(Color.inkFaint)
                                TextField("0", text: $amount)
                                    .decimalKeyboard()
                                    .accessibilityIdentifier("asset-item-amount-field")
                                    .font(.system(size: 52, weight: .ultraLight, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Color.ink)
                                    .minimumScaleFactor(0.5)
                                    .focused($focus, equals: .amount)
                            }
                        }
                        if !isEditing, !sources.isEmpty {
                            MoneySourcePicker(options: sources, selection: $source, amount: enteredAmount,
                                              total: total, bucket: String(localized: "资产"),
                                              identifierPrefix: "asset-item")
                                .padding(.top, Spacing.md)
                        }
                    }

                    Toggle(isOn: $countsInFreedom) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("计入自由天数")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.ink)
                            Text("房、车这类一时卖不掉的可以不计入，只留在净值里。")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Color.inkMuted)
                        }
                    }
                    .tint(Color.skyDeep)
                    .accessibilityIdentifier("asset-item-counts-in-freedom-toggle")

                    if isEditing, onDelete != nil {
                        Button("删除这一项") { confirmingDelete = true }
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.flame)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("delete-asset-item")
                    }
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(title)
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isValid)
                        .foregroundStyle(isValid ? Color.skyDeep : Color.inkFaint)
                        .fontWeight(.medium)
                        .accessibilityIdentifier("save-asset-item")
                }
            }
            .confirmationDialog("删除「\(existing?.name ?? "")」？", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
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
                Text("资产总数会少 ¥\((existing?.amount ?? 0).formatted(.number))。")
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    amount = existing.amount.formatted(
                        .number.grouping(.never).precision(.fractionLength(0...2))
                            .locale(Locale(identifier: "en_US_POSIX")))
                    countsInFreedom = existing.countsInFreedom
                } else {
                    countsInFreedom = true
                    source = initialSource
                }
                focus = isEditing ? nil : .name
            }
        }
        .saveErrorAlert($saveError)
        .iosSheetDetents()
    }

    // MARK: - 保存

    private var isValid: Bool {
        (try? AssetItemStore.cleanName(name)) != nil && enteredAmount != nil && !exceedsSource
    }

    private func save() {
        guard isValid, let value = enteredAmount else { return }
        do {
            try onSave(name, value, countsInFreedom, isEditing ? nil : source)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
