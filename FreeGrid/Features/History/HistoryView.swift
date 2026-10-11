// 历史记录：按月查看、按天分组，分类条筛选，支持搜索与撤销。

import SwiftUI
import SwiftData

struct HistoryView: View {

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]

    @Environment(\.modelContext) private var modelContext

    @State private var saveError: String?

    /// 当前查看的时间范围，默认本月
    @State private var scope: HistoryScope = .month(HistoryMonth(containing: .now))
    /// 分类条上选中的一项。换月后该项没有记录时自动视为「全部」。
    @State private var selection: Selection = .all

    /// 搜索时跨全部月份，不受当前月份限制
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var showingMonths = false

    /// 撤销 confirm: 左滑点撤销时 set, alert 触发, 取消/确认后清空
    @State private var pendingDelete: LedgerTransaction? = nil

    /// 分类条把「只看收入」和各支出分类放在同一排，一次只选一项
    private enum Selection: Equatable {
        case all
        case income
        case category(String)
    }

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
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isSearching = true
                        searchFocused = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("搜索")
                    Button {
                        showingMonths = true
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("月度汇总")
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
    // MARK: - 列表
    // ============================================================================

    private var ledgerList: some View {
        let scoped = HistoryLedger.transactions(
            expenses: expenses, incomes: incomes, scope: isSearching ? .allTime : scope
        )
        let summary = HistoryLedger.summary(scoped)
        let categories = isSearching ? [] : HistoryLedger.categoryTotals(scoped)
        let active = isSearching ? .all : activeSelection(categories: categories, income: summary.income)
        let visible = HistoryLedger.search(filtered(scoped, by: active), query: searchText)
        let days = HistoryLedger.days(visible)

        return List {
            Section {
                if isSearching {
                    searchField
                    searchSummary(visible)
                } else {
                    scopeCard(summary)
                    if !categories.isEmpty || summary.income != 0 {
                        chipRow(categories, income: summary.income, active: active)
                            .listRowInsets(EdgeInsets(top: Spacing.sm, leading: 0, bottom: Spacing.sm, trailing: 0))
                    }
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
                        .listRowInsets(EdgeInsets(top: Spacing.xl, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 40)
        .environment(\.defaultMinListHeaderHeight, 28)
        .dismissKeyboardOnScroll()
    }

    /// 选中的项在当前范围里已经没有记录时，退回「全部」
    private func activeSelection(
        categories: [(category: String, total: Double)], income: Double
    ) -> Selection {
        switch selection {
        case .all: return .all
        case .income: return income != 0 ? .income : .all
        case .category(let name): return categories.contains { $0.category == name } ? selection : .all
        }
    }

    private func filtered(_ transactions: [LedgerTransaction], by selection: Selection) -> [LedgerTransaction] {
        switch selection {
        case .all: return transactions
        case .income: return HistoryLedger.filter(transactions, kind: .income, category: nil)
        case .category(let name): return HistoryLedger.filter(transactions, kind: .expense, category: name)
        }
    }

    // ============================================================================
    // MARK: - 时间范围卡片
    // ============================================================================

    private func scopeCard(_ summary: HistorySummary) -> some View {
        let range = HistoryLedger.monthRange(expenses: expenses, incomes: incomes)
        return VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
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
        .listRowInsets(EdgeInsets(top: Spacing.sm, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
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

    /// 点右上角放大镜才出现；取消后回到按月视图
    private var searchField: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkFaint)
                TextField("搜索分类、备注或金额", text: $searchText)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .accessibilityIdentifier("history-search-field")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.mist))
            .overlay(Capsule().stroke(Color.hairline, lineWidth: 1))

            Button("取消") {
                searchText = ""
                searchFocused = false
                isSearching = false
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(Color.skyDeep)
            .buttonStyle(.plain)
        }
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

    /// 横滑 chip 列表: 「全部」+「收入」+ 当前范围内各支出分类; 总数已在卡片上, 「全部」不再重复金额
    private func chipRow(
        _ categories: [(category: String, total: Double)], income: Double, active: Selection
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "全部", amount: nil, selected: active == .all) {
                    selection = .all
                }
                if income != 0 {
                    chip(label: "收入", amount: income, selected: active == .income) {
                        selection = (active == .income) ? .all : .income
                    }
                }
                ForEach(categories, id: \.category) { item in
                    let this = Selection.category(item.category)
                    chip(label: item.category, amount: item.total, selected: active == this) {
                        // 二次点击同一 chip = 取消选中
                        selection = (active == this) ? .all : this
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func chip(label: String, amount: Double?, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                if let amount {
                    Text(label)
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(selected ? Color.paper : Color.inkMuted)
                    Text(FinancialFormatting.yuan(amount))
                        .font(.system(.callout, design: .rounded).weight(.medium).monospacedDigit())
                        .foregroundStyle(selected ? Color.paper : Color.ink)
                } else {
                    Text(label)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(selected ? Color.paper : Color.ink)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity)
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
