// 自检页：最上面是 GAP 倒计时（离职目标），下面是里程碑清单，最后一行写记账天数够不够让日均变稳。

import SwiftUI
import SwiftData

struct CheckView: View {

    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]
    @Query private var assetItems: [AssetItem]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    @Query private var loans: [Loan]
    @AppStorage(FreedomSettings.countsAssetsKey, store: AppPreferences.store) private var countsAssets = true
    @AppStorage(FreedomGoal.leaveDateKey, store: AppPreferences.store) private var goalLeaveDate: Double?
    @AppStorage(FreedomGoal.targetDaysKey, store: AppPreferences.store) private var goalTargetDays = 0
    @AppStorage(FreedomGoal.incomeKey, store: AppPreferences.store) private var enteredIncome: Double?
    @State private var editingGoal = false

    private var snapshot: FinancialSnapshot {
        FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                          assetItems: assetItems, cashAccounts: cashAccounts, loans: ProFeatures.loansInEffect(loans),
                          countsAssets: countsAssets)
    }

    private var goal: FreedomGoal? { FreedomGoal(leaveDate: goalLeaveDate, targetDays: goalTargetDays) }

    // 作为 Settings 顶部自检卡 push 进来的子页 — 不自带 NavigationStack(用父级的)
    var body: some View {
        let snapshot = snapshot
        let recorded = FreedomGoalMath.recordedMonthlyIncome(incomes)
        let saving = FreedomGoalMath.saving(snapshot: snapshot, enteredIncome: enteredIncome, recordedIncome: recorded)
        let summary = FreedomChecklist.evaluate(snapshot: snapshot, saving: saving)
        let result = goal.map { FreedomGoalMath.evaluate(goal: $0, snapshot: snapshot, saving: saving) }
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                FreedomGoalCard(result: result) { editingGoal = true }
                checklistCard(summary)
                if let note = summary.dataNote {
                    Text(note)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.horizontal, Spacing.xs)
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("财富自由自检")
        .inlineNavTitle()
        .sheet(isPresented: $editingGoal) {
            FreedomGoalSheet(existing: goal, enteredIncome: enteredIncome, recordedIncome: recorded,
                             snapshot: snapshot) { newGoal, income in
                goalLeaveDate = newGoal.leaveDate.timeIntervalSince1970
                goalTargetDays = newGoal.targetDays ?? 0
                enteredIncome = income
            } onClear: {
                goalLeaveDate = nil
                goalTargetDays = 0
            }
        }
    }

    // MARK: - 里程碑

    private func checklistCard(_ summary: FreedomSummary) -> some View {
        VaultCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: String(localized: "Milestones · 里程碑"))
                    Spacer()
                    Text("\(summary.doneCount) / \(summary.total)")
                        .font(.system(.callout, design: .monospaced).monospacedDigit())
                        .foregroundStyle(Color.skyDeep)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.sm)
                ForEach(Array(summary.items.enumerated()), id: \.element.id) { idx, item in
                    checklistRow(item: item)
                        .padding(.horizontal, Spacing.lg)
                    if idx < summary.items.count - 1 {
                        Hairline().padding(.leading, Spacing.lg + 30)
                    }
                }
            }
            .padding(.bottom, Spacing.xs)
        }
    }

    private func checklistRow(item: FreedomCheckItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 状态点: 达成 = sky 描边 + 勾, 未达成 = outline
            ZStack {
                Circle()
                    .stroke(item.done ? Color.skyDeep : Color.inkFaint.opacity(0.6), lineWidth: 1.2)
                    .frame(width: 18, height: 18)
                if item.done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.skyDeep)
                }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(item.done ? Color.ink : Color.inkMuted)

                if item.done {
                    // 没有进度条的项（每月有结余）达成后仍写一句数字
                    Text(item.progress == nil && !item.detail.isEmpty
                         ? String(localized: "已达成 · \(item.detail)") : String(localized: "已达成"))
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.skyDeep)
                } else {
                    if let p = item.progress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.mist2)
                                Capsule()
                                    .fill(Color.skyDeep)
                                    .frame(width: max(2, geo.size.width * p))
                            }
                        }
                        .frame(height: 4)
                    }
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.system(.caption2, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(Color.inkFaint)
                    }
                    Text("怎么前进 · \(item.hint)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
