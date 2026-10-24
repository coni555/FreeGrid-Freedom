// 首页底部三张数字小卡：点一张选它显示什么，按住拖动换位置。显示什么、怎么算在 Logic/HomeStat.swift。

import SwiftUI

/// 三张卡排成一行。按住 0.3 秒卡片浮起，跟着手指左右走，另外两张让位，松手落到新位置
struct HomeStatRow: View {
    let slots: [HomeStat]
    let inputs: HomeStat.Inputs
    /// 拖完以后的新顺序
    let onReorder: ([HomeStat]) -> Void
    /// 点了第几张
    let onPick: (Int) -> Void
    /// 拖动时首页别跟着上下滚
    let onDraggingChange: (Bool) -> Void

    @State private var dragging: HomeStat?
    @State private var translation: CGFloat = 0
    @State private var rowWidth: CGFloat = 0
    @State private var lifts = 0
    @GestureState private var pressing = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            ForEach(Array(slots.enumerated()), id: \.element) { index, stat in
                let isDragged = dragging == stat
                HomeStatCard(stat: stat, display: stat.display(inputs))
                    .scaleEffect(isDragged ? 1.06 : 1)
                    .shadow(color: .black.opacity(isDragged ? 0.14 : 0), radius: 14, y: 8)
                    .offset(x: offset(of: stat, at: index))
                    .zIndex(isDragged ? 1 : 0)
                    // 被让位的卡滑过去；拖着的那张紧跟手指，不加动画
                    .animation(isDragged ? nil : .snappy(duration: 0.25), value: targetIndex)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onTapGesture { onPick(index) }
                    .gesture(drag(stat))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("home-stat-\(index)")
                    .accessibilityHint("点一下选这张显示什么，按住拖动换位置")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .sensoryFeedback(.impact(weight: .light), trigger: lifts)
        .sensoryFeedback(.selection, trigger: targetIndex)
        // 手势被滚动或系统打断时也要放下
        .onChange(of: pressing) { _, isPressing in
            if !isPressing { drop() }
        }
    }

    /// 相邻两张卡之间的距离
    private var pitch: CGFloat {
        (rowWidth - Spacing.md * CGFloat(slots.count - 1)) / CGFloat(max(slots.count, 1)) + Spacing.md
    }

    /// 拖着的卡现在会落到第几格
    private var targetIndex: Int? {
        guard let dragging, let from = slots.firstIndex(of: dragging), pitch > 0 else { return nil }
        return min(max(from + Int((translation / pitch).rounded()), 0), slots.count - 1)
    }

    private func offset(of stat: HomeStat, at index: Int) -> CGFloat {
        guard let dragging, let from = slots.firstIndex(of: dragging), let to = targetIndex else { return 0 }
        if stat == dragging { return translation }
        if from < to, index > from, index <= to { return -pitch }
        if from > to, index >= to, index < from { return pitch }
        return 0
    }

    private func drag(_ stat: HomeStat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($pressing) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging == nil {
                    withAnimation(.snappy(duration: 0.2)) { dragging = stat }
                    lifts += 1
                    onDraggingChange(true)
                }
                translation = drag?.translation.width ?? 0
            }
            .onEnded { _ in drop() }
    }

    private func drop() {
        guard let dragging, let from = slots.firstIndex(of: dragging), let to = targetIndex else { return }
        withAnimation(.snappy(duration: 0.28)) {
            if from != to { onReorder(HomeStat.moving(slots, from: from, to: to)) }
            self.dragging = nil
            translation = 0
        }
        onDraggingChange(false)
    }
}

/// 一张小卡：细数字 / 短横线 / 小标签 / 一行小字
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
                Text(display.unit)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// 点一张卡后弹出的半屏：七个指标都画成小卡，带着现在的真实数字，点哪个就换成哪个
struct HomeStatPicker: View {
    /// 正在改第几张
    let index: Int
    let slots: [HomeStat]
    let inputs: HomeStat.Inputs
    let onSelect: (HomeStat) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                KickerLabel(text: "Card \(index + 1) of \(slots.count)")
                Text("这张卡显示什么")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Color.ink)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 3),
                      spacing: Spacing.md) {
                ForEach(HomeStat.allCases) { stat in
                    Button {
                        onSelect(stat)
                        dismiss()
                    } label: {
                        tile(stat)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("stat-option-\(stat.rawValue)")
                }
            }

            Text("在首页按住一张卡，可以左右拖动换位置")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.paper.ignoresSafeArea())
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func tile(_ stat: HomeStat) -> some View {
        let display = stat.display(inputs)
        let isCurrent = slots.indices.contains(index) && slots[index] == stat
        let elsewhere = slots.firstIndex(of: stat).flatMap { $0 == index ? nil : $0 }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(stat.title)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(isCurrent ? Color.skyDeep : Color.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if isCurrent {
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
            // 已经在另一张上的：选它就两张对调
            Text(elsewhere.map { "在第 \($0 + 1) 张 · 对调" } ?? display.unit)
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
                .stroke(isCurrent ? Color.skyDeep : Color.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
