//
//  DesignSystem.swift
//  FreeGrid
//
//  纸面/年鉴风设计语言 token 与共用组件。
//  参考: lixiaolai.com 全站(Newsreader + 朱砂 + § + hairline + OKLCH 双纸)。
//  iOS 没有 OKLCH，用最接近的 sRGB 近似；OKLCH 的"叠纸"过渡用 .opacity 模拟。
//

import SwiftUI

// ============================================================================
// MARK: - Color (纸/墨/朱砂 + 资产/收入语义色)
// ============================================================================

extension Color {

    // ===== Paper scale: 暖白纸，往下叠一档做嵌套背景 =====
    /// 主底纸色：oklch(0.985 0.001 250) 的 sRGB 近似
    static let paper    = Color(red: 0.984, green: 0.980, blue: 0.972)
    /// 嵌套区域纸色：oklch(0.965 0.002 250) 的近似，仅在需要"浮起"时用
    static let paper2   = Color(red: 0.957, green: 0.952, blue: 0.940)

    // ===== Rule: 1px hairline 分隔，纯排印的"高级感"基础 =====
    /// 主分隔线
    static let rule     = Color(red: 0.83, green: 0.82, blue: 0.80)
    /// 更轻的分隔，用于 dashed inner rule
    static let ruleSoft = Color(red: 0.91, green: 0.90, blue: 0.88)

    // ===== Ink scale: 三档字色 =====
    /// 主墨色，正文与大标题
    static let ink      = Color(red: 0.16, green: 0.14, blue: 0.12)
    /// 次级，副标 / 状态描述
    static let ink2     = Color(red: 0.40, green: 0.38, blue: 0.34)
    /// 灰阶，元信息 / kicker / unit
    static let ink3     = Color(red: 0.58, green: 0.56, blue: 0.52)

    // ===== Vermillion: 朱砂，全站唯一强调色 =====
    /// 命名"朱砂"，实际偏深红棕，避免 RGB 红色的廉价感
    static let vermillion = Color(red: 0.62, green: 0.28, blue: 0.18)

    /// 森林绿:用于收入/positive 语义，比 SwiftUI .green 暗一档以适配纸面
    static let forestGreen = Color(red: 0.30, green: 0.46, blue: 0.32)

    // ===== 业务语义色 =====
    /// 资产蓝：哑光、接近油画蓝，不抢戏
    static let assetBlue  = Color(red: 0.39, green: 0.52, blue: 0.69)
    /// 收入金：哑光、接近黄铜
    static let incomeGold = Color(red: 0.78, green: 0.62, blue: 0.32)
}

// ============================================================================
// MARK: - 字体 helper
// ============================================================================
// SwiftUI 在 iOS 17+ 把 .system(design: .serif) 映射到 "New York"，
// 气质接近 Newsreader（transitional serif），中文自动 fallback PingFang SC。
// 不引第三方字体，省 bundle 体积。

extension Font {
    /// Hero 数字：超大、轻、衬线。配合 monospacedDigit 防"84"两位字符宽度跳动
    static func heroNumber(_ size: CGFloat = 72) -> Font {
        .system(size: size, weight: .light, design: .serif).monospacedDigit()
    }

    /// 中等衬线数字：三联指标 / Assets hero 等
    static func mediumNumber(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .light, design: .serif).monospacedDigit()
    }

    /// § / mono kicker：所有"机械感"小标签
    static let monoKicker = Font.system(.caption2, design: .monospaced)

    /// 衬线副标 italic（"continue where you left off" 那种）
    static func serifItalic(_ size: CGFloat = 17) -> Font {
        .custom("", size: size).italic()
            .weight(.light)
    }
}

// ============================================================================
// MARK: - 共用组件
// ============================================================================

/// § 段落符 + uppercase mono 标签
/// 例: § FREEDOM DAYS
///
/// 设计要点：
/// - § 用 mono，tracking 0；标签用 mono uppercase + tracking 0.12em
/// - 颜色统一 ink3（灰阶），不抢主标题/数字的戏
struct SectionMark: View {
    let text: String
    var color: Color = .ink3

    var body: some View {
        HStack(spacing: 6) {
            Text("§")
                .font(.monoKicker)
            Text(text.uppercased())
                .font(.monoKicker)
                .tracking(2.0)
        }
        .foregroundStyle(color)
    }
}

/// hairline 横线（1px，rule 色）
/// 在 SwiftUI 里 frame(height: 1) 在 @2x/@3x 屏幕会渲染成 0.5pt 的视觉宽度——这是要的效果
struct Hairline: View {
    var color: Color = .rule

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// 章节分隔：横线 + 中间浮一个 § 符号
/// 模拟 colophon-card 的 .co-rule：1px hairline + § 浮起遮住线
/// 设计动机：比单纯 hairline 多一份"卷首/章节起点"的语义
struct ChapterRule: View {
    var body: some View {
        ZStack {
            Hairline()
            Text("§")
                .font(.monoKicker)
                .foregroundStyle(Color.ink3)
                .padding(.horizontal, 8)
                .background(Color.paper)
        }
    }
}

/// hairline 描边胶囊按钮（btn-pill 风格）
/// 设计动机：替代实心糖果色按钮，气质和正文 hairline 一致
/// emphasis = .primary 时用实心 ink 底 + paper 字（submit 风格）
struct PillButton: View {
    enum Emphasis { case primary, secondary }
    let title: String
    var icon: String? = nil
    var emphasis: Emphasis = .secondary
    var tint: Color = .ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .regular))
                }
                Text(title)
                    .font(.system(.subheadline, design: .serif))
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(emphasis == .primary ? Color.paper : tint)
            .background(
                ZStack {
                    Capsule().fill(emphasis == .primary ? tint : Color.clear)
                    Capsule().stroke(tint, lineWidth: 1)
                }
            )
        }
        .buttonStyle(.plain)
    }
}

/// 文字 link 按钮（下划线 + ink3 → ink hover）
/// 用于"模拟一笔"这种次级动作——比胶囊更克制
struct UnderlineLink: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.system(.subheadline, design: .serif))
                    .italic()
                    .underline(true, color: Color.ink3)
                Image(systemName: "arrow.right")
                    .font(.caption2)
            }
            .foregroundStyle(Color.ink2)
        }
        .buttonStyle(.plain)
    }
}

/// 单字 italic 强调的辅助构造器
/// 用法：emphasized("你的自由还能 ", "撑", " 多久")
/// "撑" 会用 italic + 朱砂 + light，反 bold 直觉的"贵气"招式
func emphasized(_ prefix: String, _ word: String, _ suffix: String,
                size: CGFloat = 17) -> Text {
    Text(prefix)
        .font(.system(size: size, design: .serif))
        .foregroundColor(.ink2)
    + Text(word)
        .font(.system(size: size, weight: .light, design: .serif).italic())
        .foregroundColor(.vermillion)
    + Text(suffix)
        .font(.system(size: size, design: .serif))
        .foregroundColor(.ink2)
}

// ============================================================================
// MARK: - 间距 token（按需引用，不强制全用）
// ============================================================================

enum Spacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
}
