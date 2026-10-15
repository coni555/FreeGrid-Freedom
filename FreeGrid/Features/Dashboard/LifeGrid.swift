// 把自由天数画成资产与现金格子，最后一格持续呼吸；还款日的格子中间打一个孔。

import SwiftUI

struct LifeGrid: View {
    let unit: FreedomMath.GridUnit
    let count: Int
    let assetCells: Int
    /// 还款日落在的格子（从 0 数），见 `GridState.paymentCells`
    var paymentCells: Set<Int> = []
    /// 钱撑不到下一次还款时，在最后一格后面补一个淡色带孔的格子
    var showsMissedPayment = false

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
                    let isCurrent = (i == count - 1)
                    let isCash = i >= assetCells
                    cell(isCurrent: isCurrent, isCash: isCash, isPayment: paymentCells.contains(i), breath: b)
                }
                if showsMissedPayment {
                    PunchedCell(cornerRadius: unit.cellSize * 0.11)
                        .fill(Color.inkGhost, style: FillStyle(eoFill: true))
                        .frame(width: unit.cellSize, height: unit.cellSize)
                        .accessibilityElement()
                        .accessibilityLabel("下一次还款，钱撑不到")
                        .accessibilityIdentifier("missed-repayment-cell")
                }
            }
        }
    }

    @ViewBuilder
    private func cell(isCurrent: Bool, isCash: Bool, isPayment: Bool, breath: CGFloat) -> some View {
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
        } else if isPayment {
            PunchedCell(cornerRadius: unit.cellSize * 0.11)
                .fill(baseColor, style: FillStyle(eoFill: true))
                .frame(width: unit.cellSize, height: unit.cellSize)
        } else {
            Rectangle()
                .fill(baseColor)
                .frame(width: unit.cellSize, height: unit.cellSize)
                .cornerRadius(unit.cellSize * 0.11)
        }
    }
}

/// 还款日的格子：正中挖一个圆孔，孔里透出卡片底色。是真的孔，不是描边；
/// 用 even-odd 填充，圆和方块重叠的部分不上色。图例里的小方块也用它。
struct PunchedCell: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius)
        let hole = min(rect.width, rect.height) * 0.34
        path.addEllipse(in: CGRect(x: rect.midX - hole / 2, y: rect.midY - hole / 2, width: hole, height: hole))
        return path
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
