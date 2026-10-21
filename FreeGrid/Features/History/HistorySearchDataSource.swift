import SwiftUI
import SwiftData

/// 只有账本字段变化才提取快照；输入、焦点和月份展开不会重新扫描 SwiftData。
struct HistorySearchDataSource: View, Equatable {
    let search: HistorySearchState
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.search === rhs.search }

    private struct Source: Equatable {
        let expenses: [HistorySearch.Record]
        let incomes: [HistorySearch.Record]
        // 替换导入可能保留 UUID 和全部字段，但模型对象已换，编辑/撤销必须拿到新对象。
        let identities: [ObjectIdentifier]
        let locale: Locale
        let calendar: Calendar
    }

    var body: some View {
        let source = Source(
            expenses: expenses.map { LedgerTransaction.expense($0).searchRecord },
            incomes: incomes.map { LedgerTransaction.income($0).searchRecord },
            identities: expenses.map(ObjectIdentifier.init) + incomes.map(ObjectIdentifier.init),
            locale: locale, calendar: calendar)
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: source, initial: true) { _, value in
                var records: [HistorySearch.Key: LedgerTransaction] = [:]
                for expense in expenses { records[.init(id: expense.id, isIncome: false)] = .expense(expense) }
                for income in incomes { records[.init(id: income.id, isIncome: true)] = .income(income) }
                search.replaceData(expenses: value.expenses, incomes: value.incomes, records: records,
                                   locale: value.locale, calendar: value.calendar)
            }
    }
}
