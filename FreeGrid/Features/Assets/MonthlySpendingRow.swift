// 钱包里的「每月花销」一行和填它的表单（2.2，免费）。
// 不想天天记账的人填这个月一共花了多少（固定支出也算在里面），自由天数就能算；记账的人断档时也用它补空档。
// 这一行什么时候出现见 `MonthlySpending.showsRow`，算法见 `FreedomMath.burnEstimate`。

import SwiftUI

struct MonthlySpendingRow: View {
    /// 最后一笔之后超过 14 天的那几天；没有断档时是 0
    let gapDays: Int

    @AppStorage(MonthlySpending.key, store: AppPreferences.store) private var monthlySpending = 0.0
    @State private var editing = false

    var body: some View {
        let monthly = MonthlySpending.valid(monthlySpending)
        Button { editing = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                // 和资产、现金、固定支出同一种小方块；灰色：这是估的，不是账上的钱
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.inkFaint.opacity(0.6))
                    .frame(width: 9, height: 9)
                Text("每月花销")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                if monthly == nil {
                    Text(gapDays > 0
                         ? String(localized: "\(gapDays + FreedomMath.burnGraceDays) 天没记了")
                         : String(localized: "不记账也能算"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: Spacing.sm)
                if let monthly {
                    Text("¥\(FinancialFormatting.wholeNumber(monthly)) / 月")
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
        .accessibilityIdentifier("monthly-spending")
        .sheet(isPresented: $editing) { MonthlySpendingSheet() }
    }
}

/// 首页、钱包、起步引导都打开这一张。只问一个数，不提固定支出，也不讲算法（用户 2026-10-30 定）
struct MonthlySpendingSheet: View {
    @AppStorage(MonthlySpending.key, store: AppPreferences.store) private var monthlySpending = 0.0
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    /// 空着表示清空；填了就要是大于 0 的有效金额
    private var parsed: Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), let valid = MonthlySpending.valid(value) else { return nil }
        return .some(valid)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: String(localized: "这个月一共花了多少钱？"))
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
                            .accessibilityIdentifier("monthly-spending-field")
                    }
                }
                Text("记下你的实际支出。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
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
            .navigationTitle("每月花销")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let value = parsed else { return }
                        monthlySpending = value ?? 0
                        dismiss()
                    }
                    .disabled(parsed == nil)
                    .foregroundStyle(parsed == nil ? Color.inkFaint : Color.skyDeep)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("monthly-spending-save")
                }
            }
            .onAppear {
                if let monthly = MonthlySpending.valid(monthlySpending) {
                    text = monthly.formatted(.number.grouping(.never).precision(.fractionLength(0...2))
                        .locale(Locale(identifier: "en_US_POSIX")))
                }
                focused = true
            }
        }
        .iosSheetDetents()
    }
}
