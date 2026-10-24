// 新增或编辑一笔固定支出或贷款（拆了现金账户时多一项：从哪个账户扣）。
// - 固定支出（免费）：名称、每次多少、几个月付一次、下次哪天付。下面写出之后哪天扣，方便核对。
// - 贷款（Pro）：名称、月供、每月几号还、还剩几期。期数下面实时写出最后一期是哪天。
// 账本里有金额正好等于这一期的旧支出时，问一句是不是以前记的。

import SwiftUI
import SwiftData

struct LoanSheet: View {
    enum Kind: Identifiable {
        case fixed, loan
        var id: Self { self }
    }

    let existing: Loan?
    let kind: Kind

    /// 编辑时按记录本身的类型；新增时由入口决定
    init(existing: Loan?, kind: Kind = .loan) {
        self.existing = existing
        self.kind = existing.map { $0.isOngoing ? .fixed : .loan } ?? kind
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]

    @State private var saveError: String?
    @State private var name = ""
    @State private var monthly = ""
    @State private var dueDay = Calendar.current.component(.day, from: .now)
    @State private var periods = ""
    /// 编辑的是已经还清的贷款：期数栏留空，保存时不动进度
    @State private var paidOff = false
    /// 固定支出：隔几个月一次、下次哪天付
    @State private var intervalMonths = 1
    @State private var nextDue = LoanSheet.defaultNextDue
    /// 月供固定从哪个账户扣；nil = 按扣款顺序
    @State private var cashAccountID: UUID?
    @State private var confirmingDelete = false
    /// 用户勾为「以前记的月供」的旧支出
    @State private var excluded: Set<UUID> = []
    @State private var showingCandidates = false
    private enum Field { case name, monthly, periods }
    @FocusState private var focus: Field?

    private var isEditing: Bool { existing != nil }
    private var isFixed: Bool { kind == .fixed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: String(localized: "名称"))
                        UnderlinedField(isFocused: focus == .name) {
                            TextField(isFixed ? "房租、水电、会员…" : "房贷、车贷…", text: $name)
                                .font(.system(.title3, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .monthly }
                                .accessibilityIdentifier("loan-name-field")
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: isFixed ? (intervalMonths == 1 ? String(localized: "每月付多少") : String(localized: "每次付多少")) : String(localized: "每月还多少"))
                        UnderlinedField(isFocused: focus == .monthly) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("¥")
                                    .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                                    .foregroundStyle(Color.inkFaint)
                                TextField("0", text: $monthly)
                                    .decimalKeyboard()
                                    .accessibilityIdentifier("loan-monthly-field")
                                    .font(.system(size: 52, weight: .ultraLight, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Color.ink)
                                    .minimumScaleFactor(0.5)
                                    .focused($focus, equals: .monthly)
                            }
                        }
                    }

                    if isFixed { fixedScheduleFields } else {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .top, spacing: Spacing.xl) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            KickerLabel(text: String(localized: "每月几号还"))
                            UnderlinedField(isFocused: false) {
                                // 不用系统的菜单样式：它自带内边距，会和上面的标题、旁边的期数对不齐
                                Menu {
                                    Picker("每月几号还", selection: $dueDay) {
                                        ForEach(1...31, id: \.self) { Text("\($0) 日").tag($0) }
                                    }
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("\(dueDay)")
                                            .font(.system(.title3, design: .rounded).monospacedDigit())
                                            .foregroundStyle(Color.ink)
                                        // 英文写「15」就够，标题已经说了是几号
                                        if AppLanguage.isChinese {
                                            Text(verbatim: "日")
                                                .font(.system(.body, design: .rounded))
                                                .foregroundStyle(Color.inkFaint)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color.inkFaint)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .menuIndicator(.hidden)
                                .accessibilityIdentifier("loan-due-day-picker")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            KickerLabel(text: String(localized: "还剩几期"))
                            UnderlinedField(isFocused: focus == .periods) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    TextField("24", text: $periods)
                                        .numberKeyboard()
                                        .font(.system(.title3, design: .rounded).monospacedDigit())
                                        .foregroundStyle(Color.ink)
                                        .focused($focus, equals: .periods)
                                        .accessibilityIdentifier("loan-periods-field")
                                    Text("期")
                                        .font(.system(.body, design: .rounded))
                                        .foregroundStyle(Color.inkFaint)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 最后一期是哪天：填错了一眼能看出来。紧贴在两栏下面，和它们是一组
                    Text(lastDueText ?? (keepsPaidOff ? String(localized: "已还清，不再扣款") : String(localized: "今天到期的这期算已还，从下一期开始自动扣")))
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(lastDueText == nil ? Color.inkFaint : Color.inkMuted)
                        .accessibilityIdentifier("loan-last-due")
                    }
                    }

                    if !cashAccounts.isEmpty { accountField }

                    if !candidates.isEmpty { candidatesSection }

                    if isEditing {
                        Button(isFixed ? "删除这笔固定支出" : "删除这笔贷款") { confirmingDelete = true }
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.flame)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("delete-loan")
                    }
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(title)
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isValid)
                        .foregroundStyle(isValid ? Color.skyDeep : Color.inkFaint)
                        .fontWeight(.medium)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog("删除「\(existing?.name ?? "")」？", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("删除", role: .destructive) { delete() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("以后不再自动扣。已经扣过的留在明细里。")
            }
            .onChange(of: monthly) { excluded = Set(candidates.filter { !$0.countsInBurn }.map(\.id)) }
        }
        .saveErrorAlert($saveError)
        .iosSheetDetents()
    }

    private var title: String {
        switch (isFixed, isEditing) {
        case (true, true): return String(localized: "编辑固定支出")
        case (true, false): return String(localized: "添加固定支出")
        case (false, true): return String(localized: "编辑贷款")
        case (false, false): return String(localized: "添加贷款")
        }
    }

    // MARK: - 固定支出：几个月付一次、下次哪天

    /// 默认下个月的今天
    static var defaultNextDue: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .month, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
    }

    private var nextDueRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return tomorrow...(calendar.date(byAdding: .year, value: 1, to: today) ?? tomorrow)
    }

    static func intervalLabel(_ months: Int) -> String { LoanSchedule.intervalLabel(months) }

    private var fixedScheduleFields: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    KickerLabel(text: String(localized: "几个月付一次"))
                    UnderlinedField(isFocused: false) {
                        Menu {
                            Picker("几个月付一次", selection: $intervalMonths) {
                                ForEach(LoanSchedule.intervals, id: \.self) { Text(Self.intervalLabel($0)).tag($0) }
                            }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(Self.intervalLabel(intervalMonths))
                                    .font(.system(.title3, design: .rounded))
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.inkFaint)
                            }
                            .contentShape(Rectangle())
                        }
                        .menuIndicator(.hidden)
                        .accessibilityIdentifier("fixed-interval-picker")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    KickerLabel(text: String(localized: "下次哪天付"))
                    UnderlinedField(isFocused: false) {
                        HStack {
                            DatePicker("下次哪天付", selection: $nextDue, in: nextDueRange, displayedComponents: .date)
                                .labelsHidden()
                                .tint(Color.skyDeep)
                                // 和 App 里其他日期一样写中文，不跟系统语言
                                .environment(\.locale, AppLanguage.locale)
                                .accessibilityIdentifier("fixed-next-due")
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(scheduleText)
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.inkMuted)
                .accessibilityIdentifier("fixed-schedule")
        }
    }

    /// 「到日子自动从现金扣，之后每月 5 日一次」；不按月付时先说清金额填的是一次付的总数
    private var scheduleText: String {
        guard intervalMonths != 1 else {
            let day = Calendar.current.component(.day, from: nextDue)
            return String(localized: "到日子自动记一笔支出，之后每月 \(day) 日一次")
        }
        return String(localized: "金额填一次付的总数（\(intervalMonths) 个月的钱）。\n到日子自动记一笔支出，之后\(Self.intervalLabel(intervalMonths))一次")
    }

    // MARK: - 从哪个账户扣

    /// 房贷一般绑着一张卡：指定了就只从它扣，它余额不够这期就算没扣成
    private var accountField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KickerLabel(text: String(localized: "从哪个账户扣"))
            UnderlinedField(isFocused: false) {
                Menu {
                    Picker("从哪个账户扣", selection: $cashAccountID) {
                        Text("按扣款顺序").tag(UUID?.none)
                        ForEach(cashAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                } label: {
                    HStack {
                        Text(cashAccounts.first { $0.id == cashAccountID }?.name ?? String(localized: "按扣款顺序"))
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                    }
                    .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .accessibilityIdentifier("loan-account-picker")
            }
            Text(cashAccountID == nil
                 ? "到期那天整笔扣第一个够付的账户"
                 : "只从这个账户扣，余额不够这期就先不扣")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
    }

    // MARK: - 以前记的月供

    private var candidates: [Expense] {
        guard let value = Double(monthly) else { return [] }
        return LoanStore.pastRepaymentCandidates(monthlyAmount: value, in: expenses)
    }

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Hairline()
            Button {
                withAnimation(.snappy(duration: 0.28)) { showingCandidates.toggle() }
                focus = nil
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(isFixed
                         ? "找到 \(candidates.count) 笔 ¥\(FinancialFormatting.wholeNumber(Double(monthly) ?? 0)) 的支出，是以前记的吗？"
                         : "找到 \(candidates.count) 笔 ¥\(FinancialFormatting.wholeNumber(Double(monthly) ?? 0)) 的支出，是以前记的月供吗？")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                        .rotationEffect(.degrees(showingCandidates ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("loan-candidates-toggle")

            if showingCandidates {
                VStack(spacing: 0) {
                    ForEach(candidates) { expense in
                        candidateRow(expense)
                        if expense.id != candidates.last?.id { Hairline(color: .hairlineSoft) }
                    }
                }
                Text("勾上的不再另算进日均消费（固定支出已经折进去了），记录照样留在明细里。")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }

    private func candidateRow(_ expense: Expense) -> some View {
        let isOn = excluded.contains(expense.id)
        return Button {
            if isOn { excluded.remove(expense.id) } else { excluded.insert(expense.id) }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(isOn ? Color.skyDeep : Color.inkFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.fullDate(expense.date))
                        .font(.system(.subheadline, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                    Text(expense.note.isEmpty ? ExpenseCategory.displayName(expense.category)
                         : "\(ExpenseCategory.displayName(expense.category)) · \(expense.note)")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 校验与保存

    private var periodCount: Int? {
        Int(periods.trimmingCharacters(in: .whitespaces)).flatMap {
            (1...LoanSchedule.maxPeriods).contains($0) ? $0 : nil
        }
    }

    /// 已还清的贷款、期数栏还空着：保存时只改名称、金额这些，不再排期
    private var keepsPaidOff: Bool {
        paidOff && periods.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 「最后一期：2028 年 10 月 14 日」。期数还没填好时为 nil
    private var lastDueText: String? {
        guard let count = periodCount,
              let last = LoanSchedule.dueDates(after: .now, dueDay: dueDay, count: count).last else { return nil }
        return String(localized: "最后一期：\(Self.fullDate(last))")
    }

    /// 「2028 年 10 月 14 日」/「Oct 14, 2028」，跟界面语言走
    static func fullDate(_ date: Date) -> String {
        guard AppLanguage.isChinese else { return AppLanguage.date(date, template: "yyyyMMMd") }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0) 年 \(parts.month ?? 0) 月 \(parts.day ?? 0) 日"
    }

    private var isValid: Bool {
        (try? LoanStore.cleanName(name)) != nil
            && Double(monthly).map { FinancialFormatting.validAmount($0) } == true
            && (isFixed || periodCount != nil || keepsPaidOff)
    }

    private func load() {
        if let existing {
            name = existing.name
            monthly = existing.monthlyAmount.formatted(
                .number.grouping(.never).precision(.fractionLength(0...2))
                    .locale(Locale(identifier: "en_US_POSIX")))
            dueDay = existing.dueDay
            // 指定的账户后来删了，就当没指定
            cashAccountID = cashAccounts.contains { $0.id == existing.cashAccountID } ? existing.cashAccountID : nil
            let status = LoanSchedule.status(of: existing, payments: expenses)
            if existing.isOngoing {
                intervalMonths = existing.intervalMonths
                // 下次付款日过了一年的范围（理论上不会）就退回默认
                if let next = status.nextDue, nextDueRange.contains(next) { nextDue = next }
            } else if status.isPaidOff {
                paidOff = true
            } else {
                periods = String(status.remaining)
            }
        }
        excluded = Set(candidates.filter { !$0.countsInBurn }.map(\.id))
        focus = isEditing ? nil : .name
    }

    private func save() {
        guard isValid, let value = Double(monthly) else { return }
        let account = cashAccounts.isEmpty ? nil : cashAccountID
        do {
            if isFixed {
                try LoanStore.saveFixed(existing, name: name, amount: value, intervalMonths: intervalMonths,
                                        nextDue: nextDue, cashAccountID: account,
                                        pastRepayments: candidates, excludedFromBurn: excluded, in: modelContext)
            } else {
                guard periodCount != nil || keepsPaidOff else { return }
                try LoanStore.save(existing, name: name, monthlyAmount: value, dueDay: dueDay, remaining: periodCount,
                                   cashAccountID: account,
                                   pastRepayments: candidates, excludedFromBurn: excluded, in: modelContext)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func delete() {
        guard let existing else { return }
        do {
            try LoanStore.delete(existing, in: modelContext)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
