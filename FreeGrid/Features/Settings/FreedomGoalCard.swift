// 自检页最上面的 GAP 倒计时卡：没设时邀请定一个日期；设了时大数字是还有几天，下面一句那天大约有多少天自由，
// 定了「想撑多久」再加一根进度条。点整张卡打开目标面板。

import SwiftUI

struct FreedomGoalCard: View {
    /// nil 表示还没设目标
    let result: FreedomGoalMath.Result?
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VaultCard(emphasis: .high, padding: Spacing.xl) {
                if let result { countdown(result) } else { empty }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("gap-goal-card")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            KickerLabel(text: "GAP")
            Text("想哪天离开？")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(Color.ink)
            Text("定一个日期，倒数还有几天，看那天有多少天自由。")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("定一个日期")
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

    private func countdown(_ result: FreedomGoalMath.Result) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                KickerLabel(text: "GAP · \(AppLanguage.date(result.goal.leaveDate, template: "yyyyMMMd"))")
                Spacer()
                Text("编辑")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.skyDeep)
            }

            GapCountdownNumber(daysUntil: result.daysUntil)

            // 日子过了就只留换日期的提示，不再推算那天
            if result.daysUntil >= 0 {
                details(result)
            }
        }
    }

    private func details(_ result: FreedomGoalMath.Result) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Hairline(color: .hairlineSoft)
                .padding(.bottom, Spacing.xs)
            Text(result.freedomLine)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.ink)
                .accessibilityIdentifier("gap-freedom-line")
            if let progress = result.progress {
                GapTargetBar(progress: progress, label: result.targetLine, enough: result.enough == true)
            }
            footnote(result)
        }
    }

    /// 最下面一行小字：按每月存多少推算的；不知道收入时提示填上
    @ViewBuilder
    private func footnote(_ result: FreedomGoalMath.Result) -> some View {
        if let saving = result.saving, result.projected {
            note(FreedomGoalMath.savingText(saving))
        } else if case .finite = result.freedom, result.daysUntil > 0 {
            note(String(localized: "填上每月收入，算到那天会有多少"))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

/// 「189 天后」：超细大数字，和首页大数字同一种字。今天、已经过了的日子写一句话
struct GapCountdownNumber: View {
    let daysUntil: Int
    var size: CGFloat = 64

    var body: some View {
        if daysUntil > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(daysUntil.formatted(.number))
                    .font(.system(size: size, weight: .ultraLight, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                // 英文单复数：数字和单位分两种字号显示，只能在这里分开写
                Text(daysUntil == 1 && !AppLanguage.isChinese ? "day" : String(localized: "天后"))
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gap-countdown")
        } else {
            Text(daysUntil == 0 ? "就是今天" : "这一天已经过了，点这里换一个日期")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(daysUntil == 0 ? Color.skyDeep : Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 那天的自由天数占「想撑多久」多少：细进度条，右边写够不够
struct GapTargetBar: View {
    let progress: Double
    let label: String?
    let enough: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.mist2)
                    Capsule()
                        .fill(Color.skyDeep)
                        .frame(width: max(2, geo.size.width * progress))
                }
            }
            .frame(height: 4)
            if let label {
                Text(label)
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(enough ? Color.skyDeep : Color.inkMuted)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityIdentifier("gap-target-line")
            }
        }
    }
}
