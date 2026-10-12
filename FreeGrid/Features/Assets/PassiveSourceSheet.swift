// 新增或编辑月均被动收入源。

import SwiftUI

struct PassiveSourceSheet: View {

    let existing: PassiveSource?
    let onSave: (String, Double) throws -> Void

    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var monthly: String = ""
    private enum Field { case name, monthly }
    @FocusState private var focus: Field?

    private var isEditing: Bool { existing != nil }
    private var title: String { isEditing ? "编辑被动源" : "添加被动源" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // 名字
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "名称")
                        UnderlinedField(isFocused: focus == .name) {
                            TextField("房租、股息、利息、副业…", text: $name)
                                .font(.system(.title3, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .monthly }
                        }
                    }

                    // 月入
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "每月收入")
                        UnderlinedField(isFocused: focus == .monthly, accent: .mossGreen) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("¥")
                                    .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                                    .foregroundStyle(Color.inkFaint)
                                TextField("0", text: $monthly)
                                    .decimalKeyboard()
                                    .accessibilityIdentifier("passive-monthly-field")
                                    .font(.system(size: 52, weight: .ultraLight, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Color.ink)
                                    .minimumScaleFactor(0.5)
                                    .focused($focus, equals: .monthly)
                            }
                        }

                        // 细线下面一行: 输入后换算成每天多少
                        if let m = Double(monthly), FinancialFormatting.validAmount(m) {
                            Text("相当于每天 ¥\(String(format: "%.1f", m / 30))")
                                .font(.system(.caption, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.mossGreen)
                        } else {
                            Text("不用持续工作也能稳定拿到的钱，按每月的金额填")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                if let e = existing {
                    name = e.name
                    monthly = String(format: "%g", e.monthlyAmount)
                }
                focus = isEditing ? nil : .name  // 新增聚焦名字, 编辑不自动弹键盘
            }
        }
        .saveErrorAlert($saveError)
        .iosSheetDetents()
    }

    private var isValid: Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n.count <= FinancialLimits.nameCharacters,
              let monthlyAmount = Double(monthly) else { return false }
        return FinancialFormatting.validAmount(monthlyAmount)
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n.count <= FinancialLimits.nameCharacters,
              let monthlyAmount = Double(monthly),
              FinancialFormatting.validAmount(monthlyAmount) else { return }
        do {
            try onSave(n, monthlyAmount)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
