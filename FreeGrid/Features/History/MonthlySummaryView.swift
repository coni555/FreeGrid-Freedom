// 按月汇总收入、支出和净；从明细页进入时可选一个月回去看明细。钱花在哪几类看明细页的月份卡片，这里不再重复。

import SwiftUI
import SwiftData

struct MonthlySummaryView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @Environment(\.dismiss) private var dismiss

    /// 选定时间范围后回到历史页; nil 时不显示跳转入口
    var onSelect: ((HistoryScope) -> Void)? = nil

    struct MonthlyStat: Identifiable {
        let id: String          // "2026-05"
        let month: HistoryMonth
        var label: String { month.label }
        let totalExpense: Double
        let totalIncome: Double
        var net: Double { totalIncome - totalExpense }
    }

    var body: some View {
        let months = monthlyStats
        ScrollView {
            if months.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "calendar")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.inkFaint)
                    Text("还没有可汇总的记录")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else {
                LazyVStack(spacing: Spacing.md) {
                    if onSelect != nil {
                        GhostButton(title: String(localized: "查看全部时间的明细")) { select(.allTime) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(months) { monthCard($0) }
                }
                .padding()
            }
        }
        .background(Color.paper)
        .navigationTitle("月度汇总")
        .inlineNavTitle()
    }

    private func monthCard(_ stat: MonthlyStat) -> some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text(stat.label)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Text("净 \(FinancialFormatting.signedYuan(stat.net))")
                            .font(.system(.callout, design: .rounded).weight(.medium).monospacedDigit())
                            .foregroundStyle(stat.net >= 0 ? Color.mossGreen : Color.flame)
                    }
                    HStack(spacing: Spacing.xl) {
                        amountStat(String(localized: "支出"), stat.totalExpense, Color.ink)
                        amountStat(String(localized: "收入"), stat.totalIncome, Color.skyDeep)
                    }
                }

                if onSelect != nil {
                    GhostButton(title: String(localized: "查看这个月的明细")) { select(.month(stat.month)) }
                        .accessibilityIdentifier("open-month-\(stat.id)")
                }
            }
        }
    }

    private func select(_ scope: HistoryScope) {
        onSelect?(scope)
        dismiss()
    }

    private func amountStat(_ label: String, _ amount: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.inkFaint)
            Text("¥" + amount.formatted(.number.precision(.fractionLength(0...2))))
                .font(.system(.title3, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    /// 按 年-月 分组聚合。最近的月在前。
    private var monthlyStats: [MonthlyStat] {
        let cal = Calendar.current
        func key(_ d: Date) -> String {
            let c = cal.dateComponents([.year, .month], from: d)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
        var expByMonth: [String: [Expense]] = [:]
        var incByMonth: [String: Double] = [:]
        var keys = Set<String>()
        for e in expenses { let k = key(e.date); keys.insert(k); expByMonth[k, default: []].append(e) }
        for i in incomes  { let k = key(i.date); keys.insert(k); incByMonth[k, default: 0] += i.amount }

        return keys.sorted(by: >).map { k in
            let exps = expByMonth[k] ?? []
            let parts = k.split(separator: "-")
            return MonthlyStat(
                id: k, month: HistoryMonth(year: Int(parts[0]) ?? 0, month: Int(parts[1]) ?? 1),
                totalExpense: exps.reduce(0) { $0 + $1.amount },
                totalIncome: incByMonth[k] ?? 0
            )
        }
    }
}
