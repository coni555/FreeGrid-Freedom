// 自检页最上面「我的目标」那张卡：没设时邀请设一个；设了时圆环是离目标多近，大数字是还要多少天。点整张卡打开目标面板。

import SwiftUI

struct FreedomGoalCard: View {
    /// nil 表示还没设目标
    let result: FreedomGoalMath.Result?
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VaultCard(emphasis: .high, padding: Spacing.xl) {
                if let result { goal(result) } else { empty }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("gap-goal-card")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            KickerLabel(text: String(localized: "GAP · 我的目标"))
            Text("想攒够能撑多久再走？")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(Color.ink)
            Text("设一个目标，按每月能存下的钱，算还要多少天。")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("设定目标")
                Image(systemName: "arrow.right").font(.system(size: 11))
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(Color.skyDeep)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
            .padding(.top, Spacing.xs)
        }
    }

    private func goal(_ result: FreedomGoalMath.Result) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                KickerLabel(text: String(localized: "GAP · 我的目标"))
                Spacer()
                Text("编辑")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.skyDeep)
            }

            HStack(alignment: .center, spacing: Spacing.lg) {
                ring(result.progress)
                headline(result)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Hairline(color: .hairlineSoft)
                    .padding(.bottom, 4)
                line(goalLine(result))
                if let saving = result.saving { line(FreedomGoalMath.savingText(saving)) }
                if let leave = result.leaveLine {
                    line(leave, color: result.leave?.enough == true ? .skyDeep : .inkMuted)
                }
            }
        }
    }

    private func ring(_ progress: Double) -> some View {
        ZStack {
            Circle().stroke(Color.mist2, lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.skyDeep, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(FinancialFormatting.percentage(progress))
                .font(.system(size: 15, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.ink)
                .minimumScaleFactor(0.6)
                .padding(8)
        }
        .frame(width: 76, height: 76)
        .accessibilityLabel(Text("离目标 \(FinancialFormatting.percentage(progress))"))
    }

    /// 还要多少天时用超细大数字（和首页的大数字同一种字），其余状态写一句话
    @ViewBuilder
    private func headline(_ result: FreedomGoalMath.Result) -> some View {
        switch result.status {
        case .onTheWay(let days, _):
            VStack(alignment: .leading, spacing: 2) {
                Text(days.formatted(.number))
                    .font(.system(size: 52, weight: .ultraLight, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("天后可以走")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
            }
            .accessibilityElement(children: .combine)
        case .reached:
            Text("现在就可以走")
                .font(.system(.title3, design: .rounded).weight(.medium))
                .foregroundStyle(Color.skyDeep)
        default:
            Text(result.statusLine)
                .font(.system(.headline, design: .rounded).weight(.regular))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func goalLine(_ result: FreedomGoalMath.Result) -> String {
        if case .onTheWay(_, let ready) = result.status {
            return String(localized: "撑 \(result.goal.months) 个月 · 预计 \(FreedomMath.depleteDateText(ready))")
        }
        return String(localized: "目标：撑 \(result.goal.months) 个月")
    }

    private func line(_ text: String, color: Color = .inkMuted) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
