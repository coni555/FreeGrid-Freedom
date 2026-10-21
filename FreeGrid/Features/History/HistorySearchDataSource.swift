import SwiftUI
import SwiftData
import Observation

/// body 只比较记录身份和地区设置；焦点或键盘更新不读取整本账的字段。
struct HistorySearchDataSource: View, Equatable {
    let search: HistorySearchState
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @State private var observer = HistorySearchModelObserver()

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.search === rhs.search }

    private struct Input: Equatable {
        // 替换导入可能保留 UUID 和全部字段，但模型对象已换。
        let identities: [ObjectIdentifier]
        let locale: Locale
        let calendar: Calendar
    }

    var body: some View {
        let input = Input(identities: expenses.map(ObjectIdentifier.init) + incomes.map(ObjectIdentifier.init),
                          locale: locale, calendar: calendar)
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: input, initial: true) { _, value in
                observer.update(search: search, expenses: expenses, incomes: incomes,
                                locale: value.locale, calendar: value.calendar)
            }
    }
}

/// 在 SwiftUI body 之外跟踪实际读取的模型字段。
/// 模型始终留在主 actor；字段变动后重新订阅，交给搜索的仍是 Sendable 快照。
@MainActor
final class HistorySearchModelObserver {
    private weak var search: HistorySearchState?
    private var expenses: [Expense] = []
    private var incomes: [Income] = []
    private var locale = Locale.current
    private var calendar = Calendar.current
    private var generation = 0
    private var managedModels: Set<ObjectIdentifier> = []

    func update(search: HistorySearchState, expenses: [Expense], incomes: [Income],
                locale: Locale = .current, calendar: Calendar = .current) {
        self.search = search
        self.expenses = expenses
        self.incomes = incomes
        self.locale = locale
        self.calendar = calendar
        managedModels = Set(expenses.filter { $0.modelContext != nil }.map(ObjectIdentifier.init) +
                            incomes.filter { $0.modelContext != nil }.map(ObjectIdentifier.init))
        refresh()
    }

    private func refresh() {
        generation += 1
        let current = generation
        let snapshot = withObservationTracking {
            // 保存删除后 isDeleted 可能复位，但 modelContext 已清空；不要再读失效模型的字段。
            let expenses = expenses.filter { !$0.isDeleted && (!managedModels.contains(ObjectIdentifier($0)) || $0.modelContext != nil) }
            let incomes = incomes.filter { !$0.isDeleted && (!managedModels.contains(ObjectIdentifier($0)) || $0.modelContext != nil) }
            let expenseValues = expenses.map { LedgerTransaction.expense($0).searchRecord }
            let incomeValues = incomes.map { LedgerTransaction.income($0).searchRecord }
            var records: [HistorySearch.Key: LedgerTransaction] = [:]
            for (value, model) in zip(expenseValues, expenses) { records[value.key] = .expense(model) }
            for (value, model) in zip(incomeValues, incomes) { records[value.key] = .income(model) }
            return (expenseValues, incomeValues, records)
        } onChange: { [weak self] in
            // Observation 在 willSet 通知；排回主 actor，读取本轮修改完成后的值。
            // 同一轮多字段修改只触发一次，旧集合的回调不能覆盖新集合。
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.refresh()
            }
        }
        search?.replaceData(expenses: snapshot.0, incomes: snapshot.1, records: snapshot.2,
                            locale: locale, calendar: calendar)
    }
}
