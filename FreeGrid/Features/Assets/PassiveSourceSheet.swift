// 新增或编辑月均被动收入源。

import SwiftUI

struct PassiveSourceSheet: View {

    let existing: PassiveSource?
    let onSave: (String, Double) throws -> Void

    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var monthly: String = ""
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { existing != nil }
    private var title: String { isEditing ? "编辑被动源" : "添加被动源" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // 名字
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "名称")
                        TextField("房租 / 股息 / 利息 / 副业 ...", text: $name)
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .focused($nameFocused)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.skyDeep.opacity(0.45), lineWidth: 1)
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.skyFaint.opacity(0.4))
                            )
                    }

                    // 月入
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "月入 (元 / 月)")
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("¥")
                                .font(.system(size: 28, weight: .ultraLight, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                            TextField("0", text: $monthly)
                                .decimalKeyboard()
                                .font(.system(size: 36, weight: .ultraLight, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.ink)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.mossGreen.opacity(0.45), lineWidth: 1)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.mossGreen.opacity(0.08))
                        )

                        // 日均预览
                        if let m = Double(monthly), FinancialFormatting.validAmount(m) {
                            Text("≈ ¥\(String(format: "%.1f", m / 30)) / 天")
                                .font(.system(.caption, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.mossGreen)
                                .padding(.top, 2)
                        }
                    }

                    // 说明
                    Text("被动收入: 不需要持续工作就能稳定获得的收入。每月固定金额, 按 ÷ 30 转日均, 用来计算「被动覆盖率」。")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
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
                nameFocused = !isEditing  // 新增聚焦名字, 编辑不自动弹键盘
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
