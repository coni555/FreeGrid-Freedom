// 历史记录：按月查看、按天分组，分类条筛选，支持搜索与撤销。

import SwiftUI
import SwiftData

struct HistoryView: View {

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    /// 筛选条上认出月供扣款（它的「分类」是贷款名）
    @Query private var loans: [Loan]

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
    @State private var search = HistorySearchState()
    @FocusState private var searchFocused: Bool
    @State private var showingMonths = false
    /// 搜索结果里手动展开或收起过的月份；换搜索词时清空，回到默认
    @State private var monthExpansion: [HistoryMonth: Bool] = [:]

    /// 撤销 confirm: 左滑点撤销时 set, alert 触发, 取消/确认后清空
    @State private var pendingDelete: LedgerTransaction? = nil

    /// 点一行打开修改表单
    @State private var editing: LedgerTransaction? = nil

    /// 行首的分类图标（Pro 里可以换）
    @AppStorage(ExpenseCategoryStorage.key, store: AppPreferences.store) private var encodedCategoryOptions = ""

    /// 首次进入时的逐步指引；遮罩本身挂在 ContentView，这里只负责上报位置和触发
    @Environment(AppGuide.self) private var guide
    /// 搜索和筛选两个图标的位置，合起来作为指引的一个目标
    @State private var toolFrames = HistoryToolFrames()
    @AppStorage("historyGuideCompleted", store: AppPreferences.store) private var guideCompleted = false
    /// 重放指引前让列表回到顶部，每次加一
    @State private var scrollToTop = 0

    /// 分类条把「只看收入」和各支出分类放在同一排，一次只选一项
    private typealias Selection = HistorySearch.Filter

    var body: some View {
        NavigationStack {
            Group {
                if expenses.isEmpty && incomes.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .background(Color.paper)
            .paperNavigationContent()
            .background { HistorySearchDataSource(search: search).equatable() }
            .navigationTitle("History")
            .historySearchKeyboardMetrics()
            .navigationDestination(isPresented: $showingMonths) {
                MonthlySummaryView { scope = $0 }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        HistorySearchMetrics.begin()
                        if isSearching {
                            searchFocused = true
                        } else {
                            search.begin(filter: showingFilters ? selection : .all)
                            isSearching = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { toolFrames.report(0, frame: $0, guide: guide) }
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
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { toolFrames.report(1, frame: $0, guide: guide) }
                    }
                    .accessibilityLabel(showingFilters ? "收起筛选" : "按分类筛选")
                }
            }
            .onChange(of: showingFilters ? selection : .all) { _, value in search.setFilter(value) }
            .onChange(of: search.appliedQuery) { monthExpansion = [:] }
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
                "撤销这笔记录？",
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
        .paperNavigationBackground()
    }

    private func resetForGuide() {
        showingMonths = false
        isSearching = false
        search.end()
        searchFocused = false
        showingFilters = false
        selection = .all
        scope = .month(HistoryMonth(containing: .now))
        scrollToTop += 1
    }

    // ============================================================================
    // MARK: - 列表
    // ============================================================================

    private var historyList: some View {
        ScrollViewReader { proxy in
            List {
                if isSearching { searchSections }
                else { ledgerSections }
            }
            .ledgerListStyle()
            .onChange(of: scrollToTop) { proxy.scrollTo(Self.topID, anchor: .top) }
        }
    }

    private var ledgerSections: some View {
        let scoped = HistoryLedger.transactions(expenses: expenses, incomes: incomes, scope: scope)
        let summary = HistoryLedger.summary(scoped)
        let categories = HistoryLedger.categoryTotals(scoped)
        let active = showingFilters ? activeSelection(categories: categories, income: summary.income) : .all
        let visible = filtered(scoped, by: active)
        let days = HistoryLedger.days(visible)

        let options = ExpenseCategoryStorage.decode(encodedCategoryOptions)
        return Group {
            Section {
                scopeCard(summary)
                    .id(Self.topID)
                if showingFilters && (!categories.isEmpty || summary.income != 0) {
                    chipRow(categories, income: summary.income, active: active)
                        .listRowInsets(EdgeInsets(top: Spacing.sm, leading: 0, bottom: Spacing.sm, trailing: 0))
                }

                if days.isEmpty {
                    listMessage("这里还没有记录")
                        .onAppear { guide.forget(.row) }
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.paper)

            ForEach(days) { day in
                Section {
                    ForEach(day.transactions) { tx in
                        transactionRow(tx, options: options)
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
                        .padding(EdgeInsets(top: Spacing.lg, leading: Spacing.lg, bottom: Spacing.sm, trailing: Spacing.lg))
                        // 顶部不再用系统模糊遮挡，吸顶日期要有自己的纸色底，避免账目透到文字后面。
                        .background(Color.paper)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
    }

    private func listMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(Color.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xxl)
    }

    // ============================================================================
    // MARK: - 搜索
    // ============================================================================

    /// 空搜索只展示已经准备好的推荐；匹配、格式化和分组不在 body 中执行。
    private var searchSections: some View {
        let filter: Selection = showingFilters ? selection : .all
        let groups = search.months
        let fewMatches = (search.result?.summary.count ?? 0) <= Self.searchExpandAllLimit
        let options = ExpenseCategoryStorage.decode(encodedCategoryOptions)

        return Group {
            Section {
                HistorySearchBar(search: search, focused: $searchFocused, filterName: filterName(filter),
                                 onClearFilter: { selection = .all }, onCancel: {
                    search.end()
                    searchFocused = false
                    isSearching = false
                })
                if search.isEmpty {
                    searchSuggestions(search.suggestions)
                } else if let result = search.result {
                    if result.summary.count == 0 {
                        listMessage(
                            ExpenseCategory.canonical.contains { $0.contains(result.query) }
                                ? "没有匹配的记录\n想按分类看，用右上角的筛选"
                                : "没有匹配的记录"
                        )
                        .multilineTextAlignment(.center)
                    } else {
                        searchSummary(result)
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.paper)

            ForEach(groups) { group in
                let expanded = monthExpansion[group.month] ?? (fewMatches || group.month == groups.first?.month)
                Section {
                    monthRow(group, expanded: expanded)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.paper)
                    ForEach(expanded ? group.transactions : []) { row in
                        let tx = row.record
                        transactionRow(row, options: options, showsDay: true, onEdit: {
                            if let current = search.transaction(for: tx.key) { editing = current }
                        }, onUndo: {
                            if let current = search.transaction(for: tx.key) { pendingDelete = current }
                        })
                            .equatable()
                            .listRowBackground(Color.paper)
                            .listRowSeparatorTint(Color.hairlineSoft)
                    }
                }
            }
        }
    }

    /// 结果不超过这么多笔时，各月默认都展开
    private static let searchExpandAllLimit = 20

    /// 搜索结果里的一个月：点它展开或收起这个月的明细
    private func monthRow(_ group: HistorySearchState.DisplayMonth, expanded: Bool) -> some View {
        let summary = group.summary
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { monthExpansion[group.month] = !expanded }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
                    .frame(width: 12)
                Text(group.month.label)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.ink)
                Text("\(summary.count) 笔")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
                Spacer()
                if summary.income != 0 {
                    Text(FinancialFormatting.signedYuan(summary.income))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.skyDeep)
                }
                if summary.expense != 0 {
                    Text(FinancialFormatting.signedYuan(-summary.expense))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.inkMuted)
                }
            }
            .padding(.vertical, Spacing.sm)
            .overlay(alignment: .top) { Rectangle().fill(Color.hairlineSoft).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-month-\(group.month.year)-\(group.month.month)")
        .accessibilityValue(expanded ? "已展开" : "已收起")
    }

    /// 还没输入时：一句提示，加上自己常写的几个备注，点一下就搜
    @ViewBuilder
    private func searchSuggestions(_ notes: [String]) -> some View {
        if notes.isEmpty {
            listMessage("输入备注或金额")
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("输入备注或金额，或者点一个常写的备注")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .padding(.horizontal, Spacing.lg)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(notes, id: \.self) { note in
                            Button {
                                search.setText(note, immediately: true)
                                searchFocused = false
                            } label: {
                                Text(note)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.inkMuted)
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .overlay(Capsule().stroke(Color.hairline, lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                }
            }
            .padding(.top, Spacing.sm)
            .listRowInsets(EdgeInsets())
        }
    }

    private static let topID = "history-top"

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
        let dailyBurn = FreedomMath.burnEstimate(FreedomMath.burnEntries(expenses)).dailyBurn
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

    private func filterName(_ filter: Selection) -> String? {
        switch filter {
        case .all: return nil
        case .income: return "收入"
        case .category(let name): return name
        }
    }

    /// 搜索跨全部时间，所以这里回答的是「这样东西一共花了多少」
    private func searchSummary(_ result: HistorySearch.Result) -> some View {
        let summary = result.summary
        let groups = result.months
        // 跨了几个月时写出起止，知道这个合计是多长时间里的
        let span = groups.count > 1
            ? " · \(groups[groups.count - 1].month.label) 至 \(groups[0].month.label)" : ""
        return HStack(spacing: Spacing.md) {
            Text("找到 \(summary.count) 笔" + span)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
                    chip(label: item.category, amount: item.total, selected: active == this,
                         icon: chipIcon(for: item.category)) {
                        // 二次点击同一 chip = 取消选中
                        selection = (active == this) ? .all : this
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.lg)
        }
    }

    /// 筛选条上的分类图标；月供扣款的「分类」是贷款名，用日历
    private func chipIcon(for category: String) -> String {
        let options = ExpenseCategoryStorage.decode(encodedCategoryOptions)
        if !options.allNames.contains(category), loans.contains(where: { $0.name == category }) { return "calendar" }
        return options.icon(for: category)
    }

    private func chip(label: String, amount: Double?, selected: Bool, icon: String? = nil,
                      onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                if let amount {
                    HStack(spacing: 4) {
                        if let icon {
                            Image(systemName: icon)
                                .font(.system(size: 10, weight: .light))
                                .accessibilityHidden(true)
                        }
                        Text(label)
                            .font(.system(.caption2, design: .monospaced))
                            .tracking(0.5)
                    }
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
        .accessibilityIdentifier("history-filter-" + label)
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

    /// `showsDay`：搜索结果里没有日期段头，行首写上是几号
    private func transactionRow(_ tx: LedgerTransaction, options: ExpenseCategoryOptions, showsDay: Bool = false) -> some View {
        transactionRow(HistorySearch.Row(record: tx.searchRecord, includesDay: showsDay), options: options, showsDay: showsDay,
                       onEdit: { editing = tx }, onUndo: { pendingDelete = tx })
    }

    private func transactionRow(_ row: HistorySearch.Row, options: ExpenseCategoryOptions, showsDay: Bool = false,
                                onEdit: @escaping () -> Void, onUndo: @escaping () -> Void) -> HistoryTransactionRow {
        let tx = row.record
        let icon = tx.isLoanPayment ? "calendar" : tx.key.isIncome ? "arrow.down.left" : options.icon(for: tx.title)
        return HistoryTransactionRow(row: row, icon: icon, showsDay: showsDay, onEdit: onEdit, onUndo: onUndo)
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
            Text("回首页，记下第一笔支出或收入")
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

private extension View {
    /// 月份视图和搜索结果共用的列表外观
    func ledgerListStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.paper)
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 40)
            .environment(\.defaultMinListHeaderHeight, 28)
            .dismissKeyboardOnScroll()
    }
}

/// 导航栏收放时坐标每帧都可能改变；记录坐标不应使整个账本列表重新计算。
@MainActor
private final class HistoryToolFrames {
    private var frames: [Int: CGRect] = [:]

    func report(_ index: Int, frame: CGRect, guide: AppGuide) {
        guard frames[index] != frame else { return }
        frames[index] = frame
        guard let first = frames[0], let second = frames[1] else { return }
        guide.report(.tools, first.union(second).insetBy(dx: -6, dy: -6))
    }
}
