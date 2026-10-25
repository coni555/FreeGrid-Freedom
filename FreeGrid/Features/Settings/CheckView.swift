// 自检页：一张里程碑卡，分记录、自由天数、现金流三组，每组可以收起；最下面是「我的目标」（Pro，最多三个），没有时只有一行入口。

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
    @AppStorage(FreedomGoalStore.key, store: AppPreferences.store) private var storedGoals = ""
    @AppStorage(FreedomGoal.incomeKey, store: AppPreferences.store) private var enteredIncome: Double?
    /// 收起的组，逗号分隔；记住上次的选择
    @AppStorage(Self.collapsedKey, store: AppPreferences.store) private var collapsedGroups = ""
    /// 打开目标面板：新目标时 goal 是 nil
    @State private var editingGoal: GoalEdit?
    @State private var editingIncome = false
    @State private var showingPro = false

    private struct GoalEdit: Identifiable {
        let id = UUID()
        let goal: FreedomGoal?
    }

    static let collapsedKey = "checkCollapsedGroups"

    private var snapshot: FinancialSnapshot {
        FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                          assetItems: assetItems, cashAccounts: cashAccounts, loans: ProFeatures.loansInEffect(loans),
                          countsAssets: countsAssets)
    }

    private var goals: [FreedomGoal] { FreedomGoalStore.decode(storedGoals) }

    // 作为 Settings 顶部自检卡 push 进来的子页 — 不自带 NavigationStack(用父级的)
    var body: some View {
        let snapshot = snapshot
        let recorded = FreedomGoalMath.recordedMonthlyIncome(incomes)
        let saving = FreedomGoalMath.saving(snapshot: snapshot, enteredIncome: enteredIncome, recordedIncome: recorded)
        let summary = FreedomChecklist.evaluate(snapshot: snapshot, saving: saving)
        let results = goals.map { FreedomGoalMath.evaluate(goal: $0, snapshot: snapshot, saving: saving) }
        ScrollView {
            checklistCard(summary, goals: results)
                .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("财富自由自检")
        .inlineNavTitle()
        .sheet(item: $editingGoal) { edit in
            FreedomGoalSheet(existing: edit.goal, enteredIncome: enteredIncome, recordedIncome: recorded,
                             snapshot: snapshot) { saved, income in
                storedGoals = FreedomGoalStore.encode(FreedomGoalStore.saving(saved, into: goals))
                enteredIncome = income
            } onDelete: {
                storedGoals = FreedomGoalStore.encode(goals.filter { $0.id != edit.goal?.id })
            }
        }
        .proPaywall(isPresented: $showingPro, topic: .goals)
        .sheet(isPresented: $editingIncome) {
            MonthlyIncomeSheet(enteredIncome: enteredIncome, recordedIncome: recorded) { enteredIncome = $0 }
        }
    }

    // MARK: - 里程碑

    private func checklistCard(_ summary: FreedomSummary, goals: [FreedomGoalMath.Result]) -> some View {
        VaultCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: String(localized: "Milestones · 里程碑"))
                    Spacer()
                    Text("\(summary.doneCount) / \(summary.total)")
                        .font(.system(.callout, design: .monospaced).monospacedDigit())
                        .foregroundStyle(Color.skyDeep)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

                ForEach(FreedomCheckGroup.allCases) { group in
                    groupSection(group, items: summary.items(in: group))
                }

                Hairline()
                    .padding(.top, Spacing.sm)
                // 目标是 Pro：没有 Pro 时点加号或已有的目标都去购买页，已有的照常显示
                let unlocked = ProFeatures.canSetGoals
                FreedomGoalSection(results: goals, unlocked: unlocked) {
                    if unlocked { editingGoal = GoalEdit(goal: nil) } else { showingPro = true }
                } onEdit: { goal in
                    if unlocked { editingGoal = GoalEdit(goal: goal) } else { showingPro = true }
                }
                .padding(.horizontal, Spacing.lg)
            }
            .padding(.bottom, Spacing.xs)
        }
    }

    private func isCollapsed(_ group: FreedomCheckGroup) -> Bool {
        collapsedGroups.split(separator: ",").contains(Substring(group.rawValue))
    }

    private func toggle(_ group: FreedomCheckGroup) {
        var set = collapsedGroups.split(separator: ",").map(String.init).filter { $0 != group.rawValue }
        if !isCollapsed(group) { set.append(group.rawValue) }
        withAnimation(.snappy(duration: 0.32)) { collapsedGroups = set.joined(separator: ",") }
    }

    /// 一组：组头（小标签、达成几项、收起箭头）点了收起或展开；收起时只留组头
    private func groupSection(_ group: FreedomCheckGroup, items: [FreedomCheckItem]) -> some View {
        let collapsed = isCollapsed(group)
        let done = items.filter(\.done).count
        return VStack(alignment: .leading, spacing: 0) {
            Button { toggle(group) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    KickerLabel(text: group.kicker)
                    Spacer()
                    Text("\(done)/\(items.count)")
                        .font(.system(.caption2, design: .monospaced).monospacedDigit())
                        .foregroundStyle(done == items.count ? Color.skyDeep : Color.inkFaint)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                        .rotationEffect(.degrees(collapsed ? 0 : 180))
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("check-group-\(group.rawValue)")
            .accessibilityValue(collapsed ? "已收起" : "已展开")

            if !collapsed {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    row(item)
                        .padding(.horizontal, Spacing.lg)
                        .transition(.opacity)
                    if idx < items.count - 1 {
                        Hairline().padding(.leading, Spacing.lg + 30)
                    }
                }
            }
        }
    }

    /// 「每月有结余」点了能填每月收入，其余各行只是显示
    @ViewBuilder
    private func row(_ item: FreedomCheckItem) -> some View {
        if item.id == 4 {
            Button { editingIncome = true } label: { checklistRow(item: item) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("check-saving-row")
        } else {
            checklistRow(item: item)
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
                    Text(item.achievedNote.map { String(localized: "已达成 · \($0)") } ?? String(localized: "已达成"))
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.skyDeep)
                } else {
                    if let p = item.progress {
                        CheckProgressBar(progress: p)
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
        .contentShape(Rectangle())
    }
}

/// 里程碑和 GAP 那一行共用的细进度条
struct CheckProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.mist2)
                Capsule()
                    .fill(Color.skyDeep)
                    .frame(width: max(2, geo.size.width * progress))
            }
        }
        .frame(height: 4)
    }
}
