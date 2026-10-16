// Pro 每月还款的写入边界：增删改、到期自动扣、没扣成的那期怎么处理。
// 扣款就是一笔 `loanID` 指向贷款、不算日均的支出，和现金在同一次保存里改，失败一起回滚。

import Foundation
import SwiftData

enum LoanError: Error, LocalizedError, Equatable {
    case invalidName
    case invalidAmount
    case invalidDueDay
    case invalidPeriods
    case notPending

    var errorDescription: String? {
        switch self {
        case .invalidName: return "名称请填写 1–20 个字，不包含换行。"
        case .invalidAmount: return "月供金额无效或超出允许范围。"
        case .invalidDueDay: return "还款日请选 1–31 号。"
        case .invalidPeriods: return "剩余期数请填 1–\(LoanSchedule.maxPeriods) 之间的整数。"
        case .notPending: return "这一期已经处理过了。"
        }
    }
}

@MainActor
enum LoanStore {
    static let maximumNameCharacters = FinancialLimits.assetItemNameCharacters
    /// 自动扣款写进 History 的备注
    static let autoPaymentNote = "自动扣款"

    // MARK: - 校验

    static func cleanName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maximumNameCharacters,
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw LoanError.invalidName
        }
        return name
    }

    // MARK: - 读取

    static func loans(in context: ModelContext) throws -> [Loan] {
        try context.fetch(FetchDescriptor<Loan>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]))
    }

    /// 所有自动扣款记录（指向某笔贷款的支出）
    static func payments(in context: ModelContext) throws -> [Expense] {
        try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.loanID != nil }))
    }

    /// 以前手动记的、金额正好等于月供的支出，新的在前。添加贷款时问用户是不是月供。
    static func pastRepaymentCandidates(monthlyAmount: Double, in expenses: [Expense]) -> [Expense] {
        guard FinancialFormatting.validAmount(monthlyAmount) else { return [] }
        return expenses
            .filter { $0.loanID == nil && abs($0.amount - monthlyAmount) < 0.005 }
            .sorted { $0.date > $1.date }
    }

    // MARK: - 增删改

    /// 新增（existing 为 nil）或修改。`remaining` 是「还剩几期」，今天到期的那期算已经还过。
    /// 改了还款日或期数时从今天重新起算：之前没扣成的那几期并进新填的期数里。只改名称、金额不动进度。
    /// `pastRepayments` 是表单里列出的旧支出，在 `excludedFromBurn` 里的不再算进日均，其余的算回去。
    @discardableResult
    static func save(
        _ existing: Loan?, name: String, monthlyAmount: Double, dueDay: Int, remaining: Int,
        cashAccountID: UUID? = nil,
        pastRepayments: [Expense] = [], excludedFromBurn: Set<UUID> = [],
        now: Date = .now, calendar: Calendar = .current,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> Loan {
        let name = try cleanName(name)
        guard FinancialFormatting.validAmount(monthlyAmount) else { throw LoanError.invalidAmount }
        guard (1...31).contains(dueDay) else { throw LoanError.invalidDueDay }
        guard (1...LoanSchedule.maxPeriods).contains(remaining) else { throw LoanError.invalidPeriods }

        let today = calendar.startOfDay(for: now)
        let all = try loans(in: context)
        let loan = existing ?? Loan(name: name, monthlyAmount: monthlyAmount, dueDay: dueDay,
                                    periodsAtStart: remaining, startDate: today,
                                    sortOrder: (all.map(\.sortOrder).max() ?? -1) + 1)
        let restartsSchedule: Bool
        if existing != nil {
            let status = LoanSchedule.status(of: loan, payments: try payments(in: context), now: now, calendar: calendar)
            restartsSchedule = loan.dueDay != dueDay || status.remaining != remaining
        } else {
            restartsSchedule = false
        }

        let previousLoan = (loan.name, loan.monthlyAmount, loan.dueDay, loan.periodsAtStart,
                            loan.startDate, loan.processedThrough, loan.settledDates)
        let previousAccount = loan.cashAccountID
        let previousFlags = pastRepayments.map { ($0, $0.countsInBurn) }
        try LedgerStore.perform(in: context, save: save, restore: {
            (loan.name, loan.monthlyAmount, loan.dueDay, loan.periodsAtStart,
             loan.startDate, loan.processedThrough, loan.settledDates) = previousLoan
            loan.cashAccountID = previousAccount
            for (expense, flag) in previousFlags { expense.countsInBurn = flag }
        }) {
            if existing == nil { context.insert(loan) }
            loan.name = name
            loan.monthlyAmount = monthlyAmount
            loan.cashAccountID = cashAccountID
            if restartsSchedule {
                loan.dueDay = dueDay
                loan.periodsAtStart = remaining
                loan.startDate = today
                loan.processedThrough = today
                loan.settledDates = []
            }
            for expense in pastRepayments where expense.loanID == nil {
                expense.countsInBurn = !excludedFromBurn.contains(expense.id)
            }
        }
        return loan
    }

    /// 删掉贷款。已经扣过的月供留在 History，照样不算日均。
    static func delete(
        _ loan: Loan,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws {
        try LedgerStore.perform(in: context, save: save) { context.delete(loan) }
    }

    // MARK: - 到期自动扣

    /// 补齐每笔贷款「上次处理之后、今天及以前」的到期日：现金够就扣一期并写一笔扣款，
    /// 不够就留着等用户处理。同一个到期日只处理一次，重复调用不会重复扣。
    /// 返回这次扣了几期。没有要处理的就不保存；账本里有别的未保存修改时跳过，下次再来。
    @discardableResult
    static func processDue(
        now: Date = .now, calendar: Calendar = .current,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> Int {
        guard !context.hasChanges else { return 0 }
        let loans = try loans(in: context)
        guard !loans.isEmpty else { return 0 }
        let payments = try payments(in: context)
        let work: [(loan: Loan, dates: [Date])] = loans.compactMap { loan in
            let processed = calendar.startOfDay(for: loan.processedThrough ?? loan.startDate)
            let status = LoanSchedule.status(of: loan, payments: payments, now: now, calendar: calendar)
            let dates = status.overdue.filter { $0 > processed }
            return dates.isEmpty ? nil : (loan, dates)
        }
        guard !work.isEmpty else { return 0 }

        let previous = work.map { ($0.loan, $0.loan.processedThrough) }
        var paid = 0
        try LedgerStore.updateAssets(in: context, save: save, restore: {
            for (loan, processed) in previous { loan.processedThrough = processed }
        }) { assets in
            paid = 0
            for (loan, dates) in work {
                for date in dates where canPay(loan, assets: assets, in: context) {
                    let payment = insertPayment(for: loan, on: date, in: context)
                    payment.cashAccountID = try CashAccountStore.applyCashChange(
                        -loan.monthlyAmount, accountID: loan.cashAccountID, assets: assets, in: context)?.id
                    paid += 1
                }
                loan.processedThrough = dates.last
            }
            assets.updatedAt = .now
        }
        return paid
    }

    /// 处理一期没扣成的月供：`fromCash` 为真时现在从现金扣并写一笔扣款；
    /// 为假表示用户从别处还了，只记成已还，不动现金。
    static func resolvePending(
        _ loan: Loan, dueDate: Date, fromCash: Bool,
        now: Date = .now, calendar: Calendar = .current,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws {
        let day = calendar.startOfDay(for: dueDate)
        let status = LoanSchedule.status(of: loan, payments: try payments(in: context), now: now, calendar: calendar)
        guard status.pending.contains(day) else { throw LoanError.notPending }
        if fromCash {
            try LedgerStore.updateAssets(in: context, save: save) { assets in
                let payment = insertPayment(for: loan, on: day, in: context)
                payment.cashAccountID = try CashAccountStore.applyCashChange(
                    -loan.monthlyAmount, accountID: loan.cashAccountID, assets: assets, in: context)?.id
                assets.updatedAt = .now
            }
        } else {
            let previous = loan.settledDates
            try LedgerStore.perform(in: context, save: save, restore: { loan.settledDates = previous }) {
                loan.settledDates.append(day)
            }
        }
    }

    @discardableResult
    private static func insertPayment(for loan: Loan, on day: Date, in context: ModelContext) -> Expense {
        let payment = Expense(amount: loan.monthlyAmount, category: loan.name, note: autoPaymentNote, date: day)
        payment.loanID = loan.id
        payment.countsInBurn = false
        context.insert(payment)
        return payment
    }

    /// 到期这天扣得动吗：没拆账户看现金总数；指定了扣款账户就只看那个账户（银行卡余额不够就是扣不成）；
    /// 没指定（或那个账户删了）时要有一个账户单独够付（每笔只从一个账户扣）
    private static func canPay(_ loan: Loan, assets: UserAssets, in context: ModelContext) -> Bool {
        let accounts = (try? CashAccountStore.accounts(in: context)) ?? []
        let amount = loan.monthlyAmount
        guard !accounts.isEmpty else { return assets.cash >= amount }
        if let bound = accounts.first(where: { $0.id == loan.cashAccountID }) { return bound.amount >= amount }
        return accounts.contains { $0.amount >= amount }
    }
}
