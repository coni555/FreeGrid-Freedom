import Foundation

/// 搜索只处理值类型；SwiftData 对象留在页面的主 actor 上。
nonisolated enum HistorySearch {
    enum Filter: Hashable, Sendable {
        case all
        case income
        /// 到期自动扣的固定支出（房租、月供），在明细卡里合成一行
        case fixed
        /// 日常支出的一个分类；月供扣款的「分类」是贷款名，不算在里面
        case category(String)
    }

    struct Key: Hashable, Sendable {
        let id: UUID
        let isIncome: Bool
    }

    struct Record: Identifiable, Equatable, Sendable {
        let key: Key
        let date: Date
        let amount: Double
        let title: String
        let note: String
        var isLoanPayment = false
        var isExcludedFromBurn = false
        var id: UUID { key.id }
        var cashChange: Double { key.isIncome ? amount : -amount }
    }

    struct Row: Identifiable, Equatable, Sendable {
        let record: Record
        let day: Int
        let amount: String
        var id: Key { record.key }

        init(record: Record, locale: Locale = .current, calendar: Calendar = .current, includesDay: Bool = true) {
            self.record = record
            day = includesDay ? calendar.component(.day, from: record.date) : 0
            amount = FinancialFormatting.signedYuan(record.cashChange, locale: locale)
        }
    }

    struct Entry: Sendable {
        let row: Row
        var record: Record { row.record }
        let month: HistoryMonth
        let fields: [String]
    }

    struct Month: Identifiable, Sendable {
        let month: HistoryMonth
        var rows: [Row] = []
        var records: [Record] { rows.map(\.record) }
        var keys: [Key] { rows.map { $0.record.key } }
        var summary = HistorySummary()
        var id: HistoryMonth { month }
    }

    struct Result: Sendable {
        let query: String
        var months: [Month] = []
        var summary = HistorySummary()
    }

    struct Index: Sendable {
        let entries: [Entry]
        let locale: Locale
        let calendar: Calendar
        /// 用于测试缓存复用；变化了的记录才重新格式化金额。
        let preparedCount: Int

        init(expenses: [Record], incomes: [Record], previous: Index? = nil,
             locale: Locale = .current, calendar: Calendar = .current) throws {
            self.locale = locale
            self.calendar = calendar
            // 日期字段的观察可能先于 @Query 的重新排序到达；只在乱序时补排。
            let expenses = Self.dateOrdered(expenses)
            let incomes = Self.dateOrdered(incomes)
            let reusable = previous?.locale == locale && previous?.calendar == calendar
                ? Dictionary(uniqueKeysWithValues: (previous?.entries ?? []).map { ($0.record.key, $0) }) : [:]
            var entries: [Entry] = []
            entries.reserveCapacity(expenses.count + incomes.count)
            var expenseIndex = 0
            var incomeIndex = 0
            var preparedCount = 0
            // 两个 @Query 已按日期降序；同日支出排在收入前，与旧版稳定排序一致。
            while expenseIndex < expenses.count || incomeIndex < incomes.count {
                if entries.count.isMultiple(of: 128) { try Task.checkCancellation() }
                let record: Record
                if incomeIndex == incomes.count ||
                    (expenseIndex < expenses.count && expenses[expenseIndex].date >= incomes[incomeIndex].date) {
                    record = expenses[expenseIndex]
                    expenseIndex += 1
                } else {
                    record = incomes[incomeIndex]
                    incomeIndex += 1
                }
                if let entry = reusable[record.key], entry.record == record {
                    entries.append(entry)
                } else {
                    let amount = abs(record.amount)
                    entries.append(Entry(row: Row(record: record, locale: locale, calendar: calendar), month: HistoryMonth(containing: record.date, calendar: calendar), fields: [
                        record.key.isIncome ? record.title.lowercased() : "",
                        record.note.lowercased(),
                        amount.formatted(.number.precision(.fractionLength(0...2)).locale(locale)),
                        amount.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(locale)),
                    ]))
                    preparedCount += 1
                }
            }
            self.entries = entries
            self.preparedCount = preparedCount
        }

        private static func dateOrdered(_ records: [Record]) -> [Record] {
            for (left, right) in zip(records, records.dropFirst()) where left.date < right.date {
                return records.sorted { $0.date > $1.date }
            }
            return records
        }

        func search(_ query: String, filter: Filter = .all) throws -> Result {
            let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            var result = Result(query: query)
            guard !terms.isEmpty else { return result }
            var positions: [HistoryMonth: Int] = [:]
            for (offset, entry) in entries.enumerated() {
                if offset.isMultiple(of: 128) { try Task.checkCancellation() }
                guard includes(entry.record, filter: filter),
                      terms.allSatisfy({ term in entry.fields.contains { $0.contains(term) } }) else { continue }
                let position: Int
                if let existing = positions[entry.month] {
                    position = existing
                } else {
                    position = result.months.count
                    positions[entry.month] = position
                    result.months.append(Month(month: entry.month))
                }
                result.months[position].rows.append(entry.row)
                add(entry.record, to: &result.months[position].summary)
                add(entry.record, to: &result.summary)
            }
            return result
        }

        func frequentNotes(filter: Filter = .all, limit: Int = 6) throws -> [String] {
            var order: [String] = []
            var counts: [String: Int] = [:]
            for (offset, entry) in entries.enumerated() {
                if offset.isMultiple(of: 128) { try Task.checkCancellation() }
                guard includes(entry.record, filter: filter) else { continue }
                let note = entry.record.note.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !note.isEmpty else { continue }
                if counts[note] == nil { order.append(note) }
                counts[note, default: 0] += 1
            }
            return order.enumerated()
                .filter { counts[$0.element, default: 0] > 1 }
                .sorted { (counts[$0.element, default: 0], -$0.offset) > (counts[$1.element, default: 0], -$1.offset) }
                .prefix(limit).map(\.element)
        }

        private func includes(_ record: Record, filter: Filter) -> Bool {
            switch filter {
            case .all: return true
            case .income: return record.key.isIncome
            case .fixed: return record.isLoanPayment
            case .category(let category): return !record.key.isIncome && !record.isLoanPayment && record.title == category
            }
        }

        private func add(_ record: Record, to summary: inout HistorySummary) {
            summary.count += 1
            if record.key.isIncome { summary.income += record.amount }
            else { summary.expense += record.amount }
        }
    }

    static func background<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try await operation()
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
