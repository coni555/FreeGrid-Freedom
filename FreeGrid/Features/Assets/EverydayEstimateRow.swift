// 钱包里的「日常开销 · 每月估算」一行和填它的表单（2.2，免费）。
// 不想天天记账的人填一个每月大约花多少，自由天数就能算；记账的人断档时也用它补空档。算法见 `FreedomMath.burnEstimate`。

import SwiftUI

struct EverydayEstimateRow: View {
    @AppStorage(EverydayEstimate.key, store: AppPreferences.store) private var monthlyEstimate = 0.0
    @State private var editing = false

    var body: some View {
        let estimate = EverydayEstimate.valid(monthlyEstimate)
        Button { editing = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                // 和资产、现金、固定支出同一种小方块；灰色：这是估的，不是账上的钱
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.inkFaint.opacity(0.6))
                    .frame(width: 9, height: 9)
                Text("日常估算")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                Text(estimate == nil ? "不记账也能算自由天数" : "")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Spacing.sm)
                if let estimate {
                    Text("¥\(FinancialFormatting.wholeNumber(estimate)) / 月")
                        .font(.system(size: 17, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                } else {
                    Text("填一个")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.skyDeep)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, Spacing.lg)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.mist))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("everyday-estimate")
        .sheet(isPresented: $editing) {
            EverydayEstimateSheet(estimate: estimate) { monthlyEstimate = $0 ?? 0 }
        }
    }
}

struct EverydayEstimateSheet: View {
    let estimate: Double?
    /// nil 表示清空
    let onSave: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    /// 空着表示清空；填了就要是大于 0 的有效金额
    private var parsed: Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), let valid = EverydayEstimate.valid(value) else { return nil }
        return .some(valid)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: String(localized: "每月日常大约花多少"))
                UnderlinedField(isFocused: focused) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("¥")
                            .font(.system(size: 24, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                        TextField("0", text: $text)
                            .decimalKeyboard()
                            .font(.system(size: 32, weight: .ultraLight, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.ink)
                            .minimumScaleFactor(0.5)
                            .focused($focused)
                            .accessibilityIdentifier("everyday-estimate-field")
                    }
                }
                Text("吃饭、购物、交通这些日常。房租、订阅放在固定支出里，这里不用算。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("还没记过日常支出时，日均按这个数算；记了账就按实际记录。超过 14 天没记，空着的那些天按它补上。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                if parsed == nil {
                    Text("要填大于 0 的数字")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.flame)
                }
                Spacer()
            }
            .padding(Spacing.lg)
            .background(Color.paper)
            .navigationTitle("日常估算")
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
                    .accessibilityIdentifier("everyday-estimate-save")
                }
            }
            .onAppear {
                if let estimate {
                    text = estimate.formatted(.number.grouping(.never).precision(.fractionLength(0...2))
                        .locale(Locale(identifier: "en_US_POSIX")))
                }
                focused = true
            }
        }
        .iosSheetDetents()
    }
}
