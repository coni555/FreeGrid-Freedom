// 把自由天数画成资产与现金格子；最后是一格正在消耗的「水位格」，持续呼吸。

import SwiftUI

struct LifeGrid: View {
    let unit: FreedomMath.GridUnit
    let count: Int
    let assetCells: Int
    /// 整格之后不足一格的部分 (0 ..< 1)。大于 0 时多画一格描边的水位格: 每记一笔支出水位就降一点,
    /// 降到底整格熄灭。没有它, 一笔不到一天花销的支出在首页上什么都不会变。
    var partial: Double = 0
    /// 水位格跟最后一段的颜色: 有现金格时是蓝, 全是资产时是金
    var partialIsCash: Bool = true

    private var showsPartial: Bool { partial >= 0.02 }

    @Environment(\.colorScheme) private var scheme

    /// 呼吸周期 (秒) — 2s 一来一回, 跟之前 .easeInOut(duration: 2.0) 行为一致
    private static let breathPeriod: TimeInterval = 2.0

    /// 从墙钟相位反算 breath ∈ [0, 1], 余弦形, 自然缓入缓出。
    /// 原 @State + onAppear + withAnimation(...).repeatForever() 在 iOS 17/18+
    /// 有 view-lifecycle 边界冻结的 regression, 改用 TimelineView(.animation)
    /// 函数式驱动 — 视图可见时刷帧, 不可见时系统自动暂停, 不存 @State, 不掉。
    private func breath(at date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        let phase = t.truncatingRemainder(dividingBy: Self.breathPeriod) / Self.breathPeriod
        // 0 → 1 → 0 余弦曲线 (半周期内从 0 上到 1, 下半周期再下到 0)
        return CGFloat(0.5 - 0.5 * cos(phase * 2 * .pi))
    }

    var body: some View {
        TimelineView(.animation) { context in
            let b = breath(at: context.date)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: unit.cellSize, maximum: unit.cellSize),
                                   spacing: unit.spacing)],
                spacing: unit.spacing
            ) {
                ForEach(0..<count, id: \.self) { i in
                    // 有水位格时它才是「正在过的这一天」, 整格都不呼吸
                    let isCurrent = !showsPartial && (i == count - 1)
                    let isCash = i >= assetCells
                    cell(isCurrent: isCurrent, isCash: isCash, breath: b)
                }
                if showsPartial {
                    waterCell(breath: b)
                }
            }
        }
    }

    /// 描边方框 + 从底部往上的填充; 比普通格大一点, 9pt 里的水位差才看得清
    private func waterCell(breath: CGFloat) -> some View {
        let isDark = scheme == .dark
        let color: Color = isDark
            ? (partialIsCash
                ? Color(red: 0.83, green: 0.92, blue: 1.00)
                : Color(red: 1.00, green: 0.92, blue: 0.65))
            : (partialIsCash
                ? Color(red: 0.20, green: 0.50, blue: 0.78)
                : Color(red: 0.72, green: 0.58, blue: 0.20))
        let size = unit.cellSize
        let radius = size * 0.17
        let glow = (isDark ? 0.35 : 0.22) + 0.12 * Double(breath)
        return ZStack(alignment: .bottom) {
            Rectangle()
                .fill(color)
                .frame(width: size, height: max(1, size * CGFloat(partial)))
                .animation(.easeInOut(duration: 0.6), value: partial)
        }
        .frame(width: size, height: size, alignment: .bottom)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(color, lineWidth: 1)
        )
        .shadow(color: color.opacity(glow), radius: 4 + 3 * breath)
        .scaleEffect(1.45)
        .zIndex(1)
        .accessibilityLabel("正在消耗的一格，还剩 \(Int((partial * 100).rounded()))%")
    }

    @ViewBuilder
    private func cell(isCurrent: Bool, isCash: Bool, breath: CGFloat) -> some View {
        let baseColor: Color = isCash ? .cashBlue : .assetGold
        let isDark = scheme == .dark

        let currentColor: Color = isDark
            ? (isCash
                ? Color(red: 0.83, green: 0.92, blue: 1.00)
                : Color(red: 1.00, green: 0.92, blue: 0.65))
            : (isCash
                ? Color(red: 0.20, green: 0.50, blue: 0.78)
                : Color(red: 0.72, green: 0.58, blue: 0.20))

        let innerGlowColor: Color = isDark
            ? Color.white
            : (isCash
                ? Color(red: 0.15, green: 0.35, blue: 0.55)
                : Color(red: 0.55, green: 0.45, blue: 0.15))

        let innerOpacity: Double = isDark
            ? (0.5 + 0.3 * Double(breath))
            : (0.25 + 0.15 * Double(breath))
        let outerOpacity: Double = isDark
            ? (0.4 + 0.1 * Double(breath))
            : (0.30 + 0.10 * Double(breath))

        let peak: CGFloat = isDark ? 1.6 : 1.35
        let currentScale: CGFloat = 1.1 + (peak - 1.1) * breath
        let innerGlow: CGFloat = 4 + 3 * breath
        let outerGlow: CGFloat = 9 + 6 * breath

        if isCurrent {
            Rectangle()
                .fill(currentColor)
                .frame(width: unit.cellSize, height: unit.cellSize)
                .cornerRadius(unit.cellSize * 0.17)
                .shadow(color: innerGlowColor.opacity(innerOpacity), radius: innerGlow)
                .shadow(color: baseColor.opacity(outerOpacity), radius: outerGlow)
                .scaleEffect(currentScale)
                .zIndex(1)
        } else {
            Rectangle()
                .fill(baseColor)
                .frame(width: unit.cellSize, height: unit.cellSize)
                .cornerRadius(unit.cellSize * 0.11)
        }
    }
}

// 网格尺寸属于显示规则，财务算法只决定档位与格子数量。
extension FreedomMath.GridUnit {
    /// 每格视觉尺寸 (pt)
    var cellSize: CGFloat {
        switch self {
        case .day: return 9
        case .month: return 12
        case .year: return 16
        }
    }

    /// 格子间距 (pt) — 跟随 cellSize 比例
    var spacing: CGFloat {
        switch self {
        case .day: return 2.5
        case .month: return 3
        case .year: return 3.5
        }
    }

}
