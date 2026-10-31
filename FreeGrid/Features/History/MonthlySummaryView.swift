// 按月汇总收入、支出和净；点开一个月，在卡片里看支出构成（柱状图 / 扇形图）。从明细页进入时可选一个月回去看明细。

import SwiftUI
import SwiftData

struct MonthlySummaryView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    /// 扇形图按分类列表的顺序给每类固定一个颜色
    @AppStorage(ExpenseCategoryStorage.key, store: AppPreferences.store) private var encodedCategoryOptions = ""
    /// 手动点开或收起过的月份；没点过时最近的那个月是展开的
    @State private var toggled: Set<String> = []
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
        let breakdown: HistoryLedger.Breakdown
    }

    var body: some View {
        let months = monthlyStats
        let colors = pieColors(months)
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
                    ForEach(months) { monthCard($0, expandedByDefault: $0.id == months.first?.id, colors: colors) }
                }
                .padding()
            }
        }
        .background(Color.paper)
        .navigationTitle("月度汇总")
        .inlineNavTitle()
    }

    /// 扇形图配色在所有月份之间统一分，同一分类每个月同色
    private func pieColors(_ months: [MonthlyStat]) -> [HistoryLedger.Share.Kind: Int] {
        let kinds = Set(months.flatMap { HistoryLedger.shares($0.breakdown).map(\.kind) })
        return HistoryLedger.colorSlots(kinds, order: ExpenseCategoryStorage.decode(encodedCategoryOptions).allNames,
                                        paletteCount: MonthCategoryChart.palette.count)
    }

    private func monthCard(_ stat: MonthlyStat, expandedByDefault: Bool, colors: [HistoryLedger.Share.Kind: Int]) -> some View {
        let isExpanded = toggled.contains(stat.id) != expandedByDefault
        let hasChart = !HistoryLedger.shares(stat.breakdown).isEmpty
        return VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if toggled.contains(stat.id) { toggled.remove(stat.id) } else { toggled.insert(stat.id) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text(stat.label)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Text("净 \(FinancialFormatting.signedYuan(stat.net))")
                                .font(.system(.callout, design: .rounded).weight(.medium).monospacedDigit())
                                .foregroundStyle(stat.net >= 0 ? Color.mossGreen : Color.flame)
                            if hasChart {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.inkFaint)
                                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            }
                        }
                        HStack(spacing: Spacing.xl) {
                            amountStat(String(localized: "支出"), stat.totalExpense, Color.ink)
                            amountStat(String(localized: "收入"), stat.totalIncome, Color.skyDeep)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasChart)
                .accessibilityIdentifier("month-card-\(stat.id)")
                .accessibilityValue(hasChart ? (isExpanded ? "已展开" : "已收起") : "")

                if isExpanded && hasChart {
                    Hairline(color: .hairlineSoft)
                    MonthCategoryChart(breakdown: stat.breakdown, colorSlots: colors)
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

    /// 按 年-月 分组聚合，月内支出再按分类合计。最近的月在前。
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
                totalIncome: incByMonth[k] ?? 0,
                breakdown: HistoryLedger.breakdown(exps.map(LedgerTransaction.expense))
            )
        }
    }
}
