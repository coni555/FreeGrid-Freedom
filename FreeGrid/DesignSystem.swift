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

// ============================================================================
// MARK: - Color (冷白银 + 天空蓝 accent)
// ============================================================================

extension Color {

    // ===== Paper scale (冷白系,带极微蓝灰 hue) =====
    /// 主底:冷白纸色 oklch(0.985 0.002 230)
    static let paper      = Color(red: 0.984, green: 0.984, blue: 0.987)
    /// 雾银:卡片底/嵌套区 oklch(0.965 0.003 230)
    static let mist       = Color(red: 0.957, green: 0.957, blue: 0.963)
    /// 雾银深一档:用于嵌套深一层
    static let mist2      = Color(red: 0.935, green: 0.935, blue: 0.943)
    /// hairline:1px 主分隔
    static let hairline   = Color(red: 0.870, green: 0.870, blue: 0.882)
    /// 更轻的 hairline,虚线用
    static let hairlineSoft = Color(red: 0.920, green: 0.920, blue: 0.928)

    // ===== Ink scale (冷灰墨) =====
    /// 主墨:接近黑但带冷调
    static let ink        = Color(red: 0.145, green: 0.140, blue: 0.155)
    /// 次级:副标 / 说明
    static let inkMuted   = Color(red: 0.40, green: 0.395, blue: 0.42)
    /// 灰阶:kicker / unit / caption
    static let inkFaint   = Color(red: 0.58, green: 0.575, blue: 0.595)
    /// 极弱:几乎隐形,装饰用
    static let inkGhost   = Color(red: 0.74, green: 0.735, blue: 0.755)

    // ===== Sky: 天空蓝,唯一 accent =====
    /// 主天空蓝:清亮、低饱和、清新 oklch(0.72 0.14 230)
    /// 用于 LifeGrid 活动格、品牌圆点、Tab 选中态
    static let sky        = Color(red: 0.45, green: 0.72, blue: 0.92)
    /// 深天空蓝:用于 italic accent、bar marker、文字强调
    static let skyDeep    = Color(red: 0.28, green: 0.52, blue: 0.78)
    /// 浅天空蓝:hover/secondary,wash
    static let skySoft    = Color(red: 0.78, green: 0.88, blue: 0.96)
    /// 极淡:背景 tint
    static let skyFaint   = Color(red: 0.93, green: 0.96, blue: 0.99)

    // ===== 业务语义色 =====
    /// LifeGrid 资产蓝 = 主天空蓝(语义合并)
    static let assetBlue  = Color(red: 0.45, green: 0.72, blue: 0.92)
    /// LifeGrid 收入金 → light silverline 里改用 light teal 配 cool 调
    /// 浅青绿 oklch(0.78 0.07 195)
    static let incomeGold = Color(red: 0.62, green: 0.82, blue: 0.84)
    /// 支出朱砂:仅 destructive 语义,light 版本 coral
    static let flame      = Color(red: 0.82, green: 0.40, blue: 0.32)
    /// 收入森绿:被动收入标签
    static let mossGreen  = Color(red: 0.36, green: 0.62, blue: 0.42)

    // ===== V2 alias (dark mode 时期 token,light 版本下重新指向) =====
    // 保留旧 token 名,值已翻转为 light silverline 等价物
    static let midnight   = Color.paper       // v2 暗背景 → v3 浅纸
    static let surface    = Color.mist        // v2 暗卡片 → v3 雾银
    static let surfaceHi  = Color.paper       // v2 高亮卡片 → v3 纯白(比 mist 亮)
    static let honey      = Color.ink         // v2 蜜金主 accent → v3 hero 数字用 ink 主墨(不彩色)
    static let honeyDim   = Color.inkMuted    // v2 蜜金 dim → v3 次级
    static let ink2       = Color.inkMuted    // v1 alias
    static let ink3       = Color.inkFaint    // v1 alias
    static let vermillion = Color.flame       // v1 alias
    static let forestGreen = Color.mossGreen  // v1 alias

    // hairline 旧名 (v1)
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
                    .fill(emphasis == .high ? Color.paper : Color.mist)
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
