// 收入表单：输入、预览，确认后记账。

import SwiftUI
import SwiftData

struct AddIncomeSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 保存成功回调 — DashboardView 用它显示 5 秒撤销 toast
    var onSaved: ((Income) -> Void)? = nil

    // 预览需要读所有现有数据,实时算"如果加这一笔,自由天数增长多少"
    @Query private var expenses: [Expense]
    @Query private var assetsArr: [UserAssets]
    @Query private var passiveSources: [PassiveSource]

    @State private var saveError: String?
    @State private var amount: String = ""
    @State private var source: String = ""
    @State private var note: String = ""
    @State private var date: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section("金额 (元)") {
                    TextField("0.00", text: $amount)
                        .decimalKeyboard()
                        .font(.system(.body, design: .rounded).monospacedDigit())
                }
                Section("来源") {
                    TextField("工资 / 投资 / 副业 / ...", text: $source)
                        .font(.system(.body, design: .rounded))
                }
                Section("日期") {
                    DatePicker("日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section("备注 (可选)") {
                    TextField("备注", text: $note)
                        .font(.system(.body, design: .rounded))
                }

                if let amt = Double(amount), FinancialFormatting.validAmount(amt) {
                    Section {
                        TransactionImpactView(impact: TransactionImpact(
                            snapshot: snapshot, kind: .income, amount: amt, date: date
                        ))
                    } header: {
                        Text("自由增长预览")
                    } footer: {
                        Text("这笔收入对自由天数的回血效应。")
                            .font(.system(.caption2, design: .rounded))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("添加收入")
            .inlineNavTitle()
            .saveErrorAlert($saveError)
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
        }
    }

    private var snapshot: FinancialSnapshot {
        FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first)
    }

    /// 输入有效性: 金额、来源、备注和日期都必须落在备份可表示边界内。
    private var isValid: Bool {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(amount),
              FinancialFormatting.validAmount(value),
              !trimmedSource.isEmpty,
              trimmedSource.count <= FinancialLimits.nameCharacters,
              note.count <= FinancialLimits.noteCharacters,
              Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: .now) else {
            return false
        }
        let resultingCash = (assetsArr.first?.cash ?? 0) + value
        return resultingCash.isFinite && abs(resultingCash) <= FinancialLimits.maximumAmount
    }

    /// 保存成功才通知首页并关闭；失败保留输入。
    private func save() {
        guard isValid, let amt = Double(amount) else { return }
        let income = Income(amount: amt, source: source.trimmingCharacters(in: .whitespacesAndNewlines),
                            isPassive: false, note: note, date: date)
        do {
            try LedgerStore.add(.income(income), in: modelContext)
            onSaved?(income)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
