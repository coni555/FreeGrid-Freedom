//
//  DesignSystem.swift
//  FreeGrid
//
//  方向 v3: Silverline · Swiss-tech Light Minimal
//  - 冷白底 + 雾银低饱和(蓝灰 hue)
//  - 唯一 accent = 天空蓝 (sky blue)
//  - hairline 描边 + 大量留白替代色块填充
//  - SF Pro Rounded thin 大数字,克制不发光
//
//  与 v2 暗色金库的对应:colors 翻转(dark→light), 但 layout 结构(VaultCard 堆叠)保留
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
    /// 创建一个根据 colorScheme 自动切换的 Color
    static func dyn(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #endif
    }

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
    /// 浅 sky soft
    static let skySoft = Color.dyn(
        lightRGB: (0.78, 0.88, 0.96),
        darkRGB:  (0.28, 0.40, 0.55)
    )
    /// 极淡 sky wash (banner 底)
    static let skyFaint = Color.dyn(
        lightRGB: (0.93, 0.96, 0.99),
        darkRGB:  (0.12, 0.18, 0.26)
    )

    // ===== 业务语义色 =====
    /// LifeGrid 资产蓝 = 主天空蓝
    static let assetBlue = Color.dyn(
        lightRGB: (0.45, 0.72, 0.92),
        darkRGB:  (0.52, 0.78, 0.97)
    )
    /// LifeGrid 现金色:暖金
    /// light: 旧 (0.85,0.72,0.38) 是欠饱和 mustard, 在冷白底上发脏发弱、跟 sky 蓝不对等。
    ///        提到更饱和、略偏橙的琥珀金 —— gold 在白底需要饱和度才显贵, 不靠暗度。
    static let incomeGold = Color.dyn(
        lightRGB: (0.90, 0.65, 0.22),
        darkRGB:  (0.92, 0.80, 0.45)
    )
    /// 支出朱砂
    static let flame = Color.dyn(
        lightRGB: (0.82, 0.40, 0.32),
        darkRGB:  (0.95, 0.55, 0.42)
    )
    /// 收入森绿 (被动标签)
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

    // ===== V1/V2 alias =====
    static let midnight   = Color.paper
    static let surface    = Color.mist
    static let honey      = Color.ink
    static let honeyDim   = Color.inkMuted
    static let ink2       = Color.inkMuted
    static let ink3       = Color.inkFaint
    static let vermillion = Color.flame
    static let forestGreen = Color.mossGreen
    static let rule       = Color.hairline
    static let ruleSoft   = Color.hairlineSoft
    static let paper2     = Color.mist
}

// ============================================================================
// MARK: - 字体 helper
// ============================================================================
// 用 SF Pro Rounded thin 取代 v3 mockup 的 Geist——iOS 没有 Geist,
// SF Pro 是 system font,weight 100 ultraLight 视觉接近 Geist 100。
// 中文自动 fallback PingFang SC,thin 字重映射合理。

extension Font {
    /// Hero 自由天数:96pt rounded ultraLight,跟 mockup Geist 100 视觉等价
    static func heroNumber(_ size: CGFloat = 96) -> Font {
        .system(size: size, weight: .ultraLight, design: .rounded).monospacedDigit()
    }

    /// 中等数字:stats 用,32pt thin
    static func bigNumber(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .thin, design: .rounded).monospacedDigit()
    }

    /// 三联指标内部数字
    static func statNumber(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .thin, design: .rounded).monospacedDigit()
    }

    /// kicker / label:mono uppercase tracking
    static let kicker = Font.system(.caption2, design: .monospaced).weight(.regular)

    /// 副标 body rounded
    static let bodyRounded = Font.system(.body, design: .rounded)

    // ===== V1/V2 alias =====
    static func mediumNumber(_ size: CGFloat = 28) -> Font { bigNumber(size) }
    static let monoKicker = kicker
}

// ============================================================================
// MARK: - 共用组件
// ============================================================================

/// kicker 标签:uppercase mono tracking,默认 inkFaint
struct KickerLabel: View {
    let text: String
    var color: Color = .inkFaint

    var body: some View {
        Text(text.uppercased())
            .font(.kicker)
            .tracking(1.8)
            .foregroundStyle(color)
    }
}

/// hairline 横线
struct Hairline: View {
    var color: Color = .hairline
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// 卡片容器:Silverline 风
/// emphasis = .high 用 paper 纯白(更亮一档);.normal 用 mist 雾银
/// 设计动机:hairline 描边为主,无阴影,极简
struct VaultCard<Content: View>: View {
    enum Emphasis { case normal, high }
    var emphasis: Emphasis = .normal
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(emphasis == .high ? Color.surfaceHi : Color.mist)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
    }
}

/// 主操作按钮 — hairline 描边 pill 风
/// .primary = 实心 ink 底 paper 字
/// .secondary = 透明 + ink 描边
/// .destructive = 透明 + flame 描边 + flame 字
struct VaultButton: View {
    enum Style { case primary, secondary, destructive }
    let title: String
    var icon: String? = nil
    var style: Style = .primary
    let action: () -> Void

    private var bg: Color {
        // 所有 style 都不填色,统一 outline 风
        return .clear
    }
    private var fg: Color {
        switch style {
        case .primary: return .skyDeep   // 深天空蓝字 (跟 flame destructive 对称)
        case .secondary: return .ink
        case .destructive: return .flame
        }
    }
    private var stroke: Color {
        switch style {
        case .primary: return .skyDeep   // 深天空蓝描边
        case .secondary: return .ink
        case .destructive: return .flame
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                }
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(fg)
            .background(
                Capsule().fill(bg)
            )
            .overlay(
                Capsule().stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Ghost 按钮:underline 文字 link 风
struct GhostButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .regular))
                }
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(Color.inkFaint)
            .overlay(
                Rectangle()
                    .fill(Color.hairlineSoft)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity, alignment: .bottom),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }
}

// ============================================================================
// MARK: - V1 组件 alias (年鉴风 + 暗色金库时期遗留)
// ============================================================================

struct SectionMark: View {
    let text: String
    var color: Color = .inkFaint
    var body: some View {
        KickerLabel(text: text, color: color)
    }
}

struct ChapterRule: View {
    var body: some View { Hairline() }
}

struct PillButton: View {
    enum Emphasis { case primary, secondary }
    let title: String
    var icon: String? = nil
    var emphasis: Emphasis = .secondary
    var tint: Color = .ink
    let action: () -> Void

    var body: some View {
        let style: VaultButton.Style = (tint == .flame || tint == .vermillion) ? .destructive : .primary
        VaultButton(title: title, icon: icon, style: style, action: action)
    }
}

struct UnderlineLink: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        GhostButton(title: title, icon: icon, action: action)
    }
}

/// emphasized():单字 italic 强调
/// light silverline 版本:用 sky-deep 深天空蓝代替 honey/vermillion
/// 配合 .italic 用类衬线感强调(SF 没 italic serif,但 .italic() + tracking 微调可以)
func emphasized(_ prefix: String, _ word: String, _ suffix: String,
                size: CGFloat = 17) -> Text {
    Text(prefix)
        .font(.system(size: size, weight: .regular, design: .rounded))
        .foregroundColor(.inkMuted)
    + Text(word)
        .font(.system(size: size, weight: .regular, design: .serif).italic())
        .foregroundColor(.skyDeep)
    + Text(suffix)
        .font(.system(size: size, weight: .regular, design: .rounded))
        .foregroundColor(.inkMuted)
}

// ============================================================================
// MARK: - 间距 token
// ============================================================================

enum Spacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// ============================================================================
// MARK: - Sparkline (折线图组件)
// ============================================================================
// 设计动机:hero card 底部展示过去 12 周自由天数走势。
// silverline 风:1pt skyDeep stroke,无填充,无 axes,无 grid。
// 最后一个 point 放一个小圆点强调"现在"。

struct Sparkline: View {
    /// y 值数组,index 0 = 最老,index n-1 = 最新
    let values: [Double]
    /// 画线颜色
    var stroke: Color = .skyDeep
    /// 终点圆点颜色
    var endDot: Color = .skyDeep
    /// 线宽
    var lineWidth: CGFloat = 1.2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts = points(in: CGSize(width: w, height: h))

            ZStack {
                // 折线
                if pts.count >= 2 {
                    Path { path in
                        path.move(to: pts[0])
                        for p in pts.dropFirst() {
                            path.addLine(to: p)
                        }
                    }
                    .stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
                // 终点小圆
                if let last = pts.last {
                    Circle()
                        .fill(endDot)
                        .frame(width: 5, height: 5)
                        .position(x: last.x, y: last.y)
                }
            }
        }
    }

    /// 把 values 映射到 view 坐标点
    private func points(in size: CGSize) -> [CGPoint] {
        let safeValues = values
            .filter { $0.isFinite && $0 >= 0 }
            .map { min($0, 365.25 * 99) }
        guard !safeValues.isEmpty else { return [] }
        let minV = safeValues.min() ?? 0
        let maxV = safeValues.max() ?? 1
        let range = max(maxV - minV, 1)   // 避免除零
        let stepX = safeValues.count > 1 ? size.width / CGFloat(safeValues.count - 1) : 0
        let pad: CGFloat = 4              // 上下留 4pt 让线不贴边

        return safeValues.enumerated().map { (i, v) in
            let x = CGFloat(i) * stepX
            let normalized = (v - minV) / range    // 0...1
            let y = size.height - pad - CGFloat(normalized) * (size.height - 2 * pad)
            return CGPoint(x: x, y: y)
        }
    }
}
