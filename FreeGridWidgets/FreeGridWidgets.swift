// FreeGrid 的系统小组件：自由天数（免费，桌面小号和锁屏三种）、自由看板和我的目标（Pro）。
// 用户 2026-10-25 定的分法：核心数字人人能放；多指标、自选内容和目标倒计时放进 Pro。
// 没有 Pro 时 Pro 小组件不消失（系统小组件库没法按人藏），显示一句说明，点了去购买页。

import SwiftUI
import WidgetKit

@main
struct FreeGridWidgetBundle: WidgetBundle {
    var body: some Widget {
        FreedomWidget()
        DashboardWidget()
        GoalWidget()
    }
}

/// 还没打开过新版 App、没有数据时
private struct NoDataView: View {
    var body: some View {
        WidgetMessageView(kicker: "FreeGrid", title: String(localized: "打开 FreeGrid"),
                          message: String(localized: "打开一次 App，这里就会显示自由天数。"))
    }
}

// MARK: - 自由天数（免费）

struct FreedomProvider: TimelineProvider {
    func placeholder(in context: Context) -> FreeGridEntry<Void> { WidgetTimeline.sample(configuration: ()) }

    func getSnapshot(in context: Context, completion: @escaping (FreeGridEntry<Void>) -> Void) {
        completion(context.isPreview ? WidgetTimeline.preview(configuration: ())
                                     : WidgetTimeline.entries(configuration: ())[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FreeGridEntry<Void>>) -> Void) {
        completion(Timeline(entries: WidgetTimeline.entries(configuration: ()), policy: .never))
    }
}

struct FreedomWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FreedomWidget", provider: FreedomProvider()) { entry in
            FreedomEntryView(entry: entry)
        }
        .configurationDisplayName("自由天数")
        .description("首页的自由天数，桌面和锁屏都能放。")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct FreedomEntryView: View {
    let entry: FreeGridEntry<Void>
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(Color.mist, for: .widget)
            .widgetURL(WidgetLink.home)
    }

    @ViewBuilder
    private var content: some View {
        if let freedom = entry.day?.freedom {
            switch family {
            case .accessoryCircular: FreedomCircularView(freedom: freedom)
            case .accessoryRectangular: FreedomRectangularView(freedom: freedom)
            case .accessoryInline: Text(freedom.inline)
            default: FreedomSmallView(freedom: freedom, note: entry.note)
            }
        } else {
            switch family {
            case .accessoryCircular, .accessoryRectangular: WidgetAccessoryMessage(text: "FreeGrid")
            case .accessoryInline: Text(verbatim: "FreeGrid")
            default: NoDataView()
            }
        }
    }
}

// MARK: - 自由看板（Pro）

struct DashboardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FreeGridEntry<DashboardIntent> {
        WidgetTimeline.sample(configuration: DashboardIntent())
    }

    func snapshot(for configuration: DashboardIntent, in context: Context) async -> FreeGridEntry<DashboardIntent> {
        context.isPreview ? WidgetTimeline.preview(configuration: configuration)
                          : WidgetTimeline.entries(configuration: configuration)[0]
    }

    func timeline(for configuration: DashboardIntent, in context: Context) async -> Timeline<FreeGridEntry<DashboardIntent>> {
        Timeline(entries: WidgetTimeline.entries(configuration: configuration), policy: .never)
    }
}

struct DashboardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DashboardWidget", intent: DashboardIntent.self,
                               provider: DashboardProvider()) { entry in
            DashboardEntryView(entry: entry)
        }
        .configurationDisplayName("自由看板")
        .description("你的自由天数，和你最关心的两项数字。")
        .supportedFamilies([.systemMedium])
    }
}

struct DashboardEntryView: View {
    let entry: FreeGridEntry<DashboardIntent>

    var body: some View {
        content
            .containerBackground(Color.mist, for: .widget)
            .widgetURL(entry.proActive || entry.day == nil ? WidgetLink.home : WidgetLink.pro)
    }

    @ViewBuilder
    private var content: some View {
        if let day = entry.day {
            if entry.proActive {
                DashboardMediumView(
                    freedom: day.freedom,
                    stats: [entry.configuration.first, entry.configuration.second].compactMap { day.stats[$0.rawValue] },
                    note: entry.note)
            } else {
                WidgetMessageView(kicker: "FreeGrid Pro", title: entry.text.proTitle, message: entry.text.proBody)
            }
        } else {
            NoDataView()
        }
    }
}

// MARK: - 我的目标（Pro）

struct GoalProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FreeGridEntry<GoalIntent> {
        WidgetTimeline.sample(configuration: GoalIntent())
    }

    func snapshot(for configuration: GoalIntent, in context: Context) async -> FreeGridEntry<GoalIntent> {
        context.isPreview ? WidgetTimeline.preview(configuration: configuration)
                          : WidgetTimeline.entries(configuration: configuration)[0]
    }

    func timeline(for configuration: GoalIntent, in context: Context) async -> Timeline<FreeGridEntry<GoalIntent>> {
        Timeline(entries: WidgetTimeline.entries(configuration: configuration), policy: .never)
    }
}

struct GoalWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GoalWidget", intent: GoalIntent.self, provider: GoalProvider()) { entry in
            GoalEntryView(entry: entry)
        }
        .configurationDisplayName("我的目标")
        .description("给自由定个目标，也为重要的日子留个倒计时。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct GoalEntryView: View {
    let entry: FreeGridEntry<GoalIntent>
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(Color.mist, for: .widget)
            .widgetURL(entry.proActive || entry.day == nil ? WidgetLink.home : WidgetLink.pro)
    }

    /// 选过的那个；选的删掉了或者没选过，看第一个
    private var goal: WidgetSnapshot.Goal? {
        guard let goals = entry.day?.goals else { return nil }
        return goals.first { $0.id == entry.configuration.goal?.id } ?? goals.first
    }

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular
    }

    @ViewBuilder
    private var content: some View {
        if entry.day == nil {
            if isAccessory { WidgetAccessoryMessage(text: "FreeGrid") } else { NoDataView() }
        } else if !entry.proActive {
            if isAccessory {
                WidgetAccessoryMessage(text: "Pro")
            } else {
                WidgetMessageView(kicker: "FreeGrid Pro", title: entry.text.proTitle, message: entry.text.proBody)
            }
        } else if let goal {
            let words = GoalWords(text: entry.text)
            switch family {
            case .accessoryCircular: GoalCircularView(goal: goal)
            case .accessoryRectangular: GoalRectangularView(goal: goal)
            case .systemMedium: GoalMediumView(goal: goal, words: words)
            default: GoalSmallView(goal: goal, words: words)
            }
        } else {
            if isAccessory {
                WidgetAccessoryMessage(text: entry.text.target)
            } else {
                WidgetMessageView(kicker: "Goal", title: entry.text.target, message: entry.text.noGoal)
            }
        }
    }
}
