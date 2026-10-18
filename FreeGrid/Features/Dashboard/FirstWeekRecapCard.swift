// 新用户记满 7 天那天在首页弹的「这一周的小结」（用户 2026-10-18 选的 N2）。
// 先是这一周每天花了多少、这周合计、日均和还能撑多久，日均和自由天数与首页同一份数字；
// Pro 只在最后一句，买过或开始过体验的人看不到这一句。
// 怎么弹看 IntroCardLayer，什么时候弹看 FirstWeekRecap 和 ContentView。

import SwiftUI

extension View {
    /// `recap` 不是 nil 时弹出，关掉后变回 nil。`onAppear`：真的出现在屏幕上时调用，用来记「弹过了」
    func firstWeekRecap(_ recap: Binding<FirstWeekRecap.Summary?>, onAppear: @escaping () -> Void) -> some View {
        let isPresented = Binding(get: { recap.wrappedValue != nil },
                                  set: { if !$0 { recap.wrappedValue = nil } })
        return introCard(isPresented: isPresented, onAppear: onAppear) { close, learnMore in
            if let summary = recap.wrappedValue {
                FirstWeekRecapCard(summary: summary, onClose: close, onLearnMore: learnMore)
            }
        }
    }
}

private struct FirstWeekRecapCard: View {
    let summary: FirstWeekRecap.Summary
    let onClose: () -> Void
    let onLearnMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                KickerLabel(text: "记满 \(FirstWeekRecap.requiredDays) 天 · \(rangeText)")
                Text("这一周的小结")
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
            }

            WeekBars(days: summary.days, totals: summary.dailyTotals)

            HStack(alignment: .top, spacing: 0) {
                stat(prefix: "¥", value: FinancialFormatting.wholeNumber(summary.total), label: "这周花了")
                divider
                stat(prefix: "¥", value: summary.dailyCost.isFinite ? String(format: "%.1f", summary.dailyCost) : "—",
                     label: "日均")
                if let freedom = freedomText {
                    divider
                    stat(value: freedom.value, suffix: freedom.unit, label: "还能撑")
                }
            }

            if summary.mentionsPro {
                Hairline(color: .hairlineSoft)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    IntroCardProTag()
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
                    Text("想用自己的分类记账，可以免费体验 \(ProOffer.trialDays) 天 Pro。")
                        .font(.system(.footnote, design: .rounded))
                        .lineSpacing(3)
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            IntroCardButtons(showsLearnMore: summary.mentionsPro, onClose: onClose, onLearnMore: onLearnMore)
        }
        // 先包成一个容器再给标识，不然标识会盖到里面每个按钮上
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("first-week-recap")
    }

    private var rangeText: String {
        let format = Date.FormatStyle().month(.defaultDigits).day(.defaultDigits)
        guard let first = summary.days.first, let last = summary.days.last else { return "" }
        return "\(first.formatted(format)) – \(last.formatted(format))"
    }

    /// 首页大数字和它的单位；还算不出来时不放这一格
    private var freedomText: (value: String, unit: String)? {
        switch summary.freedom {
        case .finite: return (FreedomMath.freedomDaysDisplay(summary.freedom), FreedomMath.gridUnit(for: summary.freedom).label)
        case .covered: return ("∞", "")
        case .insufficientData, .invalidData: return nil
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.hairlineSoft).frame(width: 1, height: 44).padding(.trailing, 14)
    }

    private func stat(prefix: String = "", value: String, suffix: String = "", label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if !prefix.isEmpty {
                    Text(prefix).font(.system(.caption, design: .rounded)).foregroundStyle(Color.inkMuted)
                }
                Text(value)
                    .font(.system(size: 26, weight: .thin, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !suffix.isEmpty {
                    Text(suffix).font(.system(.caption, design: .rounded)).foregroundStyle(Color.inkMuted)
                }
            }
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 这一周每天花了多少：7 根细柱，最高的那天顶满；没花钱的那天只剩底线
private struct WeekBars: View {
    let days: [Date]
    let totals: [Double]

    private let chartHeight: CGFloat = 88
    private static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        let peak = totals.max() ?? 0
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(days.indices, id: \.self) { index in
                    UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5, style: .continuous)
                        .fill(Color.sky)
                        .frame(maxWidth: 22)
                        .frame(height: barHeight(totals[index], peak: peak))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: chartHeight, alignment: .bottom)
            .overlay(alignment: .bottom) { Hairline() }
            HStack(spacing: 12) {
                ForEach(days.indices, id: \.self) { index in
                    Text(label(for: index))
                        .font(.kicker)
                        .foregroundStyle(index == days.count - 1 ? Color.inkMuted : Color.inkFaint)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("这一周每天的支出")
        .accessibilityValue(days.indices.map { "\(spokenLabel(for: $0)) \(FinancialFormatting.yuan(totals[$0]))" }
            .joined(separator: "，"))
    }

    private func barHeight(_ value: Double, peak: Double) -> CGFloat {
        guard peak > 0, value > 0 else { return 0 }
        return max(3, chartHeight * value / peak)
    }

    /// 最后一天是今天，写「今」
    private func label(for index: Int) -> String {
        if index == days.count - 1 { return "今" }
        return Self.weekdays[Calendar.current.component(.weekday, from: days[index]) - 1]
    }

    private func spokenLabel(for index: Int) -> String {
        index == days.count - 1 ? "今天" : "周\(label(for: index))"
    }
}
