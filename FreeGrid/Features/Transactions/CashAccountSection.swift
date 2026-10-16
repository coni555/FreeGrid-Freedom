// Pro 现金账户：记账表单里的「从哪个账户扣 / 进哪个账户」一行。没拆账户时不出现。
// 支出默认按扣款顺序挑第一个够付的；收入默认进上次用过的账户。用户点开可以换。

import SwiftUI

struct CashAccountSection: View {
    let accounts: [CashAccount]
    let kind: TransactionKind
    /// 这笔的金额；还没填好时为 nil
    let amount: Double?
    /// 用户手动选的账户；nil = 用默认的
    @Binding var picked: UUID?
    /// 没手动选时用哪个（编辑已有记录时是它原来的账户，收入是上次用过的）
    var fallback: UUID? = nil

    /// 支出：按顺序第一个够付的
    private var automatic: CashAccount? {
        if kind == .expense, fallback == nil {
            return CashAccountStore.payer(for: amount ?? 0, in: accounts)
        }
        return accounts.first { $0.id == fallback } ?? accounts.first
    }

    var chosen: CashAccount? { accounts.first { $0.id == picked } ?? automatic }

    var body: some View {
        Section {
            Menu {
                Picker(kind == .expense ? "从哪个账户扣" : "存进哪个账户", selection: Binding(
                    get: { chosen?.id },
                    set: { picked = $0 }
                )) {
                    ForEach(accounts) { account in
                        Text("\(account.name) · ¥\(account.amount.formatted(.number))").tag(Optional(account.id))
                    }
                }
            } label: {
                HStack {
                    Text(kind == .expense ? "从哪扣" : "存进")
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Text(chosen?.name ?? "")
                        .foregroundStyle(.tint)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tint)
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("transaction-account-picker")
        } footer: {
            if let note {
                Text(note)
                    .font(.system(.caption2, design: .rounded))
                    .accessibilityIdentifier("transaction-account-note")
            }
        }
    }

    /// 自动跳过了排第一的账户，或者选的账户不够付时，说一句
    private var note: String? {
        guard kind == .expense, let chosen, let amount else { return nil }
        if chosen.amount < amount {
            return "「\(chosen.name)」只有 ¥\(chosen.amount.formatted(.number))，记完会是负数"
        }
        if picked == nil, fallback == nil, let first = accounts.first, first.id != chosen.id {
            return "「\(first.name)」只剩 ¥\(first.amount.formatted(.number))，这笔从「\(chosen.name)」扣"
        }
        return nil
    }
}

enum CashAccountPreferences {
    /// 上次记收入进的账户，下次默认还进它
    static let lastIncomeAccountKey = "lastIncomeCashAccountID"
}
