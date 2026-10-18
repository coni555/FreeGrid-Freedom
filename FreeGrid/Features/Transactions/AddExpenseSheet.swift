// 支出表单：输入、预览，确认后记账。

import SwiftUI
import SwiftData

struct AddExpenseSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 保存成功回调 — DashboardView 用它显示 5 秒撤销 toast
    var onSaved: ((Expense) -> Void)? = nil

    // 预览需要读所有现有数据,实时算"如果加这一笔,自由天数变化"
    @Query private var expenses: [Expense]
    @Query private var assetsArr: [UserAssets]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetItems: [AssetItem]
    @Query private var loans: [Loan]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    /// Pro 现金账户：用户手动换的账户；nil = 按扣款顺序自动挑
    @State private var pickedAccount: UUID?

    @State private var saveError: String?
    @State private var amount: String
    @State private var category: String = ""
    @State private var note: String = ""
    @State private var date: Date = .now
    /// 分类菜单最后一项：有 Pro 进管理页，没有 Pro 打开购买页
    @State private var showingCategories = false
    @State private var showingPro = false

    @AppStorage(ExpenseCategoryStorage.key, store: AppPreferences.store) private var encodedOptions = ""
    private var categories: [String] {
        guard ProFeatures.canCustomizeExpenseCategories else { return ExpenseCategory.canonical }
        return ExpenseCategoryStorage.decode(encodedOptions)
            .including(expenses.filter { $0.loanID == nil }.map(\.category)).visibleNames
    }

    /// `initialAmount` 给「模拟完直接记为支出」用: 表单打开时金额已经填好
    init(initialAmount: String = "", onSaved: ((Expense) -> Void)? = nil) {
        self.onSaved = onSaved
        _amount = State(initialValue: initialAmount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("0.00", text: $amount)
                        .decimalKeyboard()
                        .font(.system(.body, design: .rounded).monospacedDigit())
                } header: {
                    Text("金额（元）")
                }
                // 分类这组不加小标题: 行里已经写了「分类」, 上面再写一遍是重复。
                // 管理分类的入口收在菜单最后一项：只在用户找分类时出现，平时表单里没有任何推销
                Section {
                    Menu {
                        Picker("分类", selection: $category) {
                            ForEach(categories, id: \.self) { c in
                                Text(c).tag(c)
                            }
                        }
                        Divider()
                        if ProFeatures.canCustomizeExpenseCategories {
                            Button("管理分类…", systemImage: "slider.horizontal.3") { showingCategories = true }
                        } else {
                            Button("添加自己的分类 · Pro", systemImage: "plus") { showingPro = true }
                        }
                    } label: {
                        HStack {
                            Text("分类")
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Text(category)
                                .foregroundStyle(.tint)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.tint)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("expense-category-picker")
                }
                if !cashAccounts.isEmpty { accountSection }
                Section("日期") {
                    TransactionDateRow(date: $date)
                }
                Section("备注（可选）") {
                    TextField("备注", text: $note)
                        .font(.system(.body, design: .rounded))
                }

                // ===== 这笔支出的影响（实时预览）=====
                if let amt = Double(amount), FinancialFormatting.validAmount(amt) {
                    Section {
                        TransactionImpactView(impact: TransactionImpact(
                            snapshot: snapshot, kind: .expense, amount: amt, date: date,
                            account: accountSection.chosen
                        ))
                    } header: {
                        Text("这笔支出的影响")
                    } footer: {
                        Text("记下之后，净值、日均和自由天数会怎么变。还没保存。")
                            .font(.system(.caption2, design: .rounded))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationDestination(isPresented: $showingCategories) { ExpenseCategoriesView() }
            .proPaywall(isPresented: $showingPro, topic: .categories)
            .navigationTitle("添加支出")
            .inlineNavTitle()
            .saveErrorAlert($saveError)
            .onChange(of: categories, initial: true) { _, names in
                if !names.contains(category) { category = names.first ?? ExpenseCategory.fallback }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isAmountValid)
                        .foregroundStyle(isAmountValid ? Color.skyDeep : Color.inkFaint)
                        .fontWeight(.medium)
                }
            }
        }
    }

    private var accountSection: CashAccountSection {
        CashAccountSection(accounts: cashAccounts, kind: .expense,
                           amount: Double(amount).flatMap { FinancialFormatting.validAmount($0) ? $0 : nil },
                           picked: $pickedAccount)
    }

    private var snapshot: FinancialSnapshot {
        FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                          assetItems: assetItems, cashAccounts: cashAccounts, loans: loans)
    }

    private var isAmountValid: Bool {
        guard let value = Double(amount),
              categories.contains(category),
              FinancialFormatting.validAmount(value),
              note.count <= FinancialLimits.noteCharacters,
              Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: .now) else {
            return false
        }
        let resultingCash = (assetsArr.first?.cash ?? 0) - value
        return resultingCash.isFinite && abs(resultingCash) <= FinancialLimits.maximumAmount
    }

    /// 保存成功才通知首页并关闭；失败保留输入。
    private func save() {
        guard isAmountValid, let amt = Double(amount) else { return }
        let expense = Expense(amount: amt, category: category, note: note, date: date)
        expense.cashAccountID = cashAccounts.isEmpty ? nil : accountSection.chosen?.id
        do {
            try LedgerStore.add(.expense(expense), in: modelContext)
            onSaved?(expense)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
