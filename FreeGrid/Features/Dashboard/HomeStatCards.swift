// 首页底部的卡片（几张小卡 + 今日对比长条 + 目标长条）：首页上按住拖动排序，点一下打开编辑面板加、移除、恢复默认。
// 有哪些卡、每张显示什么在 Logic/HomeStat.swift。

import SwiftUI
import UniformTypeIdentifiers

/// 首页上的卡片：小卡一行最多三张，长条占一整行。点一下打开编辑面板（「本月花销」去明细看这个月）；按住浮起后拖到别的卡上，它们就让位。
/// 拖放用系统的（和滚动、点按不打架），拖动中每经过一张卡就存一次新顺序
struct HomeCardsGrid: View {
    /// 首页上要画的（今日对比没有可比的数时不在里面）
    let items: [HomeStat]
    /// 存着的完整顺序；拖动改的是它
    let slots: [HomeStat]
    let inputs: HomeStat.Inputs
    /// 今日对比长条，首页自己画好传进来
    let todayBar: AnyView
    /// 目标长条点了打开那个目标的面板，不是编辑卡片
    let onGoal: (FreedomGoal) -> Void
    /// 「本月花销」点了去明细看这个月
    let onMonth: () -> Void
    let onEdit: () -> Void
    let onReorder: ([HomeStat]) -> Void

    @State private var dragging: HomeStat?

    var body: some View {
        StatRowsLayout(spacing: Spacing.md) {
            ForEach(items) { item in
                let goal = inputs.goal(for: item)
                Button {
                    if let goal { onGoal(goal.goal) } else if item == .month { onMonth() } else { onEdit() }
                } label: {
                    if let goal {
                        HomeGoalCard(result: goal)
                    } else if item.isWide {
                        todayBar
                    } else {
                        HomeStatCard(stat: item, display: item.display(inputs))
                    }
                }
                .buttonStyle(.plain)
                // 展开时多出来的卡淡入，收起时淡出；位置变化跟着一起滑
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                .layoutValue(key: IsWideCard.self, value: item.isWide)
                .onDrag {
                    dragging = item
                    return NSItemProvider(object: item.rawValue as NSString)
                }
                .onDrop(of: [UTType.text], delegate: CardDropDelegate(target: item, slots: slots,
                                                                       dragging: $dragging, onReorder: onReorder))
                .accessibilityIdentifier("home-stat-\(item.rawValue)")
                .accessibilityHint(goal != nil ? String(localized: "按住拖动换位置，点一下改这个目标")
                                   : item == .month ? String(localized: "按住拖动换位置，点一下看这个月的明细")
                                   : String(localized: "按住拖动换位置，点一下编辑卡片"))
                .accessibilityActions { moveActions(item) }
            }
        }
    }

    /// 读屏时拖不了：给「往前挪 / 往后挪」两个动作
    @ViewBuilder
    private func moveActions(_ item: HomeStat) -> some View {
        if let index = slots.firstIndex(of: item) {
            if index > 0 {
                Button("往前挪") { onReorder(moved(item, to: index - 1)) }
            }
            if index < slots.count - 1 {
                Button("往后挪") { onReorder(moved(item, to: index + 1)) }
            }
        }
    }

    private func moved(_ item: HomeStat, to index: Int) -> [HomeStat] {
        var result = slots.filter { $0 != item }
        result.insert(item, at: min(index, result.count))
        return result
    }
}

/// 拖着的卡进了哪张卡，就挪到那张卡的位置
private struct CardDropDelegate: DropDelegate {
    let target: HomeStat
    let slots: [HomeStat]
    @Binding var dragging: HomeStat?
    let onReorder: ([HomeStat]) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target, let to = slots.firstIndex(of: target) else { return }
        var result = slots.filter { $0 != dragging }
        result.insert(dragging, at: min(to, result.count))
        withAnimation(.snappy(duration: 0.25)) { onReorder(result) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// 排版在主线程外也会读它，不能跟着模块默认归到主线程
nonisolated private struct IsWideCard: LayoutValueKey {
    static let defaultValue = false
}

/// 按 `HomeStat.rowRanges` 排：长条占一整行；同一行的小卡一样宽、一样高
struct StatRowsLayout: Layout {
    var spacing: CGFloat

    private func rows(_ subviews: Subviews, width: CGFloat) -> [(range: Range<Int>, cardWidth: CGFloat, height: CGFloat)] {
        HomeStat.rowRanges(wide: subviews.map { $0[IsWideCard.self] }).map { range in
            let cardWidth = (width - spacing * CGFloat(range.count - 1)) / CGFloat(range.count)
            let height = range.map { subviews[$0].sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height }.max() ?? 0
            return (range, cardWidth, height)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let rows = rows(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            for (column, index) in row.range.enumerated() {
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (row.cardWidth + spacing), y: y),
                                      proposal: ProposedViewSize(width: row.cardWidth, height: row.height))
            }
            y += row.height + spacing
        }
    }
}

/// 一张小卡：细数字 / 短横线 / 小标签 / 小字。同一行的卡撑到一样高
struct HomeStatCard: View {
    let stat: HomeStat
    let display: HomeStat.Display

    var body: some View {
        VaultCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(display.value)
                    .font(.system(size: 28, weight: .thin, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Rectangle()
                    .fill(Color.inkGhost)
                    .frame(width: 22, height: 1)
                    .padding(.vertical, 2)
                KickerLabel(text: stat.kicker)
                // 小字一般一行、放不下就缩小；只有「再记录 N 天，日均趋势会更清晰」这种带逗号的长句在逗号处分成两行，
                // 不让窄卡把「上月同期」这类词从中间折断
                let isSentence = display.unit.contains("，")
                Text(isSentence ? display.unit.replacingOccurrences(of: "，", with: "，\n") : display.unit)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(isSentence ? 2 : 1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: isSentence)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 首页上的卡都移除了时，占位的虚线框，点了打开编辑面板
struct HomeStatEmptySlot: View {
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                Text("添加卡片")
                    .font(.system(.subheadline, design: .rounded))
            }
            .foregroundStyle(Color.inkMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.inkGhost, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add-first-home-stat")
    }
}

// MARK: - 编辑面板

/// 「编辑卡片」：上面是首页上的卡（按顺序，左边移除、右边拖动排序），下面是还能加的；移除的卡回到下面，点一下就加回来。
/// 今日对比长条也是其中一张。顶上「恢复默认」「完成」，「还可以添加」那组有「全部添加」
struct HomeStatEditor: View {
    let slots: [HomeStat]
    let inputs: HomeStat.Inputs
    let onChange: ([HomeStat]) -> Void
    /// 恢复成没改过的样子
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// 固定的几张加上现在能放的目标卡（没有 Pro 时没有目标卡）
    private var available: [HomeStat] { (HomeStat.builtIn + inputs.goalStats).filter { !slots.contains($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if slots.isEmpty {
                        Text("首页上还没有卡片，从下面加")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                            .listRowBackground(Color.mist)
                    }
                    ForEach(slots) { stat in
                        row(stat, added: true)
                    }
                    .onMove { from, to in
                        var moved = slots
                        moved.move(fromOffsets: from, toOffset: to)
                        onChange(moved)
                    }
                } header: {
                    sectionHeader("在首页上")
                } footer: {
                    if slots.count > 1 {
                        Text("按住右边的把手拖动调整顺序；在首页上按住卡片也能直接拖")
                            .font(.system(.caption2, design: .rounded))
                    }
                }

                Section {
                    if available.isEmpty {
                        Text("都在首页上了")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                            .listRowBackground(Color.mist)
                    }
                    ForEach(available) { stat in
                        row(stat, added: false)
                    }
                    .moveDisabled(true)
                } header: {
                    HStack {
                        sectionHeader("还可以添加")
                        Spacer()
                        if available.count > 1 {
                            Button("全部添加") {
                                withAnimation { onChange(slots + available) }
                            }
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.skyDeep)
                            .accessibilityIdentifier("add-all-stats")
                        }
                    }
                } footer: {
                    Text("移除的卡会回到这里，随时可以加回来")
                        .font(.system(.caption2, design: .rounded))
                }

            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("编辑卡片")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("恢复默认") { withAnimation { onReset() } }
                        .accessibilityIdentifier("reset-home-stats")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("home-stat-editor-done")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: slots)
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func sectionHeader(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.inkMuted)
            .textCase(nil)
    }

    /// 一行：左边移除 / 添加，中间名字和小字，右边现在的数
    private func row(_ stat: HomeStat, added: Bool) -> some View {
        let display = stat.display(inputs)
        return HStack(spacing: Spacing.md) {
            Button {
                withAnimation { onChange(added ? slots.filter { $0 != stat } : slots + [stat]) }
            } label: {
                Image(systemName: added ? "minus.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(added ? Color.flame : Color.skyDeep)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(added ? "移除\(stat.title(in: inputs))" : "添加\(stat.title(in: inputs))")
            .accessibilityIdentifier(added ? "remove-stat-\(stat.rawValue)" : "add-stat-\(stat.rawValue)")

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.title(in: inputs))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
                Text(display.unit)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: Spacing.sm)
            Text(display.value)
                .font(.system(size: 22, weight: .thin, design: .rounded).monospacedDigit())
                .foregroundStyle(added ? Color.ink : Color.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 2)
        .listRowBackground(Color.mist)
    }
}
