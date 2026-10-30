// 历史记录：按月查看、按天分组，月份卡片里列出钱花在哪几类、点一类就只看它，支持搜索与撤销。
// 搜索结果里的支出可以一起移到别的分类（Pro）。

import SwiftUI
import SwiftData

struct HistoryView: View {

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    /// 「≈ N 天」和首页同一个日均：每月花销要先扣掉固定支出
    @Query private var loans: [Loan]

    @Environment(\.modelContext) private var modelContext

    @State private var saveError: String?

    /// 当前查看的时间范围，默认本月
    @State private var scope: HistoryScope = .month(HistoryMonth(containing: .now))
    /// 月份卡片里点中的一类（或收入、固定支出），流水只留它；再点一下取消。换月后该项没有记录时自动视为「全部」。
    @State private var selection: Selection = .all
    /// 月份卡片里的各类支出默认收起，卡片和原来一样；展开过就一直展开
    @AppStorage("historyBreakdownExpanded", store: AppPreferences.store) private var breakdownExpanded = false

    /// 搜索时跨全部月份，不受当前月份限制
    @State private var isSearching = false
    @State private var search = HistorySearchState()
    @FocusState private var searchFocused: Bool
    @State private var showingMonths = false
    /// 每月一个数：写过的月份，点了改；记账方式改了要马上重算
    @State private var editingMonth: YearMonth?
    @AppStorage(MonthlyTracking.key, store: AppPreferences.store) private var storedTracking = ""
    /// 搜索结果里手动展开或收起过的月份；换搜索词时清空，回到默认
    @State private var monthExpansion: [HistoryMonth: Bool] = [:]

    /// 撤销 confirm: 左滑点撤销时 set, alert 触发, 取消/确认后清空
    @State private var pendingDelete: LedgerTransaction? = nil

    /// 点一行打开修改表单
    @State private var editing: LedgerTransaction? = nil

    /// 搜索结果「把这 N 笔移到…」：打开移动表，移完给撤销条
    @State private var moveBatch: MoveBatch?
    @State private var undoMove: CategoryMoveUndo?
    @State private var showingPro = false

    private struct MoveBatch: Identifiable {
        let id = UUID()
        let options: ExpenseCategoryOptions
        let records: [MoveExpensesSheet.Record]
    }

    /// 行首的分类图标（Pro 里可以换）
    @AppStorage(ExpenseCategoryStorage.key, store: AppPreferences.store) private var encodedCategoryOptions = ""

    /// 首次进入时的逐步指引；遮罩本身挂在 ContentView，这里只负责上报位置和触发
    @Environment(AppGuide.self) private var guide
    /// 搜索图标的位置，作为指引的一个目标
    @State private var toolFrames = HistoryToolFrames()
    @AppStorage("historyGuideCompleted", store: AppPreferences.store) private var guideCompleted = false
    /// 重放指引前让列表回到顶部，每次加一
    @State private var scrollToTop = 0

    /// 收入、固定支出和各支出分类一次只选一项
    private typealias Selection = HistorySearch.Filter

    @Environment(\.tabActivity) private var tabActivity
    @Environment(\.tabDataClock) private var tabDataClock
    @State private var freeze = TabFreezeState()

    /// 在后台时冻住，切回来、或记完账空闲时再按最新的账重画（见 TabFreeze）
    var body: some View {
        TabFreeze(activity: tabActivity, clock: tabDataClock, state: freeze) { page }.equatable()
    }

    @ViewBuilder
    private var page: some View {
        // 读整本账的在这里算好：ScrollViewReader 里的内容会被单独重跑，在那里读 @Query 就冻不住了
        let isEmpty = expenses.isEmpty && incomes.isEmpty
        let tracking = MonthlyTracking.decode(storedTracking)
        let ledger = isEmpty || isSearching ? nil : ScopedLedger(expenses: expenses, incomes: incomes, loans: ProFeatures.loansInEffect(loans), scope: scope)
        NavigationStack {
            Group {
                if isEmpty {
                    if tracking.hasNumber && tracking.isMonthly {
                        ScrollView {
                            monthsCard(tracking)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.top, Spacing.sm)
                        }
                    } else if tracking.isMonthly {
                        monthlyEmptyState
                    } else {
                        emptyState
                    }
                } else {
                    historyList(ledger, tracking: tracking)
                }
            }
            .background(Color.paper)
            .paperNavigationContent()
            .background { HistorySearchDataSource(search: search).equatable() }
            .navigationTitle("明细")
            .historySearchKeyboardMetrics()
            .navigationDestination(isPresented: $showingMonths) {
                MonthlySummaryView { scope = $0 }
            }
            .sheet(item: $editingMonth) { MonthlySpendingSheet(month: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        HistorySearchMetrics.begin()
                        if isSearching {
                            searchFocused = true
                        } else {
                            // 点中了一类就在这一类里搜：比如在「其他」里搜「咖啡」，再一起移走
                            search.begin(filter: ledger?.active(selection) ?? .all)
                            isSearching = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { toolFrames.report($0, guide: guide) }
                    }
                    .accessibilityLabel("搜索")
                }
            }
            // 搜索栏上的筛选标签点叉清掉时
            .onChange(of: selection) { _, value in if isSearching { search.setFilter(value) } }
            .onReceive(NotificationCenter.default.publisher(for: .showThisMonthInHistory)) { _ in showThisMonth() }
            .onChange(of: search.appliedQuery) { monthExpansion = [:] }
            .task(id: isEmpty) {
                // 账本里有记录才指引；等列表排好位置再开始
                guard !guideCompleted, !isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !guideCompleted, !isSearching, editing == nil else { return }
                withAnimation(.easeInOut(duration: 0.25)) { guide.start(.history) }
            }
            .task(id: guide.replays(of: .history)) {
                // 从设置页重放：先回到本月、收起搜索和筛选，圈的位置才和首次进来时一样
                guard !isEmpty, guide.takeReplay(.history) else { return }
                resetForGuide()
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) { guide.start(.history) }
            }
            .saveErrorAlert($saveError)
            .sheet(item: $editing) { EditTransactionSheet(transaction: $0) }
            .sheet(item: $moveBatch) { batch in
                MoveExpensesSheet(options: batch.options, records: batch.records) { target, ids, _ in
                    try moveExpenses(ids, to: target, options: batch.options)
                }
            }
            .proPaywall(isPresented: $showingPro, topic: .categories)
            .categoryMoveUndoBar($undoMove) { undo($0) }
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
        showThisMonth()
        scrollToTop += 1
    }

    /// 回到本月、收起搜索和筛选：重放指引前，和从首页「本月花销」点进来时
    private func showThisMonth() {
        showingMonths = false
        isSearching = false
        search.end()
        searchFocused = false
        selection = .all
        scope = .month(HistoryMonth(containing: .now))
    }

    // ============================================================================
    // MARK: - 列表
    // ============================================================================

    /// 当前范围里的账，和范围卡上要的合计、支出构成、月份范围、日均。在 page 顶层算好再交给列表
    private struct ScopedLedger {
        let transactions: [LedgerTransaction]
        let summary: HistorySummary
        let breakdown: HistoryLedger.Breakdown
        let monthRange: ClosedRange<HistoryMonth>
        let dailyBurn: Double

        init(expenses: [Expense], incomes: [Income], loans: [Loan], scope: HistoryScope) {
            transactions = HistoryLedger.transactions(expenses: expenses, incomes: incomes, scope: scope)
            summary = HistoryLedger.summary(transactions)
            breakdown = HistoryLedger.breakdown(transactions)
            monthRange = HistoryLedger.monthRange(expenses: expenses, incomes: incomes)
            // 只在按月查看时折算成天，全部时间用不到
            if case .month = scope {
                dailyBurn = FreedomMath.burnEstimate(FreedomMath.burnEntries(expenses), tracking: .current,
                                                     fixedMonthly: LoanSchedule.monthlyTotal(loans: loans, payments: expenses)).dailyBurn
            } else {
                dailyBurn = 0
            }
        }

        /// 选中的项在这个范围里已经没有记录时，退回「全部」
        func active(_ selection: Selection) -> Selection {
            switch selection {
            case .all: return .all
            case .income: return summary.income != 0 ? .income : .all
            case .fixed: return breakdown.fixed != 0 ? .fixed : .all
            case .category(let name): return breakdown.categories.contains { $0.category == name } ? selection : .all
            }
        }
    }

    private func historyList(_ ledger: ScopedLedger?, tracking: MonthlyTracking) -> some View {
        ScrollViewReader { proxy in
            List {
                if isSearching {
                    searchSections
                } else {
                    if tracking.isMonthly && tracking.hasNumber {
                        Section {
                            monthsCard(tracking)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.paper)
                    }
                    if let ledger { ledgerSections(ledger) }
                }
            }
            .ledgerListStyle()
            .onChange(of: scrollToTop) { proxy.scrollTo(Self.topID, anchor: .top) }
        }
    }

    private func ledgerSections(_ ledger: ScopedLedger) -> some View {
        let active = ledger.active(selection)
        let visible = HistoryLedger.filter(ledger.transactions, by: active)
        let days = HistoryLedger.days(visible)

        let options = ExpenseCategoryStorage.decode(encodedCategoryOptions)
        return Group {
            Section {
                scopeCard(ledger, active: active, options: options)
                    .id(Self.topID)
                if active != .all {
                    filterLine(active, count: visible.count)
                }

                if days.isEmpty {
                    listMessage(String(localized: "这里还没有记录"))
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
        let filter = selection
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
                            ExpenseCategory.canonical.contains {
                                $0.contains(result.query)
                                    || ExpenseCategory.displayName($0).localizedCaseInsensitiveContains(result.query)
                            }
                                ? String(localized: "没有匹配的记录\n想按分类看，点月份卡片里的分类")
                                : String(localized: "没有匹配的记录")
                        )
                        .multilineTextAlignment(.center)
                    } else {
                        searchSummary(result)
                        moveButton(result)
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

    /// 搜索结果里能换分类的支出：收入和月供扣款不算
    private static func movableKeys(_ result: HistorySearch.Result) -> [HistorySearch.Key] {
        result.months.flatMap(\.rows).map(\.record)
            .filter { !$0.key.isIncome && !$0.isLoanPayment }
            .map(\.key)
    }

    /// 拆分杂项：比如筛「其他」、搜「咖啡」，把搜到的一起移到新的「咖啡」
    @ViewBuilder
    private func moveButton(_ result: HistorySearch.Result) -> some View {
        let count = Self.movableKeys(result).count
        if count > 0 {
            Button {
                startMove(result)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 13, weight: .light))
                    Text(count == result.summary.count
                         ? String(localized: "把这 \(count) 笔移到其他分类…")
                         : String(localized: "把其中 \(count) 笔支出移到其他分类…"))
                    if !ProFeatures.canCustomizeExpenseCategories {
                        Text("PRO")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .tracking(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 0.8))
                    }
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.skyDeep)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("move-search-results")
        }
    }

    private func startMove(_ result: HistorySearch.Result) {
        guard ProFeatures.canCustomizeExpenseCategories else {
            showingPro = true
            return
        }
        let records: [MoveExpensesSheet.Record] = Self.movableKeys(result).compactMap { key in
            guard case .expense(let expense) = search.transaction(for: key) else { return nil }
            return MoveExpensesSheet.Record(id: expense.id, date: expense.date, amount: expense.amount,
                                            category: expense.category, note: expense.note)
        }
        guard !records.isEmpty else { return }
        searchFocused = false
        // 和分类管理页同一份：存下的设置，加上账本里用过的名字
        let options = ExpenseCategoryStorage.decode(encodedCategoryOptions)
            .including(expenses.filter { $0.loanID == nil }.map(\.category))
        moveBatch = MoveBatch(options: options, records: records)
    }

    /// 先改账再存偏好（只有新建了分类才要存）；偏好在改账前就编码好，改完账不会再失败
    private func moveExpenses(_ ids: Set<UUID>, to target: CategoryMoveTarget, options: ExpenseCategoryOptions) throws {
        let before = encodedCategoryOptions
        var next = options
        let name = target.isNew ? try next.add(target.name) : target.name
        let encoded = try ExpenseCategoryStorage.encode(next)
        let previous = try LedgerStore.moveExpenses(ids, to: name, in: modelContext)
        if target.isNew { encodedCategoryOptions = encoded }
        withAnimation(.spring(duration: 0.3)) {
            undoMove = CategoryMoveUndo(
                message: String(localized: "\(previous.count) 笔已移到「\(ExpenseCategory.displayName(name))」"),
                previous: previous, encodedOptions: before)
        }
    }

    private func undo(_ move: CategoryMoveUndo) {
        do {
            try LedgerStore.restoreCategories(move.previous, in: modelContext)
            encodedCategoryOptions = move.encodedOptions
        } catch { saveError = error.localizedDescription }
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
            listMessage(String(localized: "输入备注或金额"))
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

    // ============================================================================
    // MARK: - 时间范围卡片
    // ============================================================================

    private func scopeCard(_ ledger: ScopedLedger, active: Selection, options: ExpenseCategoryOptions) -> some View {
        let summary = ledger.summary
        let range = ledger.monthRange
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
                        monthStepButton("chevron.left", label: String(localized: "上个月"), enabled: month > range.lowerBound) {
                            scope = .month(month.shifted(by: -1))
                        }
                        monthStepButton("chevron.right", label: String(localized: "下个月"), enabled: month < range.upperBound) {
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
                    KickerLabel(text: String(localized: "支出"))
                    if let days = equivalentDays(summary, dailyBurn: ledger.dailyBurn) {
                        // 首页的日均是尺子: 这个月花掉的钱相当于平时多少天的开销
                        Text("· " + HistoryLedger.equivalentDaysLabel(days))
                            .font(.kicker)
                            .foregroundStyle(Color.inkFaint)
                            .lineLimit(1)
                    }
                }

                let canExpand = ledger.breakdown.fixed != 0 || !ledger.breakdown.categories.isEmpty
                // 这一行同时是各类支出的开关：箭头一直在这一行的右端，展开、收起都点同一处
                Button {
                    guard canExpand else { return }
                    withAnimation(.snappy(duration: 0.32)) { breakdownExpanded.toggle() }
                } label: {
                    HStack(spacing: Spacing.lg) {
                        if summary.income != 0 {
                            scopeStat(String(localized: "收入"), FinancialFormatting.yuan(summary.income))
                            scopeStat(String(localized: "净"), FinancialFormatting.signedYuan(summary.net))
                        } else if let average = dailyAverage(summary) {
                            // 没有收入时「收入 ¥0、净 = −支出」只是复述上面的数字
                            scopeStat(String(localized: "日均"), FinancialFormatting.yuan(average))
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Text("\(summary.count) 笔")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.inkFaint)
                            if canExpand {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.inkMuted)
                                    .rotationEffect(.degrees(breakdownExpanded ? 180 : 0))
                            }
                        }
                    }
                    // 点击区 36pt，视觉上仍按一行小字排
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -9)
                .accessibilityIdentifier("history-breakdown-toggle")
                .accessibilityRemoveTraits(canExpand ? [] : .isButton)
                .accessibilityValue(canExpand ? (breakdownExpanded ? "已展开" : "已收起") : "")
                .accessibilityHint(canExpand ? (breakdownExpanded ? String(localized: "收起各类支出") : String(localized: "展开各类支出")) : "")

                breakdown(ledger, active: active, options: options)
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
    private func equivalentDays(_ summary: HistorySummary, dailyBurn: Double) -> Double? {
        guard case .month = scope else { return nil }
        return HistoryLedger.equivalentDays(expense: summary.expense, dailyBurn: dailyBurn)
    }

    private var scopeLabel: String {
        switch scope {
        case .month(let month): return month.label
        case .allTime: return String(localized: "全部时间")
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
        case .income: return String(localized: "收入")
        case .fixed: return String(localized: "固定支出")
        case .category(let name): return ExpenseCategory.displayName(name)
        }
    }

    /// 搜索跨全部时间，所以这里回答的是「这样东西一共花了多少」
    private func searchSummary(_ result: HistorySearch.Result) -> some View {
        let summary = result.summary
        let groups = result.months
        // 跨了几个月时写出起止，知道这个合计是多长时间里的
        let span = groups.count > 1
            ? String(localized: " · \(groups[groups.count - 1].month.label) 至 \(groups[0].month.label)") : ""
        return HStack(spacing: Spacing.md) {
            Text(String(localized: "找到 \(summary.count) 笔") + span)
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
    // MARK: - 钱花在哪
    // ============================================================================

    /// 卡片里的一行：一个支出分类、合起来的固定支出，或收入
    private struct BreakdownRow: Identifiable {
        let filter: Selection
        let title: String
        let icon: String
        let total: Double
        var id: Selection { filter }
    }

    /// 默认收起，点上面「N 笔」那一行展开。展开后支出从多到少，每类后面写折合首页日均的几天、
    /// 下面一道细条和最多的那类比长短；收入单列在最后。点一行流水就只留这一类，再点一下回到全部
    @ViewBuilder
    private func breakdown(_ ledger: ScopedLedger, active: Selection, options: ExpenseCategoryOptions) -> some View {
        let fixed = ledger.breakdown.fixed != 0
            ? [BreakdownRow(filter: .fixed, title: String(localized: "固定支出"), icon: "calendar", total: ledger.breakdown.fixed)]
            : []
        let expenseRows = (fixed + ledger.breakdown.categories.map {
            BreakdownRow(filter: .category($0.category), title: ExpenseCategory.displayName($0.category),
                         icon: options.icon(for: $0.category), total: $0.total)
        }).sorted { $0.total > $1.total }
        let income = ledger.summary.income
        // 条长以最多的一类为满格，读起来是一排长短对比；占整月多少看后面的天数
        let largest = expenseRows.first?.total ?? 0

        if !expenseRows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if breakdownExpanded {
                    Hairline(color: .hairlineSoft)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.xs)
                    ForEach(expenseRows) { row in
                        breakdownRow(row, active: active, share: largest > 0 ? row.total / largest : 0,
                                     days: HistoryLedger.equivalentDays(expense: row.total, dailyBurn: ledger.dailyBurn))
                    }
                    if income != 0 {
                        breakdownRow(BreakdownRow(filter: .income, title: String(localized: "收入"), icon: "arrow.down.left", total: income),
                                     active: active, share: nil, days: nil)
                    }
                }
            }
        }
    }

    private func breakdownRow(_ row: BreakdownRow, active: Selection, share: Double?, days: Double?) -> some View {
        let selected = active == row.filter
        // 点中一类时，其余的退到淡色
        let dimmed = active != .all && !selected
        let isIncome = row.filter == .income
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selection = selected ? .all : row.filter }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Image(systemName: row.icon)
                        .font(.system(size: 12, weight: .light))
                        .frame(width: 18)
                        .foregroundStyle(dimmed ? Color.inkGhost : selected ? Color.skyDeep : Color.inkMuted)
                    Text(row.title)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(dimmed ? Color.inkFaint : Color.ink)
                        .lineLimit(1)
                    if let days, row.total > 0 {
                        Text(HistoryLedger.daysLabel(days))
                            .font(.system(.caption2, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkFaint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Spacing.sm)
                    Text(FinancialFormatting.yuan(row.total))
                        .font(.system(.subheadline, design: .rounded).monospacedDigit())
                        .foregroundStyle(dimmed ? Color.inkFaint : isIncome ? Color.skyDeep : Color.ink)
                        .lineLimit(1)
                }
                if let share {
                    // 退款多过支出的类没有条
                    Capsule()
                        .fill(selected ? Color.skyDeep : dimmed ? Color.hairlineSoft : Color.hairline)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: max(0, min(1, share)), anchor: .leading)
                        .padding(.leading, 18 + Spacing.sm)
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? String(localized: "再点一下看全部") : String(localized: "只看这一类"))
        .accessibilityIdentifier(Self.breakdownID(row.filter))
    }

    private static func breakdownID(_ filter: Selection) -> String {
        switch filter {
        case .all: return "history-breakdown-all"
        case .income: return "history-breakdown-income"
        case .fixed: return "history-breakdown-fixed"
        case .category(let name): return "history-breakdown-" + name
        }
    }

    /// 点中一类后，紧贴流水上方写着现在只看哪一类、几笔，随时能回到全部
    private func filterLine(_ active: Selection, count: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Text("只看「\(filterName(active) ?? "")」 · \(count) 笔")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .lineLimit(1)
            Spacer()
            Button("看全部") {
                withAnimation(.easeInOut(duration: 0.2)) { selection = .all }
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.skyDeep)
            .buttonStyle(.plain)
            .accessibilityIdentifier("history-filter-clear")
        }
        .padding(.top, Spacing.sm)
        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.lg, bottom: 0, trailing: Spacing.lg))
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
    /// 每月一个数写过的月份，点了能改；记错一个月不改掉，会一直算在平均里
    private func monthsCard(_ tracking: MonthlyTracking) -> some View {
        let written = tracking.writtenMonths
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(spacing: 0) {
                ForEach(Array(written.enumerated()), id: \.element.month) { index, item in
                    if index > 0 { Hairline() }
                    Button { editingMonth = item.month } label: {
                        HStack(spacing: Spacing.sm) {
                            Text(item.month.name())
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.ink)
                            Spacer(minLength: Spacing.sm)
                            Text("¥\(FinancialFormatting.wholeNumber(item.amount))")
                                .font(.system(.body, design: .rounded).weight(.light).monospacedDigit())
                                .foregroundStyle(Color.ink)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.inkFaint)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, Spacing.lg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("monthly-spending-\(item.month.key)")
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.mist))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
            if written.count > 1 {
                Text("日均按这 \(written.count) 个月平均。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .padding(.horizontal, Spacing.xs)
            }
        }
    }

    private var monthlyEmptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.inkFaint)
            Text("每月一个数不用记明细")
                .font(.system(.title3, design: .rounded).weight(.thin))
                .foregroundStyle(Color.ink)
            Text("想逐笔记，去 设置 → 账本 → 记账方式")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }

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

extension Notification.Name {
    /// 首页点「本月花销」卡：切到明细、回到本月。Tab 之间不传闭包（见 ContentView 的 StableTab），用通知
    static let showThisMonthInHistory = Notification.Name("FreeGrid.showThisMonthInHistory")
}

/// 导航栏收放时坐标每帧都可能改变；记录坐标不应使整个账本列表重新计算。
@MainActor
private final class HistoryToolFrames {
    private var frame: CGRect?

    func report(_ frame: CGRect, guide: AppGuide) {
        guard self.frame != frame else { return }
        self.frame = frame
        guide.report(.tools, frame.insetBy(dx: -10, dy: -10))
    }
}
