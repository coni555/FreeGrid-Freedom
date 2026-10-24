// 首页主数字、可收起的 12 周趋势和两种布局。输入是同一份财务摘要。

import SwiftUI

struct DashboardHero: View {
    let history: [FreedomMath.HistoryPoint]
    let snapshot: FinancialSnapshot
    let isDarkMode: Bool
    let heroLayout: String
    let needsSavings: Bool
    /// 自由卡升级时的一行提示（只出现一次）；nil 时不显示
    var cardPrompt: (text: String, tier: FreedomCardTier)? = nil
    /// 打开自由卡：点提示，或者长按大数字（彩蛋，不写在界面上）
    var onOpenCard: () -> Void = {}
    @State private var longPressed = 0

    /// 趋势图展开还是收起, 记住用户上次的选择。收起后只剩一行摘要, 数字和格子挨得更近。
    @AppStorage("heroTrendExpanded") private var trendExpanded = true
    @Environment(AppGuide.self) private var guide

    /// Hero: Silverline 大胆版 — 巨大数字 + trend badge + sparkline + 见底日期
    /// 参考 V3/V5 mockup 设计:把 hero card 升级为"自由仪表盘"
    var body: some View {
        let delta = FreedomMath.deltaSummary(history: history)
        let deplete = FreedomMath.depleteDate(freedomDays: freedomDays)
        let showsTrend = history.count >= 3

        // 内联 VaultCard 写法 — 为了在 paper 底之上、content 之下叠暗色流星层。
        // 普通 VaultCard 的 background fill 是 opaque, 没法在外面再叠装饰层。
        return VStack(alignment: .leading, spacing: Spacing.md) {
            // ─── 顶部: kicker + trend badge ───
            // kicker 跟随档位切换 (Days/Months/Years),hero 数字裸数字,单位由 kicker + 副标双重承载
            HStack(alignment: .firstTextBaseline) {
                KickerLabel(text: heroKickerText)
                Spacer()
                if let d = delta {
                    // 下面的趋势行已经写了「69 天 → 27 天」, 有它时不再重复变化量
                    if !showsTrend {
                        trendBadge(delta: d.delta, weeks: history.count - 1)
                    }
                } else if history.last?.state == .covered {
                    Text("被动收入已覆盖开销")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.mossGreen)
                } else if history.first?.state == .covered,
                          case .finite = history.last?.state {
                    Text("被动收入不够覆盖了")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.flame)
                } else if case .finite = snapshot.freedom {
                    Text("按现在的收支估算")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.inkGhost)
                }
            }

            // ─── 中部: 根据 heroLayout 偏好切换 ───
            heroBody(deplete: deplete)
                .guideTarget(.number, in: guide)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.5) {
                    longPressed += 1
                    onOpenCard()
                }
                .sensoryFeedback(.impact(weight: .light), trigger: longPressed)
                .accessibilityAction(named: "打开自由卡") { onOpenCard() }

            if let cardPrompt {
                Button(action: onOpenCard) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(FreedomCardMaterial.of(cardPrompt.tier).background)
                            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).stroke(Color.hairline, lineWidth: 1))
                            .frame(width: 19, height: 12)
                        Text(cardPrompt.text)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        Text("看看")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.skyDeep)
                    }
                    .frame(maxWidth: .infinity, alignment: heroLayout == "vertical" ? .center : .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityIdentifier("freedom-card-prompt")
            }

            // ─── 底部: 趋势。一行摘要常驻, 点它展开或收起折线 ───
            if let first = history.first, let last = history.last, showsTrend {
                Hairline().padding(.top, Spacing.xs)
                trendSection(first: first, last: last)
            }

        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                // 浅色和其他卡一样是白卡；深色比其他卡深一档，衬出流星
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.surfaceHi)
                if isDarkMode {
                    MeteorLayer()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
    }

    /// Hero 中部 body: 按 heroLayout 偏好切换 2 个 variant
    /// - "leading": 副标 leading + 数字 trailing,baseline 对齐 (mockup hero-a 原意图)
    /// - "vertical": 数字独占一行居中 + 副标居中下方 (仪表盘 hero 风)
    @ViewBuilder
    private func heroBody(deplete: Date?) -> some View {
        if heroLayout == "vertical" {
            heroBodyVertical(deplete: deplete)
        } else {
            heroBodyLeading(deplete: deplete)
        }
    }

    /// 已覆盖时的小字。记账不满 90 天时日均还不稳（和大额摊开同一个门槛），写出按几天算的，让人自己掂量这句「财富自由」
    private var coveredNote: String {
        snapshot.trackDays < FreedomMath.lumpSpreadDays
            ? "按 \(snapshot.trackDays) 天记账估算，被动收入已覆盖开销"
            : "按目前的记账估算，被动收入已覆盖开销"
    }

    /// Variant A: 副标 leading + 数字 trailing,baseline 底部对齐
    /// 副标 18pt 拆 2 行 (card 内副标可用宽 ~121pt, 22pt 7 字会强行 break)
    @ViewBuilder
    private func heroBodyLeading(deplete: Date?) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                switch snapshot.freedom {
                case .covered:
                    emphasized("你已", "财富", "自由", size: 18)
                    Text(coveredNote)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.mossGreen)
                        .padding(.top, 4)
                case .insufficientData:
                    if needsSavings {
                        emphasized("先记下", "你有多少钱", "", size: 18)
                    } else {
                        emphasized("再记", "一笔支出", "", size: 18)
                    }
                    Text(needsSavings
                         ? "资产或现金都算，记完再记一笔支出"
                         : "再记一笔支出，就能算出自由天数")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.top, 4)
                case .invalidData:
                    emphasized("检查", "财务数据", "", size: 18)
                    Text("有一笔金额不对，去 History 找找特别大或负数的")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.flame)
                        .padding(.top, 4)
                case .finite:
                    emphasized("你的", "自由", "", size: 18)
                    Text("还能撑这么多\(heroSubUnit)")
                        .font(.system(size: 18, weight: .light, design: .rounded))
                        .foregroundStyle(Color.ink)
                    if let d = deplete {
                        Text("大约撑到 \(FreedomMath.depleteDateText(d))")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                            .padding(.top, 4)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Text(freedomDaysDisplay)
                .font(.system(size: 110, weight: .ultraLight, design: .rounded).monospacedDigit())
                .foregroundStyle(isFreedomCovered ? Color.mossGreen : Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .padding(.vertical, -8)
                .layoutPriority(0)
        }
    }

    /// Variant B: 数字独占居中 + 副标单行居中下方 + 见底 caption
    @ViewBuilder
    private func heroBodyVertical(deplete: Date?) -> some View {
        VStack(alignment: .center, spacing: Spacing.sm) {
            // 数字自带的行高上下留白很大，收紧一些，首屏才放得下记账按钮
            Text(freedomDaysDisplay)
                .font(.system(size: 110, weight: .ultraLight, design: .rounded).monospacedDigit())
                .foregroundStyle(isFreedomCovered ? Color.mossGreen : Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .padding(.vertical, -16)

            switch snapshot.freedom {
            case .covered:
                emphasized("你已", "财富", "自由", size: 18)
                Text(coveredNote)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.mossGreen)
                    .padding(.top, 2)
            case .insufficientData:
                if needsSavings {
                    emphasized("先记下", "你有多少钱", "", size: 18)
                } else {
                    emphasized("再记", "一笔支出", "", size: 18)
                }
                Text(needsSavings
                     ? "资产或现金都算，记完再记一笔支出"
                     : "再记一笔支出，就能算出自由天数")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .padding(.top, 2)
            case .invalidData:
                emphasized("检查", "财务数据", "", size: 18)
                Text("有一笔金额不对，去 History 找找特别大或负数的")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.flame)
                    .padding(.top, 2)
            case .finite:
                emphasized("你的", "自由", " 还能撑这么多\(heroSubUnit)", size: 18)
                if let d = deplete {
                    Text("大约撑到 \(FreedomMath.depleteDateText(d))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 摘要行是开关: 箭头朝下表示可以展开, 展开后转成朝上。
    /// 折线淡入淡出, 卡片高度和下面的内容跟着一起滑动, 不跳。
    @ViewBuilder
    private func trendSection(first: FreedomMath.HistoryPoint, last: FreedomMath.HistoryPoint) -> some View {
        // 有资产或现金不计入时少了一块往回推，早期会被压到 0；那个 0 不是算出来的，不写
        let summaryText = FreedomMath.trendSummaryText(first: first, last: last,
                                                       hidesFlooredStart: snapshot.hasUncountedMoney)
        Button {
            withAnimation(.snappy(duration: 0.32)) { trendExpanded.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(history.count - 1) 周自由趋势 · 估算")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                Spacer()
                Text(summaryText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
                    .rotationEffect(.degrees(trendExpanded ? 180 : 0))
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .guideTarget(.trend, in: guide)
        .accessibilityIdentifier("hero-trend-toggle")
        .accessibilityLabel(summaryText == last.description
                            ? "\(history.count - 1) 周自由趋势估算，现在 \(last.description)"
                            : "\(history.count - 1) 周自由趋势估算，\(first.description) 到 \(last.description)")
        .accessibilityValue(trendExpanded ? "已展开" : "已收起")
        .accessibilityHint(trendExpanded ? "收起折线" : "展开折线")

        if trendExpanded {
            // 趋势是按账目（和现在的被动收入）往回推的，标题里已写「估算」
            Group {
                if let values = FreedomMath.historyPlotValues(history) {
                    Sparkline(values: values)
                        .frame(height: 36)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }

    /// trend badge: ▲ +N d / Nw 或 ▼ -N d / Nw
    /// 增加用 skyDeep,减少用 flame
    private func trendBadge(delta: Int, weeks: Int) -> some View {
        let isUp = delta >= 0
        let color: Color = isUp ? .skyDeep : .flame
        let symbol = isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
        let sign = isUp ? "+" : ""
        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8))
            Text("\(sign)\(delta) d · \(weeks)w")
                .font(.system(.caption2, design: .monospaced))
                .tracking(0.3)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(color.opacity(0.10))
        )
    }

    /// 三联 stat 卡片:横向 3 个独立 VaultCard,各自有 padding 和描边
    /// 设计动机:工具 App 需要清晰的"信息卡片"层级,这里 3 个并列 stat
    private var freedomDays: Double {
        switch snapshot.freedom {
        case .finite(let days): return days
        case .covered: return .infinity
        case .insufficientData, .invalidData: return .nan
        }
    }

    private var isFreedomCovered: Bool {
        if case .covered = snapshot.freedom { return true }
        return false
    }

    /// 三档无后缀 hero 数字: 日整数 / 月整数 / 年1位小数 / ∞
    private var freedomDaysDisplay: String {
        FreedomMath.freedomDaysDisplay(snapshot.freedom)
    }

    private var heroSubUnit: String {
        FreedomMath.gridUnit(for: snapshot.freedom).label
    }

    private var heroKickerText: String {
        switch snapshot.freedom {
        case .covered: return "Freedom"
        case .insufficientData: return "Freedom Pending"
        case .invalidData: return "Data Check"
        case .finite:
            switch FreedomMath.gridUnit(for: snapshot.freedom) {
            case .day: return "Freedom Days"
            case .month: return "Freedom Months"
            case .year: return "Freedom Years"
            }
        }
    }
}
