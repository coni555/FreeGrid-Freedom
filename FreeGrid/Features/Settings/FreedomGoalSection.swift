// 自检页里程碑卡最下面的「我的目标」：没设时一行「加一个自己的目标」；设了时和里程碑同样的一行，
// 右边是还有几天，下面一句那天大约有多少天自由，定了「想撑多久」再加一根进度条。点了打开 GAP 面板。
// GAP 不算进里程碑的达成数：那是大家共用的清单，目标只是自己的。

import SwiftUI

struct FreedomGoalSection: View {
    /// nil 表示还没设目标
    let result: FreedomGoalMath.Result?
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            if let result { goalRow(result) } else { addRow }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("gap-goal-row")
    }

    /// 没设：虚线圆圈加号，一行字说能做什么
    private var addRow: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.inkGhost, style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2.5]))
                    .frame(width: 18, height: 18)
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.skyDeep)
            }
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("加一个自己的目标")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.skyDeep)
                Text("比如想 GAP 一年：定个离开的日子，看那天的自由天数够不够")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 设了：组头「我的目标 · 编辑」，下面一行和里程碑同样的排法，右边是超细的「189 天后」
    private func goalRow(_ result: FreedomGoalMath.Result) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                KickerLabel(text: String(localized: "Mine · 我的目标"))
                Spacer()
                Text("编辑")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.skyDeep)
            }
            .padding(.top, Spacing.lg)

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.skyDeep, lineWidth: 1.2)
                        .frame(width: 18, height: 18)
                    Image(systemName: "flag")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.skyDeep)
                }
                .padding(.top, 3)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Self.leaveTitle(result.goal.leaveDate))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Spacer(minLength: Spacing.sm)
                        if result.daysUntil > 0 {
                            GapCountdownNumber(daysUntil: result.daysUntil, size: 30, unitFont: .caption)
                        }
                    }
                    if result.daysUntil >= 0 {
                        details(result)
                    } else {
                        Text("这一天已经过了，点这里换一个日期")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        }
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func details(_ result: FreedomGoalMath.Result) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if result.daysUntil == 0 {
                Text("就是今天")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.skyDeep)
            }
            if let progress = result.progress {
                CheckProgressBar(progress: progress)
                    .padding(.vertical, 2)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(result.freedomLine)
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkMuted)
                    .accessibilityIdentifier("gap-freedom-line")
                Spacer(minLength: Spacing.sm)
                if let line = result.targetLine {
                    Text(line)
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(result.enough == true ? Color.skyDeep : Color.inkMuted)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityIdentifier("gap-target-line")
                }
            }
            if let note = Self.footnote(result) {
                Text(note)
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 「5 月 1 日离开」；不是今年的日子带上年份
    static func leaveTitle(_ date: Date, now: Date = .now) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        let day = AppLanguage.date(date, template: sameYear ? "MMMd" : "yyyyMMMd")
        return String(localized: "\(day)离开")
    }

    /// 最下面一行小字：按每月存多少推算的；不知道收入时提示填上。首页的 GAP 卡也用
    static func footnote(_ result: FreedomGoalMath.Result) -> String? {
        if let saving = result.saving, result.projected { return FreedomGoalMath.savingText(saving) }
        if case .finite = result.freedom, result.daysUntil > 0 { return String(localized: "填上每月收入，算到那天会有多少") }
        return nil
    }
}

/// 「189 天后」：超细大数字，和首页大数字同一种字。今天、已经过了的日子写一句话
struct GapCountdownNumber: View {
    let daysUntil: Int
    var size: CGFloat = 64
    var unitFont: Font.TextStyle = .title3

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
                    .font(.system(unitFont, design: .rounded))
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
