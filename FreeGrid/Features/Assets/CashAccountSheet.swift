// 新增或编辑一个现金账户（名称 + 余额）；保存由父页面处理。
// 新增时可以选这笔钱从哪来：新的钱让现金总数变大，从已有账户里分出来则总数不变。

import SwiftUI

struct CashAccountSheet: View {

    struct SourceOption: Identifiable {
        let source: CashAccountStore.Source
        let name: String
        let amount: Double
        var id: String {
            switch source {
            case .unsplitTotal: return "total"
            case .account(let id): return id.uuidString
            }
        }
    }

    let existing: CashAccount?
    var sources: [SourceOption] = []
    var initialSource: CashAccountStore.Source? = nil
    let onSave: (String, Double, CashAccountStore.Source?) throws -> Void
    var onDelete: (() throws -> Void)? = nil

    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var source: CashAccountStore.Source?
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
                        KickerLabel(text: "名称")
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
                        KickerLabel(text: "余额")
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
                            sourceMenu
                        }
                    }

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

    private var sourceMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                Picker("从哪来", selection: $source) {
                    Text("新的钱").tag(CashAccountStore.Source?.none)
                    ForEach(sources) { option in
                        Text("从「\(option.name)」分出 · ¥\(option.amount.formatted(.number))")
                            .tag(Optional(option.source))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(pickedSource.map { "从「\($0.name)」分出，现金总数不变" } ?? "新的钱，现金总数会增加")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .accessibilityIdentifier("cash-account-source-menu")
            if exceedsSource, let pickedSource {
                Text("「\(pickedSource.name)」只有 ¥\(pickedSource.amount.formatted(.number))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.flame)
            }
        }
    }

    private var isValid: Bool {
        (try? CashAccountStore.cleanName(name)) != nil && enteredAmount != nil && !exceedsSource
    }

    private func save() {
        guard isValid, let value = enteredAmount else { return }
        do {
            try onSave(name, value, isEditing ? nil : source)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
