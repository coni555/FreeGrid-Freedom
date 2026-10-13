// 修改一笔已有的支出或收入：金额、分类/来源、日期、备注。

import SwiftUI
import SwiftData

struct EditTransactionSheet: View {
    let transaction: LedgerTransaction

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [Expense]

    @State private var saveError: String?
    @State private var amount: String
    @State private var title: String
    @State private var note: String
    @State private var date: Date

    @AppStorage(ExpenseCategoryStorage.key) private var encodedOptions = ""

    init(transaction: LedgerTransaction) {
        self.transaction = transaction
        _amount = State(initialValue: Self.amountText(transaction.amount))
        _title = State(initialValue: transaction.title)
        _note = State(initialValue: transaction.note)
        _date = State(initialValue: transaction.date)
    }

    /// 和记支出时同一份选项；这笔账原来的分类即使已删除也保留在列表里，不逼用户改掉它。
    private var categories: [String] {
        let options = ProFeatures.canCustomizeExpenseCategories
            ? ExpenseCategoryStorage.decode(encodedOptions).including(expenses.map(\.category)).visibleNames
            : ExpenseCategory.canonical
        return options.contains(transaction.title) ? options : options + [transaction.title]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("金额 (元)") {
                    TextField("0.00", text: $amount)
                        .decimalKeyboard()
                        .font(.system(.body, design: .rounded).monospacedDigit())
                        .accessibilityIdentifier("edit-amount")
                }
                switch transaction.kind {
                case .expense:
                    // 分类这组不加小标题: 行里已经写了「分类」
                    Section {
                        Picker("分类", selection: $title) {
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                        .accessibilityIdentifier("edit-category-picker")
                    }
                case .income:
                    Section("来源") {
                        TextField("工资 / 投资 / 副业 / ...", text: $title)
                            .font(.system(.body, design: .rounded))
                    }
                }
                Section("日期") {
                    TransactionDateRow(date: $date, latestDate: max(Date.now, transaction.date))
                }
                Section("备注 (可选)") {
                    TextField("备注", text: $note)
                        .font(.system(.body, design: .rounded))
                        .accessibilityIdentifier("edit-note")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(transaction.kind == .expense ? "修改支出" : "修改收入")
            .inlineNavTitle()
            .saveErrorAlert($saveError)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(pendingEdit == nil)
                        .foregroundStyle(pendingEdit == nil ? Color.inkFaint : Color.skyDeep)
                        .fontWeight(.medium)
                }
            }
        }
    }

    /// 输入有效时要写入的内容；无效时为 nil，保存按钮不可用。
    private var pendingEdit: LedgerStore.TransactionEdit? {
        EditTransactionSheet.edit(
            for: transaction, amountText: amount, title: title, note: note, date: date
        )
    }

    /// 没碰过的金额和日期保持原值：旧备份里的退款(负数)、零元记录和具体时刻不会因为只改分类而丢失。
    static func edit(
        for transaction: LedgerTransaction,
        amountText: String, title: String, note: String, date: Date,
        calendar: Calendar = .current
    ) -> LedgerStore.TransactionEdit? {
        let original = transaction.amount
        let newAmount: Double
        if amountText == Self.amountText(original) {
            newAmount = original
        } else {
            guard let value = Double(amountText), FinancialFormatting.validAmount(value) else { return nil }
            newAmount = value
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= FinancialLimits.nameCharacters,
              note.count <= FinancialLimits.noteCharacters else { return nil }
        let newDate = calendar.isDate(date, inSameDayAs: transaction.date) ? transaction.date : date
        return LedgerStore.TransactionEdit(amount: newAmount, title: name, note: note, date: newDate)
    }

    static func amountText(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    /// 保存成功才关闭；失败保留输入。
    private func save() {
        guard let edit = pendingEdit else { return }
        do {
            try LedgerStore.edit(id: transaction.id, kind: transaction.kind, in: modelContext, to: edit)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
