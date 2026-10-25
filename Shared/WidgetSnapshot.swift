// 桌面和锁屏小组件读的那一份数。App 用首页同一套规则算好，写进 App Group 共享容器里的一个 JSON；
// 小组件只读这个文件，不打开账本、不自己算。账本照旧留在 App 自己的容器里，升级不用搬数据。
// 自由天数每过一天都会变（日均的分母多一天、到期的房租要扣），所以从今天起每天算一份，小组件到点换下一份。
// 字都是 App 按自己的界面语言写好的，小组件照着显示。这个文件 App 和小组件两边都编译。

import Foundation

nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let appGroup = "group.cn.conilab.FreeGrid"
    static let fileName = "widget-snapshot.json"
    /// 往后算多少天。超过了还没打开 App，小组件停在最后一天，并提示打开 App
    static let projectedDays = 30
    /// 字段有不兼容的改动时加一；读到不认识的版本当作没有数据
    static let currentVersion = 1

    var version = currentVersion
    var generatedAt: Date
    /// Pro 有没有生效。看板和目标小组件是 Pro 的，没有 Pro 时显示一句说明
    var proActive: Bool
    /// 从今天起每天一份，按日期从早到晚
    var days: [Day]
    /// 小组件自己要的几句话
    var text: Text

    nonisolated struct Day: Codable, Equatable, Sendable {
        /// 这一份从什么时候起生效：第一份是写的时刻，之后是每天零点
        var date: Date
        var freedom: Freedom
        /// 首页小卡的那几项，按 `HomeStat.rawValue` 存
        var stats: [String: Stat]
        /// 自己的目标（只在 Pro 生效时有），顺序和自检里一样
        var goals: [Goal]
    }

    nonisolated struct Freedom: Codable, Equatable, Sendable {
        enum State: String, Codable, Sendable { case finite, covered, pending, invalid }
        var state: State
        /// 首页大数字：日、月是整数，年带一位小数，已覆盖是 ∞，算不出是 —
        var value: String
        /// 大数字上面的等宽小标签：Freedom Days / Months / Years
        var kicker: String
        /// 大数字下面一行：「还能撑这么多天」
        var caption: String
        /// 带单位的一句，锁屏这种地方用：「341 天」
        var short: String
        /// 数字的单位：天、月、年；已覆盖或算不出时为空
        var unit: String
        /// 锁屏日期旁边那一行：「自由 341 天」
        var inline: String
        /// 日均消费（含固定支出折算），算不出时为 nil
        var dailyCost: Double?
    }

    nonisolated struct Stat: Codable, Equatable, Sendable {
        /// 等宽小标签，和首页小卡一样：Daily、Month…
        var kicker: String
        var title: String
        var value: String
        var unit: String
    }

    nonisolated struct Goal: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var name: String
        var targetDays: Int
        /// 截止日（零点）；没定日子时为 nil
        var deadline: Date?
        /// 截止日的写法，和自检里一样：今年的不写年
        var deadlineText: String?
        /// 离截止日还有几天；0 是今天，负数是过了
        var daysUntil: Int?
        /// 现在的自由天数占目标多少，0...1；算不出时为 nil
        var progress: Double?
        var enough: Bool
        /// 现在的自由天数取整；已覆盖或算不出时为 nil
        var freedomDays: String?
        /// 「现在 341 / 365 天」
        var freedomLine: String
        /// 「还差 24 天自由」或「已达成」
        var targetLine: String?
        /// 「GAP · 189 天后」
        var countdownLine: String?
    }

    nonisolated struct Text: Codable, Equatable, Sendable {
        /// 没有 Pro 时 Pro 小组件上的两行
        var proTitle: String
        var proBody: String
        /// Pro 生效、还没有目标时目标小组件上的一句
        var noGoal: String
        /// 算到的最后一天也过了
        var stale: String
        /// 目标小组件：「天后」「就是今天」「已经过了」「天」
        var daysLater: String
        var today: String
        var passed: String
        var target: String
        var now: String
    }

    /// 这一刻该显示哪一份：生效时间不晚于 `date` 的最后一份；都还没到时用第一份
    func day(at date: Date) -> Day? {
        days.last { $0.date <= date } ?? days.first
    }

    /// 算到的最后一天也过完了
    func isStale(at date: Date, calendar: Calendar = .current) -> Bool {
        guard let last = days.last?.date,
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else { return true }
        return date >= end
    }
}

nonisolated enum WidgetSnapshotFile {
    /// 共享容器里的那个文件；拿不到共享容器（没配 App Group 的构建）时为 nil
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
            .appendingPathComponent(WidgetSnapshot.fileName)
    }

    static func encode(_ snapshot: WidgetSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(snapshot)
    }

    /// 读不出来、版本不认识都当作没有
    static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion else { return nil }
        return snapshot
    }

    static func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
}

/// 点小组件打开 App 时带的地址。小组件的地址不用在 Info.plist 里登记，系统直接交给 App
nonisolated enum WidgetLink {
    static let scheme = "freegrid"
    /// 回首页
    static let home = URL(string: "freegrid://home")!
    /// 没有 Pro 时点了 Pro 小组件：打开购买页
    static let pro = URL(string: "freegrid://pro")!
}
