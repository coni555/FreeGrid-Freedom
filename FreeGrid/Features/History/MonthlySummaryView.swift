// 按月汇总收入、支出与分类。

import SwiftUI
import SwiftData

struct MonthlySummaryView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @State private var expanded: Set<String> = []

    struct MonthlyStat: Identifiable {
        let id: String          // "2026-05"
        let label: String       // "2026年5月"
        let totalExpense: Double
        let totalIncome: Double
        var net: Double { totalIncome - totalExpense }
        let categories: [(category: String, total: Double)]  // 月内支出分类, 降序
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
                    ForEach(months) { monthCard($0) }
                }
                .padding()
            }
        }
        .background(Color.paper)
        .navigationTitle("月度汇总")
        .inlineNavTitle()
    }

    @ViewBuilder
    private func monthCard(_ stat: MonthlyStat) -> some View {
        let isExpanded = expanded.contains(stat.id)
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded { expanded.remove(stat.id) } else { expanded.insert(stat.id) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text(stat.label)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Text("净 " + FinancialFormatting.signedYuan(stat.net))
                                .font(.system(.callout, design: .rounded).weight(.medium).monospacedDigit())
                                .foregroundStyle(stat.net >= 0 ? Color.mossGreen : Color.flame)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.inkFaint)
                        }
                        HStack(spacing: Spacing.xl) {
                            amountStat("支出", stat.totalExpense, Color.ink)
                            amountStat("收入", stat.totalIncome, Color.assetGold)
                        }
                    }
                }
                .buttonStyle(.plain)

                if isExpanded && !stat.categories.isEmpty {
                    Rectangle().fill(Color.hairlineSoft).frame(height: 1)
                    let maxCat = stat.categories.first?.total ?? 1
                    VStack(spacing: Spacing.sm) {
                        ForEach(stat.categories, id: \.category) { c in
                            categoryRow(c.category, c.total, maxCat: maxCat, monthTotal: stat.totalExpense)
                        }
                    }
                }
            }
        }
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

    private func categoryRow(_ name: String, _ total: Double, maxCat: Double, monthTotal: Double) -> some View {
        let pct = monthTotal > 0 ? total / monthTotal : 0
        return HStack(spacing: Spacing.sm) {
            Text(name)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.mist)
                    Capsule().fill(Color.cashBlue)
                        .frame(width: max(4, geo.size.width * (maxCat > 0 ? total / maxCat : 0)))
                }
            }
            .frame(height: 8)
            Text("¥" + total.formatted(.number.precision(.fractionLength(0...2))))
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.ink)
                .frame(width: 56, alignment: .trailing)
            Text(pct.formatted(.percent.precision(.fractionLength(0...0))))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.inkFaint)
                .frame(width: 34, alignment: .trailing)
        }
    }

    /// 按 年-月 分组聚合; 月内再按分类聚合支出。最近的月在前。
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
            let cats = Dictionary(grouping: exps, by: { $0.category })
                .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
                .sorted { $0.total > $1.total }
            let parts = k.split(separator: "-")
            let label = "\(parts[0])年\(Int(parts[1]) ?? 0)月"
            return MonthlyStat(
                id: k, label: label,
                totalExpense: exps.reduce(0) { $0 + $1.amount },
                totalIncome: incByMonth[k] ?? 0,
                categories: cats
            )
        }
    }
}
