// 固定支出：资产页上和「资产」「现金」同样的抽屉。标题行是每月一共付多少，下面一行写下次哪天扣哪笔；
// 展开后一笔一行（点开编辑或删除），没扣成的那期在行下面给出处理入口。
// 房租这类固定支出免费；房贷、车贷这类带期数的贷款是 Pro，行首的色块打孔，和首页格子上的还款日同一个记号。

import SwiftUI
import SwiftData

/// 经典版的固定支出抽屉：标题行 + `LoanRows`
struct LoanDrawer: View {
    @Query(sort: [SortDescriptor(\Loan.sortOrder), SortDescriptor(\Loan.createdAt)])
    private var loans: [Loan]
    @Query private var expenses: [Expense]
    @AppStorage("loansDrawerOpen", store: AppPreferences.store) private var isOpen = true

    var body: some View {
        let summary = LoanRows.Summary(loans: loans, expenses: expenses)
        AccountDrawer(title: "固定支出", color: .cashBlue, count: loans.isEmpty ? nil : "\(loans.count) 笔",
                      total: loans.isEmpty ? nil : summary.monthlyTotal, totalSuffix: "/月",
                      punched: loans.contains(where: \.punchesGrid),
                      subtitle: loans.isEmpty ? LoanRows.emptyLine : summary.line,
                      isOpen: $isOpen, headerID: "loans-drawer") {
            LoanRows()
        }
    }
}

/// 固定支出的各行：一笔一行（点开编辑；贷款在退款后点开问删不删），没扣成的那期在行下面给处理入口；最后是添加和说明。
struct LoanRows: View {
    @Query(sort: [SortDescriptor(\Loan.sortOrder), SortDescriptor(\Loan.createdAt)])
    private var loans: [Loan]
    @Query private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.amountUnit) private var unit

    @State private var adding: LoanSheet.Kind?
    @State private var showingPro = false
    @State private var editing: Loan?
    @State private var pendingDelete: Loan?
    /// 没扣成的那一期，等用户选「从现金扣」还是「从别处还的」
    @State private var resolving: PendingPayment?
    @State private var saveError: String?

    struct PendingPayment: Identifiable {
        let loan: Loan
        let dueDate: Date
        var id: String { "\(loan.id)-\(dueDate.timeIntervalSince1970)" }
    }

    /// 能不能加、改贷款（Pro）。固定支出谁都能管
    private var canManageLoans: Bool { ProFeatures.canManageLoans }

    /// 还没加过时，标题下面那行
    static let emptyLine = "房租、水电、会员，到日子自动记账"

    /// 每月一共付多少、下次哪天扣哪笔、有几期没扣成：标题行和新版「每月」里用
    struct Summary {
        /// 每 3 个月一次的折成每月
        let monthlyTotal: Double
        /// 「有 1 期没扣成，展开处理」或「下次 10月25日 扣「车贷」」
        let line: String

        init(loans: [Loan], expenses: [Expense], now: Date = .now) {
            let payments = expenses.filter { $0.loanID != nil }
            let statuses = loans.map { LoanSchedule.status(of: $0, payments: payments, now: now) }
            let active = zip(loans, statuses).filter { !$0.1.isPaidOff }
            monthlyTotal = active.reduce(0) { $0 + $1.0.monthlyEquivalent }
            let pending = statuses.reduce(0) { $0 + $1.pending.count }
            if pending > 0 {
                line = "有 \(pending) 期没扣成，展开处理"
            } else if let (loan, date) = active.compactMap({ pair in pair.1.nextDue.map { (pair.0, $0) } })
                        .min(by: { $0.1 < $1.1 }) {
                line = "下次 \(LoanRows.monthDay(date)) 扣「\(loan.name)」"
            } else {
                line = "没有要付的了"
            }
        }
    }

    var body: some View {
        let payments = expenses.filter { $0.loanID != nil }
        let statuses = loans.map { LoanSchedule.status(of: $0, payments: payments) }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(zip(loans, statuses)), id: \.0.id) { loan, status in
                loanRow(loan, status: status)
            }
            DrawerAddRow(title: "添加固定支出", showsPro: false, identifier: "add-fixed-button") { adding = .fixed }
            DrawerAddRow(title: "添加贷款", showsPro: !canManageLoans, identifier: "add-loan-button") {
                if canManageLoans { adding = .loan } else { showingPro = true }
            }
            if !loans.isEmpty {
                let lockedLoans = !canManageLoans && loans.contains(where: \.punchesGrid)
                DrawerFooter(text: lockedLoans
                             ? "管理贷款是 Pro 功能，已经加的照常自动扣。点贷款那一行可以删除。"
                             : "到日子在 App 里自动记一笔，从现金扣，不会动你的银行卡。自由天数会把每期的钱先留出来。",
                             locked: lockedLoans, showsActions: false)
            }
        }
        .saveErrorAlert($saveError)
        .sheet(item: $adding) { LoanSheet(existing: nil, kind: $0) }
        .sheet(item: $editing) { LoanSheet(existing: $0) }
        .proPaywall(isPresented: $showingPro, topic: .loans)
        .confirmationDialog("删除「\(pendingDelete?.name ?? "")」？",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { loan in
            Button("删除", role: .destructive) {
                do { try LoanStore.delete(loan, in: modelContext) }
                catch { saveError = error.localizedDescription }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("以后不再自动扣。已经扣过的留在 History。")
        }
        .confirmationDialog(
            resolving.map { "\(Self.monthDay($0.dueDate))这期 ¥\(FinancialFormatting.wholeNumber($0.loan.monthlyAmount))" } ?? "",
            isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } }),
            titleVisibility: .visible,
            presenting: resolving
        ) { payment in
            Button(boundAccount(of: payment.loan).map { "从「\($0.name)」扣" } ?? "从现金扣") {
                resolve(payment, fromCash: true)
            }
            Button("从别处还的，不动现金") { resolve(payment, fromCash: false) }
            Button("取消", role: .cancel) { resolving = nil }
        } message: { payment in
            Text(boundAccount(of: payment.loan).map { "到期那天「\($0.name)」余额不够，没有自动扣。" }
                 ?? "到期那天现金不够，没有自动扣。")
        }
    }


    // MARK: - 一行

    private func loanRow(_ loan: Loan, status: LoanSchedule.Status) -> some View {
        let paidOff = status.isPaidOff
        var detail: String
        if loan.isOngoing {
            detail = loan.intervalMonths == 1 ? "每月 \(loan.dueDay) 日"
                : "\(LoanSheet.intervalLabel(loan.intervalMonths)) · 下次 \(status.nextDue.map(Self.monthDay) ?? "—")"
        } else {
            detail = paidOff ? "已还清" : "每月 \(loan.dueDay) 日 · 还剩 \(status.remaining) 期"
        }
        if !paidOff, let account = boundAccount(of: loan) { detail += " · \(account.name)" }
        return VStack(alignment: .leading, spacing: 0) {
            Hairline()
            Button {
                if loan.isOngoing || canManageLoans { editing = loan } else { pendingDelete = loan }
            } label: {
                HStack(spacing: 0) {
                    // 贷款和首页格子上的还款日同一个记号；固定支出不打孔
                    Group {
                        if loan.punchesGrid {
                            PunchedCell(cornerRadius: 1.5)
                                .fill(paidOff ? Color.inkGhost : Color.cashBlue, style: FillStyle(eoFill: true))
                        } else {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(Color.cashBlue)
                        }
                    }
                    .frame(width: 9, height: 9)
                    .frame(width: 19, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loan.name)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(paidOff ? Color.inkMuted : Color.ink)
                            .lineLimit(1)
                        Text(detail)
                            .font(.system(.caption2, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkFaint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Spacing.sm)
                    Text(unit.text(loan.monthlyAmount, sign: "−"))
                        .font(.system(.footnote, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(paidOff ? Color.inkFaint : Color.inkMuted)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("loan-row")

            if let due = status.pending.first {
                Button {
                    resolving = PendingPayment(loan: loan, dueDate: due)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(Self.monthDay(due))这期没扣：\(boundAccount(of: loan).map { "「\($0.name)」余额不够" } ?? "现金不够")")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        Text("处理")
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.skyDeep)
                        Spacer()
                    }
                    .padding(.leading, 19)
                    .padding(.bottom, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("loan-pending")
            }
        }
    }

    /// 这笔贷款指定的扣款账户（还在的话）
    private func boundAccount(of loan: Loan) -> CashAccount? {
        cashAccounts.first { $0.id == loan.cashAccountID }
    }

    private func resolve(_ payment: PendingPayment, fromCash: Bool) {
        do {
            try LoanStore.resolvePending(payment.loan, dueDate: payment.dueDate, fromCash: fromCash, in: modelContext)
            resolving = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// 「11月14日」
    static func monthDay(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }
}
