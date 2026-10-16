// Pro 每月还款：新增或编辑一笔贷款。只填名称、月供、每月几号还、还剩几期（拆了现金账户时多一项：从哪个账户扣）；
// 期数下面实时写出最后一期是哪天，方便核对。账本里有金额正好等于月供的旧支出时，问一句是不是以前记的月供。

import SwiftUI
import SwiftData

struct LoanSheet: View {
    let existing: Loan?

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
    /// 月供固定从哪个账户扣；nil = 按扣款顺序
    @State private var cashAccountID: UUID?
    @State private var confirmingDelete = false
    /// 用户勾为「以前记的月供」的旧支出
    @State private var excluded: Set<UUID> = []
    @State private var showingCandidates = false
    private enum Field { case name, monthly, periods }
    @FocusState private var focus: Field?

    private var isEditing: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "名称")
                        UnderlinedField(isFocused: focus == .name) {
                            TextField("房贷、车贷…", text: $name)
                                .font(.system(.title3, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .monthly }
                                .accessibilityIdentifier("loan-name-field")
                        }
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "每月还多少")
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

                    HStack(alignment: .top, spacing: Spacing.xl) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            KickerLabel(text: "每月几号还")
                            UnderlinedField(isFocused: false) {
                                Picker("每月几号还", selection: $dueDay) {
                                    ForEach(1...31, id: \.self) { Text("\($0) 日").tag($0) }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .tint(Color.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("loan-due-day-picker")
                            }
                        }
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            KickerLabel(text: "还剩几期")
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
                    }

                    // 最后一期是哪天：填错了一眼能看出来
                    Text(lastDueText ?? "今天到期的那期算已经还过")
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(lastDueText == nil ? Color.inkFaint : Color.inkMuted)
                        .accessibilityIdentifier("loan-last-due")

                    if !cashAccounts.isEmpty { accountField }

                    if !candidates.isEmpty { candidatesSection }

                    if isEditing {
                        Button("删除这笔还款") { confirmingDelete = true }
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
            .navigationTitle(isEditing ? "编辑每月还款" : "添加每月还款")
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
                Text("以后不再自动扣。已经扣过的月供留在 History。")
            }
            .onChange(of: monthly) { excluded = Set(candidates.filter { !$0.countsInBurn }.map(\.id)) }
        }
        .saveErrorAlert($saveError)
        .iosSheetDetents()
    }

    // MARK: - 从哪个账户扣

    /// 房贷一般绑着一张卡：指定了就只从它扣，它余额不够这期就算没扣成
    private var accountField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KickerLabel(text: "从哪个账户扣")
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
                        Text(cashAccounts.first { $0.id == cashAccountID }?.name ?? "按扣款顺序")
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                        Spacer()
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
                    Text("找到 \(candidates.count) 笔 ¥\(FinancialFormatting.wholeNumber(Double(monthly) ?? 0)) 的支出，是以前记的月供吗？")
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
                Text("勾上的不再算进日均消费，记录照样留在 History。")
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
                    Text(expense.note.isEmpty ? expense.category : "\(expense.category) · \(expense.note)")
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

    /// 「最后一期：2028 年 10 月 14 日」。期数还没填好时为 nil
    private var lastDueText: String? {
        guard let count = periodCount,
              let last = LoanSchedule.dueDates(after: .now, dueDay: dueDay, count: count).last else { return nil }
        return "最后一期：" + Self.fullDate(last)
    }

    /// 「2028 年 10 月 14 日」，不跟系统语言走，和 App 其他地方的日期写法一致
    static func fullDate(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0) 年 \(parts.month ?? 0) 月 \(parts.day ?? 0) 日"
    }

    private var isValid: Bool {
        (try? LoanStore.cleanName(name)) != nil
            && Double(monthly).map { FinancialFormatting.validAmount($0) } == true
            && periodCount != nil
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
            periods = String(max(1, status.remaining))
        }
        excluded = Set(candidates.filter { !$0.countsInBurn }.map(\.id))
        focus = isEditing ? nil : .name
    }

    private func save() {
        guard isValid, let value = Double(monthly), let count = periodCount else { return }
        do {
            try LoanStore.save(existing, name: name, monthlyAmount: value, dueDay: dueDay, remaining: count,
                               cashAccountID: cashAccounts.isEmpty ? nil : cashAccountID,
                               pastRepayments: candidates, excludedFromBurn: excluded, in: modelContext)
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
