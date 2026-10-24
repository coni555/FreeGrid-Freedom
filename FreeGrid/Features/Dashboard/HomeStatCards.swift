// 首页底部的数字小卡：点一张换内容或移除，按住拖动换位置（可以跨行），「添加卡片」加新的、开关今日对比。
// 有哪些指标、每个显示什么在 Logic/HomeStat.swift。

import SwiftUI

/// 小卡排成几行（一行最多三张）。按住 0.3 秒卡片浮起跟着手指走，经过别的卡时它们让位，松手落下
struct HomeStatGrid: View {
    let slots: [HomeStat]
    let inputs: HomeStat.Inputs
    /// 拖完以后的新顺序
    let onReorder: ([HomeStat]) -> Void
    /// 点了哪一张
    let onPick: (HomeStat) -> Void
    /// 拖动时首页别跟着上下滚
    let onDraggingChange: (Bool) -> Void

    /// 拖动中的顺序；不拖时跟 `slots` 一样
    @State private var order: [HomeStat] = []
    @State private var dragging: HomeStat?
    /// 拖起来那一刻，卡片中心在格子区里的位置
    @State private var startCenter: CGPoint = .zero
    /// 拖起来那一刻每一格的位置（按顺序）。拖动中只是卡在这几格之间换，格子本身不动；
    /// 按格子判断落点，不等卡片换位后的新位置报上来，免得两张卡在同一帧里来回对调
    @State private var slotFrames: [CGRect] = []
    @State private var translation: CGSize = .zero
    /// 每张卡在格子区里排好的位置（不含拖动的偏移）
    @State private var frames: [HomeStat: CGRect] = [:]
    @State private var lifts = 0
    @GestureState private var pressing = false

    private static let space = "home-stat-grid"

    private var shown: [HomeStat] { dragging == nil ? slots : order }

    var body: some View {
        StatRowsLayout(spacing: Spacing.md) {
            ForEach(shown) { stat in
                let isDragged = dragging == stat
                HomeStatCard(stat: stat, display: stat.display(inputs))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[stat] = $0 }
                    .scaleEffect(isDragged ? 1.06 : 1)
                    .shadow(color: .black.opacity(isDragged ? 0.14 : 0), radius: 14, y: 8)
                    .offset(isDragged ? draggedOffset(stat) : .zero)
                    .zIndex(isDragged ? 1 : 0)
                    // 拖着的那张换格子时不做动画，才能一直贴着手指；让位的卡照常滑过去
                    .transaction { if isDragged { $0.animation = nil } }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onTapGesture { onPick(stat) }
                    .gesture(drag(stat))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("home-stat-\(stat.rawValue)")
                    .accessibilityHint("点一下换内容或移除，按住拖动换位置")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityActions { moveActions(stat) }
            }
        }
        .coordinateSpace(.named(Self.space))
        .sensoryFeedback(.impact(weight: .light), trigger: lifts)
        .sensoryFeedback(.selection, trigger: order)
        // 手势被滚动或系统打断时也要放下
        .onChange(of: pressing) { _, isPressing in
            if !isPressing { drop() }
        }
    }

    /// 拖着的卡：手指现在的位置减去它现在那一格的中心
    private func draggedOffset(_ stat: HomeStat) -> CGSize {
        guard let index = order.firstIndex(of: stat), slotFrames.indices.contains(index) else { return translation }
        let slot = slotFrames[index]
        return CGSize(width: startCenter.x + translation.width - slot.midX,
                      height: startCenter.y + translation.height - slot.midY)
    }

    private func drag(_ stat: HomeStat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .updating($pressing) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging == nil {
                    order = slots
                    slotFrames = slots.map { frames[$0] ?? .zero }
                    startCenter = frames[stat].map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
                    withAnimation(.snappy(duration: 0.2)) { dragging = stat }
                    lifts += 1
                    onDraggingChange(true)
                }
                translation = drag?.translation ?? .zero
                // 手指进了哪一格，就把拖着的卡挪到那一格
                let finger = CGPoint(x: startCenter.x + translation.width, y: startCenter.y + translation.height)
                if let to = slotFrames.firstIndex(where: { $0.contains(finger) }),
                   let from = order.firstIndex(of: stat), from != to {
                    withAnimation(.snappy(duration: 0.25)) {
                        order = HomeStat.moving(order, from: from, to: to)
                    }
                }
            }
            .onEnded { _ in drop() }
    }

    private func drop() {
        guard dragging != nil else { return }
        let final = order
        withAnimation(.snappy(duration: 0.28)) {
            if final != slots { onReorder(final) }
            dragging = nil
            translation = .zero
        }
        onDraggingChange(false)
    }

    /// 读屏时拖不了：给「往前挪 / 往后挪」两个动作
    @ViewBuilder
    private func moveActions(_ stat: HomeStat) -> some View {
        if let index = slots.firstIndex(of: stat) {
            if index > 0 {
                Button("往前挪") { onReorder(HomeStat.moving(slots, from: index, to: index - 1)) }
            }
            if index < slots.count - 1 {
                Button("往后挪") { onReorder(HomeStat.moving(slots, from: index, to: index + 1)) }
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

/// 一张小卡：细数字 / 短横线 / 小标签 / 小字（最多两行）。同一行的卡撑到一样高
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
    }
}

// MARK: - 选卡的半屏

/// 每个指标画成一张小卡、带着现在的真实数字
private struct StatOptionTile: View {
    let stat: HomeStat
    let display: HomeStat.Display
    /// 打勾的：这张卡现在显示的，或已经在首页上的
    let isChecked: Bool
    /// 小字换成这句（比如「在首页 · 对调」）；nil 时显示指标自己的小字
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(stat.title)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(isChecked ? Color.skyDeep : Color.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.skyDeep)
                }
            }
            Text(display.value)
                .font(.system(size: 24, weight: .thin, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(note ?? display.unit)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.mist))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isChecked ? Color.skyDeep : Color.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 半屏的外壳：小标签 + 标题 + 内容
private struct StatSheet<Content: View>: View {
    let kicker: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    KickerLabel(text: kicker)
                    Text(title)
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.ink)
                }
                content
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.lg)
        }
        .background(Color.paper.ignoresSafeArea())
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

private let optionColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 3)

/// 点了首页上的一张卡：换成别的，或者移除
struct HomeStatPicker: View {
    let stat: HomeStat
    let slots: [HomeStat]
    let inputs: HomeStat.Inputs
    let onChange: ([HomeStat]) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        StatSheet(kicker: stat.kicker, title: "这张卡显示什么") {
            LazyVGrid(columns: optionColumns, spacing: Spacing.md) {
                ForEach(HomeStat.allCases) { option in
                    Button {
                        if option != stat, let index = slots.firstIndex(of: stat) {
                            onChange(HomeStat.replacing(slots, at: index, with: option))
                        }
                        dismiss()
                    } label: {
                        // 已经在另一张上的：选它就两张对调
                        StatOptionTile(stat: option, display: option.display(inputs), isChecked: option == stat,
                                       note: option != stat && slots.contains(option) ? "在首页 · 对调" : nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("stat-option-\(option.rawValue)")
                }
            }
            Button {
                onChange(slots.filter { $0 != stat })
                dismiss()
            } label: {
                Text("从首页移除这张")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.flame)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("remove-home-stat")
            Text("按住卡片可以拖动换位置")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .frame(maxWidth: .infinity)
        }
    }
}

/// 「添加卡片」：点一张加到最后，再点一次拿掉；下面开关今日对比长条
struct HomeStatAdder: View {
    let slots: [HomeStat]
    let inputs: HomeStat.Inputs
    let onChange: ([HomeStat]) -> Void
    @Binding var showsToday: Bool

    var body: some View {
        StatSheet(kicker: "Home Cards", title: "首页放哪些卡") {
            LazyVGrid(columns: optionColumns, spacing: Spacing.md) {
                ForEach(HomeStat.allCases) { option in
                    Button {
                        withAnimation(.snappy(duration: 0.3)) { onChange(HomeStat.toggling(slots, option)) }
                    } label: {
                        StatOptionTile(stat: option, display: option.display(inputs), isChecked: slots.contains(option))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("stat-option-\(option.rawValue)")
                    .accessibilityAddTraits(slots.contains(option) ? .isSelected : [])
                }
            }
            VaultCard(padding: Spacing.md) {
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
            }
            Text("打勾的在首页上，再点一次拿掉。按住首页的卡片可以拖动换位置")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }
}
