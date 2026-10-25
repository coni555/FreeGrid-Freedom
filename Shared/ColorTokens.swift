//
//  ColorTokens.swift
//  FreeGrid
//
//  颜色从 DesignSystem.swift 挪到这里，App 和桌面小组件共用同一套色值。
//  方向和取值说明见 DesignSystem.swift 开头。
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// ============================================================================
// MARK: - Dynamic color helper
// ============================================================================
// SwiftUI Color 没有原生 light/dark 双值 init,用 UIColor.dynamicProvider 桥接。
// 切换 .preferredColorScheme(.light/.dark) 时所有 dynamic color 自动 resolve。

extension Color {
    /// 直接用 RGB 三元组创建 dynamic (避免嵌套 Color)
    static func dyn(
        lightRGB: (Double, Double, Double),
        darkRGB: (Double, Double, Double)
    ) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let (r, g, b) = traits.userInterfaceStyle == .dark ? darkRGB : lightRGB
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            let (r, g, b) = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkRGB : lightRGB
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        })
        #endif
    }
}

// ============================================================================
// MARK: - Color tokens (light silverline / dark vault dual mode)
// ============================================================================

extension Color {

    // ===== Surface (light: 冷白银 / dark: 冷蓝紫黑 — 天文台气质) =====
    /// 主底
    /// light: 旧版背景近白(0.984)、卡片反而更灰(mist 0.957)→ 卡片像凹陷、层次弱。
    ///        反转为「柔和冷灰背景 + 纯白浮起卡片」(高级分组列表观感), 不靠阴影提供深度。
    ///        高强调卡(VaultCard .high)改走 surfaceHi 也保持纯白, 故 paper 现在纯粹是屏幕主底。
    static let paper = Color.dyn(
        lightRGB: (0.951, 0.953, 0.961),  // 冷银灰主底
        darkRGB:  (0.040, 0.045, 0.075)   // 深蓝紫黑 (oklch 0.08 0.015 250)
    )
    /// 卡片底
    static let mist = Color.dyn(
        lightRGB: (0.998, 0.999, 1.000),  // 纯白浮起卡片(在冷灰底上 pop)
        darkRGB:  (0.078, 0.085, 0.130)   // 蓝紫卡片 (oklch 0.13 0.018 250)
    )
    /// 嵌套深一档
    static let mist2 = Color.dyn(
        lightRGB: (0.935, 0.935, 0.943),
        darkRGB:  (0.110, 0.120, 0.175)   // 高亮蓝紫
    )
    /// hairline 主分隔
    static let hairline = Color.dyn(
        lightRGB: (0.870, 0.870, 0.882),
        darkRGB:  (0.215, 0.222, 0.280)   // 蓝紫灰 hairline
    )
    /// hairline 次级
    static let hairlineSoft = Color.dyn(
        lightRGB: (0.920, 0.920, 0.928),
        darkRGB:  (0.150, 0.158, 0.215)
    )

    // ===== Ink scale (light: 冷灰墨 / dark: 蓝白系) =====
    /// 主文字
    static let ink = Color.dyn(
        lightRGB: (0.145, 0.140, 0.155),
        darkRGB:  (0.940, 0.945, 0.960)   // 蓝白,带极微蓝调
    )
    /// 次级文字
    static let inkMuted = Color.dyn(
        lightRGB: (0.40, 0.395, 0.42),
        darkRGB:  (0.660, 0.680, 0.730)
    )
    /// 灰阶 (kicker/unit/caption)
    static let inkFaint = Color.dyn(
        lightRGB: (0.58, 0.575, 0.595),
        darkRGB:  (0.480, 0.495, 0.555)
    )
    /// 极弱
    static let inkGhost = Color.dyn(
        lightRGB: (0.74, 0.735, 0.755),
        darkRGB:  (0.310, 0.325, 0.380)
    )

    // ===== Sky: 主 accent (light/dark 都偏亮以 stand out) =====
    /// 主天空蓝
    static let sky = Color.dyn(
        lightRGB: (0.45, 0.72, 0.92),
        darkRGB:  (0.52, 0.78, 0.97)   // 暗底上稍亮一档
    )
    /// 深天空蓝 (强调字 / bar marker / italic accent)
    static let skyDeep = Color.dyn(
        lightRGB: (0.28, 0.52, 0.78),
        darkRGB:  (0.65, 0.85, 1.00)   // 暗底上反而要更亮才显眼
    )
    /// 极淡 sky wash (banner 底)
    static let skyFaint = Color.dyn(
        lightRGB: (0.93, 0.96, 0.99),
        darkRGB:  (0.12, 0.18, 0.26)
    )

    // ===== 业务语义色 =====
    /// 现金桶和现金格子使用蓝色
    static let cashBlue = Color.dyn(
        lightRGB: (0.45, 0.72, 0.92),
        darkRGB:  (0.52, 0.78, 0.97)
    )
    /// 资产桶和资产格子使用暖金
    /// light: 旧 (0.85,0.72,0.38) 是欠饱和 mustard, 在冷白底上发脏发弱、跟 sky 蓝不对等。
    ///        提到更饱和、略偏橙的琥珀金 —— gold 在白底需要饱和度才显贵, 不靠暗度。
    static let assetGold = Color.dyn(
        lightRGB: (0.90, 0.65, 0.22),
        darkRGB:  (0.92, 0.80, 0.45)
    )
    /// 支出朱砂
    static let flame = Color.dyn(
        lightRGB: (0.82, 0.40, 0.32),
        darkRGB:  (0.95, 0.55, 0.42)
    )
    /// 被动覆盖与达成状态使用绿色
    static let mossGreen = Color.dyn(
        lightRGB: (0.36, 0.62, 0.42),
        darkRGB:  (0.55, 0.82, 0.62)
    )

    /// 高强调卡填充(VaultCard .high)。light: 纯白(跟普通卡一致, 避免反转后高强调卡变灰);
    /// dark: 维持原 paper 暗值, 暗色高强调卡观感不变。
    static let surfaceHi = Color.dyn(
        lightRGB: (0.998, 0.999, 1.000),
        darkRGB:  (0.040, 0.045, 0.075)
    )

}
