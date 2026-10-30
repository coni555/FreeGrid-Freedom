// 两种记账方式（2.2，用户 2026-10-30 定）：逐笔记账，或者每月一个数。
// 每月一个数：每个月写一个总花销（房租、订阅这些固定支出也算在里面），日均只看写下的这些数；
// 旧记录留着但不计入日均，现金不自动扣。问哪个月见 `prompt`，日均怎么算见 `FreedomMath.burnEstimate(_:tracking:…)`。
// 存在本机偏好里，JSON 备份会带上（见 `BackupEnvelope.monthlyTracking`）。

import Foundation

/// 一个日历月。键是「2026-11」这样的字符串，备份和偏好里都用它
struct YearMonth: Hashable, Comparable, Identifiable {
    let year: Int
    let month: Int

    var id: String { key }
    var key: String { String(format: "%04d-%02d", year, month) }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1)
    }

    init?(key: String) {
        let parts = key.split(separator: "-")
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        self.init(year: year, month: month)
    }

    var previous: YearMonth {
        month == 1 ? YearMonth(year: year - 1, month: 12) : YearMonth(year: year, month: month - 1)
    }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// 界面上的名字：「11 月」「November」；不是今年的月份带上年，明细里才分得清
    func name(now: Date = .now, calendar: Calendar = .current) -> String {
        let sameYear = year == YearMonth(now, calendar: calendar).year
        guard AppLanguage.isChinese else {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return key }
            return AppLanguage.date(date, template: sameYear ? "MMMM" : "yyyyMMMM", calendar: calendar)
        }
        return sameYear ? "\(month) 月" : "\(year) 年 \(month) 月"
    }
}

struct MonthlyTracking: Equatable {
    enum Method: String {
        case entries, monthly
    }

    /// 用「每月一个数」的一段时间。还在用时 `end` 是 nil。这段时间不算记账天数，也不摊进逐笔记账的日均
    struct Pause: Equatable {
        var start: Date
        var end: Date?
    }

    /// 首页问的那个月
    struct Prompt: Equatable {
        let month: YearMonth
        /// 这个月已经写下的数；没写时是 nil
        let amount: Double?
        /// 还在这个月里，且离月底还早：这时才说「建议月底去记」
        let isEarly: Bool
    }

    static let key = "monthlyTracking"
    /// 月底的最后这么多天不再说「建议月底去记」：现在就是月底
    static let monthEndDays = 3

    var method = Method.entries
    /// 写下的数，键是 `YearMonth.key`
    var months: [String: Double] = [:]
    /// 从哪个月开始问：更早的月份没写也不追问
    var startMonth: String?
    var pauses: [Pause] = []
    /// 改回逐笔记账的那天：日均从这天起用 30 天过渡到记录
    var switchedBackAt: Date?

    var isMonthly: Bool { method == .monthly }

    /// 单元测试不读这台设备上填过的数：模拟器账本是拿来试用的，填过以后不该让别的测试变结果
    static var current: MonthlyTracking {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            ? MonthlyTracking() : decode(AppPreferences.store.string(forKey: key) ?? "")
    }

    static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= FinancialLimits.maximumAmount else { return nil }
        return value
    }

    // MARK: - 写下的数

    /// 写过的月份，最近的在前
    var writtenMonths: [(month: YearMonth, amount: Double)] {
        months.compactMap { key, value in
            guard let month = YearMonth(key: key), let amount = Self.valid(value) else { return nil }
            return (month, amount)
        }
        .sorted { $0.month > $1.month }
    }

    var hasNumber: Bool { !writtenMonths.isEmpty }

    /// 写过的所有月份的平均；一个都没写时是 nil
    var monthlyAverage: Double? {
        let written = writtenMonths
        guard !written.isEmpty else { return nil }
        return written.reduce(0) { $0 + $1.amount } / Double(written.count)
    }

    /// 日常的部分：平均每月花销扣掉固定支出。固定支出按日历另扣，不扣掉就算了两遍；
    /// 固定支出比它还多时是 0，自由天数只按日历扣固定支出（见 `FreedomMath.freedomRun`）
    func everyday(fixedMonthly: Double) -> Double? {
        monthlyAverage.map { max(0, $0 - fixedMonthly) }
    }

    func amount(for month: YearMonth) -> Double? {
        Self.valid(months[month.key])
    }

    /// 传 nil 就是清空这个月
    mutating func set(_ amount: Double?, for month: YearMonth) {
        months[month.key] = Self.valid(amount)
    }

    // MARK: - 问哪个月

    /// 上个月过完了还没写，先问上个月；隔了几个月才打开也只问最近过完的那个月，不补更早的。
    /// 上个月写过了（或者还没开始用），问这个月。
    func prompt(now: Date = .now, calendar: Calendar = .current) -> Prompt {
        let current = YearMonth(now, calendar: calendar)
        let start = startMonth.flatMap(YearMonth.init(key:)) ?? writtenMonths.last?.month ?? current
        if current.previous >= start, amount(for: current.previous) == nil {
            return Prompt(month: current.previous, amount: nil, isEarly: false)
        }
        return Prompt(month: current, amount: amount(for: current),
                      isEarly: Self.isEarly(in: current, now: now, calendar: calendar))
    }

    /// `month` 还没过完、离月底还早。写这个月的面板和首页都看它，决定说不说「建议月底去记」
    static func isEarly(in month: YearMonth, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard month == YearMonth(now, calendar: calendar),
              let days = calendar.range(of: .day, in: .month, for: now)?.count else { return false }
        return days - calendar.component(.day, from: now) >= monthEndDays
    }

    /// 改成每月一个数时问哪个月：上个月已经在用 App，就问上个月（那个月过完了，数是完整的）；
    /// 第一笔记录就在这个月、或者还没有记录，只能问这个月
    static func firstMonth(firstRecord: Date?, now: Date = .now, calendar: Calendar = .current) -> YearMonth {
        let current = YearMonth(now, calendar: calendar)
        guard let firstRecord, YearMonth(firstRecord, calendar: calendar) < current else { return current }
        return current.previous
    }

    // MARK: - 切换

    /// 改成每月一个数，从 `month` 开始问
    mutating func adopt(startingAt month: YearMonth, now: Date = .now) {
        guard !isMonthly else { return }
        method = .monthly
        if startMonth.flatMap(YearMonth.init(key:)).map({ $0 > month }) ?? true { startMonth = month.key }
        pauses.append(Pause(start: now, end: nil))
        switchedBackAt = nil
    }

    /// 改回逐笔记账：写过的数留着，日均用它过渡 30 天
    mutating func switchBack(now: Date = .now) {
        guard isMonthly else { return }
        method = .entries
        if let last = pauses.indices.last, pauses[last].end == nil { pauses[last].end = now }
        switchedBackAt = now
    }

    // MARK: - 显示

    /// 日均卡的小字：只写了一个月就写是哪个月，多了写几个月
    func burnNote(now: Date = .now, calendar: Calendar = .current) -> String {
        let written = writtenMonths
        if written.count > 1 { return String(localized: "按 \(written.count) 个月平均") }
        guard let month = written.first?.month else { return String(localized: "还没写") }
        return String(localized: "按 \(month.name(now: now, calendar: calendar)) 估算")
    }

    // MARK: - 存取

    private struct Stored: Codable {
        var method: String
        var months: [String: Double]
        var startMonth: String?
        var pauses: [StoredPause]
        var switchedBackAt: Date?
    }

    private struct StoredPause: Codable {
        var start: Date
        var end: Date?
    }

    /// 读不出来时当作从没用过
    static func decode(_ stored: String) -> MonthlyTracking {
        guard let data = stored.data(using: .utf8),
              let value = try? JSONDecoder().decode(Stored.self, from: data) else { return MonthlyTracking() }
        return MonthlyTracking(method: Method(rawValue: value.method) ?? .entries, months: value.months,
                               startMonth: value.startMonth,
                               pauses: value.pauses.map { Pause(start: $0.start, end: $0.end) },
                               switchedBackAt: value.switchedBackAt)
    }

    var encoded: String {
        let value = Stored(method: method.rawValue, months: months, startMonth: startMonth,
                           pauses: pauses.map { StoredPause(start: $0.start, end: $0.end) },
                           switchedBackAt: switchedBackAt)
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// 从没用过每月一个数：备份里不写这一段
    var isUntouched: Bool { self == MonthlyTracking() }
}
