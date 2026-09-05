// 展示 FreedomChecklist 计算出的八项自检结果。

import SwiftUI
import SwiftData

struct CheckView: View {

    @Query private var expenses: [Expense]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]

    /// 8 项自检 + 汇总 — 逻辑统一在 FreedomChecklist, collapsed 卡与本页共用
    private var summary: FreedomSummary {
        FreedomChecklist.evaluate(expenses: expenses,
                                  passiveSources: passiveSources,
                                  assets: assetsArr.first)
    }

    // 作为 Settings 顶部自检卡 push 进来的子页 — 不自带 NavigationStack(用父级的)
    var body: some View {
        let result = summary
        ScrollView {
            VStack(spacing: Spacing.lg) {
                heroCard(result)
                checklistCard(result)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("财富自由自检")
        .inlineNavTitle()
    }

    // MARK: - Hero 进度卡

    private func heroCard(_ summary: FreedomSummary) -> some View {
        VaultCard(emphasis: .high, padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "Freedom Checklist")

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(summary.doneCount)")
                        .font(.system(size: 56, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                    Text("/ \(summary.total)")
                        .font(.system(size: 22, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                    Spacer()
                    Text(FinancialFormatting.percentage(summary.progress))
                        .font(.system(.callout, design: .monospaced).monospacedDigit())
                        .foregroundStyle(Color.skyDeep)
                }

                // 进度长条 silverline 风
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.mist)
                        Capsule()
                            .fill(Color.skyDeep)
                            .frame(width: max(2, geo.size.width * summary.progress))
                    }
                }
                .frame(height: 4)

                Text("达成项越多,离财富自由越近")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }

    // MARK: - 8 项列表卡

    private func checklistCard(_ summary: FreedomSummary) -> some View {
        VaultCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(summary.items.enumerated()), id: \.element.id) { idx, item in
                    checklistRow(item: item)
                        .padding(.horizontal, Spacing.lg)
                    if idx < summary.items.count - 1 {
                        Hairline().padding(.leading, Spacing.lg + 30)
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func checklistRow(item: FreedomCheckItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 状态点: 达成 = sky 实心 + 勾, 未达成 = outline
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
                Text("\(item.id). \(item.title)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(item.done ? Color.ink : Color.inkMuted)
                    .strikethrough(item.done, color: Color.inkFaint)

                if item.done {
                    Text("已达成")
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.skyDeep)
                } else {
                    // 量化项(1/4/5/7/8): 细进度条 + 当前/目标; 二元项(2/3/6): 跳过
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
                        Text(item.detail)
                            .font(.system(.caption2, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(Color.inkFaint)
                    }
                    // 怎么前进
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
