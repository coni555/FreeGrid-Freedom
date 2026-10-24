// 新增或编辑一个现金账户（名称 + 余额 + 算不算进自由天数）；保存由父页面处理。
// 新增时可以选这笔钱从哪来：新增的钱让现金总数变大，从已有账户里分出来则总数不变。

import SwiftUI

struct CashAccountSheet: View {

    /// 新增时可以从这里拆出来的一项
    typealias SourceOption = MoneySourcePicker<CashAccountStore.Source>.Option

    let existing: CashAccount?
    var sources: [SourceOption] = []
    /// 现在的总数，写「保存后总数变成多少」用
    var total: Double = 0
    var initialSource: CashAccountStore.Source? = nil
    let onSave: (String, Double, Bool, CashAccountStore.Source?) throws -> Void
    var onDelete: (() throws -> Void)? = nil

    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var source: CashAccountStore.Source?
    @State private var countsInFreedom = true
    @State private var confirmingDelete = false
    private enum Field { case name, amount }
    @FocusState private var focus: Field?

    private var isEditing: Bool { existing != nil }
    private var pickedSource: SourceOption? { sources.first { $0.source == source } }
    private var enteredAmount: Double? {
        Double(amount).flatMap { FinancialFormatting.validAmount($0, allowsZero: true) ? $0 : nil }
    }
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
                            TextField("微信、支付宝、招行卡…", text: $name)
                                .font(.system(.title3, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .amount }
                                .accessibilityIdentifier("cash-account-name-field")
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: String(localized: "余额"))
                        UnderlinedField(isFocused: focus == .amount, accent: .cashBlue) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("¥")
                                    .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                                    .foregroundStyle(Color.inkFaint)
                                TextField("0", text: $amount)
                                    .decimalKeyboard()
                                    .accessibilityIdentifier("cash-account-amount-field")
                                    .font(.system(size: 52, weight: .ultraLight, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Color.ink)
                                    .minimumScaleFactor(0.5)
                                    .focused($focus, equals: .amount)
                            }
                        }
                        if !isEditing, !sources.isEmpty {
                            MoneySourcePicker(options: sources, selection: $source, amount: enteredAmount,
                                              total: total, bucket: String(localized: "现金"),
                                              identifierPrefix: "cash-account")
                                .padding(.top, Spacing.md)
                        }
                    }

                    Toggle(isOn: $countsInFreedom) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("计入自由天数")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.ink)
                            Text("留着不打算动的储蓄可以不计入，只留在净值里。")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Color.inkMuted)
                        }
                    }
                    .tint(Color.skyDeep)
                    .accessibilityIdentifier("cash-account-counts-in-freedom-toggle")

                    if isEditing, onDelete != nil {
                        Button("删除这个账户") { confirmingDelete = true }
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.flame)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("delete-cash-account")
                    }
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(isEditing ? "编辑账户" : "添加账户")
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
                        .accessibilityIdentifier("save-cash-account")
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
                Text("现金总数会少 ¥\((existing?.amount ?? 0).formatted(.number))。记过的账不变。")
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    countsInFreedom = existing.countsInFreedom
                    amount = existing.amount.formatted(
                        .number.grouping(.never).precision(.fractionLength(0...2))
                            .locale(Locale(identifier: "en_US_POSIX")))
                } else {
                    source = initialSource
                }
                focus = isEditing ? nil : .name
            }
        }
        .saveErrorAlert($saveError)
        .iosSheetDetents()
    }

    private var isValid: Bool {
        (try? CashAccountStore.cleanName(name)) != nil && enteredAmount != nil && !exceedsSource
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
