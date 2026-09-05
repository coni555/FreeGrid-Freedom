// 所有交易预览共用的显示：金额带货币符号，自由天数每一端都带单位。

import SwiftUI

struct TransactionImpactView: View {
    let impact: TransactionImpact

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ImpactRow(
                label: impact.kind == .expense ? "KILL 1 净值" : "GAIN 1 净值",
                from: FinancialFormatting.yuan(impact.before.netWorth),
                to: FinancialFormatting.yuan(impact.newNetWorth),
                delta: FinancialFormatting.signedYuan(impact.cashChange),
                color: changeColor(impact.cashChange)
            )
            if impact.kind == .expense {
                let burnChange = impact.newDailyBurn - impact.before.dailyBurn
                ImpactRow(
                    label: "KILL 2 日均",
                    from: FinancialFormatting.yuan(impact.before.dailyBurn, precision: 1),
                    to: FinancialFormatting.yuan(impact.newDailyBurn, precision: 2),
                    delta: FinancialFormatting.signedYuan(burnChange, precision: 2),
                    color: changeColor(-burnChange)
                )
            }
            ImpactRow(
                label: impact.kind == .expense ? "KILL 3 自由天数" : "GAIN 2 自由天数",
                from: FreedomMath.freedomDescription(impact.before.freedom),
                to: FreedomMath.freedomDescription(impact.newFreedom),
                delta: FinancialFormatting.daysChange(impact.freedomChange),
                color: changeColor(impact.freedomChange ?? .nan)
            )
            if impact.changesTrackingStart {
                Text("补录提前了追踪起点，日均消费与自由天数按新的统计区间重算。")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
            }
        }
        .padding(.vertical, 4)
    }

    private func changeColor(_ value: Double) -> Color {
        guard value.isFinite, value != 0 else { return .inkMuted }
        return value > 0 ? .skyDeep : .flame
    }
}

private struct ImpactRow: View {
    let label: String
    let from: String
    let to: String
    let delta: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KickerLabel(text: label)
            HStack {
                Text("\(from) → \(to)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.ink)
                Spacer()
                Text(delta)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(color)
            }
        }
    }
}
