// 自检页里程碑卡最下面的「我的目标」（Pro）：每个目标一行，和里程碑同样的排法；只定天数的是靶心，定了日子的是旗子，
// 有日子的右边是超细的「189 天后」。少于三个时最下面一行「加一个自己的目标」，没有 Pro 时后面标个小 PRO。
// 目标不算进里程碑的达成数：那是大家共用的清单，目标只是自己的。

import SwiftUI

struct FreedomGoalSection: View {
    let results: [FreedomGoalMath.Result]
    /// 没有 Pro 时点哪里都去购买页（由 CheckView 决定）
    let unlocked: Bool
    let onAdd: () -> Void
    let onEdit: (FreedomGoal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !results.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: String(localized: "Mine · 我的目标"))
                    Spacer()
                    Text("\(results.count)/\(FreedomGoalStore.limit)")
                        .font(.system(.caption2, design: .monospaced).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                }
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xs)
                ForEach(Array(results.enumerated()), id: \.element.goal.id) { index, result in
                    Button { onEdit(result.goal) } label: { goalRow(result) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("goal-row-\(index)")
                    if index < results.count - 1 || results.count < FreedomGoalStore.limit {
                        Hairline().padding(.leading, 30)
                    }
                }
            }
            if results.count < FreedomGoalStore.limit {
                Button(action: onAdd) { addRow }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("goal-add")
            }
        }
    }

    /// 虚线圆圈加号，一行字说能做什么；已经有目标时只留一行「再加一个目标」
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
                HStack(spacing: 6) {
                    Text(results.isEmpty ? "加一个自己的目标" : "再加一个目标")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.skyDeep)
                    if !unlocked {
                        Text("PRO")
                            .font(.system(.caption2, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(Color.skyDeep)
                    }
                }
                if results.isEmpty {
                    Text("比如攒够半年的应急金，或者给 GAP 定个日子")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 一行：图标、名字（右边有日子时是还有几天，没日子时是目标天数），日期，进度条，结论，小字
    private func goalRow(_ result: FreedomGoalMath.Result) -> some View {
        let goal = result.goal
        return HStack(alignment: .top, spacing: 12) {
            GoalIcon(dated: goal.deadline != nil, done: goal.deadline == nil && result.enough == true)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(goal.displayName)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.sm)
                    if let daysUntil = result.daysUntil, daysUntil > 0 {
                        GapCountdownNumber(daysUntil: daysUntil, size: 28, unitFont: .caption)
                    } else if goal.deadline == nil, let target = goal.targetDays {
                        Text(FreedomGoal.targetName(target))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.inkFaint)
                    }
                }
                if let deadline = goal.deadline {
                    Text(Self.dateLine(deadline, target: goal.targetDays))
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.inkFaint)
                }
                if let daysUntil = result.daysUntil, daysUntil < 0 {
                    Text("这一天已经过了，点这里换一个日期")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                } else {
                    details(result)
                }
            }
        }
        .padding(.vertical, 12)
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
                Spacer(minLength: Spacing.sm)
                if let line = result.targetLine {
                    Text(line)
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(result.enough == true ? Color.skyDeep : Color.inkMuted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if let note = result.footnote {
                Text(note)
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 「2027年5月2日 · 想撑两年」；不是今年的日子带上年份
    static func dateLine(_ date: Date, target: Int?, now: Date = .now) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        let day = AppLanguage.date(date, template: sameYear ? "MMMd" : "yyyyMMMd")
        guard let target else { return day }
        return String(localized: "\(day) · 想撑\(FreedomGoal.targetName(target))")
    }
}

/// 目标的小图标：只定天数是靶心（达成了换成勾），定了日子是旗子
struct GoalIcon: View {
    let dated: Bool
    let done: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.skyDeep, lineWidth: 1.2)
                .frame(width: 18, height: 18)
            Image(systemName: done ? "checkmark" : dated ? "flag" : "scope")
                .font(.system(size: done ? 10 : 8, weight: .semibold))
                .foregroundStyle(Color.skyDeep)
        }
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
