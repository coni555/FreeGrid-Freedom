// 编辑资产或现金金额；保存由父页面处理。

import SwiftUI

struct EditBucketSheet: View {

    enum Bucket: String, Identifiable {
        case assets, cash
        var id: String { rawValue }
        var label: String { self == .assets ? "资产" : "现金" }
        var hint: String {
            self == .assets
                ? "锁定的钱 — 定期 / 股票 / 基金 / 不动产等"
                : "可花的钱 — 活期 / 钱包余额 / 微信支付宝"
        }
        var color: Color { self == .assets ? .assetGold : .cashBlue }
        var icon: String { self == .assets ? "lock.fill" : "banknote" }
    }

    let bucket: Bucket
    let currentAmount: Double
    let onSave: (Double) throws -> Void

    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var amount: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // ===== 当前金额参考 =====
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: 4) {
                            Image(systemName: bucket.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(bucket.color)
                            KickerLabel(text: "当前 \(bucket.label)")
                        }
                        Text("¥" + currentAmount.formatted(.number))
                            .font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkMuted)
                    }

                    // ===== 新金额输入 =====
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "新金额")

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("¥")
                                .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                            TextField("0", text: $amount)
                                .decimalKeyboard()
                                .accessibilityIdentifier("bucket-amount-field")
                                .font(.system(size: 40, weight: .ultraLight, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.ink)
                                .focused($fieldFocused)
                                .submitLabel(.done)
                                .onSubmit { save() }
                        }
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

                        // delta 预览: 写新金额后实时显示净值变化
                        if let new = Double(amount),
                           FinancialFormatting.validAmount(new, allowsZero: true),
                           new != currentAmount {
                            HStack(spacing: 4) {
                                Image(systemName: new > currentAmount ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 10))
                                Text("\(new > currentAmount ? "+" : "")\((new - currentAmount).formatted(.number)) 元")
                                    .font(.system(.caption, design: .rounded).monospacedDigit())
                            }
                            .foregroundStyle(new > currentAmount ? Color.skyDeep : Color.inkMuted)
                            .padding(.top, 2)
                        }
                    }

                    // ===== 说明 =====
                    Text(bucket.hint)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("编辑\(bucket.label)")
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
                // 不预填 — 用户看到"当前 ¥X"作为参考再录入新值, 心智更清晰。
                // 自动聚焦让键盘立即弹出, 减少点击次数。
                fieldFocused = true
            }
        }
        .saveErrorAlert($saveError)
        .iosSheetDetents()
    }

    private var isValid: Bool {
        guard let value = Double(amount) else { return false }
        return FinancialFormatting.validAmount(value, allowsZero: true)
    }

    private func save() {
        guard let value = Double(amount),
              FinancialFormatting.validAmount(value, allowsZero: true) else { return }
        do {
            try onSave(value)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
