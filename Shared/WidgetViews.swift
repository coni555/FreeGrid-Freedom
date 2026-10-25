// 小组件长什么样。小组件和 App 两边都编译：小组件拿来显示，App 的测试拿来出图对比（`_local` 下的截图脚本）。
// 沿用 App 的视觉：等宽大写小标签、超细圆体大数字、1 像素细线，颜色用 ColorTokens。
// 这里不写字面文字，字全从 `WidgetSnapshot` 来（App 按界面语言写好的）；系统的背景、点击地址由小组件那边加。

#if os(iOS)
import SwiftUI
import WidgetKit

// MARK: - 零件

/// 等宽大写小标签，和 App 里的 KickerLabel 一样，只是小组件里字号固定
struct WidgetKicker: View {
    let text: String
    var color: Color = .inkFaint

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// 超细圆体大数字
struct WidgetNumber: View {
    let text: String
    var size: CGFloat
    var color: Color = .ink

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .ultraLight, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .widgetAccentable()
    }
}

/// 进度：一条细线底，走过的部分用天空蓝，够了换绿色
struct WidgetProgressLine: View {
    let progress: Double?
    var done = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.hairline).frame(height: 2)
                Capsule().fill(done ? Color.mossGreen : Color.skyDeep)
                    .frame(width: proxy.size.width * min(1, max(0, progress ?? 0)), height: 2)
                    .widgetAccentable()
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 4)
    }
}

private let captionFont = Font.system(size: 12, weight: .regular, design: .rounded)
private let noteFont = Font.system(size: 11, weight: .regular, design: .rounded)

extension WidgetSnapshot.Freedom {
    /// 被动收入盖住开销时数字用绿色，和首页一样
    var numberColor: Color { state == .covered ? .mossGreen : .ink }
}

// MARK: - 自由天数（免费）

/// 桌面小号：小标签、大数字、一行说明
struct FreedomSmallView: View {
    let freedom: WidgetSnapshot.Freedom
    /// 算到的最后一天也过了时写一句，提醒打开 App
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetKicker(text: freedom.kicker, color: .skyDeep)
            Spacer(minLength: 0)
            WidgetNumber(text: freedom.value, size: 64, color: freedom.numberColor)
                .padding(.bottom, -4)
            Text(freedom.caption)
                .font(captionFont)
                .foregroundStyle(Color.inkMuted)
                .lineLimit(2)
            if let note {
                Text(note).font(noteFont).foregroundStyle(Color.inkFaint).lineLimit(1).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// 锁屏圆形：数字和单位
struct FreedomCircularView: View {
    let freedom: WidgetSnapshot.Freedom

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text(freedom.value)
                    .font(.system(size: 22, weight: .light, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !freedom.unit.isEmpty {
                    Text(freedom.unit).font(.system(size: 10, weight: .medium, design: .rounded))
                }
            }
            .padding(6)
        }
        .widgetAccentable()
    }
}

/// 锁屏长条：小标签，数字加单位，一行说明
struct FreedomRectangularView: View {
    let freedom: WidgetSnapshot.Freedom

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(freedom.kicker.uppercased())
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .tracking(1.2)
                .opacity(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(freedom.value)
                    .font(.system(size: 30, weight: .light, design: .rounded).monospacedDigit())
                    .widgetAccentable()
                Text(freedom.unit).font(.system(size: 12, weight: .regular, design: .rounded))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(freedom.caption).font(.system(size: 11, design: .rounded)).lineLimit(1).opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 看板（Pro）

/// 桌面中号：左边自由天数，右边两项自己选的数
struct DashboardMediumView: View {
    let freedom: WidgetSnapshot.Freedom
    let stats: [WidgetSnapshot.Stat]
    var note: String? = nil

    var body: some View {
        HStack(spacing: 16) {
            FreedomSmallView(freedom: freedom, note: note)
            Rectangle().fill(Color.hairline).frame(width: 1).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stats.prefix(2).enumerated()), id: \.offset) { index, stat in
                    if index > 0 {
                        Rectangle().fill(Color.hairlineSoft).frame(height: 1).padding(.vertical, 8)
                    }
                    statView(stat)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func statView(_ stat: WidgetSnapshot.Stat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetKicker(text: stat.kicker)
            Text(stat.value)
                .font(.system(size: 26, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            Text(stat.unit)
                .font(noteFont)
                .foregroundStyle(Color.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - 目标（Pro）

/// 目标小组件用到的几句固定说法
struct GoalWords {
    let text: WidgetSnapshot.Text

    /// 倒数的大数字和它后面的小字：189 天后、就是今天、已经过了
    func countdown(_ days: Int) -> (number: String?, word: String) {
        if days > 0 { return ("\(days)", text.daysLater) }
        return (nil, days == 0 ? text.today : text.passed)
    }
}

/// 桌面小号：定了日子的倒数，没定日子的写现在多少；下面是进度和还差多少
struct GoalSmallView: View {
    let goal: WidgetSnapshot.Goal
    let words: GoalWords

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetKicker(text: "Goal · \(goal.name)", color: .skyDeep)
            Spacer(minLength: 0)
            headline
            WidgetProgressLine(progress: goal.progress, done: goal.enough)
                .padding(.top, 6)
            Text(goal.targetLine ?? goal.freedomLine)
                .font(noteFont)
                .foregroundStyle(goal.enough ? Color.mossGreen : Color.inkMuted)
                .lineLimit(1)
                .padding(.top, 6)
            if goal.daysUntil != nil {
                Text(goal.freedomLine).font(noteFont).foregroundStyle(Color.inkFaint).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var headline: some View {
        if let days = goal.daysUntil {
            let countdown = words.countdown(days)
            if let number = countdown.number {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    WidgetNumber(text: number, size: 52)
                    Text(countdown.word).font(captionFont).foregroundStyle(Color.inkFaint)
                }
            } else {
                Text(countdown.word)
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .foregroundStyle(Color.ink)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                WidgetNumber(text: goal.freedomDays ?? (goal.enough ? "∞" : "—"), size: 52,
                             color: goal.enough ? .mossGreen : .ink)
                Text(verbatim: "/ \(goal.targetDays)").font(captionFont).foregroundStyle(Color.inkFaint)
            }
        }
    }
}

/// 桌面中号：现在 → 目标两个数，下面进度、还差多少和倒数
struct GoalMediumView: View {
    let goal: WidgetSnapshot.Goal
    let words: GoalWords

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetKicker(text: goal.deadlineText.map { "Goal · \(goal.name) · \($0)" } ?? "Goal · \(goal.name)",
                         color: .skyDeep)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 12) {
                figure(goal.freedomDays ?? (goal.enough ? "∞" : "—"), label: words.text.now,
                       color: goal.enough ? .mossGreen : .ink, alignment: .leading)
                HStack(spacing: 0) {
                    Rectangle().fill(Color.skyDeep).frame(height: 1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(Color.skyDeep)
                }
                .padding(.bottom, 14)
                figure("\(goal.targetDays)", label: words.text.target, color: .skyDeep, alignment: .trailing)
            }
            WidgetProgressLine(progress: goal.progress, done: goal.enough)
                .padding(.top, 8)
            HStack {
                Text(goal.targetLine ?? goal.freedomLine)
                    .foregroundStyle(goal.enough ? Color.mossGreen : Color.inkMuted)
                Spacer(minLength: 8)
                if let days = goal.daysUntil {
                    let countdown = words.countdown(days)
                    Text(countdown.number.map { "\($0) \(countdown.word)" } ?? countdown.word)
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .font(noteFont)
            .lineLimit(1)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func figure(_ value: String, label: String, color: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            WidgetNumber(text: value, size: 48, color: color)
            Text(label).font(noteFont).foregroundStyle(Color.inkFaint)
        }
    }
}

/// 锁屏长条：名字和倒数，现在多少，进度
struct GoalRectangularView: View {
    let goal: WidgetSnapshot.Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(goal.countdownLine ?? goal.name)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .widgetAccentable()
            Text(goal.targetLine ?? goal.freedomLine)
                .font(.system(size: 12, design: .rounded))
                .lineLimit(1)
                .opacity(0.85)
            Gauge(value: min(1, max(0, goal.progress ?? 0))) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 锁屏圆形：进度环，中间是倒数的天数；没定日子写百分比
struct GoalCircularView: View {
    let goal: WidgetSnapshot.Goal

    var body: some View {
        Gauge(value: min(1, max(0, goal.progress ?? 0))) {
            EmptyView()
        } currentValueLabel: {
            Text(centerText)
                .font(.system(size: 16, weight: .light, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var centerText: String {
        if let days = goal.daysUntil, days > 0 { return "\(days)" }
        guard let progress = goal.progress else { return "—" }
        return "\(Int((progress * 100).rounded(.down)))%"
    }
}

// MARK: - 没有 Pro、没有目标、没有数据

/// 一个小标签加一两句话：没有 Pro 时的 Pro 小组件、还没有目标、还没打开过 App
struct WidgetMessageView: View {
    let kicker: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetKicker(text: kicker, color: .skyDeep)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
            Text(message)
                .font(noteFont)
                .foregroundStyle(Color.inkMuted)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// 锁屏上放不下句子，只写一个短词
struct WidgetAccessoryMessage: View {
    let text: String

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded)).multilineTextAlignment(.center)
                .minimumScaleFactor(0.6).padding(4)
        }
    }
}
#endif
