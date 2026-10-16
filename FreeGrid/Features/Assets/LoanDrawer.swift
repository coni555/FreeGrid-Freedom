// Pro 每月还款：资产页上和「资产」「现金」同样的抽屉。标题行是每月一共还多少，下面一行写下次哪天扣哪笔；
// 展开后一笔贷款一行（点开编辑或删除），没扣成的那期在行下面给出处理入口。

import SwiftUI
import SwiftData

struct LoanDrawer: View {
    @Query(sort: [SortDescriptor(\Loan.sortOrder), SortDescriptor(\Loan.createdAt)])
    private var loans: [Loan]
    @Query private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    @Environment(\.modelContext) private var modelContext
    @AppStorage("loansDrawerOpen", store: AppPreferences.store) private var isOpen = true

    @State private var adding = false
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

    private var canManage: Bool { ProFeatures.canManageLoans }

    var body: some View {
        let payments = expenses.filter { $0.loanID != nil }
        let statuses = loans.map { LoanSchedule.status(of: $0, payments: payments) }
        let active = zip(loans, statuses).filter { !$0.1.isPaidOff }
        let monthlyTotal = active.reduce(0) { $0 + $1.0.monthlyAmount }
        let next = active.compactMap { pair in pair.1.nextDue.map { (pair.0, $0) } }.min { $0.1 < $1.1 }
        let pendingCount = statuses.reduce(0) { $0 + $1.pending.count }

        AccountDrawer(title: "每月还款", color: .cashBlue, count: loans.isEmpty ? nil : "\(loans.count) 笔",
                      total: loans.isEmpty ? nil : monthlyTotal, totalSuffix: "/月", punched: true,
                      subtitle: subtitle(next: next, pendingCount: pendingCount, empty: loans.isEmpty),
                      isOpen: $isOpen, headerID: "loans-drawer") {
            ForEach(Array(zip(loans, statuses)), id: \.0.id) { loan, status in
                loanRow(loan, status: status)
            }
            if canManage {
                DrawerAddRow(title: loans.isEmpty ? "添加房贷、车贷" : "添加还款", showsPro: false,
                             identifier: "add-loan-button") { adding = true }
            }
            if !loans.isEmpty {
                DrawerFooter(text: canManage
                             ? "到期那天自动从现金扣，自由天数会把每期的钱先留出来。"
                             : "管理还款是 Pro 功能，已经加的照常自动扣。点一行可以删除。")
            }
        }
        .saveErrorAlert($saveError)
        .sheet(isPresented: $adding) { LoanSheet(existing: nil) }
        .sheet(item: $editing) { LoanSheet(existing: $0) }
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
            Text("以后不再自动扣。已经扣过的月供留在 History。")
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

    /// 收起时也看得到的一行：有没扣成的先说这个，否则说下次哪天扣哪笔
    private func subtitle(next: (Loan, Date)?, pendingCount: Int, empty: Bool) -> String? {
        if empty { return "房贷、车贷、分期，到期自动扣" }
        if pendingCount > 0 { return "有 \(pendingCount) 期没扣成，展开处理" }
        guard let (loan, date) = next else { return "都还清了" }
        return "下次 \(Self.monthDay(date)) 扣「\(loan.name)」"
    }

    // MARK: - 一行贷款

    private func loanRow(_ loan: Loan, status: LoanSchedule.Status) -> some View {
        let paidOff = status.isPaidOff
        var detail = paidOff ? "已还清" : "每月 \(loan.dueDay) 日 · 还剩 \(status.remaining) 期"
        if !paidOff, let account = boundAccount(of: loan) { detail += " · \(account.name)" }
        return VStack(alignment: .leading, spacing: 0) {
            Hairline()
            Button {
                if canManage { editing = loan } else { pendingDelete = loan }
            } label: {
                HStack(spacing: 0) {
                    // 和首页格子上的还款日同一个记号
                    PunchedCell(cornerRadius: 1.5)
                        .fill(paidOff ? Color.inkGhost : Color.cashBlue, style: FillStyle(eoFill: true))
                        .frame(width: 9, height: 9)
                        .frame(width: 19, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loan.name)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(paidOff ? Color.inkMuted : Color.ink)
                            .lineLimit(1)
                        Text(detail)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.inkFaint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Spacing.sm)
                    Text("−¥\(FinancialFormatting.wholeNumber(loan.monthlyAmount))")
                        .font(.system(.caption, design: .monospaced))
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
