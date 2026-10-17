// 设置页的「一叠卡」：自检卡在最前，后面每张藏在上一张背后，只露出下沿。
// 全页只有自由卡用材质（黑卡也是深色的，所以别的卡都不用深色）；其余卡是同一种纸，越往后底色深一档。

import SwiftUI

enum SettingsDeck {
    /// 后一张卡藏在前一张背后的高度
    static let tuck: CGFloat = 22
    static let radius: CGFloat = 22
    /// 每张卡露出来的卡头高度（大字号时跟着长）
    static let headerHeight: CGFloat = 52
    /// 都收着时，每张卡最多露出多高（屏幕高时铺开，像 Wallet）
    static let maxPeek: CGFloat = 92
    /// 露出这么高以上，卡头下面多写一行「里面有什么」
    static let detailPeek: CGFloat = 76

    /// 都收着时每张卡露出多高：把可视高度分给后面 5 张，夹在 52…92 之间。有一张抽出来时都是 52
    static func peek(viewport: CGFloat, cover: CGFloat, anyOpen: Bool) -> CGFloat {
        guard !anyOpen, viewport > 0, cover > 0 else { return headerHeight }
        return min(maxPeek, max(headerHeight, (viewport - cover - 64) / 5))
    }

    /// 抽出、收回：弹一下就停
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)

    /// 第 0…4 张纸的底色：越往后越深一档
    static func paper(_ depth: Int) -> Color {
        switch depth {
        case 0: return .dyn(lightRGB: (0.998, 0.999, 1.000), darkRGB: (0.090, 0.098, 0.149))
        case 1: return .dyn(lightRGB: (0.976, 0.980, 0.984), darkRGB: (0.078, 0.086, 0.133))
        case 2: return .dyn(lightRGB: (0.957, 0.961, 0.969), darkRGB: (0.067, 0.075, 0.118))
        case 3: return .dyn(lightRGB: (0.937, 0.941, 0.953), darkRGB: (0.059, 0.067, 0.102))
        default: return .dyn(lightRGB: (0.918, 0.922, 0.937), darkRGB: (0.051, 0.059, 0.090))
        }
    }

    /// 卡的细边：深色下比页面的 hairline 再暗一点，叠在一起不显得花
    static let edge = Color.dyn(lightRGB: (0.870, 0.870, 0.882), darkRGB: (0.173, 0.180, 0.235))
}

/// 一张卡：圆角、细边、朝下的影子；深色下顶边一道淡高光。
/// 不是第一张时，顶上 `tuck` 那一段藏在上一张背后，内容从它下面开始排。
struct DeckCard<Content: View>: View {
    var fill: AnyShapeStyle = AnyShapeStyle(SettingsDeck.paper(0))
    var edge: Color = SettingsDeck.edge
    var tucked = true
    /// 露在上一张下面的高度；内容不够高时卡本身撑到这么高（卡头在上，下面空着，像 Wallet）
    var peek: CGFloat = 0
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsDeck.radius, style: .continuous)
        content
            .frame(maxWidth: .infinity, minHeight: peek, alignment: .topLeading)
            .padding(.top, tucked ? SettingsDeck.tuck : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(shape.stroke(edge, lineWidth: 1))
            .overlay(
                shape.stroke(LinearGradient(colors: [.white.opacity(colorScheme == .dark ? 0.08 : 0), .clear],
                                            startPoint: .top, endPoint: .center), lineWidth: 1)
            )
            .shadow(color: colorScheme == .dark ? .black.opacity(0.55) : Color(red: 0.08, green: 0.09, blue: 0.16).opacity(0.08),
                    radius: 9, y: 6)
    }
}

/// 卡头：左边标题，右边一个读数，能展开的卡最右边一个向下的小箭头（展开时转过来）
struct DeckHeader<Leading: View, Trailing: View>: View {
    let title: String
    var titleColor: Color = .ink
    /// 卡头下面一行「里面有什么」，卡叠铺开时才写
    var detail: String?
    /// nil：这张卡不展开（点了跳走），不画箭头
    var isOpen: Bool?
    var chevronColor: Color = .inkGhost
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.sm) {
                    leading
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(titleColor)
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(titleColor.opacity(0.5))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: Spacing.sm)
            trailing
            if let isOpen {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(chevronColor)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: SettingsDeck.headerHeight)
        .contentShape(Rectangle())
    }
}

/// 卡头右边的读数：SF Pro Light 数字 + 等宽小单位（圆体 Thin 在这个字号下发飘，用户 2026-10-17 选了 SF Pro）
struct DeckReading: View {
    let value: String
    var unit: String?
    var color: Color = .ink
    var unitColor: Color = .inkFaint

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 21, weight: .light).monospacedDigit())
                .foregroundStyle(color)
            if let unit {
                Text(unit)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(unitColor)
            }
        }
    }
}

/// 外观卡头上的主题记号：和首页左上角那个切换按钮同一个样子，浅色是细圈里一颗蓝点，深色是月亮
struct ThemeGlyph: View {
    let isDark: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ink, lineWidth: 1)
                .frame(width: 20, height: 20)
            if isDark {
                Image(systemName: "moon.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.sky)
            } else {
                Circle()
                    .fill(Color.sky)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(isDark ? "现在是深色" : "现在是浅色")
    }
}

/// 卡里展开的一行：标题、右边的值、›。行高 48，直接铺在卡面上
struct DeckRow<Trailing: View>: View {
    let title: String
    var titleColor: Color = .ink
    var chevron: String? = "chevron.right"
    var chevronColor: Color = .inkGhost
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(titleColor)
            Spacer(minLength: Spacing.sm)
            trailing
            if let chevron {
                Image(systemName: chevron)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(chevronColor)
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

/// 卡里行与行之间的细线，左边缩进和文字对齐
struct DeckDivider: View {
    var color: Color = SettingsDeck.edge

    var body: some View {
        Rectangle().fill(color).frame(height: 1).padding(.leading, 20)
    }
}
