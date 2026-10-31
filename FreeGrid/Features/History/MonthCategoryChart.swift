// 月度汇总里点开一个月看到的支出构成：柱状图和扇形图二选一。选哪种记在偏好里，所有月份一起换。
// 分几份、怎么合并在 Logic/HistoryLedger.swift 的 shares。

import SwiftUI
import Charts

struct MonthCategoryChart: View {
    enum Style: String {
        case bars, pie
    }

    let breakdown: HistoryLedger.Breakdown
    /// 扇形图里每一份的颜色（调色板的第几个）：由月度汇总按所有月份统一分好，同一分类每个月同色
    var colorSlots: [HistoryLedger.Share.Kind: Int] = [:]

    @AppStorage("monthlyChartStyle", store: AppPreferences.store) private var style = Style.bars
    /// 扇形图上点中的一份；再点一下取消
    @State private var selected: HistoryLedger.Share.Kind?
    @State private var angle: Double?

    /// 扇形图的调色板：和现金蓝、资产金同样的明度和饱和度，深色模式各提亮一点。
    /// 十个颜色，默认九类加固定支出都不撞色；相邻两个色相拉开，列表里挨着的分类不会像
    static let palette: [Color] = [
        .cashBlue,
        .dyn(lightRGB: (0.91, 0.53, 0.45), darkRGB: (0.96, 0.63, 0.55)),  // 珊瑚
        .dyn(lightRGB: (0.90, 0.68, 0.28), darkRGB: (0.93, 0.80, 0.47)),  // 金
        .dyn(lightRGB: (0.33, 0.70, 0.62), darkRGB: (0.47, 0.82, 0.73)),  // 青
        .dyn(lightRGB: (0.58, 0.50, 0.86), darkRGB: (0.71, 0.64, 0.95)),  // 紫
        .dyn(lightRGB: (0.86, 0.49, 0.68), darkRGB: (0.93, 0.63, 0.79)),  // 玫瑰
        .dyn(lightRGB: (0.55, 0.72, 0.38), darkRGB: (0.69, 0.84, 0.53)),  // 草绿
        .dyn(lightRGB: (0.38, 0.47, 0.80), darkRGB: (0.55, 0.63, 0.93)),  // 靛蓝
        .dyn(lightRGB: (0.78, 0.62, 0.47), darkRGB: (0.86, 0.73, 0.59)),  // 沙
        .dyn(lightRGB: (0.66, 0.42, 0.62), darkRGB: (0.80, 0.58, 0.77)),  // 梅
    ]

    var body: some View {
        let shares = HistoryLedger.shares(breakdown)
        let total = shares.reduce(0) { $0 + $1.total }
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    KickerLabel(text: String(localized: "支出构成"))
                    Spacer()
                    styleSwitch
                }
                switch style {
                case .bars: bars(shares, total: total)
                case .pie: pie(shares, total: total)
                }
            }
        }
    }

    // MARK: - 切换

    private var styleSwitch: some View {
        HStack(spacing: 0) {
            switchButton(.bars, icon: "chart.bar", label: String(localized: "柱状图"))
            switchButton(.pie, icon: "chart.pie", label: String(localized: "扇形图"))
        }
        .overlay(Capsule().stroke(Color.hairline, lineWidth: 1))
    }

    private func switchButton(_ value: Style, icon: String, label: String) -> some View {
        let on = style == value
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                style = value
                selected = nil
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: on ? .regular : .light))
                .foregroundStyle(on ? Color.ink : Color.inkFaint)
                .frame(width: 34, height: 26)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("month-chart-\(value.rawValue)")
    }

    // MARK: - 柱状图

    private func bars(_ shares: [HistoryLedger.Share], total: Double) -> some View {
        let largest = shares.first?.total ?? 1
        return VStack(spacing: Spacing.sm) {
            ForEach(shares) { share in
                HStack(spacing: Spacing.sm) {
                    Text(name(share.kind))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)
                        // 英文分类名更长（Breakfast、Shopping），给宽一点
                        .frame(width: AppLanguage.isChinese ? 56 : 80, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.mist)
                            Capsule().fill(Color.cashBlue)
                                .frame(width: max(4, geo.size.width * share.total / largest))
                        }
                    }
                    .frame(height: 8)
                    Text(FinancialFormatting.yuan(share.total))
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 56, alignment: .trailing)
                    Text(percent(share.total, of: total))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.inkFaint)
                        .frame(width: 34, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .transition(.opacity)
    }

    // MARK: - 扇形图

    private func pie(_ shares: [HistoryLedger.Share], total: Double) -> some View {
        let focus = shares.first { $0.kind == selected }
        return HStack(alignment: .center, spacing: Spacing.lg) {
            Chart(shares) { share in
                SectorMark(angle: .value("金额", share.total), innerRadius: .ratio(0.8), angularInset: 1.5)
                    .cornerRadius(1.5)
                    .foregroundStyle(color(share.kind))
            }
            .chartLegend(.hidden)
            .chartAngleSelection(value: $angle)
            .accessibilityIdentifier("month-chart-pie-view")
            .frame(width: 116, height: 116)
            .overlay {
                // 中间：没点时是这个月支出，点了一份就换成那一份
                VStack(spacing: 2) {
                    Text(focus.map { percent($0.total, of: total) } ?? FinancialFormatting.yuan(total, precision: 0))
                        .font(.system(size: 20, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(focus.map { name($0.kind) } ?? String(localized: "支出"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                        .accessibilityIdentifier("month-chart-pie-center")
                }
                .frame(width: 80)
                .allowsHitTesting(false)
            }
            // 手指滑动时角度连着变，抬手回到 nil：按下那一下才是点选（再点取消），之后滑到哪份选哪份
            .onChange(of: angle) { old, value in
                guard let value, let kind = kind(at: value, in: shares) else { return }
                let next = old == nil && selected == kind ? nil : kind
                guard next != selected else { return }
                withAnimation(.easeInOut(duration: 0.2)) { selected = next }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(shares) { share in
                    legendRow(share, color: color(share.kind), total: total)
                }
            }
        }
        .transition(.opacity)
    }

    private func legendRow(_ share: HistoryLedger.Share, color: Color, total: Double) -> some View {
        let dimmed = selected != nil && selected != share.kind
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selected = selected == share.kind ? nil : share.kind }
        } label: {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(name(share.kind))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(dimmed ? Color.inkFaint : Color.ink)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs)
                Text(FinancialFormatting.yuan(share.total, precision: 0))
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(dimmed ? Color.inkFaint : Color.inkMuted)
                    .lineLimit(1)
                Text(percent(share.total, of: total))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == share.kind ? .isSelected : [])
    }

    /// 点中一份时，其余几份退到很淡
    private func color(_ kind: HistoryLedger.Share.Kind) -> Color {
        let base = Self.palette[colorSlots[kind] ?? 0]
        guard let selected, selected != kind else { return base }
        return base.opacity(0.22)
    }

    /// 扇形图上点到的位置落在哪一份：按金额从起点累加
    private func kind(at value: Double, in shares: [HistoryLedger.Share]) -> HistoryLedger.Share.Kind? {
        var running = 0.0
        for share in shares {
            running += share.total
            if value <= running { return share.kind }
        }
        return shares.last?.kind
    }

    private func name(_ kind: HistoryLedger.Share.Kind) -> String {
        switch kind {
        case .fixed: return String(localized: "固定支出")
        case .category(let category): return ExpenseCategory.displayName(category)
        }
    }

    private func percent(_ value: Double, of total: Double) -> String {
        guard total > 0 else { return "" }
        let share = value / total
        return share < 0.01 ? "<1%" : share.formatted(.percent.precision(.fractionLength(0)))
    }
}
