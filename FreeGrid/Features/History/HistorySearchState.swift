import Foundation
import Observation

/// 输入框只更新 text；结果列表只观察已经完成的搜索和分组。
@MainActor
@Observable
final class HistorySearchState {
    struct DisplayMonth: Identifiable {
        let month: HistoryMonth
        let transactions: [HistorySearch.Row]
        let summary: HistorySummary
        var id: HistoryMonth { month }
    }

    private(set) var text = ""
    private(set) var isEmpty = true
    private(set) var appliedQuery = ""
    private(set) var result: HistorySearch.Result?
    private(set) var months: [DisplayMonth] = []
    private(set) var suggestions: [String] = []
    private(set) var indexRevision = 0
    @ObservationIgnored private var records: [HistorySearch.Key: LedgerTransaction] = [:]
    @ObservationIgnored private var index: HistorySearch.Index?
    @ObservationIgnored private var notesCache: [HistorySearch.Filter: [String]] = [:]
    @ObservationIgnored private var filter: HistorySearch.Filter = .all
    @ObservationIgnored private var active = false
    @ObservationIgnored private var needsInitialFocus = false
    @ObservationIgnored private var dataRevision = 0
    @ObservationIgnored private var requestID = 0
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let evaluate: @Sendable (HistorySearch.Index, String, HistorySearch.Filter) async throws -> HistorySearch.Result

    init(debounce: Duration = .milliseconds(180),
         evaluate: @escaping @Sendable (HistorySearch.Index, String, HistorySearch.Filter) async throws -> HistorySearch.Result = {
             try $0.search($1, filter: $2)
         }) {
        self.debounce = debounce
        self.evaluate = evaluate
    }

    func replaceData(expenses: [HistorySearch.Record], incomes: [HistorySearch.Record],
                     records: [HistorySearch.Key: LedgerTransaction], locale: Locale = .current, calendar: Calendar = .current) {
        dataRevision += 1
        let revision = dataRevision
        preparation?.cancel()
        invalidateRequest()
        self.records = records
        let previous = index
        index = nil
        notesCache = [:]
        suggestions = []
        result = nil
        months = []
        preparation = Task { [weak self] in
            do {
                let (built, notes) = try await HistorySearch.background {
                    let built = try HistorySearch.Index(expenses: expenses, incomes: incomes, previous: previous,
                                                        locale: locale, calendar: calendar)
                    return (built, try built.frequentNotes())
                }
                guard let self, !Task.isCancelled, self.dataRevision == revision else { return }
                self.index = built
                self.indexRevision += 1
                self.notesCache[.all] = notes
                if self.filter == .all { self.suggestions = notes }
                self.schedule(immediately: true)
            } catch { /* 取消旧快照时，新任务接手；不展示过期结果。 */ }
        }
    }

    func transaction(for key: HistorySearch.Key) -> LedgerTransaction? { records[key] }

    func begin(filter: HistorySearch.Filter) {
        active = true
        needsInitialFocus = true
        self.filter = filter
        suggestions = notesCache[filter] ?? []
        schedule(immediately: true)
    }

    /// List 里的输入行可能多次出现；滚回顶部不能再次弹键盘。
    func takeInitialFocus() -> Bool {
        guard active, needsInitialFocus else { return false }
        needsInitialFocus = false
        return true
    }

    func end() {
        active = false
        needsInitialFocus = false
        invalidateRequest()
        text = ""
        isEmpty = true
        appliedQuery = ""
        result = nil
        months = []
    }

    func setText(_ value: String, immediately: Bool = false) {
        guard text != value || immediately else { return }
        text = value
        let empty = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmpty != empty { isEmpty = empty }
        if isEmpty {
            appliedQuery = ""
            result = nil
            months = []
        }
        schedule(immediately: immediately)
    }

    func setFilter(_ value: HistorySearch.Filter) {
        guard filter != value else { return }
        filter = value
        suggestions = notesCache[value] ?? []
        result = nil
        months = []
        schedule(immediately: true)
    }

    private func invalidateRequest() {
        requestID += 1
        request?.cancel()
        request = nil
    }

    private func schedule(immediately: Bool) {
        invalidateRequest()
        guard active, let index else { return }
        let id = requestID
        let revision = dataRevision
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = filter
        let cachedNotes = notesCache[filter]
        let evaluate = evaluate
        let delay = debounce
        // 清空输入只需要使用已有推荐，不必启动后台匹配。
        if query.isEmpty, let cachedNotes {
            suggestions = cachedNotes
            return
        }
        request = Task { [weak self] in
            do {
                if !immediately, !query.isEmpty { try await Task.sleep(for: delay) }
                let (result, notes) = try await HistorySearch.background {
                    let notes = try cachedNotes ?? index.frequentNotes(filter: filter)
                    let result = query.isEmpty ? nil : try await evaluate(index, query, filter)
                    return (result, notes)
                }
                guard let self, !Task.isCancelled, self.requestID == id, self.dataRevision == revision else { return }
                self.notesCache[filter] = notes
                self.suggestions = notes
                self.result = result
                if let result, self.appliedQuery != result.query { self.appliedQuery = result.query }
                self.months = result?.months.map { group in
                    DisplayMonth(month: group.month, transactions: group.rows, summary: group.summary)
                } ?? []
            } catch { /* 快速输入、清空和取消都通过取消任务结束。 */ }
        }
    }
}
