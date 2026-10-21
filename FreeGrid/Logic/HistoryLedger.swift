// 历史页的时间范围、筛选、搜索与按天分组；只做计算，不读写数据库。

import Foundation

/// 一个自然月。历史页默认按月查看。
nonisolated struct HistoryMonth: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(containing date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 1)
    }

    static func < (lhs: HistoryMonth, rhs: HistoryMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// 向前(负数)或向后(正数)移动若干个月，跨年自动进位。
    func shifted(by offset: Int) -> HistoryMonth {
        let index = year * 12 + (month - 1) + offset
        return HistoryMonth(year: Int((Double(index) / 12).rounded(.down)), month: (index % 12 + 12) % 12 + 1)
    }

    /// 这个月在本地日历中的起止时刻，含月初、不含下月初。
    func interval(calendar: Calendar = .current) -> DateInterval? {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        return calendar.dateInterval(of: .month, for: start)
    }

    var label: String { "\(year)年\(month)月" }
}

enum HistoryScope: Equatable {
    case month(HistoryMonth)
    case allTime
}

enum HistoryKindFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case expense = "支出"
    case income = "收入"
    var id: String { rawValue }
}

/// 同一自然日的记录，新的在上。
struct HistoryDay: Identifiable {
    /// 当天零点
    let id: Date
    let transactions: [LedgerTransaction]

    /// 当天这些记录合计的现金变化
    var net: Double { transactions.reduce(0) { $0 + $1.cashChange } }

    /// 当天花掉的钱；段头显示它而不是净额，否则有收入的日子会把大额支出盖住
    var expense: Double { HistoryLedger.summary(transactions).expense }
    var income: Double { HistoryLedger.summary(transactions).income }
}

/// 搜索结果里同一个月的记录，新的在上。
struct HistoryMonthGroup: Identifiable {
    let month: HistoryMonth
    let transactions: [LedgerTransaction]
    var id: HistoryMonth { month }
    var summary: HistorySummary { HistoryLedger.summary(transactions) }
}

nonisolated struct HistorySummary: Equatable, Sendable {
    var expense: Double = 0
    var income: Double = 0
    var count: Int = 0
    var net: Double { income - expense }
}

enum HistoryLedger {
    /// 取出范围内的全部记录，按日期从新到旧。
    static func transactions(
        expenses: [Expense],
        incomes: [Income],
        scope: HistoryScope,
        calendar: Calendar = .current
    ) -> [LedgerTransaction] {
        let all = expenses.map(LedgerTransaction.expense) + incomes.map(LedgerTransaction.income)
        let scoped: [LedgerTransaction]
        switch scope {
        case .allTime:
            scoped = all
        case .month(let month):
            guard let interval = month.interval(calendar: calendar) else { return [] }
            scoped = all.filter { $0.date >= interval.start && $0.date < interval.end }
        }
        return scoped.sorted { $0.date > $1.date }
    }

    /// 选了分类时只留该分类的支出；收入没有分类，不会出现在结果里。
    static func filter(
        _ transactions: [LedgerTransaction],
        kind: HistoryKindFilter,
        category: String?
    ) -> [LedgerTransaction] {
        transactions.filter { transaction in
            if let category {
                guard case .expense(let expense) = transaction else { return false }
                return expense.category == category
            }
            switch kind {
            case .all: return true
            case .expense: return transaction.kind == .expense
            case .income: return transaction.kind == .income
            }
        }
    }

    /// 空格分开的每个词都要命中备注、收入来源或金额中的一处；不分大小写。
    /// 不搜支出分类：分类只有固定几个，按分类看是筛选的事，搜它只会命中上千笔。
    static func search(_ transactions: [LedgerTransaction], query: String) -> [LedgerTransaction] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return transactions }
        return transactions.filter { transaction in
            let amount = abs(transaction.cashChange)
            let fields = [
                transaction.kind == .income ? transaction.title.lowercased() : "",
                transaction.note.lowercased(),
                // 同时接受 "1,234.5" 与 "1234.5" 两种输入
                amount.formatted(.number.precision(.fractionLength(0...2))),
                amount.formatted(.number.grouping(.never).precision(.fractionLength(0...2))),
            ]
            return terms.allSatisfy { term in fields.contains { $0.contains(term) } }
        }
    }

    /// 按自然日分组；输入已按日期从新到旧时，天和天内顺序都保持不变。
    static func days(_ transactions: [LedgerTransaction], calendar: Calendar = .current) -> [HistoryDay] {
        var order: [Date] = []
        var groups: [Date: [LedgerTransaction]] = [:]
        for transaction in transactions {
            let day = calendar.startOfDay(for: transaction.date)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(transaction)
        }
        return order.map { HistoryDay(id: $0, transactions: groups[$0] ?? []) }
    }

    /// 按自然月分组；输入已按日期从新到旧时，月和月内顺序都保持不变。
    static func months(_ transactions: [LedgerTransaction], calendar: Calendar = .current) -> [HistoryMonthGroup] {
        var order: [HistoryMonth] = []
        var groups: [HistoryMonth: [LedgerTransaction]] = [:]
        for transaction in transactions {
            let month = HistoryMonth(containing: transaction.date, calendar: calendar)
            if groups[month] == nil { order.append(month) }
            groups[month, default: []].append(transaction)
        }
        return order.map { HistoryMonthGroup(month: $0, transactions: groups[$0] ?? []) }
    }

    /// 写过不止一次的备注，次数多的在前；同次数时先出现的（更近的）在前。给搜索当快捷词。
    static func frequentNotes(_ transactions: [LedgerTransaction], limit: Int = 6) -> [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for transaction in transactions {
            let note = transaction.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { continue }
            if counts[note] == nil { order.append(note) }
            counts[note, default: 0] += 1
        }
        let ranked = order.enumerated()
            .filter { counts[$0.element, default: 0] > 1 }
            .sorted { (counts[$0.element, default: 0], -$0.offset) > (counts[$1.element, default: 0], -$1.offset) }
        return ranked.prefix(limit).map(\.element)
    }

    /// 退款以负数支出保存，会冲减支出合计。
    static func summary(_ transactions: [LedgerTransaction]) -> HistorySummary {
        var summary = HistorySummary()
        for transaction in transactions {
            summary.count += 1
            switch transaction {
            case .expense(let expense): summary.expense += expense.amount
            case .income(let income): summary.income += income.amount
            }
        }
        return summary
    }

    /// 各支出分类合计，金额高的在前；同额按名称排，顺序稳定。
    static func categoryTotals(_ transactions: [LedgerTransaction]) -> [(category: String, total: Double)] {
        var totals: [String: Double] = [:]
        for case .expense(let expense) in transactions {
            totals[expense.category, default: 0] += expense.amount
        }
        return totals
            .map { (category: $0.key, total: $0.value) }
            .sorted { ($0.total, $1.category) > ($1.total, $0.category) }
    }

    /// 可切换的月份范围：最早一笔记录所在月，到本月与最晚记录所在月中较晚的一个。
    static func monthRange(
        expenses: [Expense],
        incomes: [Income],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ClosedRange<HistoryMonth> {
        let current = HistoryMonth(containing: now, calendar: calendar)
        let dates = expenses.map(\.date) + incomes.map(\.date)
        guard let earliest = dates.min(), let latest = dates.max() else { return current...current }
        let first = HistoryMonth(containing: earliest, calendar: calendar)
        let last = HistoryMonth(containing: latest, calendar: calendar)
        return min(first, current)...max(last, current)
    }

    /// 算月内日均用的天数：过去的月份按整月，本月算到今天，还没到的月份为 0。
    static func elapsedDays(in month: HistoryMonth, now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let interval = month.interval(calendar: calendar) else { return 0 }
        if now < interval.start { return 0 }
        let end = min(now, interval.end.addingTimeInterval(-1))
        return (calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: end)).day ?? 0) + 1
    }

    /// 这笔钱按长期日均折合成多少天；日均不可用时为 nil。
    static func equivalentDays(expense: Double, dailyBurn: Double) -> Double? {
        guard expense.isFinite, dailyBurn.isFinite, dailyBurn > 0, expense > 0 else { return nil }
        return expense / dailyBurn
    }

    /// 不足 10 天保留一位小数，其余取整。
    static func equivalentDaysLabel(_ days: Double) -> String {
        let digits = days < 10 ? 0...1 : 0...0
        return "相当于 " + days.formatted(.number.precision(.fractionLength(digits))) + " 天"
    }

    /// 段头用的日期：今天、昨天直接说，不在今年的带上年份。
    static func dayLabel(_ day: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = weekdays[((parts.weekday ?? 1) - 1 + 7) % 7]
        var text = "\(parts.month ?? 0)月\(parts.day ?? 0)日 \(weekday)"
        if parts.year != calendar.component(.year, from: now) {
            text = "\(parts.year ?? 0)年" + text
        }
        if calendar.isDate(day, inSameDayAs: now) { return "今天 · " + text }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "昨天 · " + text }
        return text
    }
}
