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

    @State private var saveError: String?
    @State private var amount: String = ""
    @State private var category: String = "早餐"
    @State private var note: String = ""
    @State private var date: Date = .now

    /// 分类清单 = 权威 canonical(单一来源 ExpenseCategory.canonical)。
    /// "人情"/"日用" 已不在清单(2026-05 移除);旧记录仍能在 History 正常显示。
    private let categories = ExpenseCategory.canonical

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    TransactionFormFields(mode: .expense, amount: $amount, title: $category,
                                          note: $note, date: $date, categories: categories)

                    // ===== 戴维斯三杀实时预览: 金额有效才出现, 还没保存 =====
                    if let amt = Double(amount), FinancialFormatting.validAmount(amt) {
                        impactCard(title: "戴维斯三杀预览", note: "这笔消费对自由天数的传导效应。还没保存，只是看看。") {
                            TransactionImpactView(impact: TransactionImpact(
                                snapshot: snapshot, kind: .expense, amount: amt, date: date
                            ))
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .dismissKeyboardOnScroll()
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("添加支出")
            .inlineNavTitle()
            .saveErrorAlert($saveError)
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

    private var snapshot: FinancialSnapshot {
        FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first)
    }

    private var isAmountValid: Bool {
        guard let value = Double(amount),
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
        do {
            try LedgerStore.add(.expense(expense), in: modelContext)
            onSaved?(expense)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
