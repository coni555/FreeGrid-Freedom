// 小组件的时间线：读 App 写好的那份数，现在一份，之后每天零点换下一份。
// App 每次写完都会请系统刷新，所以这里不定时去读；算到的最后一天过完，就停在最后一份并提示打开 App。

import WidgetKit
import Foundation

struct FreeGridEntry<Configuration>: TimelineEntry {
    let date: Date
    /// 还没打开过新版 App 时没有
    let snapshot: WidgetSnapshot?
    let day: WidgetSnapshot.Day?
    /// 算到的最后一天也过了
    let stale: Bool
    let configuration: Configuration

    var text: WidgetSnapshot.Text { snapshot?.text ?? WidgetSample.text }
    var proActive: Bool { snapshot?.proActive ?? false }
    /// 过期时写在数字下面的一句
    var note: String? { stale ? text.stale : nil }
}

enum WidgetTimeline {
    static func entries<C>(configuration: C, now: Date = .now) -> [FreeGridEntry<C>] {
        guard let snapshot = WidgetSnapshotFile.read(), !snapshot.days.isEmpty else {
            return [FreeGridEntry(date: now, snapshot: nil, day: nil, stale: false, configuration: configuration)]
        }
        if snapshot.isStale(at: now) {
            return [FreeGridEntry(date: now, snapshot: snapshot, day: snapshot.days.last, stale: true,
                                  configuration: configuration)]
        }
        var entries = [FreeGridEntry(date: now, snapshot: snapshot, day: snapshot.day(at: now), stale: false,
                                     configuration: configuration)]
        for day in snapshot.days where day.date > now {
            entries.append(FreeGridEntry(date: day.date, snapshot: snapshot, day: day, stale: false,
                                         configuration: configuration))
        }
        let calendar = Calendar.current
        if let last = snapshot.days.last,
           let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last.date)) {
            entries.append(FreeGridEntry(date: end, snapshot: snapshot, day: last, stale: true,
                                         configuration: configuration))
        }
        return entries
    }

    /// 添加小组件时的预览：有真数用真数，没有用示例
    static func preview<C>(configuration: C, now: Date = .now) -> FreeGridEntry<C> {
        if let entry = entries(configuration: configuration, now: now).first, entry.day != nil { return entry }
        return sample(configuration: configuration, now: now)
    }

    static func sample<C>(configuration: C, now: Date = .now) -> FreeGridEntry<C> {
        FreeGridEntry(date: now, snapshot: WidgetSample.snapshot(now: now), day: WidgetSample.day(now: now),
                      stale: false, configuration: configuration)
    }
}

/// 小组件库里的示例：一个过得还不错的普通人。字用小组件自己的语言（跟系统）
enum WidgetSample {
    static var text: WidgetSnapshot.Text {
        WidgetSnapshot.Text(
            proTitle: String(localized: "Pro 小组件"),
            proBody: String(localized: "看板和目标小组件属于 Pro，点一下了解。"),
            noGoal: String(localized: "在自检里加一个目标，这里就会显示。"),
            stale: String(localized: "打开 FreeGrid 更新"),
            daysLater: String(localized: "天后"),
            today: String(localized: "就是今天"),
            passed: String(localized: "已经过了"),
            target: String(localized: "目标"),
            now: String(localized: "现在"))
    }

    static func day(now: Date) -> WidgetSnapshot.Day {
        let deadline = Calendar.current.date(byAdding: .day, value: 189, to: Calendar.current.startOfDay(for: now))
        return WidgetSnapshot.Day(
            date: now,
            freedom: WidgetSnapshot.Freedom(
                state: .finite, value: "341", kicker: "Freedom Days",
                caption: String(localized: "此刻拥有的自由"), short: String(localized: "341 天"),
                unit: String(localized: "天"), inline: String(localized: "自由 341 天"), dailyCost: 128.6),
            stats: [
                "daily": WidgetSnapshot.Stat(kicker: "Daily Spend", title: String(localized: "日均消费"),
                                             value: "128.6", unit: String(localized: "元/天")),
                "month": WidgetSnapshot.Stat(kicker: "Monthly Spend", title: String(localized: "本月花销"),
                                             value: "2,860", unit: String(localized: "比上月同期少 12%")),
            ],
            goals: [WidgetSnapshot.Goal(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000189")!, name: "GAP", targetDays: 365,
                deadline: deadline, deadlineText: nil, daysUntil: 189, progress: 341.0 / 365, enough: false, freedomDays: "341",
                freedomLine: String(localized: "现在 341 / 365 天"), targetLine: String(localized: "距离目标还差 24 天"),
                countdownLine: String(localized: "GAP · 189 天后"))])
    }

    static func snapshot(now: Date) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: now, proActive: true,
                       days: [day(now: now)], text: text)
    }
}
