// 首页主数字、趋势和两种布局。输入是同一份财务摘要。

import SwiftUI

struct DashboardHero: View {
    let expenses: [Expense]
    let incomes: [Income]
    let snapshot: FinancialSnapshot
    let isDarkMode: Bool
    let heroLayout: String
    let needsSavings: Bool

    /// Hero: Silverline 大胆版 — 巨大数字 + trend badge + sparkline + 见底日期
    /// 参考 V3/V5 mockup 设计:把 hero card 升级为"自由仪表盘"
    var body: some View {
        let history = FreedomMath.freedomDaysHistory(
            expenses: expenses,
            incomes: incomes,
            currentNetWorth: snapshot.netWorth,
            firstRecordDate: snapshot.firstExpenseDate,
            dailyPassive: snapshot.dailyPassive
        )
        let delta = FreedomMath.deltaSummary(history: history)
        let deplete = FreedomMath.depleteDate(freedomDays: freedomDays)

        // 内联 VaultCard 写法 — 为了在 paper 底之上、content 之下叠暗色流星层。
        // 普通 VaultCard 的 background fill 是 opaque, 没法在外面再叠装饰层。
        return VStack(alignment: .leading, spacing: Spacing.md) {
            // ─── 顶部: kicker + trend badge ───
            // kicker 跟随档位切换 (Days/Months/Years),hero 数字裸数字,单位由 kicker + 副标双重承载
            HStack(alignment: .firstTextBaseline) {
                KickerLabel(text: heroKickerText)
                Spacer()
                if let d = delta {
                    trendBadge(delta: d.delta, weeks: history.count - 1)
                } else {
                    Text("(资产 + 净储蓄) ÷ 日均消费")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.inkGhost)
                }
            }

            // ─── 中部: 根据 heroLayout 偏好切换 ───
            heroBody(deplete: deplete)

            // ─── 底部: 趋势 caption + sparkline ───
            if let d = delta, history.count >= 3 {
                Hairline().padding(.top, Spacing.xs)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(history.count - 1) 周以来的自由天数")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    Spacer()
                    Text("\(d.start) → \(d.end)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.ink)
                }
                Sparkline(values: history.map { $0.freedomDays })
                    .frame(height: 36)
                    .padding(.top, 2)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.paper)
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

    /// Variant A: 副标 leading + 数字 trailing,baseline 底部对齐
    /// 副标 18pt 拆 2 行 (card 内副标可用宽 ~121pt, 22pt 7 字会强行 break)
    @ViewBuilder
    private func heroBodyLeading(deplete: Date?) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                switch snapshot.freedom {
                case .covered:
                    emphasized("你已", "财富", "自由", size: 18)
                    Text("按当前日均消费, 被动已覆盖")
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
                         : "建立日均消费后开始计算自由天数")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.top, 4)
                case .invalidData:
                    emphasized("检查", "财务数据", "", size: 18)
                    Text("存在无法计算的金额, 请检查记录")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.flame)
                        .padding(.top, 4)
                case .finite:
                    emphasized("你的", "自由", "", size: 18)
                    Text("还能撑这么多\(heroSubUnit)")
                        .font(.system(size: 18, weight: .light, design: .rounded))
                        .foregroundStyle(Color.ink)
                    if let d = deplete {
                        Text("约 \(depleteDateString(d)) 见底")
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
            Text(freedomDaysDisplay)
                .font(.system(size: 110, weight: .ultraLight, design: .rounded).monospacedDigit())
                .foregroundStyle(isFreedomCovered ? Color.mossGreen : Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .padding(.vertical, -8)

            switch snapshot.freedom {
            case .covered:
                emphasized("你已", "财富", "自由", size: 18)
                Text("按当前日均消费, 被动已覆盖")
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
                     : "建立日均消费后开始计算自由天数")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .padding(.top, 2)
            case .invalidData:
                emphasized("检查", "财务数据", "", size: 18)
                Text("存在无法计算的金额, 请检查记录")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.flame)
                    .padding(.top, 2)
            case .finite:
                emphasized("你的", "自由", " 还能撑这么多\(heroSubUnit)", size: 18)
                if let d = deplete {
                    Text("约 \(depleteDateString(d)) 见底")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
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

    /// 格式化"约 X 月 X 日"
    private func depleteDateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        return f.string(from: d)
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
