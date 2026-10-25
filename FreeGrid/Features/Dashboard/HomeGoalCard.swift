// 首页的目标长条（Pro），和今日对比同一种排法，按目标填了什么分三种：
// 只填天数：左边现在 / 目标，右边还差几天，下面一根进度条和每月多几天；
// 只填日子：左边还有几天，中间一根箭头线，右边那天大约有多少天自由；
// 两项都填：同上，右边写成「641 / 730 天」，下面进度条和还差几天。点长条打开这个目标的面板。

import SwiftUI

struct HomeGoalCard: View {
    let result: FreedomGoalMath.Result

    var body: some View {
        VaultCard(padding: Spacing.lg) {
            Group {
                if let daysUntil = result.daysUntil {
                    if daysUntil > 0 {
                        countdown(daysUntil)
                    } else {
                        Text(daysUntil == 0 ? String(localized: "\(result.goal.displayName) · 就是今天")
                                            : String(localized: "\(result.goal.displayName) · 这一天已经过了，点这里换一个日期"))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(daysUntil == 0 ? Color.skyDeep : Color.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    progress
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home-goal-card")
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - 只填天数

    private var progress: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                number(result.freedomDaysText ?? (isCovered ? "∞" : "—"),
                       unit: result.goal.targetDays.map { "/ \($0.formatted(.number)) " + String(localized: "天") } ?? "",
                       color: .ink)
                Spacer(minLength: Spacing.sm)
                if result.enough == true {
                    Text("已达成")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.skyDeep)
                } else if let short = shortfall {
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
                Spacer(minLength: Spacing.sm)
                if let note = result.footnote {
                    Text(note)
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    // MARK: - 有日子

    private func countdown(_ daysUntil: Int) -> some View {
        VStack(spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    number(daysUntil.formatted(.number),
                           unit: daysUntil == 1 && !AppLanguage.isChinese ? "day" : String(localized: "天后"),
                           color: .ink)
                    // 名字长时缩小，不折成两行
                    KickerLabel(text: kicker)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .layoutPriority(1)

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
                    number(result.freedomDaysText ?? (isCovered ? "∞" : "—"),
                           unit: result.goal.targetDays.map { "/ \($0.formatted(.number)) " + String(localized: "天") }
                               ?? String(localized: "天"),
                           color: .skyDeep)
                    KickerLabel(text: result.goal.targetDays.map { String(localized: "想撑\(FreedomGoal.targetName($0))") }
                                ?? (result.projected ? String(localized: "那天的自由") : String(localized: "现在的自由")))
                }
            }
            if let p = result.progress, result.goal.targetDays != nil {
                CheckProgressBar(progress: p)
            }
            if let note = bottomLine {
                Text(note)
                    .font(.system(.footnote, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// 有日子时最下面一行：设了天数先写还差几天，再写按什么算的
    private var bottomLine: String? {
        let parts = [result.enough == false ? result.targetLine : nil, result.footnote].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - 小件

    /// 「GAP · 5月2日」；没日子的是名字
    private var kicker: String {
        guard let deadline = result.goal.deadline else { return result.goal.displayName }
        return "\(result.goal.displayName) · \(AppLanguage.date(deadline, template: "MMMd"))"
    }

    private var isCovered: Bool {
        if case .covered = result.freedom { return true }
        return false
    }

    private var shortfall: String? {
        guard let target = result.goal.targetDays, case .finite(let days) = result.freedom else { return nil }
        return FinancialFormatting.wholeNumber(max(0, Double(target) - days).rounded(.up))
    }

    private func number(_ value: String, unit: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .thin, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
            }
        }
    }
}
