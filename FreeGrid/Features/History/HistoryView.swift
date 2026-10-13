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
    /// 分类条默认收起，点右上角筛选图标才出现；收起时一并清掉筛选，避免列表被看不见的条件过滤
    @State private var showingFilters = false

    /// 分类条上选中的一项。换月后该项没有记录时自动视为「全部」。
    @State private var selection: Selection = .all

    /// 搜索时跨全部月份，不受当前月份限制
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var showingMonths = false

    /// 撤销 confirm: 左滑点撤销时 set, alert 触发, 取消/确认后清空
    @State private var pendingDelete: LedgerTransaction? = nil

    /// 点一行打开修改表单
    @State private var editing: LedgerTransaction? = nil

    /// 首次进入时的逐步指引；遮罩本身挂在 ContentView，这里只负责上报位置和触发
    @Environment(AppGuide.self) private var guide
    /// 搜索和筛选两个图标的位置，合起来作为指引的一个目标
    @State private var toolFrames: [Int: CGRect] = [:]
    @AppStorage("historyGuideCompleted") private var guideCompleted = false
    /// 重放指引前让列表回到顶部，每次加一
    @State private var scrollToTop = 0

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
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { toolFrames[0] = $0 }
                    }
                    .accessibilityLabel("搜索")
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingFilters.toggle()
                            if !showingFilters { selection = .all }
                        }
                    } label: {
                        Image(systemName: showingFilters
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { toolFrames[1] = $0 }
                    }
                    .accessibilityLabel(showingFilters ? "收起筛选" : "按分类筛选")
                }
            }
            .onChange(of: toolFrames) { _, frames in
                guard let first = frames[0], let second = frames[1] else { return }
                guide.report(.tools, first.union(second).insetBy(dx: -6, dy: -6))
            }
            .task(id: expenses.isEmpty && incomes.isEmpty) {
                // 账本里有记录才指引；等列表排好位置再开始
                guard !guideCompleted, !(expenses.isEmpty && incomes.isEmpty) else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !guideCompleted, !isSearching, editing == nil else { return }
                withAnimation(.easeInOut(duration: 0.25)) { guide.start(.history) }
            }
            .task(id: guide.replays(of: .history)) {
                // 从设置页重放：先回到本月、收起搜索和筛选，圈的位置才和首次进来时一样
                guard !(expenses.isEmpty && incomes.isEmpty), guide.takeReplay(.history) else { return }
                resetForGuide()
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) { guide.start(.history) }
            }
            .saveErrorAlert($saveError)
            .sheet(item: $editing) { EditTransactionSheet(transaction: $0) }
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

    private func resetForGuide() {
        showingMonths = false
        isSearching = false
        searchText = ""
        showingFilters = false
        selection = .all
        scope = .month(HistoryMonth(containing: .now))
        scrollToTop += 1
    }

    // ============================================================================
    // MARK: - 列表
    // ============================================================================

    private var ledgerList: some View {
        // 刚点开搜索、还没输入时不把全部记录铺出来：几千笔一次排进列表会卡住
        let awaitingQuery = isSearching && searchText.allSatisfy(\.isWhitespace)
        let scoped = awaitingQuery ? [] : HistoryLedger.transactions(
            expenses: expenses, incomes: incomes, scope: isSearching ? .allTime : scope
        )
        let summary = HistoryLedger.summary(scoped)
        let categories = isSearching ? [] : HistoryLedger.categoryTotals(scoped)
        let active = isSearching || !showingFilters
            ? .all : activeSelection(categories: categories, income: summary.income)
        let visible = HistoryLedger.search(filtered(scoped, by: active), query: searchText)
        // 搜索结果只排最近的一部分，合计仍按全部匹配算
        let shown = isSearching ? Array(visible.prefix(Self.searchRowLimit)) : visible
        let days = HistoryLedger.days(shown)

        return ScrollViewReader { proxy in
        List {
            Section {
                if isSearching {
                    searchField
                    if !awaitingQuery { searchSummary(visible) }
                } else {
                    scopeCard(summary)
                        .id(Self.topID)
                    if showingFilters && (!categories.isEmpty || summary.income != 0) {
                        chipRow(categories, income: summary.income, active: active)
                            .listRowInsets(EdgeInsets(top: Spacing.sm, leading: 0, bottom: Spacing.sm, trailing: 0))
                    }
                }

                if days.isEmpty {
                    Text(awaitingQuery ? "输入分类、备注或金额" : isSearching ? "没有匹配的记录" : "这里还没有记录")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xxl)
                        .onAppear { guide.forget(.row) }
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.paper)

            ForEach(days) { day in
                Section {
                    ForEach(day.transactions) { tx in
                        transactionRow(tx)
                            .background {
                                // 只上报第一行的位置
                                if tx.id == visible.first?.id {
                                    Color.clear.guideTarget(.row, in: guide)
                                }
                            }
                            .listRowBackground(Color.paper)
                            .listRowSeparatorTint(Color.hairlineSoft)
                    }
                } header: {
                    dayHeader(day)
                        .listRowInsets(EdgeInsets(top: Spacing.lg, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                }
            }

            if visible.count > shown.count {
                Text("只显示最近 \(shown.count) 笔，继续输入可以缩小范围")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.paper)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 40)
        .environment(\.defaultMinListHeaderHeight, 28)
        .dismissKeyboardOnScroll()
        .onChange(of: scrollToTop) { proxy.scrollTo(Self.topID, anchor: .top) }
        }
    }

    private static let topID = "history-top"
    /// 搜索时最多排进列表的行数
    private static let searchRowLimit = 200

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
        return VaultCard(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    // 点月份进月度汇总，在那里可以跳到任意一个月
                    Button {
                        showingMonths = true
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text(scopeLabel)
                                .font(.system(.footnote, design: .rounded))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundStyle(Color.inkMuted)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(scopeLabel)，月度汇总")
                    .accessibilityIdentifier("history-scope-title")
                    .guideTarget(.month, in: guide)
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
                // 点击区是 44pt，视觉上仍按 26pt 的一行排
                .padding(.vertical, -9)

                HStack(alignment: .lastTextBaseline, spacing: Spacing.sm) {
                    // 大数字只到元，零头留给下面的明细
                    Text(FinancialFormatting.yuan(summary.expense, precision: 0))
                        .font(.system(size: 30, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    KickerLabel(text: "支出")
                    if let days = equivalentDays(summary) {
                        // 首页的日均是尺子: 这个月花掉的钱相当于平时多少天的开销
                        Text("· " + HistoryLedger.equivalentDaysLabel(days))
                            .font(.kicker)
                            .foregroundStyle(Color.inkFaint)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: Spacing.lg) {
                    if summary.income != 0 {
                        scopeStat("收入", FinancialFormatting.yuan(summary.income))
                        scopeStat("净", FinancialFormatting.signedYuan(summary.net))
                    } else if let average = dailyAverage(summary) {
                        // 没有收入时「收入 ¥0、净 = −支出」只是复述上面的数字
                        scopeStat("日均", FinancialFormatting.yuan(average))
                    }
                    Spacer()
                    Text("\(summary.count) 笔")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.inkFaint)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.lg, bottom: Spacing.xs, trailing: Spacing.lg))
    }

    /// 当前月份的日均支出；全部时间或还没到的月份不显示
    private func dailyAverage(_ summary: HistorySummary) -> Double? {
        guard case .month(let month) = scope else { return nil }
        let days = HistoryLedger.elapsedDays(in: month)
        return days > 0 ? summary.expense / Double(days) : nil
    }

    /// 只在按月查看时折算；全部时间折出来就是追踪天数，没有信息
    private func equivalentDays(_ summary: HistorySummary) -> Double? {
        guard case .month = scope else { return nil }
        let firstDate = FreedomMath.earliestExpenseDate(expenses)
        let dailyBurn = FreedomMath.dailyBurn(
            totalExpenses: expenses.reduce(0) { $0 + $1.amount },
            trackDays: FreedomMath.trackDays(firstRecordDate: firstDate)
        )
        return HistoryLedger.equivalentDays(expense: summary.expense, dailyBurn: dailyBurn)
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
                .font(.system(.caption, design: .rounded).monospacedDigit())
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
                .frame(width: 26, height: 26)
                .background(Circle().stroke(Color.hairline, lineWidth: 1))
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
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

    /// 搜索跨全部时间，所以这里回答的是「这样东西一共花了多少」
    private func searchSummary(_ transactions: [LedgerTransaction]) -> some View {
        let summary = HistoryLedger.summary(transactions)
        return HStack(spacing: Spacing.md) {
            Text("找到 \(summary.count) 笔")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
            Spacer()
            if summary.income != 0 {
                Text("收入 \(FinancialFormatting.yuan(summary.income))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.skyDeep)
            }
            if summary.expense != 0 || summary.income == 0 {
                Text("支出 \(FinancialFormatting.yuan(summary.expense))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.ink)
            }
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
                        .foregroundStyle(selected ? Color.ink : Color.inkFaint)
                    Text(FinancialFormatting.yuan(amount))
                        .font(.system(.callout, design: .rounded).weight(.medium).monospacedDigit())
                        .foregroundStyle(selected ? Color.ink : Color.inkMuted)
                } else {
                    Text(label)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(selected ? Color.ink : Color.inkMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.mist)
            )
            // 选中只加深描边和文字，不填实心块
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.ink : Color.hairlineSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // ============================================================================
    // MARK: - 按天分组的记录
    // ============================================================================

    private func dayHeader(_ day: HistoryDay) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(HistoryLedger.dayLabel(day.id))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
            Spacer()
            // 支出和收入分开写: 合成净额的话, 交房租又收到转账的那天会像个普通日子
            if day.income != 0 {
                Text(FinancialFormatting.signedYuan(day.income))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.skyDeep)
            }
            if day.expense != 0 {
                Text(FinancialFormatting.signedYuan(-day.expense))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
            }
        }
        .textCase(nil)
    }

    private func transactionRow(_ tx: LedgerTransaction) -> some View {
        // 支出有备注时备注才是这笔账的事实(「租房」), 分类(「其他」)退成小标签; 收入的来源本身就是事实
        let noteLeads = tx.kind == .expense && !tx.note.isEmpty
        return Button {
            editing = tx
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(noteLeads ? tx.note : tx.title)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .layoutPriority(1)
                if noteLeads {
                    Text(tx.title)
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                } else if !tx.note.isEmpty {
                    Text(tx.note)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: Spacing.sm)
                Text(FinancialFormatting.signedYuan(tx.cashChange))
                    .font(.system(.callout, design: .rounded).weight(.regular).monospacedDigit())
                    .foregroundStyle(amountColor(tx))
                    .layoutPriority(2)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("修改这笔记录")
        // 不用 destructive role: 它会在确认前就把行滑走
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("撤销") { pendingDelete = tx }
                .tint(Color.flame)
        }
        .contextMenu {
            Button("修改", systemImage: "pencil") { editing = tx }
            Button("撤销这笔", systemImage: "arrow.uturn.backward", role: .destructive) {
                pendingDelete = tx
            }
        }
    }

    private func amountColor(_ tx: LedgerTransaction) -> Color {
        tx.cashChange < 0 ? Color.flame : Color.skyDeep
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
