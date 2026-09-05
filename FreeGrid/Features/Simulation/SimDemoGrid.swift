// 模拟收支的格子点亮/熄灭动画。

import SwiftUI

/// 演示三态:静止(旧态)/ 播放中 / 落定(新态)
enum SimDemoPhase: Equatable {
    case idle
    case playing(Date)
    case done
}

/// 计时:级联窗口 span(所有格子起跑时刻铺开的区间)+ 单格 envelope 时长 cellDur。
/// span 随 delta 增大而拉长并 cap,避免大 delta 拖沓。
/// 方向区分:点亮(收入)刻意放慢 —— 增格是"赚回自由"的奖励时刻,逐格慢点更有满足感;
/// 熄灭(支出)保持利落。grid 渲染和 sheet 落定计时器共用这一份,保证 totalDur 一致。
func simDemoTiming(delta: Int, ignite: Bool) -> (span: Double, cellDur: Double, total: Double) {
    if ignite {
        let cellDur = 0.72
        let span = min(3.0, max(0.5, 0.18 * Double(delta)))
        return (span, cellDur, span + cellDur)
    } else {
        let cellDur = 0.55
        let span = min(1.6, max(0.25, 0.10 * Double(delta)))
        return (span, cellDur, span + cellDur)
    }
}

struct SimDemoGrid: View {
    let unit: FreedomMath.GridUnit
    let oldCount: Int
    let newCount: Int
    /// 资产格数（金色）：分别保存旧态和新态，后面的格子属于现金（蓝色）。
    let oldAssetCells: Int
    let newAssetCells: Int
    let phase: SimDemoPhase


    private var total: Int { max(oldCount, newCount) }
    private var delta: Int { abs(newCount - oldCount) }
    private var isIgnite: Bool { newCount > oldCount }

    var body: some View {
        Group {
            switch phase {
            case .idle:
                gridFrame(elapsed: -1)            // 停在旧态
            case .done:
                gridFrame(elapsed: 9999)          // 停在新态
            case .playing(let start):
                TimelineView(.animation) { ctx in
                    gridFrame(elapsed: ctx.date.timeIntervalSince(start))
                }
            }
        }
    }

    @ViewBuilder
    private func gridFrame(elapsed: Double) -> some View {
        let timing = simDemoTiming(delta: delta, ignite: isIgnite)
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: unit.cellSize, maximum: unit.cellSize),
                               spacing: unit.spacing)],
            spacing: unit.spacing
        ) {
            ForEach(0..<total, id: \.self) { i in
                cell(index: i, elapsed: elapsed, timing: timing)
            }
        }
    }

    /// 单格:稳定区直接满亮;过渡区按 envelope 点燃/熄灭。
    @ViewBuilder
    private func cell(index i: Int, elapsed: Double,
                      timing: (span: Double, cellDur: Double, total: Double)) -> some View {
        let stableCount = min(oldCount, newCount)

        if i < stableCount {
            // 稳定区:始终满亮,用新态配色
            // 与首页一致：前段资产为金色，后段现金为蓝色。
            litCell(base: i < newAssetCells ? .assetGold : .cashBlue, opacity: 1, scale: 1, glow: 0, glowColor: .clear)
        } else {
            // 过渡区:计算该格在级联里的顺序 k → 本地进度 lt ∈ [0,1]
            let k: Int = isIgnite ? (i - oldCount) : (oldCount - 1 - i)
            let startK = delta <= 1 ? 0 : (Double(k) / Double(delta - 1)) * timing.span
            let lt = min(1, max(0, (elapsed - startK) / timing.cellDur))

            if isIgnite {
                let base: Color = i < newAssetCells ? .assetGold : .cashBlue
                let e = envelope(lt, attack: 0.12, release: 1.4)
                let opacity = 0.14 + 0.86 * easeOut(min(1, lt / 0.30))
                litCell(base: base, opacity: opacity, scale: 1 + 0.20 * e,
                        glow: e * 0.9, glowColor: base)
            } else {
                let base: Color = i < oldAssetCells ? .assetGold : .cashBlue
                let e = envelope(lt, attack: 0.16, release: 1.4)
                let opacity = 1 - 0.86 * easeOut(min(1, lt / 0.55))
                // 熄灭用 flame 焰光 —— 贴合 App "支出 = 朱砂" 语义
                litCell(base: base, opacity: opacity, scale: 1 + 0.12 * e,
                        glow: e * 0.8, glowColor: .flame)
            }
        }
    }

    private func litCell(base: Color, opacity: Double, scale: CGFloat,
                         glow: Double, glowColor: Color) -> some View {
        Rectangle()
            .fill(base.opacity(opacity))
            .frame(width: unit.cellSize, height: unit.cellSize)
            .cornerRadius(unit.cellSize * 0.13)
            .shadow(color: glowColor.opacity(glow * 0.9),
                    radius: unit.cellSize * 0.8 * glow)
            .scaleEffect(scale)
            .zIndex(glow > 0.01 ? 1 : 0)
    }

    // ===== envelope helpers(移植 早期 web 版 _eoq / _env)=====

    /// ease-out quart:1-(1-t)^4,收尾绵软
    private func easeOut(_ t: Double) -> Double {
        let c = min(1, max(0, t))
        return 1 - pow(1 - c, 4)
    }

    /// attack-release 包络:t<attack 缓入到 1,之后按 release 指数衰减回 0。
    /// 给辉光/缩放脉冲用 —— 点亮瞬间鼓一下再落定。
    private func envelope(_ t: Double, attack: Double, release: Double) -> Double {
        if t >= 1 { return 0 }
        if t < attack { return easeOut(t / attack) }
        return pow(1 - (t - attack) / (1 - attack), release)
    }
}
