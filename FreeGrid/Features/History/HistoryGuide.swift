// History 页的首次指引：压暗页面，逐步圈出要点的位置并说明。

import SwiftUI

/// 指引要圈出的位置。页面把这些位置的屏幕坐标报上来，遮罩据此开洞。
@MainActor
@Observable
final class HistoryGuide {
    enum Target: Hashable {
        case month, row, tools
    }

    struct Step: Equatable {
        let target: Target
        let text: String
        /// 这一步教的是左滑，圈内加一个向左移动的箭头
        var showsSwipe = false
    }

    static let steps: [Step] = [
        Step(target: .month, text: "点月份，跳到任意一个月。\n旁边的箭头可以前后翻月。"),
        Step(target: .row, text: "点一行，修改金额、分类、日期或备注。"),
        Step(target: .row, text: "向左滑一行，撤销这笔。", showsSwipe: true),
        Step(target: .tools, text: "这里搜索全部记录，\n或者按分类筛选。"),
    ]

    var frames: [Target: CGRect] = [:]
    /// nil 表示没有在指引
    var index: Int?

    /// 当前屏幕上找不到位置的步骤直接跳过，例如这个月还没有记录时没有「行」。
    var availableSteps: [Step] { Self.steps.filter { frames[$0.target] != nil } }

    var current: Step? {
        guard let index, availableSteps.indices.contains(index) else { return nil }
        return availableSteps[index]
    }

    func start() {
        if index == nil, !availableSteps.isEmpty { index = 0 }
    }

    /// 返回 true 表示指引已经走完
    func advance() -> Bool {
        guard let index else { return true }
        if index + 1 < availableSteps.count {
            self.index = index + 1
            return false
        }
        self.index = nil
        return true
    }

    func report(_ target: Target, _ frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        if frames[target] != frame { frames[target] = frame }
    }
}

extension View {
    /// 把这个视图在屏幕上的位置报给指引
    func historyGuideTarget(_ target: HistoryGuide.Target, in guide: HistoryGuide) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { guide.report(target, $0) }
    }
}

/// 盖在整个窗口上（包括导航栏和底部 Tab），所以挂在 ContentView 而不是 History 页内部。
struct HistoryGuideOverlay: View {
    let guide: HistoryGuide
    let onFinish: () -> Void

    @State private var swipeOffset: CGFloat = 0

    var body: some View {
        if let step = guide.current, let target = guide.frames[step.target] {
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                let hole = target
                    .offsetBy(dx: -origin.x, dy: -origin.y)
                    .insetBy(dx: -8, dy: -6)
                let total = guide.availableSteps.count
                let number = (guide.index ?? 0) + 1

                ZStack(alignment: .topLeading) {
                    // 压暗全屏，在目标位置开洞
                    Rectangle()
                        .fill(Color.black.opacity(0.55))
                        .overlay(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .frame(width: hole.width, height: hole.height)
                                .offset(x: hole.minX, y: hole.minY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                        .frame(width: hole.width, height: hole.height)
                        .offset(x: hole.minX, y: hole.minY)

                    if step.showsSwipe {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(Color.skyDeep)
                            .offset(x: hole.midX + 30 + swipeOffset, y: hole.midY - 10)
                            .onAppear {
                                swipeOffset = 0
                                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                                    swipeOffset = -90
                                }
                            }
                    }

                    bubble(step: step, number: number, total: total)
                        .frame(width: min(proxy.size.width - 2 * Spacing.xl, 320))
                        .position(bubbleCenter(hole: hole, in: proxy.size))
                }
                .contentShape(Rectangle())
                .onTapGesture { next() }
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func bubble(step: HistoryGuide.Step, number: Int, total: Int) -> some View {
        VaultCard(emphasis: .high, padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(step.text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("history-guide-text")
                HStack {
                    Text("\(number) / \(total)")
                        .font(.kicker)
                        .foregroundStyle(Color.inkFaint)
                    Spacer()
                    if number < total {
                        Button("跳过") { finish() }
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                            .buttonStyle(.plain)
                            .padding(.trailing, Spacing.md)
                            .accessibilityIdentifier("history-guide-skip")
                    }
                    Button { next() } label: {
                        Text(number < total ? "下一步" : "知道了")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.skyDeep)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, 6)
                            .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("history-guide-next")
                }
            }
        }
    }

    /// 说明放在目标下方；目标在屏幕下半部时放到上方
    private func bubbleCenter(hole: CGRect, in size: CGSize) -> CGPoint {
        let half: CGFloat = 70
        let below = hole.maxY + Spacing.lg + half
        let y = hole.midY < size.height / 2 ? below : hole.minY - Spacing.lg - half
        return CGPoint(x: size.width / 2, y: min(max(y, half + 60), size.height - half - 60))
    }

    private func next() {
        var done = false
        withAnimation(.easeInOut(duration: 0.25)) { done = guide.advance() }
        if done { onFinish() }
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.25)) { guide.index = nil }
        onFinish()
    }
}
