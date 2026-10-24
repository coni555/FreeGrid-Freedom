// 自由卡的卡面和竖版海报。卡是一件「实物」：材质随等级变，不跟深浅色变；
// 海报的底色跟着 App 当前的深浅色。所有尺寸按卡宽的百分比算，App 里和导出成图一模一样。

import SwiftUI

// MARK: - 材质

/// 每种卡的颜色。卡本身不跟深浅色变，只在深色背景上多一圈亮边（见 `FreedomCardView`）
struct FreedomCardMaterial {
    let background: AnyShapeStyle
    let ink: Color
    let muted: Color
    let line: Color
    let cellA: Color
    let cellB: Color
    let cellOpacity: Double
    /// 卡面下半部分盖住格子的那层底色，让字读得清
    let veil: Color
    let sheen: Double
    let accent: Color
    /// 浅色的卡（深色背景上要一圈高光才看得出轮廓）
    var isLight = true

    static func of(_ tier: FreedomCardTier) -> FreedomCardMaterial {
        switch tier {
        case .paper:
            return .init(background: AnyShapeStyle(LinearGradient(colors: [.hex(0xFBFBFC), .hex(0xE9EAEE)],
                                                                    startPoint: .topLeading, endPoint: .bottomTrailing)),
                         ink: .hex(0x26252A), muted: .hex(0x8A8990), line: .black.opacity(0.09),
                         cellA: .hex(0xE6A638), cellB: .hex(0x73B8EB), cellOpacity: 0.18,
                         veil: .hex(0xF1F2F4), sheen: 0.5, accent: .hex(0x9A9AA3))
        case .silver:
            return .init(background: AnyShapeStyle(LinearGradient(stops: [
                            .init(color: .hex(0xF4F6F9), location: 0), .init(color: .hex(0xCFD4DC), location: 0.45),
                            .init(color: .hex(0xEEF1F5), location: 0.7), .init(color: .hex(0xB9BFC9), location: 1)],
                                                                    startPoint: .topLeading, endPoint: .bottomTrailing)),
                         ink: .hex(0x1F2328), muted: .hex(0x5D636D), line: .hex(0x1E232D).opacity(0.16),
                         cellA: .hex(0x6C737F), cellB: .hex(0x3F4652), cellOpacity: 0.14,
                         veil: .hex(0xDFE3E9), sheen: 0.75, accent: .hex(0x73B8EB))
        case .champagne:
            return .init(background: AnyShapeStyle(LinearGradient(stops: [
                            .init(color: .hex(0xF5F1EA), location: 0), .init(color: .hex(0xE6DCCB), location: 0.36),
                            .init(color: .hex(0xF8F4EE), location: 0.6), .init(color: .hex(0xD5C6AC), location: 1)],
                                                                    startPoint: .topLeading, endPoint: .bottomTrailing)),
                         ink: .hex(0x2A2620), muted: .hex(0x81766A), line: .hex(0x463723).opacity(0.13),
                         cellA: .hex(0xA38C6B), cellB: .hex(0x7D7262), cellOpacity: 0.13,
                         veil: .hex(0xECE4D6), sheen: 0.7, accent: .hex(0xC2A67A))
        case .obsidian:
            return .init(background: AnyShapeStyle(RadialGradient(colors: [.hex(0x2A2D3A), .hex(0x121420), .hex(0x07080E)],
                                                                    center: UnitPoint(x: 0.8, y: 0), startRadius: 0, endRadius: 520)),
                         ink: .hex(0xF2F0EA), muted: .hex(0x9C9AA5), line: .white.opacity(0.12),
                         cellA: .hex(0xEBCC73), cellB: .hex(0x85C7F7), cellOpacity: 0.22,
                         veil: .hex(0x0A0B13), sheen: 0.35, accent: .hex(0x8CD19E), isLight: false)
        case .infinite:
            return .init(background: AnyShapeStyle(AngularGradient(colors: [.hex(0x0B1020), .hex(0x1B2A4A), .hex(0x2C1F45),
                                                                              .hex(0x10203A), .hex(0x0B1020)],
                                                                     center: UnitPoint(x: 0.7, y: 0.3))),
                         ink: .white, muted: .hex(0xB7BED4), line: .white.opacity(0.16),
                         cellA: .hex(0xEBCC73), cellB: .hex(0x85C7F7), cellOpacity: 0.45,
                         veil: .hex(0x0B1020).opacity(0.75), sheen: 0.5, accent: .hex(0xEBCC73), isLight: false)
        }
    }
}

extension Color {
    /// 0xRRGGBB
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - 卡面

/// 一张信用卡比例（85.6 × 54）的卡。`tilt` 是 -1…1 的倾斜量：App 里跟着手机晃，导出时是 0
struct FreedomCardView: View {
    let data: FreedomCardData
    let holder: String
    var tilt: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    private static let columns = 34
    private static let rows = 22

    var body: some View {
        let material = FreedomCardMaterial.of(data.tier)
        GeometryReader { geo in
            let u = geo.size.width / 100   // 1u = 卡宽的 1%
            ZStack {
                RoundedRectangle(cornerRadius: 5.2 * u, style: .continuous).fill(material.background)
                cells(material, u: u)
                LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: material.veil, location: 0.78)],
                               startPoint: .top, endPoint: .bottom)
                RoundedRectangle(cornerRadius: 3.6 * u, style: .continuous)
                    .stroke(material.line, lineWidth: 1)
                    .padding(2.4 * u)
                content(material, u: u)
                    .padding(.horizontal, 7 * u)
                    .padding(.vertical, 6.5 * u)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // 一道斜着走的光：倾斜手机时跟着移动。放在 overlay 里，比卡宽也不会把卡撑大
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.38),
                                       .init(color: .white.opacity(material.sheen), location: 0.48),
                                       .init(color: .clear, location: 0.58)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 1.8)
                    .rotationEffect(.degrees(15))
                    .offset(x: (tilt.width - 0.3) * geo.size.width * 0.6)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5.2 * u, style: .continuous))
            .overlay(
                // 深色背景上：浅色卡加一圈淡高光，深色卡加一圈亮边，轮廓才清楚
                RoundedRectangle(cornerRadius: 5.2 * u, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(material.isLight ? 0.18 : 0.14)
                                                 : Color.black.opacity(material.isLight ? 0.08 : 0.25), lineWidth: 1)
            )
        }
        .aspectRatio(85.6 / 54, contentMode: .fit)
        .rotation3DEffect(.degrees(Double(tilt.width) * 9), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(Double(-tilt.height) * 7), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(data.tier.name)，自由天数 \(data.daysText) 天，持卡人 \(holder.isEmpty ? String(localized: "未填") : holder)")
        .accessibilityIdentifier("freedom-card")
    }

    /// 卡面铺满的小格子：前面按天数亮成金 / 蓝（资产 / 现金），后面不画
    private func cells(_ material: FreedomCardMaterial, u: CGFloat) -> some View {
        Canvas { context, size in
            let gap = 1.6 * u
            let inset = 5 * u
            let side = (size.width - inset * 2 - gap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
            let total = Self.columns * Self.rows
            let lit = data.litCells(of: total)
            let gold = Int((Double(lit) * data.assetShare).rounded())
            for index in 0..<lit {
                let row = index / Self.columns, column = index % Self.columns
                let rect = CGRect(x: inset + CGFloat(column) * (side + gap), y: inset + CGFloat(row) * (side + gap),
                                  width: side, height: side)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.35 * u),
                             with: .color((index < gold ? material.cellA : material.cellB).opacity(material.cellOpacity)))
            }
        }
        .allowsHitTesting(false)
    }

    private func content(_ material: FreedomCardMaterial, u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                HStack(spacing: 2.4 * u) {
                    // 2×2 的小格子：FreeGrid 的记号
                    VStack(spacing: 0.8 * u) {
                        HStack(spacing: 0.8 * u) { mark(material.ink.opacity(0.9), u); mark(.hex(0xE6A638), u) }
                        HStack(spacing: 0.8 * u) { mark(.hex(0x73B8EB), u); mark(material.ink.opacity(0.9), u) }
                    }
                    VStack(alignment: .leading, spacing: 0.4 * u) {
                        Text("FREEGRID")
                            .font(.system(size: 3.6 * u, weight: .semibold))
                            .tracking(1.3 * u)
                            .foregroundStyle(material.ink)
                        Text("FREEDOM CARD")
                            .font(.system(size: 2 * u, design: .monospaced))
                            .tracking(0.6 * u)
                            .foregroundStyle(material.muted)
                    }
                }
                Spacer()
                HStack(spacing: 1.4 * u) {
                    Circle().fill(material.accent).frame(width: 1.6 * u, height: 1.6 * u)
                        .shadow(color: material.accent, radius: u)
                    Text(data.tier.label)
                        .font(.system(size: 2.2 * u, design: .monospaced))
                        .tracking(0.5 * u)
                        .foregroundStyle(material.muted)
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1.8 * u) {
                    Text("FREEDOM DAYS · 自由天数")
                        .font(.system(size: 2 * u, design: .monospaced))
                        .tracking(0.5 * u)
                        .foregroundStyle(material.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 1.2 * u) {
                        Text(data.daysText)
                            .font(.system(size: 19 * u, weight: .ultraLight, design: .rounded).monospacedDigit())
                            .foregroundStyle(material.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if case .finite = data.freedom {
                            Text("天")
                                .font(.system(size: 4.2 * u, weight: .light, design: .rounded))
                                .foregroundStyle(material.muted)
                        }
                    }
                }
                Spacer(minLength: 2 * u)
                VStack(alignment: .trailing, spacing: 0.6 * u) {
                    Text("HOLDER")
                        .font(.system(size: 1.9 * u, design: .monospaced))
                        .tracking(0.5 * u)
                        .foregroundStyle(material.muted)
                    Text(holder.isEmpty ? "—" : holder)
                        .font(.system(size: 4.4 * u, weight: .light, design: .rounded))
                        .foregroundStyle(material.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }

            Rectangle().fill(material.line).frame(height: 1).padding(.top, 4.5 * u)

            HStack(alignment: .top) {
                stat("TRACKED", data.trackDays.formatted(.number), unit: "D", material, u)
                Spacer(minLength: 0)
                stat("PASSIVE", FinancialFormatting.percentage(data.passiveRatio), unit: nil, material, u)
                Spacer(minLength: 0)
                stat("MILESTONES", "\(data.milestonesDone)/\(data.milestonesTotal)", unit: nil, material, u)
                Spacer(minLength: 0)
                stat("SINCE", data.since.map(Self.sinceText) ?? "—", unit: nil, material, u)
            }
            .padding(.top, 3 * u)
        }
    }

    private func mark(_ color: Color, _ u: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 0.5 * u, style: .continuous).fill(color).frame(width: 2.8 * u, height: 2.8 * u)
    }

    private func stat(_ title: String, _ value: String, unit: String?, _ material: FreedomCardMaterial,
                      _ u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0.8 * u) {
            Text(title)
                .font(.system(size: 1.8 * u, design: .monospaced))
                .tracking(0.4 * u)
                .foregroundStyle(material.muted)
            HStack(alignment: .firstTextBaseline, spacing: 0.4 * u) {
                Text(value)
                    .font(.system(size: 3.4 * u, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(material.ink)
                if let unit {
                    Text(unit)
                        .font(.system(size: 2.1 * u, design: .rounded))
                        .foregroundStyle(material.muted)
                }
            }
        }
    }

    /// 「2026.06」
    static func sinceText(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%d.%02d", parts.year ?? 0, parts.month ?? 0)
    }
}

// MARK: - 竖版海报

/// 9:16 的海报：一句话 + 卡 + 「App Store 搜 FreeGrid」。底色跟着 App 当前的深浅色
struct FreedomPosterView: View {
    let data: FreedomCardData
    let holder: String

    var body: some View {
        GeometryReader { geo in
            let u = geo.size.width / 100
            ZStack {
                Color.paper
                // 底下铺一层很淡的格子，和首页同一种东西
                Canvas { context, size in
                    let columns = 18, gap = 1.2 * u, inset = 4 * u
                    let side = (size.width - inset * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)
                    let rows = Int((size.height - inset * 2) / (side + gap))
                    for index in 0..<(rows * columns) {
                        let rect = CGRect(x: inset + CGFloat(index % columns) * (side + gap),
                                          y: inset + CGFloat(index / columns) * (side + gap), width: side, height: side)
                        context.fill(Path(roundedRect: rect, cornerRadius: 0.6 * u),
                                     with: .color((index % 3 == 0 ? Color.cashBlue : Color.assetGold).opacity(0.1)))
                    }
                }
                VStack(spacing: 8 * u) {
                    Spacer()
                    Text(data.posterLine)
                        .font(.system(size: 7.4 * u, weight: .light, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineSpacing(1.6 * u)
                        .foregroundStyle(Color.ink)
                    FreedomCardView(data: data, holder: holder)
                        .padding(.horizontal, 7 * u)
                        .shadow(color: .black.opacity(0.18), radius: 6 * u, y: 3 * u)
                    Spacer()
                    Text("FREEGRID · APP STORE 搜 FREEGRID")
                        .font(.system(size: 2.8 * u, design: .monospaced))
                        .tracking(0.8 * u)
                        .foregroundStyle(Color.inkFaint)
                        .padding(.bottom, 8 * u)
                }
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
    }
}
