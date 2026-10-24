// 把收入与支出统一为历史列表的一行。

import Foundation

enum LedgerTransaction: Identifiable {
    case expense(Expense)
    case income(Income)

    var id: UUID {
        switch self {
        case .expense(let e): return e.id
        case .income(let i): return i.id
        }
    }

    /// 只把搜索需要的事实复制出去，不把 SwiftData 模型传给后台。
    var searchRecord: HistorySearch.Record {
        HistorySearch.Record(key: .init(id: id, isIncome: kind == .income), date: date,
                             amount: amount, title: displayTitle, note: displayNote,
                             isLoanPayment: isLoanPayment, isExcludedFromBurn: isExcludedFromBurn)
    }

    /// 用于排序的日期
    var date: Date {
        switch self {
        case .expense(let e): return e.date
        case .income(let i): return i.date
        }
    }
    var kind: TransactionKind {
        switch self {
        case .expense: return .expense
        case .income: return .income
        }
    }

    var title: String {
        switch self {
        case .expense(let expense): return expense.category
        case .income(let income): return income.source
        }
    }

    var note: String {
        switch self {
        case .expense(let expense): return expense.note
        case .income(let income): return income.note
        }
    }

    /// 界面上显示的标题：默认分类按当前语言，自建分类、贷款名和收入来源原样
    var displayTitle: String {
        kind == .expense ? ExpenseCategory.displayName(title) : title
    }

    /// 自动扣款的那句备注是 App 写进账本的，按当前语言显示；用户自己写的原样
    var displayNote: String {
        isLoanPayment && note == LoanStore.autoPaymentNote ? String(localized: "自动扣款") : note
    }

    /// Pro 现金账户：这笔记在哪个账户
    var cashAccountID: UUID? {
        switch self {
        case .expense(let expense): return expense.cashAccountID
        case .income(let income): return income.cashAccountID
        }
    }

    func setCashAccountID(_ id: UUID?) {
        switch self {
        case .expense(let expense): expense.cashAccountID = id
        case .income(let income): income.cashAccountID = id
        }
    }

    /// Pro 每月还款到期自动扣的那一笔
    var isLoanPayment: Bool {
        if case .expense(let expense) = self { return expense.loanID != nil }
        return false
    }

    /// 用户确认过是以前记的月供、不再算进日均的手动支出
    var isExcludedFromBurn: Bool {
        if case .expense(let expense) = self { return expense.loanID == nil && !expense.countsInBurn }
        return false
    }

    /// 记录里保存的金额，不带方向。
    var amount: Double {
        switch self {
        case .expense(let expense): return expense.amount
        case .income(let income): return income.amount
        }
    }

    /// 正数代表现金增加，负数代表现金减少。负数支出（退款）自然显示为增加。
    var cashChange: Double {
        switch self {
        case .expense(let expense): return -expense.amount
        case .income(let income): return income.amount
        }
    }

    var undoMessage: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let noteText = displayNote.isEmpty ? "" : " · \(displayNote)"
        return "\(formatter.string(from: date)) · \(displayTitle)\(noteText)\n\(FinancialFormatting.signedYuan(cashChange))\n\n"
            + String(localized: "撤销后现金变化：\(FinancialFormatting.signedYuan(-cashChange))")
    }
}
