// 首页底部的数字小卡：首页上只负责显示，点卡片或「编辑卡片」打开编辑面板，在面板里加、移除、拖动排序、恢复默认。
// 有哪些指标、每个显示什么在 Logic/HomeStat.swift。

import SwiftUI

/// 小卡排成几行（一行最多三张）。点任意一张打开编辑面板；首页上不藏别的手势，免得和滚动、点按打架
struct HomeStatGrid: View {
    let slots: [HomeStat]
    let inputs: HomeStat.Inputs
    let onEdit: () -> Void

    var body: some View {
        StatRowsLayout(spacing: Spacing.md) {
            ForEach(slots) { stat in
                Button(action: onEdit) {
                    HomeStatCard(stat: stat, display: stat.display(inputs))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-stat-\(stat.rawValue)")
                .accessibilityHint("打开编辑卡片")
            }
        }
    }
}

/// 按 `HomeStat.rowSizes` 排：同一行的卡一样宽、一样高
struct StatRowsLayout: Layout {
    var spacing: CGFloat

    private func rows(_ subviews: Subviews, width: CGFloat) -> [(range: Range<Int>, cardWidth: CGFloat, height: CGFloat)] {
        var start = 0
        return HomeStat.rowSizes(count: subviews.count).map { count in
            let cardWidth = (width - spacing * CGFloat(count - 1)) / CGFloat(count)
            let range = start..<(start + count)
            start += count
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

/// 首页卡片都移除、今日对比也关了时，占位的虚线框，点了打开编辑面板
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
/// 顶上「恢复默认」「完成」，「还可以添加」那组有「全部添加」，最后是今日对比长条的开关
struct HomeStatEditor: View {
    let slots: [HomeStat]
    let inputs: HomeStat.Inputs
    let onChange: ([HomeStat]) -> Void
    @Binding var showsToday: Bool
    /// 恢复成没改过的样子（卡片和今日对比都回到默认）
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var available: [HomeStat] { HomeStat.allCases.filter { !slots.contains($0) } }

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
                        Text("按住右边的把手拖动，调整首页上的顺序")
                            .font(.system(.caption2, design: .rounded))
                    }
                }

                Section {
                    if available.isEmpty {
                        Text("七张都在首页上了")
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

                Section {
                    Toggle(isOn: $showsToday.animation(.snappy(duration: 0.3))) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("今日对比长条")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Color.ink)
                            Text("今天的日常支出和日常比，放在小卡下面")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                    .tint(Color.skyDeep)
                    .accessibilityIdentifier("today-strip-toggle")
                    .listRowBackground(Color.mist)
                } header: {
                    sectionHeader("长条")
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

    private func sectionHeader(_ text: String) -> some View {
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
            .accessibilityLabel(added ? "移除\(stat.title)" : "添加\(stat.title)")
            .accessibilityIdentifier(added ? "remove-stat-\(stat.rawValue)" : "add-stat-\(stat.rawValue)")

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.title)
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
