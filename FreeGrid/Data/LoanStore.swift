// 固定支出和贷款的写入边界：增删改、到期自动扣、没扣成的那期怎么处理。
// 扣款就是一笔 `loanID` 指向它、不算日均的支出，和现金在同一次保存里改，失败一起回滚。

import Foundation
import SwiftData

enum LoanError: Error, LocalizedError, Equatable {
    case invalidName
    case invalidAmount
    case invalidDueDay
    case invalidPeriods
    case invalidInterval
    case invalidNextDue
    case notPending

    var errorDescription: String? {
        switch self {
        case .invalidName: return "名称请填写 1–20 个字，不包含换行。"
        case .invalidAmount: return "金额不对，或者超出了能记的范围。"
        case .invalidDueDay: return "还款日请选 1–31 号。"
        case .invalidPeriods: return "剩余期数请填 1–\(LoanSchedule.maxPeriods) 之间的整数。"
        case .invalidInterval: return "请选每 1、2、3、6 或 12 个月一次。"
        case .invalidNextDue: return "下次付款请选明天到一年以内的日子。"
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

    /// 以前手动记的、金额正好等于这一期的支出，新的在前。添加时问用户是不是以前记的。
    static func pastRepaymentCandidates(monthlyAmount: Double, in expenses: [Expense]) -> [Expense] {
        guard FinancialFormatting.validAmount(monthlyAmount) else { return [] }
        return expenses
            .filter { $0.loanID == nil && abs($0.amount - monthlyAmount) < 0.005 }
            .sorted { $0.date > $1.date }
    }

    // MARK: - 增删改

    /// 贷款：新增（existing 为 nil）或修改。`remaining` 是「还剩几期」，今天到期的那期算已经还过。
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
        guard (1...31).contains(dueDay) else { throw LoanError.invalidDueDay }
        guard (1...LoanSchedule.maxPeriods).contains(remaining) else { throw LoanError.invalidPeriods }
        let today = calendar.startOfDay(for: now)
        return try write(existing, name: name, amount: monthlyAmount, cashAccountID: cashAccountID,
                         pastRepayments: pastRepayments, excludedFromBurn: excludedFromBurn,
                         isOngoing: false, in: context, save: save,
                         schedule: Schedule(dueDay: dueDay, periods: remaining, intervalMonths: 1, startDate: today),
                         restarts: { loan in
            let status = LoanSchedule.status(of: loan, payments: try payments(in: context), now: now, calendar: calendar)
            return loan.dueDay != dueDay || status.remaining != remaining
        })
    }

    /// 固定支出（房租、保险、订阅）：新增或修改。`nextDue` 是下次哪天付，之后每隔 `intervalMonths` 个月一次。
    /// 改了下次付款日或周期时从新的日子重新起算，之前没扣成的那几期不再追。只改名称、金额不动进度。
    @discardableResult
    static func saveFixed(
        _ existing: Loan?, name: String, amount: Double, intervalMonths: Int, nextDue: Date,
        cashAccountID: UUID? = nil,
        pastRepayments: [Expense] = [], excludedFromBurn: Set<UUID> = [],
        now: Date = .now, calendar: Calendar = .current,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws -> Loan {
        guard LoanSchedule.intervals.contains(intervalMonths) else { throw LoanError.invalidInterval }
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: nextDue)
        guard due > today, let latest = calendar.date(byAdding: .year, value: 1, to: today), due <= latest,
              let start = calendar.date(byAdding: .day, value: -1, to: due) else { throw LoanError.invalidNextDue }
        let dueDay = calendar.component(.day, from: due)
        return try write(existing, name: name, amount: amount, cashAccountID: cashAccountID,
                         pastRepayments: pastRepayments, excludedFromBurn: excludedFromBurn,
                         isOngoing: true, in: context, save: save,
                         schedule: Schedule(dueDay: dueDay, periods: 0, intervalMonths: intervalMonths, startDate: start),
                         restarts: { loan in
            let status = LoanSchedule.status(of: loan, payments: try payments(in: context), now: now, calendar: calendar)
            return loan.intervalMonths != intervalMonths || status.nextDue != due
        })
    }

    private struct Schedule {
        let dueDay: Int
        let periods: Int
        let intervalMonths: Int
        let startDate: Date
    }

    private static func write(
        _ existing: Loan?, name: String, amount: Double, cashAccountID: UUID?,
        pastRepayments: [Expense], excludedFromBurn: Set<UUID>, isOngoing: Bool,
        in context: ModelContext, save: LedgerStore.SaveAction,
        schedule: Schedule, restarts: (Loan) throws -> Bool
    ) throws -> Loan {
        let name = try cleanName(name)
        guard FinancialFormatting.validAmount(amount) else { throw LoanError.invalidAmount }

        let all = try loans(in: context)
        let loan = existing ?? Loan(name: name, monthlyAmount: amount, dueDay: schedule.dueDay,
                                    periodsAtStart: schedule.periods, startDate: schedule.startDate,
                                    sortOrder: (all.map(\.sortOrder).max() ?? -1) + 1,
                                    isOngoing: isOngoing, intervalMonths: schedule.intervalMonths)
        let restartsSchedule = existing != nil ? try restarts(loan) : false

        let previousLoan = (loan.name, loan.monthlyAmount, loan.dueDay, loan.periodsAtStart,
                            loan.startDate, loan.processedThrough, loan.settledDates)
        let previousInterval = loan.intervalMonths
        let previousAccount = loan.cashAccountID
        let previousFlags = pastRepayments.map { ($0, $0.countsInBurn) }
        try LedgerStore.perform(in: context, save: save, restore: {
            (loan.name, loan.monthlyAmount, loan.dueDay, loan.periodsAtStart,
             loan.startDate, loan.processedThrough, loan.settledDates) = previousLoan
            loan.cashAccountID = previousAccount
            loan.intervalMonths = previousInterval
            for (expense, flag) in previousFlags { expense.countsInBurn = flag }
        }) {
            if existing == nil { context.insert(loan) }
            loan.name = name
            loan.monthlyAmount = amount
            loan.cashAccountID = cashAccountID
            if restartsSchedule {
                loan.dueDay = schedule.dueDay
                loan.periodsAtStart = schedule.periods
                loan.intervalMonths = schedule.intervalMonths
                loan.startDate = schedule.startDate
                loan.processedThrough = schedule.startDate
                loan.settledDates = []
            }
            for expense in pastRepayments where expense.loanID == nil {
                expense.countsInBurn = !excludedFromBurn.contains(expense.id)
            }
        }
        return loan
    }

    /// 删掉。已经扣过的留在 History，照样不算日均。
    static func delete(
        _ loan: Loan,
        in context: ModelContext,
        save: LedgerStore.SaveAction = { try $0.save() }
    ) throws {
        try LedgerStore.perform(in: context, save: save) { context.delete(loan) }
    }

    // MARK: - 到期自动扣

    /// 补齐每一笔「上次处理之后、今天及以前」的到期日：现金够就扣一期并写一笔扣款，
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

    /// 处理没扣成的一期：`fromCash` 为真时现在从现金扣并写一笔扣款；
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
