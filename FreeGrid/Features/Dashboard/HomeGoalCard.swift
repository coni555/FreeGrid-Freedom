// 首页的目标长条（Pro）：和首页的自由天数直接比。左边现在 / 目标，右边还差几天，下面一根进度条；
// 最下面一行是名字，定了日子的右边写还有几天。点长条打开这个目标的面板。

import SwiftUI

struct HomeGoalCard: View {
    let result: FreedomGoalProgress

    var body: some View {
        VaultCard(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    number(result.freedomDaysText ?? (result.enough == true ? "∞" : "—"),
                           unit: "/ \(result.goal.targetDays.formatted(.number)) " + String(localized: "天"), color: .ink)
                    Spacer(minLength: Spacing.sm)
                    if result.enough == true {
                        Text("已达成")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.skyDeep)
                    } else if let short = result.shortText {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("还差")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                            number(short, unit: String(localized: "天"), color: .skyDeep)
                        }
                    }
                }
                if let p = result.progress {
                    CheckProgressBar(progress: p)
                }
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: kicker)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: Spacing.sm)
                    if let countdown {
                        Text(countdown)
                            .font(.system(.caption, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkMuted)
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home-goal-card")
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 「GAP · 5月2日」；没日子的是名字
    private var kicker: String {
        guard let deadline = result.goal.deadline else { return result.goal.displayName }
        return "\(result.goal.displayName) · \(AppLanguage.date(deadline, template: "MMMd"))"
    }

    /// 定了日子时：还有几天、就是今天、已经过了
    private var countdown: String? {
        guard let daysUntil = result.daysUntil else { return nil }
        if daysUntil > 0 {
            return String(localized: "\(daysUntil) 天后")
        }
        return daysUntil == 0 ? String(localized: "就是今天") : String(localized: "这一天已经过了")
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
                .lineLimit(1)
        }
    }
}
