// 历史记录：筛选、分类汇总与撤销。

import SwiftUI
import SwiftData

struct HistoryView: View {

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]

    @Environment(\.modelContext) private var modelContext

    /// 筛选状态: "all" / "expense" / "income"
    @State private var saveError: String?
    @State private var filter: FilterKind = .all

    /// 分类二级筛选: nil 表示全部分类。仅在 filter == .expense 时有意义,
    /// 切到 .all / .income 时自动清空。
    @State private var selectedCategory: String? = nil

    /// 撤销 confirm: 点行右侧 × 时 set, alert 触发, 取消/确认后清空
    @State private var pendingDelete: LedgerTransaction? = nil

    enum FilterKind: String, CaseIterable, Identifiable {
        case all = "全部"
        case expense = "支出"
        case income = "收入"
        var id: String { rawValue }
    }

    var body: some View {
        let transactions = filteredTransactions
        let categories = expenseCategoryTotals
        NavigationStack {
            VStack(spacing: 0) {
                // ===== 顶部 segmented 筛选器 =====
                Picker("筛选", selection: $filter) {
                    ForEach(FilterKind.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, Spacing.sm)
                .onChange(of: filter) { _, newValue in
                    // 切出支出 tab 时清掉分类二级筛选
                    if newValue != .expense { selectedCategory = nil }
                }

                // ===== 分类汇总条 (仅支出 tab) =====
                if filter == .expense && !categories.isEmpty {
                    categoryChipRow(categories)
                        .padding(.bottom, Spacing.sm)
                }

                if transactions.isEmpty {
                    emptyState
                } else {
                    transactionList(transactions)
                }
            }
            .background(Color.paper)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        MonthlySummaryView()
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
            }
            .saveErrorAlert($saveError)
            .alert(
                "撤销这笔记录?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { tx in
                Button("撤销", role: .destructive) { confirmDelete(tx) }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: { tx in
                Text(tx.undoMessage)
            }
        }
    }

    // ============================================================================
    // MARK: - 分类汇总条
    // ============================================================================

    /// 横滑 chip 列表: 首"全部"chip + 各分类 chip, 每 chip 显示分类名 + 总额
    private func categoryChipRow(_ categories: [(category: String, total: Double)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(
                    label: "全部",
                    amount: categories.reduce(0) { $0 + $1.total },
                    selected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }
                ForEach(categories, id: \.category) { item in
                    categoryChip(
                        label: item.category,
                        amount: item.total,
                        selected: selectedCategory == item.category
                    ) {
                        // 二次点击同一 chip = 取消选中
                        selectedCategory = (selectedCategory == item.category) ? nil : item.category
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func categoryChip(label: String, amount: Double, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(.caption2, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(selected ? Color.paper : Color.inkMuted)
                Text("¥" + amount.formatted(.number.precision(.fractionLength(0...2))))
                    .font(.system(.callout, design: .rounded).weight(.medium).monospacedDigit())
                    .foregroundStyle(selected ? Color.paper : Color.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.ink : Color.mist)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.hairlineSoft, lineWidth: selected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// 各支出分类总额,降序排列
    private var expenseCategoryTotals: [(category: String, total: Double)] {
        let grouped = Dictionary(grouping: expenses, by: { $0.category })
        return grouped
            .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    // ============================================================================
    // MARK: - 列表渲染
    // ============================================================================

    private func transactionList(_ transactions: [LedgerTransaction]) -> some View {
        let net = transactions.reduce(0) { $0 + $1.cashChange }
        return List {
            Section {
                HStack {
                    Text("共 \(transactions.count) 笔")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    Spacer()
                    Text("净 \(FinancialFormatting.signedYuan(net))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                }
                .listRowBackground(Color.paper)
            }

            Section {
                ForEach(transactions) { tx in
                    transactionRow(tx)
                        .listRowBackground(Color.paper)
                        .listRowSeparatorTint(Color.hairlineSoft)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .listStyle(.plain)
    }

    private func transactionRow(_ tx: LedgerTransaction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tx.title)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                if !tx.note.isEmpty {
                    Text(tx.note)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                }
                Text(tx.date, format: .dateTime.year().month().day())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
            }
            Spacer()
            Text(FinancialFormatting.signedYuan(tx.cashChange))
                .font(.system(.callout, design: .rounded).weight(.regular).monospacedDigit())
                .foregroundStyle(tx.cashChange < 0 ? Color.flame : Color.skyDeep)
            deleteButton(for: tx)
        }
        .padding(.vertical, 4)
    }

    /// 行右侧 × 撤销按钮: silverline outline 圆, 点击 set pendingDelete 触发 alert
    private func deleteButton(for tx: LedgerTransaction) -> some View {
        Button {
            pendingDelete = tx
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.inkFaint)
                .frame(width: 22, height: 22)
                .background(
                    Circle().stroke(Color.hairlineSoft, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("撤销这笔")
    }

    /// 空状态:silverline 风简洁提示
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.inkFaint)
            Text("还没有记录")
                .font(.system(.title3, design: .rounded).weight(.thin))
                .foregroundStyle(Color.ink)
            Text("回 Dashboard 添加第一笔支出或收入")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }

    // ============================================================================
    // MARK: - 业务逻辑
    // ============================================================================

    /// 根据筛选返回排好序的交易列表
    private var filteredTransactions: [LedgerTransaction] {
        var all: [LedgerTransaction] = []
        if filter == .all || filter == .expense {
            // selectedCategory != nil 时仅取该分类的支出(只可能在 filter == .expense 时发生)
            let exps = selectedCategory.map { cat in expenses.filter { $0.category == cat } } ?? expenses
            all.append(contentsOf: exps.map { .expense($0) })
        }
        if filter == .all || filter == .income {
            all.append(contentsOf: incomes.map { .income($0) })
        }
        // 按日期降序,新的在上
        return all.sorted { $0.date > $1.date }
    }

    private func confirmDelete(_ tx: LedgerTransaction) {
        do {
            try LedgerStore.undo(id: tx.id, kind: tx.kind, in: modelContext)
            pendingDelete = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
