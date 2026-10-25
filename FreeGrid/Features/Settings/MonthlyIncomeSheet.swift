// 自检里点「每月有结余」打开：只填每月到手收入。和 GAP 面板里「算得更准」存的是同一个值，空着就按收入记录算。

import SwiftUI

struct MonthlyIncomeSheet: View {
    let enteredIncome: Double?
    /// 近 90 天的收入记录折成每月；记录不够时为 nil
    let recordedIncome: Double?
    /// nil 表示清空、改回按记录算
    let onSave: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var income = ""
    @FocusState private var focused: Bool

    /// 空着表示按记录；填了就必须是有效金额（可以是 0：已经没有收入了）
    private var parsed: Double?? {
        let trimmed = income.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), FinancialFormatting.validAmount(value, allowsZero: true) else { return nil }
        return .some(value)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: String(localized: "每月到手收入"))
                UnderlinedField(isFocused: focused) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("¥")
                            .font(.system(size: 24, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                        TextField(recordedIncome.map { FinancialFormatting.wholeNumber($0) } ?? "0", text: $income)
                            .decimalKeyboard()
                            .font(.system(size: 32, weight: .ultraLight, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.ink)
                            .minimumScaleFactor(0.5)
                            .focused($focused)
                            .accessibilityIdentifier("monthly-income")
                    }
                }
                Text(recordedIncome == nil
                     ? String(localized: "税后到手的工资。被动收入已经算在里面")
                     : String(localized: "不填就按近 90 天的收入记录，每月约 ¥\(FinancialFormatting.wholeNumber(recordedIncome ?? 0))"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                if parsed == nil {
                    Text("收入要填数字")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.flame)
                }
                Spacer()
            }
            .padding(Spacing.lg)
            .background(Color.paper)
            .navigationTitle("每月有结余")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let value = parsed else { return }
                        onSave(value)
                        dismiss()
                    }
                    .disabled(parsed == nil)
                    .foregroundStyle(parsed == nil ? Color.inkFaint : Color.skyDeep)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("monthly-income-save")
                }
            }
            .onAppear {
                if let enteredIncome {
                    income = enteredIncome.formatted(.number.grouping(.never).precision(.fractionLength(0...2))
                        .locale(Locale(identifier: "en_US_POSIX")))
                }
                focused = true
            }
        }
        .iosSheetDetents()
    }
}
