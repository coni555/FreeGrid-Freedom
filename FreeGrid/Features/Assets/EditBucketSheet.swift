// 编辑资产或现金金额；保存由父页面处理。

import SwiftUI

struct EditBucketSheet: View {

    enum Bucket: String, Identifiable {
        case assets, cash
        var id: String { rawValue }
        var label: String { self == .assets ? "资产" : "现金" }
        var hint: String {
            self == .assets
                ? "锁定的钱：定期、股票、基金、不动产等"
                : "可花的钱：活期、钱包余额、微信、支付宝"
        }
        var color: Color { self == .assets ? .assetGold : .cashBlue }
        var icon: String { self == .assets ? "lock.fill" : "banknote" }
    }

    let bucket: Bucket
    let currentAmount: Double
    let onSave: (Double) throws -> Void
    /// 资产桶才有：「拆成多项」（Pro），弹窗收起后由父页面接着开添加资产项
    var onOpenItems: (() -> Void)? = nil

    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var amount: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // 是哪一桶、这一桶指什么
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: bucket.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(bucket.color)
                            KickerLabel(text: bucket.label)
                        }
                        Text(bucket.hint)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // 现在的金额就是输入框里的灰色占位: 直接打新数字盖掉它, 不用先看一眼再抄一遍
                    UnderlinedField(isFocused: fieldFocused, accent: bucket.color) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("¥")
                                .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                            TextField(currentAmount.formatted(.number), text: $amount)
                                .decimalKeyboard()
                                .accessibilityIdentifier("bucket-amount-field")
                                .font(.system(size: 52, weight: .ultraLight, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.ink)
                                .minimumScaleFactor(0.5)
                                .focused($fieldFocused)
                                .submitLabel(.done)
                                .onSubmit { save() }
                        }
                    }
                    .padding(.top, Spacing.sm)

                    // 细线下面一行: 没输入时说明灰字是什么, 输入后显示和现在差多少
                    Group {
                        if let new = Double(amount),
                           FinancialFormatting.validAmount(new, allowsZero: true),
                           new != currentAmount {
                            HStack(spacing: 4) {
                                Image(systemName: new > currentAmount ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 10))
                                Text("比现在\(new > currentAmount ? "多" : "少") ¥\(abs(new - currentAmount).formatted(.number))")
                                    .font(.system(.caption, design: .rounded).monospacedDigit())
                            }
                            .foregroundStyle(new > currentAmount ? Color.skyDeep : Color.inkMuted)
                        } else {
                            Text("现在是 ¥\(currentAmount.formatted(.number))，输入新的金额替换它")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                        }
                    }

                    if let onOpenItems {
                        Hairline()
                        Button {
                            onOpenItems()
                            dismiss()
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Text("拆成多项")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.ink)
                                if !ProFeatures.canManageAssetItems {
                                    Text("PRO")
                                        .font(.system(.caption2, design: .monospaced))
                                        .tracking(2)
                                        .foregroundStyle(Color.skyDeep)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.inkGhost)
                            }
                            .padding(.vertical, Spacing.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("split-assets-into-items")
                    }
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
                // 不预填: 现在的金额是输入框的占位, 一打字就被替换。
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
