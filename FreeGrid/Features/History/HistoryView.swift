// 历史记录：按月查看、按天分组，支持分类筛选、搜索与撤销。

import SwiftUI
import SwiftData

struct HistoryView: View {

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]

    @Environment(\.modelContext) private var modelContext

    @State private var saveError: String?

    /// 当前查看的时间范围，默认本月
    @State private var scope: HistoryScope = .month(HistoryMonth(containing: .now))
    @State private var kind: HistoryKindFilter = .all

    /// 分类筛选: nil 表示全部分类。换月后该分类没有记录时自动视为未选。
    @State private var selectedCategory: String? = nil

    /// 搜索时跨全部月份，不受当前月份限制
    @State private var searchText = ""
    @State private var showingMonths = false

    /// 撤销 confirm: 左滑点撤销时 set, alert 触发, 取消/确认后清空
    @State private var pendingDelete: LedgerTransaction? = nil

    var body: some View {
        NavigationStack {
            Group {
                if expenses.isEmpty && incomes.isEmpty {
                    emptyState
                } else {
                    ledgerList
                }
            }
            .background(Color.paper)
            .navigationTitle("History")
            .navigationDestination(isPresented: $showingMonths) {
                MonthlySummaryView { scope = $0 }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingMonths = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("月度汇总")
                }
            }
            .searchable(text: $searchText, prompt: "搜索分类、备注或金额")
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
    // MARK: - 列表
    // ============================================================================

    private var ledgerList: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let scoped = HistoryLedger.transactions(
            expenses: expenses, incomes: incomes, scope: isSearching ? .allTime : scope
        )
        let categories = isSearching ? [] : HistoryLedger.categoryTotals(scoped)
        let category = categories.contains { $0.category == selectedCategory } ? selectedCategory : nil
        let visible = HistoryLedger.search(
            HistoryLedger.filter(scoped, kind: kind, category: category), query: searchText
        )
        let days = HistoryLedger.days(visible)

        return List {
            Section {
                if isSearching {
                    searchSummary(visible)
                } else {
                    scopeCard(HistoryLedger.summary(scoped))
                }

                Picker("筛选", selection: $kind) {
                    ForEach(HistoryKindFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, newValue in
                    // 收入没有分类
                    if newValue == .income { selectedCategory = nil }
                }

                if kind != .income && !categories.isEmpty {
                    categoryChipRow(categories, selected: category)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }

                if days.isEmpty {
                    Text(isSearching ? "没有匹配的记录" : "这里还没有记录")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xxl)
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.paper)

            ForEach(days) { day in
                Section {
                    ForEach(day.transactions) { tx in
                        transactionRow(tx)
                            .listRowBackground(Color.paper)
                            .listRowSeparatorTint(Color.hairlineSoft)
                    }
                } header: {
                    dayHeader(day)
                        .listRowInsets(EdgeInsets(top: Spacing.md, leading: Spacing.lg, bottom: Spacing.xs, trailing: Spacing.lg))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 40)
        .environment(\.defaultMinListHeaderHeight, 28)
    }

    // ============================================================================
    // MARK: - 时间范围卡片
    // ============================================================================

    private func scopeCard(_ summary: HistorySummary) -> some View {
        let range = HistoryLedger.monthRange(expenses: expenses, incomes: incomes)
        return VaultCard(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Text(scopeLabel)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                    Spacer()
                    if case .month(let month) = scope {
                        monthStepButton("chevron.left", label: "上个月", enabled: month > range.lowerBound) {
                            scope = .month(month.shifted(by: -1))
                        }
                        monthStepButton("chevron.right", label: "下个月", enabled: month < range.upperBound) {
                            scope = .month(month.shifted(by: 1))
                        }
                    } else {
                        Button("回到本月") {
                            scope = .month(HistoryMonth(containing: .now))
                        }
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.skyDeep)
                        .buttonStyle(.plain)
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: Spacing.sm) {
                    Text(FinancialFormatting.yuan(summary.expense))
                        .font(.system(size: 40, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    KickerLabel(text: "支出")
                }

                Hairline(color: .hairlineSoft)

                HStack(spacing: Spacing.lg) {
                    scopeStat("收入", FinancialFormatting.yuan(summary.income))
                    scopeStat("净", FinancialFormatting.signedYuan(summary.net))
                    Spacer()
                    Text("\(summary.count) 笔")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.inkFaint)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.lg, bottom: Spacing.xs, trailing: Spacing.lg))
    }

    private var scopeLabel: String {
        switch scope {
        case .month(let month): return month.label
        case .allTime: return "全部时间"
        }
    }

    private func scopeStat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.inkFaint)
            Text(value)
                .font(.system(.footnote, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.ink)
        }
    }

    /// 切月按钮: hairline 描边圆; 到头时变淡并禁用
    private func monthStepButton(
        _ icon: String, label: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(enabled ? Color.inkMuted : Color.inkGhost)
                .frame(width: 30, height: 30)
                .background(Circle().stroke(Color.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func searchSummary(_ transactions: [LedgerTransaction]) -> some View {
        let net = transactions.reduce(0) { $0 + $1.cashChange }
        return HStack {
            Text("找到 \(transactions.count) 笔")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
            Spacer()
            Text("净 \(FinancialFormatting.signedYuan(net))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.ink)
        }
    }

    // ============================================================================
    // MARK: - 分类汇总条
    // ============================================================================

    /// 横滑 chip 列表: 首"全部"chip + 当前范围内各分类 chip, 每 chip 显示分类名 + 合计
    private func categoryChipRow(
        _ categories: [(category: String, total: Double)], selected: String?
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(
                    label: "全部",
                    amount: categories.reduce(0) { $0 + $1.total },
                    selected: selected == nil
                ) {
                    selectedCategory = nil
                }
                ForEach(categories, id: \.category) { item in
                    categoryChip(
                        label: item.category,
                        amount: item.total,
                        selected: selected == item.category
                    ) {
                        // 二次点击同一 chip = 取消选中
                        selectedCategory = (selected == item.category) ? nil : item.category
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func categoryChip(label: String, amount: Double, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(.caption2, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(selected ? Color.paper : Color.inkMuted)
                Text(FinancialFormatting.yuan(amount))
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
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // ============================================================================
    // MARK: - 按天分组的记录
    // ============================================================================

    private func dayHeader(_ day: HistoryDay) -> some View {
        HStack {
            Text(HistoryLedger.dayLabel(day.id))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
            Spacer()
            Text(FinancialFormatting.signedYuan(day.net))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.inkFaint)
        }
        .textCase(nil)
    }

    private func transactionRow(_ tx: LedgerTransaction) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(tx.title)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .layoutPriority(1)
            if !tx.note.isEmpty {
                Text(tx.note)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.sm)
            Text(FinancialFormatting.signedYuan(tx.cashChange))
                .font(.system(.callout, design: .rounded).weight(.regular).monospacedDigit())
                .foregroundStyle(tx.cashChange < 0 ? Color.flame : Color.skyDeep)
                .layoutPriority(2)
        }
        .padding(.vertical, 2)
        // 不用 destructive role: 它会在确认前就把行滑走
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("撤销") { pendingDelete = tx }
                .tint(Color.flame)
        }
        .contextMenu {
            Button("撤销这笔", systemImage: "arrow.uturn.backward", role: .destructive) {
                pendingDelete = tx
            }
        }
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

    private func confirmDelete(_ tx: LedgerTransaction) {
        do {
            try LedgerStore.undo(id: tx.id, kind: tx.kind, in: modelContext)
            pendingDelete = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
