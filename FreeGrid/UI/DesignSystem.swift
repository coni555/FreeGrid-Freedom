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
//  颜色 token 在 Shared/ColorTokens.swift：App 和桌面小组件共用
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// ============================================================================
// MARK: - 字体 helper
// ============================================================================
// 用 SF Pro Rounded thin 取代 v3 mockup 的 Geist——iOS 没有 Geist,
// SF Pro 是 system font,weight 100 ultraLight 视觉接近 Geist 100。
// 中文自动 fallback PingFang SC,thin 字重映射合理。

extension Font {
    /// kicker / label:mono uppercase tracking
    static let kicker = Font.system(.caption2, design: .monospaced).weight(.regular)

}

// ============================================================================
// MARK: - 共用组件
// ============================================================================

/// kicker 标签:uppercase mono tracking,默认 inkFaint
/// 主题偏好：老的 `isDarkMode` 仍记着固定时选的浅色或深色，另用一个开关记「跟随系统」，
/// 这样老用户升级后外观不变。存在 `AppPreferences.store`：UI 测试里是临时偏好、默认不跟随，`-isDarkMode` 启动参数照常有效
enum AppTheme {
    static let followsSystemKey = "themeFollowsSystem"
}

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
/// 表单输入框的统一样子: 没有底色和外框, 只在下面压一条细线; 聚焦时细线换成强调色。
/// 和卡片的 1 像素描边是同一种语言, 不再用带底色的圆角盒子。
struct UnderlinedField<Content: View>: View {
    var isFocused: Bool
    var accent: Color = .skyDeep
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Spacing.sm) {
            content
            Rectangle()
                .fill(isFocused ? accent : Color.hairline)
                .frame(height: 1)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
    }
}

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
/// .high 使用 surfaceHi，.normal 使用 mist；每个颜色都适配深浅主题。
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
/// 全部使用描边：primary 蓝色，secondary 墨色，destructive 支出红。
struct VaultButton: View {
    enum Style { case primary, secondary, destructive }
    let title: String
    var icon: String? = nil
    var style: Style = .primary
    /// 上下留白。购买页底栏放得东西多，用矮一点的 11
    var verticalPadding: CGFloat = 14
    let action: () -> Void

    private var fg: Color {
        switch style {
        case .primary: return .skyDeep   // 深天空蓝字 (跟 flame destructive 对称)
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
            .padding(.vertical, verticalPadding)
            .foregroundStyle(fg)
            .overlay(
                Capsule().stroke(fg, lineWidth: 1)
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

/// emphasized():一句话里用 *…* 标出强调的词，强调词用衬线斜体和 sky-deep 深天空蓝，其余是圆体灰字。
/// 整句是一条可翻译的文字（「你已*财富*自由」/「You're *financially* free」），各语言自己决定强调词放哪。
func emphasized(_ sentence: LocalizedStringResource, size: CGFloat = 17) -> Text {
    var text = AppLanguage.attributed(sentence)
    for run in text.runs {
        let isWord = run.inlinePresentationIntent?.contains(.emphasized) == true
        text[run.range].font = isWord
            ? .system(size: size, weight: .regular, design: .serif).italic()
            : .system(size: size, weight: .regular, design: .rounded)
        text[run.range].foregroundColor = isWord ? .skyDeep : .inkMuted
    }
    return Text(text)
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
