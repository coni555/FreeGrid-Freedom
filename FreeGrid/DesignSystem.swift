//
//  DesignSystem.swift
//  FreeGrid
//
//  方向 v2: 静谧金库 / Calm Vault · Native iOS
//  - 暗色暖底(深棕,带温度)代替纯黑/冷灰
//  - 唯一主 accent = 蜜金 (honey gold),"自由的颜色"
//  - 拥抱 iOS 26 Liquid Glass / ultraThinMaterial
//  - SF Pro Rounded 大数字,product feel 而非 editorial feel
//

import SwiftUI

// ============================================================================
// MARK: - Color (暗色暖底 + 蜜金主色 + 语义色)
// ============================================================================

extension Color {

    // ===== 背景与表面 (暗色暖底,带 hue,不是死黑) =====
    /// 主背景:深暖棕,接近 oklch(0.135 0.012 60)
    static let midnight   = Color(red: 0.090, green: 0.075, blue: 0.062)
    /// 卡片表面:比 midnight 亮一档,做"浮起"基底
    static let surface    = Color(red: 0.140, green: 0.120, blue: 0.100)
    /// 高层表面:更亮一档,active/important card
    static let surfaceHi  = Color(red: 0.180, green: 0.155, blue: 0.128)
    /// hairline:浅白半透,在暗底上做 subtle 描边
    static let hairline   = Color(white: 1.0).opacity(0.08)

    // ===== 文字 (暖白系) =====
    /// 主文字:暖白,绝不刺眼,带 hue 跟背景呼应
    static let ink        = Color(red: 0.965, green: 0.945, blue: 0.910)
    /// 次级:用于副标/说明
    static let inkMuted   = Color(red: 0.965, green: 0.945, blue: 0.910).opacity(0.62)
    /// 极弱:kicker / unit / caption
    static let inkFaint   = Color(red: 0.965, green: 0.945, blue: 0.910).opacity(0.38)

    // ===== Honey: 主 accent,"自由的颜色" =====
    /// 蜜金:饱和暖黄,在暗底上发光感强。所有 hero/active/primary action 都吃这一色
    static let honey      = Color(red: 0.990, green: 0.780, blue: 0.380)
    /// honey 的 muted 版本,用于次级强调
    static let honeyDim   = Color(red: 0.990, green: 0.780, blue: 0.380).opacity(0.55)

    // ===== 业务语义色 (饱和版,暗底友好) =====
    /// 资产蓝:LifeGrid 蓝格,饱和+略偏 cyan,在暗底上跳得出
    static let assetBlue  = Color(red: 0.45, green: 0.78, blue: 1.00)
    /// 收入金:LifeGrid 金格——和 honey 主色统一,语义"收入即自由"
    static let incomeGold = Color(red: 0.990, green: 0.780, blue: 0.380)
    /// 支出朱砂:暖红,落日色,跟蜜金构成"日落"色温对
    static let flame      = Color(red: 1.00, green: 0.48, blue: 0.30)
    /// 收入绿:深森绿,只在需要明确"成功"语义时用(被动收入标签)
    static let mossGreen  = Color(red: 0.50, green: 0.85, blue: 0.58)

    // ===== V1 alias (年鉴风 token,渐进迁移用) =====
    // 这些是 v1 时期的命名,现在指向 v2 的暗色等价物
    // 等所有 ContentView 改完后可移除
    static let paper      = Color.midnight
    static let paper2     = Color.surface
    static let rule       = Color.hairline
    static let ruleSoft   = Color.hairline
    static let ink2       = Color.inkMuted
    static let ink3       = Color.inkFaint
    static let vermillion = Color.flame
    static let forestGreen = Color.mossGreen
}

// ============================================================================
// MARK: - 字体 helper
// ============================================================================
// SF Pro Rounded 是 iOS 系统字体,适合产品工具 + 数字 feel。
// 中文自动 fallback PingFang SC,字重映射合理。

extension Font {
    /// Hero 自由天数:96pt rounded bold,占半屏
    static func heroNumber(_ size: CGFloat = 96) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    /// 中等数字:Assets hero / 三联指标 用
    static func bigNumber(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    /// 三联指标内部数字
    static func statNumber(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .medium, design: .rounded).monospacedDigit()
    }

    /// kicker / label:mono uppercase,tracking 1.5
    static let kicker = Font.system(.caption, design: .monospaced).weight(.medium)

    /// 副标 body
    static let bodyRounded = Font.system(.body, design: .rounded)

    // ===== V1 Font alias =====
    static func mediumNumber(_ size: CGFloat = 28) -> Font { bigNumber(size) }
    static let monoKicker = kicker
}

// ============================================================================
// MARK: - 共用组件
// ============================================================================

/// kicker 标签:uppercase mono,tracking 1.5,默认 inkFaint
/// 替代旧版的 § + uppercase 组合,更"工具"feel
struct KickerLabel: View {
    let text: String
    var color: Color = .inkFaint

    var body: some View {
        Text(text.uppercased())
            .font(.kicker)
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

/// hairline 横线(暗底上的 subtle 分隔)
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// 卡片容器:暗底上的浮层
/// 设计动机: 使用 .ultraThinMaterial + 自定义底色 surface,模拟 iOS 26 Liquid Glass
/// emphasis = .high 用 surfaceHi,适合 hero
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
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(emphasis == .high ? Color.surfaceHi : Color.surface)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                }
            )
    }
}

/// 主操作按钮 (filled rounded, prominent)
/// emphasis = .primary 用 honey 主色,.secondary 用 surfaceHi 描边
struct VaultButton: View {
    enum Style { case primary, secondary, destructive }
    let title: String
    var icon: String? = nil
    var style: Style = .primary
    let action: () -> Void

    private var bg: Color {
        switch style {
        case .primary: return .honey
        case .secondary: return .surfaceHi
        case .destructive: return .flame
        }
    }
    private var fg: Color {
        switch style {
        case .primary: return Color(red: 0.18, green: 0.12, blue: 0.04)  // 暗棕字配蜜金底
        case .secondary: return .ink
        case .destructive: return Color(red: 0.20, green: 0.06, blue: 0.04)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(fg)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(bg)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Ghost button (次级动作,模拟决策用)
/// 透明底 + hairline 描边 + ink 字
struct GhostButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(Color.inkMuted)
            .background(
                Capsule().stroke(Color.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// ============================================================================
// MARK: - V1 组件 alias (年鉴风遗留,逐步替换)
// ============================================================================

/// V1 SectionMark → 现在 forward 到 KickerLabel (不再有 § 段落符)
struct SectionMark: View {
    let text: String
    var color: Color = .inkFaint
    var body: some View {
        KickerLabel(text: text, color: color)
    }
}

/// V1 ChapterRule → 简化为 hairline,不再有 § 浮起
struct ChapterRule: View {
    var body: some View { Hairline() }
}

/// V1 PillButton → forward 到 VaultButton
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

/// V1 UnderlineLink → forward 到 GhostButton
struct UnderlineLink: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        GhostButton(title: title, icon: icon, action: action)
    }
}

/// V1 emphasized() → 暗色版,关键词改用 honey 而非朱砂
func emphasized(_ prefix: String, _ word: String, _ suffix: String,
                size: CGFloat = 17) -> Text {
    Text(prefix)
        .font(.system(size: size, design: .rounded))
        .foregroundColor(.inkMuted)
    + Text(word)
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .foregroundColor(.honey)
    + Text(suffix)
        .font(.system(size: size, design: .rounded))
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
