// 新增或编辑一项资产（名称 + 金额）；保存由父页面处理。

import SwiftUI

struct AssetItemSheet: View {

    let existing: AssetItem?
    let onSave: (String, Double) throws -> Void

    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var amount: String = ""
    private enum Field { case name, amount }
    @FocusState private var focus: Field?

    private var isEditing: Bool { existing != nil }
    private var title: String { isEditing ? "编辑资产项" : "添加资产项" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "名称")
                        UnderlinedField(isFocused: focus == .name) {
                            TextField("房、车、定期、基金…", text: $name)
                                .font(.system(.title3, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .amount }
                                .accessibilityIdentifier("asset-item-name-field")
                        }
                        Text("最多 \(AssetItemStore.maximumNameCharacters) 个字")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "金额")
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
                        Text("这一项现在值多少钱，资产总数是各项相加")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
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
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    amount = existing.amount.formatted(
                        .number.grouping(.never).precision(.fractionLength(0...2))
                            .locale(Locale(identifier: "en_US_POSIX")))
                }
                focus = isEditing ? nil : .name
            }
        }
        .saveErrorAlert($saveError)
        .iosSheetDetents()
    }

    private var isValid: Bool {
        (try? AssetItemStore.cleanName(name)) != nil
            && Double(amount).map { FinancialFormatting.validAmount($0, allowsZero: true) } == true
    }

    private func save() {
        guard isValid, let value = Double(amount) else { return }
        do {
            try onSave(name, value)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
