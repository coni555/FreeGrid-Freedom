// 首页的 GAP 长条：和今日对比同一种排法。左边还有几天离开，中间一根箭头线，右边那天大约有多少天自由，下面一行小字是按什么算的。
// 还没设 GAP 时是一句邀请；点长条打开 GAP 面板。

import SwiftUI

struct HomeGapCard: View {
    /// nil 表示还没设 GAP
    let result: FreedomGoalMath.Result?

    var body: some View {
        VaultCard(padding: Spacing.lg) {
            if let result, result.daysUntil > 0 {
                countdown(result)
            } else if let result {
                Text(result.daysUntil == 0 ? "GAP · 就是今天" : "这一天已经过了，点这里换一个日期")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(result.daysUntil == 0 ? Color.skyDeep : Color.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                invite
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func countdown(_ result: FreedomGoalMath.Result) -> some View {
        VStack(spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    number(result.daysUntil.formatted(.number),
                           unit: result.daysUntil == 1 && !AppLanguage.isChinese ? "day" : String(localized: "天后"),
                           color: .ink)
                    KickerLabel(text: "GAP · \(AppLanguage.date(result.goal.leaveDate, template: "MMMd"))")
                }

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.skyDeep)
                        .frame(height: 1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(Color.skyDeep)
                        .padding(.leading, -3)
                }
                .frame(minWidth: 24)

                VStack(alignment: .trailing, spacing: 2) {
                    number(rightValue(result), unit: String(localized: "天"), color: .skyDeep)
                    KickerLabel(text: result.projected ? String(localized: "那天的自由") : String(localized: "现在的自由"))
                }
            }
            if let note = FreedomGoalSection.footnote(result) {
                Text(note)
                    .font(.system(.footnote, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-gap-countdown")
    }

    /// 那天的自由天数；被动收入盖住开销时没有尽头
    private func rightValue(_ result: FreedomGoalMath.Result) -> String {
        if case .covered = result.freedom { return "∞" }
        return result.freedomDaysText ?? "—"
    }

    private func number(_ value: String, unit: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .thin, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
    }

    private var invite: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                KickerLabel(text: "GAP")
                Text("想哪天离开？")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
            }
            Spacer(minLength: Spacing.sm)
            HStack(spacing: 6) {
                Text("定一个日期")
                Image(systemName: "arrow.right").font(.system(size: 11))
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.skyDeep)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
        }
    }
}
