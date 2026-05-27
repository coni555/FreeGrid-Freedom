//
//  ContentView.swift
//  FreeGrid
//
//  Phase 2 架构: TabView 4 Tab 主框架。
//  - Dashboard: Freedom Days + 三联卡 + 收支记录按钮
//  - Assets: 资产总额管理(Freedom Days 的基准)
//  - History: 历史记录(占位,下一轮实现)
//  - Check: 自检清单(占位,下一轮实现)
//
//  设计原则:
//  - 每个 Tab 独立 NavigationStack,各自的 navigationTitle
//  - 数据通过 @Query 自动反应式同步,任何 Tab 改数据,其他 Tab 数字自动更新
//  - Sheet 表单(添加支出/收入)用模态弹窗,符合 iOS 原生交互
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers   // 提供 .json UTType,供 fileImporter 使用

// ============================================================================
// MARK: - Color(hex:) (颜色扩展)
// ============================================================================
// SwiftUI 没有内置 hex 颜色构造器,加一个方便用 lead-wealth web 版的色板
// 例: Color(hex: "9cc3ff") = 资产蓝, Color(hex: "ffd166") = 收入金

extension Color {
    init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        let scanner = Scanner(string: cleaned)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// ============================================================================
// MARK: - LifeGrid (自适应单位的生命网格 View)
// ============================================================================
// 设计动机: 把"自由天数"这个数字可视化为格子。
// 颗粒度随自由度自适应升级(参考 FreedomMath.GridUnit):
//   日格 9pt / 月格 12pt / 年格 16pt
// 网格随屏幕宽度自适应列数,行数随内容增长。
// 颜色暂用单色 assetBlue(双色阶段再恢复资产/收入区分)。
// 最后一格呼吸高亮(萤火虫/浮起)永远保留——产品记忆点。
//
// 性能: LazyVGrid 懒加载,即使 365 格日档也不卡。

struct LifeGrid: View {
    let unit: FreedomMath.GridUnit
    let count: Int           // 应绘制的格数

    /// current 格呼吸:暗模式发光萤火虫,亮模式深色浮起
    @State private var breath: CGFloat = 0   // 0 = 起点, 1 = 峰值

    /// 读取当前 colorScheme,适配两 mode 的不同视觉策略
    @Environment(\.colorScheme) private var scheme

    /// 当前 scale: dark 放大到 1.6 (萤火虫绽放感)
    /// light 放大到 1.35 (更克制,不至于太抢戏)
    private var currentScale: CGFloat {
        let peak: CGFloat = scheme == .dark ? 1.6 : 1.35
        return 1.1 + (peak - 1.1) * breath
    }
    /// 内 glow radius
    private var innerGlow: CGFloat { 4 + 3 * breath }
    /// 外 glow radius
    private var outerGlow: CGFloat { 9 + 6 * breath }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: unit.cellSize, maximum: unit.cellSize),
                               spacing: unit.spacing)],
            spacing: unit.spacing
        ) {
            ForEach(0..<count, id: \.self) { i in
                let isCurrent = (i == count - 1)
                cell(isCurrent: isCurrent)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breath = 1
            }
        }
    }

    /// 单个 cell:non-current 静态,current 用呼吸效果
    /// dark mode = 萤火虫发光态 (浅色 + 白光 + 蓝光)
    /// light mode = 加深浮起态 (深色 + 浅 base 色光晕,无白光)
    @ViewBuilder
    private func cell(isCurrent: Bool) -> some View {
        let baseColor: Color = .assetBlue
        let isDark = scheme == .dark

        // current 格颜色:
        // dark = 浅色(萤火虫发光) / light = 深色(凸起强调)
        let currentColor: Color = isDark
            ? Color(red: 0.83, green: 0.92, blue: 1.00)
            : Color(red: 0.20, green: 0.50, blue: 0.78)    // 深天空蓝

        // 内 glow 颜色:
        // dark = 白光 (萤火虫) / light = 深 base 色 (浮起阴影感)
        let innerGlowColor: Color = isDark
            ? Color.white
            : Color(red: 0.15, green: 0.35, blue: 0.55)

        // glow opacity 随呼吸缩放
        let innerOpacity: Double = isDark
            ? (0.5 + 0.3 * Double(breath))      // dark 白光强
            : (0.25 + 0.15 * Double(breath))    // light 浅一档,避免太重
        let outerOpacity: Double = isDark
            ? (0.4 + 0.1 * Double(breath))
            : (0.30 + 0.10 * Double(breath))

        if isCurrent {
            Rectangle()
                .fill(currentColor)
                .frame(width: unit.cellSize, height: unit.cellSize)
                .cornerRadius(unit.cellSize * 0.17)   // 跟随 cellSize 等比例圆角
                .shadow(color: innerGlowColor.opacity(innerOpacity), radius: innerGlow)
                .shadow(color: baseColor.opacity(outerOpacity), radius: outerGlow)
                .scaleEffect(currentScale)
                .zIndex(1)
        } else {
            Rectangle()
                .fill(baseColor)
                .frame(width: unit.cellSize, height: unit.cellSize)
                .cornerRadius(unit.cellSize * 0.11)   // 静态格更小圆角
        }
    }
}

// ============================================================================
// MARK: - ContentView (Tab 主框架)
// ============================================================================

struct ContentView: View {
    /// 跨启动持久化主题选择
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                }

            AssetsView()
                .tabItem {
                    Label("Assets", systemImage: "banknote")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            CheckView()
                .tabItem {
                    Label("Check", systemImage: "checklist")
                }
        }
        // tab 选中态吃 sky 主色,品牌一致
        .tint(Color.sky)
        // 用户在 topBar 切换 dark/light,全 app 自动重绘
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}

// ============================================================================
// MARK: - DashboardView (主面板)
// ============================================================================
// 对应 lead-wealth web 版的 Dashboard tab
// 核心: Hero (Freedom Days) + 三联卡 + 收支按钮

struct DashboardView: View {

    // ===== SwiftData 反应式查询 =====
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]

    @Environment(\.modelContext) private var modelContext

    // ===== Sheet 状态 =====
    @State private var showingAddExpense = false
    @State private var showingAddIncome = false
    @State private var showingSimulate = false

    // ===== 主题切换 (与 ContentView 共享同一 key) =====
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    topBar           // 圆点 + FreeGrid + 副标
                    heroSection      // Freedom Days 巨大数字 hero
                    gridSection      // 1825 格,占整个 mid 区
                    statsRow         // 3 个 stat 卡片横向
                    actionRow        // 支出 + 收入 (提前,放在 stats 后方便操作)
                    simulateRow      // 模拟决策
                    todaySection     // 今日 vs 日均 (推到最底,是 review 信息)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollContentBackground(.hidden)
            .background(Color.midnight.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseSheet()
            }
            .sheet(isPresented: $showingAddIncome) {
                AddIncomeSheet()
            }
            .sheet(isPresented: $showingSimulate) {
                SimulateSheet()
            }
        }
    }

    // ============================================================================
    // MARK: - 顶部 wordmark
    // ============================================================================

    /// 顶部 brand bar:靶心 mark(同时是 dark/light 切换按钮) + 品牌名 + VOL 标识
    /// mark 内部:light mode = sky 实心点(太阳),dark mode = moon icon
    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            // 主题切换按钮:外圈 outline + 内 sun/moon
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isDarkMode.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.ink, lineWidth: 1)
                        .frame(width: 22, height: 22)
                    if isDarkMode {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.sky)
                    } else {
                        Circle()
                            .fill(Color.sky)
                            .frame(width: 9, height: 9)
                    }
                }
                .contentShape(Rectangle())   // 扩大点击区
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDarkMode ? "切换浅色模式" : "切换深色模式")

            Text("FreeGrid")
                .font(.system(.title3, design: .rounded).weight(.medium))
                .foregroundStyle(Color.ink)

            Text("财富自由指路灯")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.inkFaint)

            Spacer()

            Text("VOL.001")
                .font(.kicker)
                .tracking(1.8)
                .foregroundStyle(Color.inkFaint)
        }
        .padding(.bottom, Spacing.xs)
    }

    // ============================================================================
    // MARK: - Hero & 三联卡 (UI 组件)
    // ============================================================================

    /// Hero: Silverline 大胆版 — 巨大数字 + trend badge + sparkline + 见底日期
    /// 参考 V3/V5 mockup 设计:把 hero card 升级为"自由仪表盘"
    private var heroSection: some View {
        let history = FreedomMath.freedomDaysHistory(
            expenses: expenses,
            incomes: incomes,
            currentAssets: totalAssets,
            firstRecordDate: firstRecordDate
        )
        let delta = FreedomMath.deltaSummary(history: history)
        let deplete = FreedomMath.depleteDate(freedomDays: freedomDays)

        return VaultCard(emphasis: .high, padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
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

                // ─── 中部: 副标 leading + 数字 trailing (mockup hero-a 布局) ───
                // baseline 底部对齐:副标多行的最后一行底部 = 数字底部
                // 副标拆 2 行(18pt): card 内副标可用宽 ~121pt,22pt 7 字会强行 break
                HStack(alignment: .lastTextBaseline, spacing: Spacing.md) {
                    // 副标 leading, 2 行 + 见底 caption
                    VStack(alignment: .leading, spacing: 2) {
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
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    // 大数字 trailing
                    // lineLimit(1) + minimumScaleFactor: 5+ 位数自动缩字号,不换行
                    Text(freedomDaysDisplay)
                        .font(.system(size: 110, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)
                        .padding(.vertical, -8)
                        .layoutPriority(0)
                }

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

    /// 格式化"约 X 月 X 日"
    private func depleteDateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        return f.string(from: d)
    }

    /// 三联 stat 卡片:横向 3 个独立 VaultCard,各自有 padding 和描边
    /// 设计动机:工具 App 需要清晰的"信息卡片"层级,这里 3 个并列 stat
    private var statsRow: some View {
        HStack(spacing: Spacing.md) {
            statCard(label: "Daily",
                     value: String(format: "%.1f", dailyBurn),
                     unit: "元/天")
            statCard(label: "Passive",
                     value: String(format: "%.0f%%", passiveRatio * 100),
                     unit: "被动覆盖")
            statCard(label: "Track",
                     value: "\(trackDays)",
                     unit: "天追踪")
        }
    }

    /// 单个 stat 卡片:数字 / hairline / kicker / sub label 四层(silverline)
    private func statCard(label: String, value: String, unit: String) -> some View {
        VaultCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                // 大 thin 数字(silverline 风格)
                Text(value)
                    .font(.system(size: 28, weight: .thin, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                // 短 hairline 短横线
                Rectangle()
                    .fill(Color.inkGhost)
                    .frame(width: 22, height: 1)
                    .padding(.vertical, 2)
                // kicker
                KickerLabel(text: label)
                // sub unit
                Text(unit)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }

    /// Today: Silverline 版 — 单行 bar 设计
    /// 左 ¥5 (today) — bar with marker — 右 ¥72 (avg)
    /// 下方 delta caption 居中
    private var todaySection: some View {
        VaultCard(padding: Spacing.lg) {
            VStack(spacing: Spacing.md) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    // 左:今日金额
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "¥%.1f", todaySpending))
                            .font(.system(size: 24, weight: .thin, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.ink)
                        KickerLabel(text: "Today")
                    }
                    .frame(minWidth: 60, alignment: .leading)

                    // 中:bar with sky fill + marker
                    GeometryReader { geo in
                        let pct = max(0.04, min(todayPercent, 1.0))
                        ZStack(alignment: .leading) {
                            // mist 底 bar
                            Rectangle()
                                .fill(Color.mist2)
                                .frame(height: 2)
                            // sky fill
                            Rectangle()
                                .fill(Color.sky)
                                .frame(width: geo.size.width * CGFloat(pct), height: 2)
                            // sky-deep marker (短竖线在 fill 末端)
                            Rectangle()
                                .fill(Color.skyDeep)
                                .frame(width: 1.5, height: 10)
                                .offset(x: geo.size.width * CGFloat(pct) - 0.75)
                        }
                    }
                    .frame(height: 10)

                    // 右:日均金额
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "¥%.1f", dailyBurn))
                            .font(.system(size: 24, weight: .thin, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkMuted)
                        KickerLabel(text: "avg")
                    }
                    .frame(minWidth: 60, alignment: .trailing)
                }

                // delta caption (居中)
                if dailyBurn > 0 {
                    Text(todayDeltaText)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                }
            }
        }
    }

    /// today bar 下方的 delta 文案
    private var todayDeltaText: String {
        if dailyBurn == 0 { return "等待日均数据" }
        if todaySpending == 0 {
            return "今日尚未消费"
        }
        let diffPct = Int(abs((1 - todayPercent) * 100))
        if todaySpending > dailyBurn {
            let over = todaySpending - dailyBurn
            return "高于日均 \(diffPct)% · 多花 ¥\(String(format: "%.1f", over))"
        } else {
            let savings = dailyBurn - todaySpending
            return "低于日均 \(diffPct)% · 节省 ¥\(String(format: "%.1f", savings))"
        }
    }

    /// 今日支出
    private var todaySpending: Double {
        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        return expenses
            .filter { $0.date >= today && $0.date < tomorrow }
            .reduce(0) { $0 + $1.amount }
    }

    /// 今日花费占日均的百分比(用于颜色判断)
    private var todayPercent: Double {
        guard dailyBurn > 0 else { return 0 }
        return todaySpending / dailyBurn
    }

    /// 今日 vs 日均的描述文案,根据高低给出不同评价
    private var todayVsAvgText: String {
        if dailyBurn == 0 {
            return "还没有日均数据,先记几笔再看对比。"
        }
        let today = todaySpending
        let avg = dailyBurn
        if today == 0 {
            return "今日尚未消费 · 日均 ¥\(Int(avg))"
        }
        let diff = today - avg
        let pct = abs(diff) / avg * 100
        if today > avg {
            return "今日已花 ¥\(Int(today)) · 日均 ¥\(Int(avg)) · 高于日均 \(String(format: "%.0f", pct))%"
        } else {
            return "今日已花 ¥\(Int(today)) · 日均 ¥\(Int(avg)) · 低于日均 \(String(format: "%.0f", pct))%"
        }
    }

    /// Freedom Grid:1825 格可视化,作为 hero 卡片之一,占大空间
    /// 设计动机:这是 FreeGrid 的产品记忆点,在暗底上每格"发光"质感
    private var gridSection: some View {
        let state = FreedomMath.gridState(assets: totalAssets,
                                          netSavings: netSavings,
                                          dailyBurn: dailyBurn)
        return VaultCard(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // 标题行
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "Freedom Grid")
                    Spacer()
                    Text(gridSummary(state: state))
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.inkFaint)
                }

                // 网格本身
                if state.count == 0 {
                    emptyGridHint
                } else {
                    LifeGrid(unit: state.unit, count: state.count)
                        .padding(.vertical, Spacing.sm)
                }

                // 图例:单色 dot(双色阶段再恢复 incomeGold) + 单位 caption
                HStack(spacing: Spacing.lg) {
                    legendDot(color: .assetBlue, label: "自由")
                    Spacer()
                    Text("每格 = 1 \(state.unit.label)自由")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    /// 图例:silverline 版小方块 + 标签(无 glow)
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 8)
                .cornerRadius(1)
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkMuted)
        }
    }

    /// 网格右上角文案:按档位显示当前格数 + 单位
    /// 日档 "127 天" / 月档 "16 月" / 年档 "34 年" / 溢出 "99+ 年"
    private func gridSummary(state: FreedomMath.GridState) -> String {
        if state.count == 0 { return "等待数据" }
        if state.isOverflow { return "\(state.count)+ \(state.unit.label)" }
        return "\(state.count) \(state.unit.label)"
    }

    /// 空网格时的提示:暗色 SF symbol + 文案
    private var emptyGridHint: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "square.grid.3x3.middleandbottom.filled")
                .font(.system(size: 36))
                .foregroundStyle(Color.inkFaint)
            Text("记录第一笔后,网格开始点亮")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }

    /// 收支双按钮:filled prominent
    /// 支出 = destructive flame,收入 = primary honey(自由的颜色,鼓励多记)
    private var actionRow: some View {
        HStack(spacing: Spacing.md) {
            VaultButton(title: "记支出",
                        icon: "minus",
                        style: .destructive) {
                showingAddExpense = true
            }
            VaultButton(title: "记收入",
                        icon: "plus",
                        style: .primary) {
                showingAddIncome = true
            }
        }
    }

    /// 模拟决策:ghost button,放在主按钮下方
    private var simulateRow: some View {
        HStack {
            Spacer()
            GhostButton(title: "模拟一笔 · 看决策影响",
                        icon: "wand.and.stars") {
                showingSimulate = true
            }
            Spacer()
        }
        .padding(.top, Spacing.xs)
    }

    // ============================================================================
    // MARK: - 核心计算 (业务逻辑)
    // ============================================================================
    // lead-wealth web 版 app.html 的业务函数 1:1 Swift 复刻
    // 用 computed property,SwiftUI 自动追踪依赖,@Query 数据变化时自动重算

    private var totalAssets: Double {
        assetsArr.first?.total ?? 0
    }

    private var firstRecordDate: Date? {
        assetsArr.first?.firstRecordDate
    }

    private var totalExpenses: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    private var totalIncome: Double {
        incomes.reduce(0) { $0 + $1.amount }
    }

    /// 净储蓄 = 总收入 - 总支出 (可能为负 = 透支)
    private var netSavings: Double {
        totalIncome - totalExpenses
    }

    /// 记录天数: 从首次记账到今天,最小 1
    private var trackDays: Int {
        guard let firstDate = firstRecordDate else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: firstDate, to: .now).day ?? 0
        return max(1, days + 1)
    }

    /// 日均消费 = 总支出 ÷ 记录天数
    private var dailyBurn: Double {
        guard trackDays > 0 else { return 0 }
        return totalExpenses / Double(trackDays)
    }

    /// 日均被动收入 = Σ(月被动收入 ÷ 30)
    private var dailyPassive: Double {
        passiveSources.reduce(0) { $0 + $1.monthlyAmount / 30 }
    }

    /// 被动覆盖率 = 日均被动收入 ÷ 日均消费 (≥1 即财务自由)
    private var passiveRatio: Double {
        guard dailyBurn > 0 else { return 0 }
        return dailyPassive / dailyBurn
    }

    /// 自由天数 = (资产 + max(净储蓄, 0)) ÷ 日均消费
    /// 设计动机: 把"还能不上班多久"量化为具体天数
    /// 净储蓄为负不算(透支不能让你更自由)
    /// 没记账时返回 ∞ (没有消费数据,自由是无限的)
    private var freedomDays: Double {
        guard dailyBurn > 0 else { return .infinity }
        let assetDays = totalAssets / dailyBurn
        let incomeDays = max(0, netSavings) / dailyBurn
        return assetDays + incomeDays
    }

    /// 三档无后缀 hero 数字: 日整数 / 月整数 / 年1位小数 / ∞
    private var freedomDaysDisplay: String {
        FreedomMath.freedomDaysDisplay(freedomDays)
    }

    /// hero 副标单位:跟数字档位同步
    private var heroSubUnit: String {
        if freedomDays.isInfinite { return "久" }
        if freedomDays < 365 { return "天" }
        if freedomDays < 3650 { return "月" }
        return "年"
    }

    /// hero kicker 文案:跟数字档位同步
    /// FREEDOM DAYS / FREEDOM MONTHS / FREEDOM YEARS / FREEDOM
    private var heroKickerText: String {
        if freedomDays.isInfinite { return "Freedom" }
        if freedomDays < 365 { return "Freedom Days" }
        if freedomDays < 3650 { return "Freedom Months" }
        return "Freedom Years"
    }
}

// ============================================================================
// MARK: - AssetsView (资产管理 Tab)
// ============================================================================
// 设计动机: 资产是 Freedom Days 的基准。
// 用户必须主动设"我有多少钱",否则 App 永远不知道你的真实储蓄(只能从交易推算)。
// 这个 Tab 是"会计基准"的设定面板。
//
// 交互: 顶部 Hero 显示当前资产 + 上次更新时间;下方 Form 编辑新值。

struct AssetsView: View {

    @Query private var assetsArr: [UserAssets]
    @Environment(\.modelContext) private var modelContext

    /// 输入框状态。用 String 而不是 Double 因为 TextField 编辑过程中可能短暂为空
    @State private var newAmount: String = ""

    /// 跟踪是否已经显示过提交后的反馈,避免每次切 Tab 都闪
    @State private var showSavedHint = false

    // ===== 数据管理状态 =====
    @State private var showingFileImporter = false
    @State private var showingPurgeAlert = false
    @State private var importStatus: String? = nil   // 用于显示导入结果反馈

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    editForm
                    explainCard
                    dataManagementCard   // 数据管理:导入 / 清空
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("Assets")
            // ===== 文件选择器(系统弹出) =====
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            // ===== 清空确认 Alert =====
            .alert("清空所有数据?", isPresented: $showingPurgeAlert) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { purgeData() }
            } message: {
                Text("将删除所有支出、收入、被动收入源、设备记录和资产数据。此操作不可撤销。")
            }
        }
    }

    /// Hero: VaultCard 高亮卡片 + 大 thin 数字 (silverline)
    private var heroCard: some View {
        VaultCard(emphasis: .high, padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "Total Assets")

                Text("¥" + currentAsset.formatted(.number))
                    .font(.system(size: 44, weight: .ultraLight, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .padding(.top, Spacing.xs)

                if let updated = assetsArr.first?.updatedAt {
                    Text("上次更新 · \(updated, format: .relative(presentation: .named))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                } else {
                    Text("尚未设置 · 请在下方输入当前可变现资产")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
            }
        }
    }

    /// 编辑表单: VaultCard + 文本框 + sky outline 按钮
    private var editForm: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "Update")

                HStack(spacing: 6) {
                    Text("¥")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    TextField("0", text: $newAmount)
                        .keyboardType(.decimalPad)
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.hairline, lineWidth: 1)
                        )
                }

                VaultButton(
                    title: showSavedHint ? "已保存" : "更新资产",
                    icon: showSavedHint ? "checkmark" : "arrow.up",
                    style: .primary
                ) {
                    updateAsset()
                }
                .disabled(!isValid)
                .opacity(isValid || showSavedHint ? 1.0 : 0.4)
            }
        }
    }

    /// 说明卡片: 帮助用户理解"资产"的含义 (silverline 极淡 mist 底)
    private var explainCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkFaint)
                Text("什么算资产")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
            }

            Text("可变现资产 = 存款 + 余额宝 + 货币基金等\"随时能用的钱\"。这是 Freedom Days 的基准:每次记账时会自动扣减(支出)/增加(收入),你也可以随时手动同步真实余额。")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.skyFaint)
        )
    }

    // ============================================================================
    // MARK: - 数据管理卡片
    // ============================================================================
    // 导入 lead-wealth web 版的 JSON 备份 + 清空所有数据
    // 适用场景:从 web 版迁移历史数据 / 重置测试数据

    private var dataManagementCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: 6) {
                    KickerLabel(text: "Data")
                    Spacer()
                    Image(systemName: "externaldrive")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkFaint)
                }

                VaultButton(title: "从 JSON 导入",
                            icon: "square.and.arrow.down",
                            style: .secondary) {
                    showingFileImporter = true
                }

                VaultButton(title: "清空所有数据",
                            icon: "trash",
                            style: .destructive) {
                    showingPurgeAlert = true
                }

                if let status = importStatus {
                    Text(status)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .padding(.top, Spacing.xs)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // ============================================================================
    // MARK: - 数据管理:业务方法
    // ============================================================================

    /// 处理文件选择器返回的结果
    /// iOS 文件 picker 返回的 URL 是 security-scoped,必须 startAccess/stopAccess
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importStatus = "未选择文件"
                return
            }
            // 沙盒文件访问授权
            guard url.startAccessingSecurityScopedResource() else {
                importStatus = "无法访问该文件"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let result = try DataIO.importJSON(data: data, context: modelContext)
                importStatus = """
                ✓ 导入成功
                支出 \(result.expensesAdded) 笔 · 收入 \(result.incomesAdded) 笔 · 被动源 \(result.passiveSourcesAdded) 个
                资产 ¥\(Int(result.assetsTotal))
                """
            } catch {
                importStatus = "✗ 导入失败: \(error.localizedDescription)"
            }
        case .failure(let error):
            importStatus = "✗ 文件读取失败: \(error.localizedDescription)"
        }
    }

    /// 清空所有数据
    private func purgeData() {
        do {
            try DataIO.purgeAll(context: modelContext)
            // 清空后重置输入框
            newAmount = ""
            importStatus = "✓ 已清空所有数据"
        } catch {
            importStatus = "✗ 清空失败: \(error.localizedDescription)"
        }
    }

    // ===== 业务方法 =====

    /// 当前资产(单例的 total,没有就是 0)
    private var currentAsset: Double {
        assetsArr.first?.total ?? 0
    }

    /// 输入是否有效:必须是非负数字
    private var isValid: Bool {
        guard let v = Double(newAmount), v >= 0 else { return false }
        return true
    }

    /// 更新资产: 修改单例的 total + updatedAt
    /// 第一次没有单例时会创建一个
    private func updateAsset() {
        guard let value = Double(newAmount) else { return }

        let assets: UserAssets
        if let existing = assetsArr.first {
            assets = existing
        } else {
            assets = UserAssets(total: 0)
            modelContext.insert(assets)
        }
        assets.total = value
        assets.updatedAt = .now

        // 如果用户还没记账,把今天定为首次记账日
        // 这样 trackDays 至少有意义,Freedom Days 不会一直 ∞
        if assets.firstRecordDate == nil {
            assets.firstRecordDate = .now
        }

        // 清空输入,显示已保存反馈
        newAmount = ""
        withAnimation {
            showSavedHint = true
        }
        // 2 秒后恢复按钮文字
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSavedHint = false
            }
        }
    }
}

// ============================================================================
// MARK: - TxKind (交易类型统一)
// ============================================================================
// 支出和收入是两个独立的 @Model 类型,但 History 列表要把它们混排。
// 用 enum 包装成同一类型,方便排序、渲染、删除时分发。

enum TxKind: Identifiable {
    case expense(Expense)
    case income(Income)

    var id: UUID {
        switch self {
        case .expense(let e): return e.id
        case .income(let i): return i.id
        }
    }

    /// 用于排序的日期
    var date: Date {
        switch self {
        case .expense(let e): return e.date
        case .income(let i): return i.date
        }
    }
}

// ============================================================================
// MARK: - LumenDataJSON (lead-wealth web 版 JSON 数据结构)
// ============================================================================
// 用于把 web 版导出的 lumen_data_*.json 解析到 Swift 类型。
// keyDecodingStrategy = .convertFromSnakeCase 会自动把 is_passive → isPassive
// monthly_amount → monthlyAmount 等。

struct LumenDataJSON: Codable {
    struct AssetsJSON: Codable {
        let total: Double
        let updatedAt: String?      // ISO 字符串 "2026-05-25T08:55:55.159Z"
    }
    struct ExpenseJSON: Codable {
        let amount: Double
        let category: String
        let date: String            // "YYYY-MM-DD"
        let note: String?
        let createdAt: String?      // ISO 字符串
    }
    struct IncomeJSON: Codable {
        let amount: Double
        let source: String
        let date: String
        let note: String?
        let isPassive: Bool?
        let createdAt: String?
    }
    struct PassiveSourceJSON: Codable {
        let name: String
        let monthlyAmount: Double
    }

    let assets: AssetsJSON?
    let expenses: [ExpenseJSON]?
    let incomes: [IncomeJSON]?
    let passiveSources: [PassiveSourceJSON]?
    let firstRecordDate: String?    // "YYYY-MM-DD"
}

// ============================================================================
// MARK: - DataImporter / DataPurger (导入 + 清空数据)
// ============================================================================
// 设计动机:用户的 lead-wealth web 版已经积累几百天数据,iOS 版要能继承。
// 不然测试数据(trackDays=1)会让 dailyBurn 算法看不出真实表现。

enum DataIO {

    /// 导入结果统计,UI 用来展示反馈
    struct ImportResult {
        let expensesAdded: Int
        let incomesAdded: Int
        let passiveSourcesAdded: Int
        let assetsTotal: Double
        let firstRecordDate: Date?
    }

    /// 解析 JSON 数据并导入到 SwiftData
    /// 注意:此函数不清空已有数据,只追加。调用前如需清空,先调 purgeAll()
    static func importJSON(data: Data, context: ModelContext) throws -> ImportResult {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let dump = try decoder.decode(LumenDataJSON.self, from: data)

        // ===== 1. 导入 expenses =====
        var expCount = 0
        for e in dump.expenses ?? [] {
            let exp = Expense(
                amount: e.amount,
                category: e.category,
                note: e.note ?? "",
                date: parseDate(e.date) ?? .now
            )
            // 覆盖 createdAt 用原始时间戳(默认 init 用 .now)
            if let createdAt = e.createdAt, let d = parseISO(createdAt) {
                exp.createdAt = d
            }
            context.insert(exp)
            expCount += 1
        }

        // ===== 2. 导入 incomes =====
        var incCount = 0
        for i in dump.incomes ?? [] {
            let inc = Income(
                amount: i.amount,
                source: i.source,
                isPassive: i.isPassive ?? false,
                note: i.note ?? "",
                date: parseDate(i.date) ?? .now
            )
            if let createdAt = i.createdAt, let d = parseISO(createdAt) {
                inc.createdAt = d
            }
            context.insert(inc)
            incCount += 1
        }

        // ===== 3. 导入 passive sources =====
        var passCount = 0
        for p in dump.passiveSources ?? [] {
            let src = PassiveSource(name: p.name, monthlyAmount: p.monthlyAmount)
            context.insert(src)
            passCount += 1
        }

        // ===== 4. 设置 UserAssets 单例 =====
        // 如果已存在就 update,否则 insert
        let firstDate = dump.firstRecordDate.flatMap { parseDate($0) }
        let assetsTotal = dump.assets?.total ?? 0
        let updatedAt = dump.assets?.updatedAt.flatMap { parseISO($0) } ?? .now

        let existing = try? context.fetch(FetchDescriptor<UserAssets>()).first
        let userAssets: UserAssets
        if let existing = existing {
            userAssets = existing
        } else {
            userAssets = UserAssets(total: 0)
            context.insert(userAssets)
        }
        userAssets.total = assetsTotal
        userAssets.updatedAt = updatedAt
        userAssets.firstRecordDate = firstDate

        return ImportResult(
            expensesAdded: expCount,
            incomesAdded: incCount,
            passiveSourcesAdded: passCount,
            assetsTotal: assetsTotal,
            firstRecordDate: firstDate
        )
    }

    /// 清空所有数据(包括 UserAssets 单例)
    /// SwiftData 提供了批量删除 API: context.delete(model:)
    static func purgeAll(context: ModelContext) throws {
        try context.delete(model: Expense.self)
        try context.delete(model: Income.self)
        try context.delete(model: Device.self)
        try context.delete(model: PassiveSource.self)
        try context.delete(model: UserAssets.self)
    }

    // ===== 内部:日期解析工具 =====

    /// 解析 "YYYY-MM-DD" 为 Date (当地时区午夜 0:00)
    private static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.date(from: s)
    }

    /// 解析 ISO 8601 时间戳 "2024-09-08T08:00:00.000Z"
    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        // fallback: 没毫秒的格式
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// ============================================================================
// MARK: - HistoryView (历史交易 Tab)
// ============================================================================
// 设计动机:用户记完账必须能"看 + 删",否则记错的没法挽回。
// 这是闭环必备,不是 nice-to-have。
//
// 功能:
// - 支出 + 收入混排,按日期降序
// - 顶部 segmented 筛选: 全部 / 支出 / 收入
// - 滑动删除时同步还原资产(删支出 +=,删收入 -=)
// - 空状态友好引导

struct HistoryView: View {

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @Query private var assetsArr: [UserAssets]

    @Environment(\.modelContext) private var modelContext

    /// 筛选状态: "all" / "expense" / "income"
    @State private var filter: FilterKind = .all

    enum FilterKind: String, CaseIterable, Identifiable {
        case all = "全部"
        case expense = "支出"
        case income = "收入"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ===== 顶部 segmented 筛选器 =====
                Picker("筛选", selection: $filter) {
                    ForEach(FilterKind.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if filteredTransactions.isEmpty {
                    emptyState
                } else {
                    transactionList
                }
            }
            .background(Color.paper)
            .navigationTitle("History")
        }
    }

    // ============================================================================
    // MARK: - 列表渲染
    // ============================================================================

    private var transactionList: some View {
        List {
            Section {
                HStack {
                    Text("共 \(filteredTransactions.count) 笔")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    Spacer()
                    Text("净 \(netDisplay)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                }
                .listRowBackground(Color.paper)
            }

            Section {
                ForEach(filteredTransactions) { tx in
                    transactionRow(tx)
                        .listRowBackground(Color.paper)
                        .listRowSeparatorTint(Color.hairlineSoft)
                }
                .onDelete(perform: deleteTransactions)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .listStyle(.plain)
    }

    @ViewBuilder
    private func transactionRow(_ tx: TxKind) -> some View {
        switch tx {
        case .expense(let e):
            expenseRow(e)
        case .income(let i):
            incomeRow(i)
        }
    }

    /// 支出行:朱砂金额 + 分类 + 备注 + 日期 (silverline rounded)
    private func expenseRow(_ e: Expense) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(e.category)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                if !e.note.isEmpty {
                    Text(e.note)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                }
                Text(e.date, format: .dateTime.year().month().day())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
            }
            Spacer()
            Text("−¥" + e.amount.formatted(.number.precision(.fractionLength(0...2))))
                .font(.system(.callout, design: .rounded).weight(.regular).monospacedDigit())
                .foregroundStyle(Color.flame)
        }
        .padding(.vertical, 4)
    }

    /// 收入行:深天空蓝金额 + 来源 + 被动标签 + 备注 + 日期
    /// (silverline:跟"记收入"按钮同色统一)
    private func incomeRow(_ i: Income) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(i.source)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                    if i.isPassive {
                        Text("被动")
                            .font(.system(.caption2, design: .monospaced))
                            .tracking(0.5)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(Color.mossGreen)
                            .overlay(
                                Capsule().stroke(Color.mossGreen.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
                if !i.note.isEmpty {
                    Text(i.note)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                }
                Text(i.date, format: .dateTime.year().month().day())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
            }
            Spacer()
            Text("+¥" + i.amount.formatted(.number.precision(.fractionLength(0...2))))
                .font(.system(.callout, design: .rounded).weight(.regular).monospacedDigit())
                .foregroundStyle(Color.skyDeep)
        }
        .padding(.vertical, 4)
    }

    /// 空状态:silverline 风简洁提示
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.inkFaint)
            Text("还没有记录")
                .font(.system(.title3, design: .rounded).weight(.thin))
                .foregroundStyle(Color.ink)
            Text("回 Dashboard 添加第一笔支出或收入")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }

    // ============================================================================
    // MARK: - 业务逻辑
    // ============================================================================

    /// 根据筛选返回排好序的交易列表
    private var filteredTransactions: [TxKind] {
        var all: [TxKind] = []
        if filter == .all || filter == .expense {
            all.append(contentsOf: expenses.map { .expense($0) })
        }
        if filter == .all || filter == .income {
            all.append(contentsOf: incomes.map { .income($0) })
        }
        // 按日期降序,新的在上
        return all.sorted { $0.date > $1.date }
    }

    /// 净额显示文案:正数绿色,负数红色,前面带符号
    private var netDisplay: String {
        let total = filteredTransactions.reduce(0.0) { sum, tx in
            switch tx {
            case .expense(let e): return sum - e.amount
            case .income(let i): return sum + i.amount
            }
        }
        let sign = total >= 0 ? "+" : "−"
        return "\(sign)¥" + abs(total).formatted(.number.precision(.fractionLength(0...2)))
    }

    /// 删除交易:同步还原资产
    /// 设计动机: 记错的一笔删掉后,资产要变回去,不然数据就脏了
    private func deleteTransactions(offsets: IndexSet) {
        let toDelete = offsets.map { filteredTransactions[$0] }

        // 确保有 UserAssets 实例(理论上必有,因为记账过)
        let assets = assetsArr.first

        for tx in toDelete {
            switch tx {
            case .expense(let e):
                // 删支出 = 资产加回去
                assets?.total += e.amount
                modelContext.delete(e)
            case .income(let i):
                // 删收入 = 资产减回去
                assets?.total -= i.amount
                modelContext.delete(i)
            }
        }
        assets?.updatedAt = .now
    }
}

// ============================================================================
// MARK: - CheckView (自检清单 Tab - 占位)
// ============================================================================
// 下一轮实现: 9 项财富自由自检清单

struct CheckView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                // silverline outline 圆 + 内 sky 圆点(品牌一致 mark)
                ZStack {
                    Circle()
                        .stroke(Color.inkFaint, lineWidth: 1)
                        .frame(width: 56, height: 56)
                    Image(systemName: "checklist")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color.inkFaint)
                }
                Text("Check")
                    .font(.system(.title2, design: .rounded).weight(.thin))
                    .foregroundStyle(Color.ink)
                Text("财富自由自检清单 · 即将上线")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color.paper)
            .navigationTitle("Check")
        }
    }
}

// ============================================================================
// MARK: - AddExpenseSheet (添加支出的模态弹窗)
// ============================================================================
// 触发: Dashboard 的"添加支出"按钮
// 闭环: 用户填 → 保存 → modelContext.insert + 扣资产 → @Query 自动感知 → Dashboard 数字变化

struct AddExpenseSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // 预览需要读所有现有数据,实时算"如果加这一笔,自由天数变化"
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var assetsArr: [UserAssets]

    @State private var amount: String = ""
    @State private var category: String = "早餐"
    @State private var note: String = ""
    @State private var date: Date = .now

    /// 分类清单,和 lead-wealth web 版 CATEGORIES 完全一致
    private let categories = ["早餐", "午餐", "晚餐", "购物", "交通", "娱乐",
                              "成长投资", "医疗", "人情", "日用", "其他"]

    var body: some View {
        NavigationStack {
            Form {
                Section("金额 (元)") {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(.body, design: .rounded).monospacedDigit())
                }
                Section("分类") {
                    Picker("分类", selection: $category) {
                        ForEach(categories, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                }
                Section("日期") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }
                Section("备注 (可选)") {
                    TextField("备注", text: $note)
                        .font(.system(.body, design: .rounded))
                }

                // ===== 戴维斯三杀实时预览 =====
                if let amt = Double(amount), amt > 0 {
                    Section {
                        impactPreview(amount: amt)
                    } header: {
                        Text("戴维斯三杀预览")
                    } footer: {
                        Text("这笔消费对自由天数的传导效应。还没保存,只是看看。")
                            .font(.system(.caption2, design: .rounded))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("添加支出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isAmountValid)
                        .foregroundStyle(isAmountValid ? Color.skyDeep : Color.inkFaint)
                        .fontWeight(.medium)
                }
            }
        }
    }

    // ============================================================================
    // MARK: - 戴维斯三杀预览渲染
    // ============================================================================

    /// 预览组件: 3 行 KILL 显示 from → to + delta
    private func impactPreview(amount: Double) -> some View {
        // ===== 当前快照 =====
        let currentAssets = assetsArr.first?.total ?? 0
        let firstDate = assetsArr.first?.firstRecordDate
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)

        let currentTotalExp = expenses.reduce(0) { $0 + $1.amount }
        let totalInc = incomes.reduce(0) { $0 + $1.amount }
        let currentAvg = FreedomMath.dailyBurn(totalExpenses: currentTotalExp, trackDays: days)
        let currentNetSavings = totalInc - currentTotalExp
        let currentFreedom = FreedomMath.freedomDays(assets: currentAssets,
                                                     netSavings: currentNetSavings,
                                                     dailyBurn: currentAvg)

        // ===== 如果加这一笔 =====
        let newAssets = currentAssets - amount
        let newAvg = FreedomMath.dailyBurn(totalExpenses: currentTotalExp + amount, trackDays: days)
        let newNetSavings = currentNetSavings - amount  // 支出减少净储蓄
        let newFreedom = FreedomMath.freedomDays(assets: newAssets,
                                                 netSavings: newNetSavings,
                                                 dailyBurn: newAvg)

        // ===== 计算 delta =====
        let freedomLoss: Double = currentFreedom.isInfinite ? 0 : (currentFreedom - newFreedom)

        return VStack(alignment: .leading, spacing: 10) {
            killRow(label: "KILL 1 储蓄",
                    from: formatYuan(currentAssets),
                    to: formatYuan(newAssets),
                    delta: "−\(formatYuan(amount))")

            killRow(label: "KILL 2 日均",
                    from: formatYuan(currentAvg, precision: 1),
                    to: formatYuan(newAvg, precision: 2),
                    delta: "+\(formatYuan(newAvg - currentAvg, precision: 2))")

            killRow(label: "KILL 3 自由天数",
                    from: FreedomMath.freedomDaysDisplay(currentFreedom),
                    to: FreedomMath.freedomDaysDisplay(newFreedom),
                    delta: currentFreedom.isInfinite ? "—" : "−\(String(format: "%.0f", freedomLoss)) 天")
        }
        .padding(.vertical, 4)
    }

    /// 单行 KILL: silverline 风 — kicker label / mono from → to / delta 朱砂
    private func killRow(label: String, from: String, to: String, delta: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            KickerLabel(text: label)
            HStack {
                Text("\(from) → \(to)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.ink)
                Spacer()
                Text(delta)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color.flame)
            }
        }
    }

    /// 格式化金额: 1234.56 → "¥1,234.56" (带千分位 + 指定精度)
    /// 用 NumberFormatter 自动加千分位逗号,精度由参数控制
    private func formatYuan(_ value: Double, precision: Int = 0) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = precision
        f.maximumFractionDigits = precision
        let s = f.string(from: NSNumber(value: value)) ?? String(format: "%.\(precision)f", value)
        return "¥\(s)"
    }

    private var isAmountValid: Bool {
        guard let v = Double(amount), v > 0 else { return false }
        return true
    }

    /// 保存: 创建 Expense + 同步扣资产 (KILL 1) + 维护 firstRecordDate
    private func save() {
        guard let amt = Double(amount), amt > 0 else { return }

        let expense = Expense(amount: amt, category: category, note: note, date: date)
        modelContext.insert(expense)

        let assets: UserAssets
        if let existing = assetsArr.first {
            assets = existing
        } else {
            assets = UserAssets(total: 0)
            modelContext.insert(assets)
        }
        assets.total -= amt
        assets.updatedAt = .now

        if assets.firstRecordDate == nil || date < assets.firstRecordDate! {
            assets.firstRecordDate = date
        }

        dismiss()
    }
}

// ============================================================================
// MARK: - AddIncomeSheet (添加收入的模态弹窗)
// ============================================================================
// 和 AddExpenseSheet 对称,但保存时:
// - 资产 += 金额 (而不是扣)
// - 多一个"是否被动收入"开关(决定是否纳入 Passive Ratio)

struct AddIncomeSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // 预览需要读所有现有数据,实时算"如果加这一笔,自由天数增长多少"
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var assetsArr: [UserAssets]

    @State private var amount: String = ""
    @State private var source: String = ""
    @State private var isPassive: Bool = false
    @State private var note: String = ""
    @State private var date: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section("金额 (元)") {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(.body, design: .rounded).monospacedDigit())
                }
                Section("来源") {
                    TextField("工资 / 投资 / 副业 / ...", text: $source)
                        .font(.system(.body, design: .rounded))
                }
                Section {
                    Toggle("这是被动收入", isOn: $isPassive)
                        .tint(Color.sky)
                } footer: {
                    Text("被动收入: 不需要持续工作就能稳定获得的收入(房租/股息/版税/利息)。勾选后会纳入「被动覆盖率」统计,这是财富自由的核心指标。")
                        .font(.system(.caption2, design: .rounded))
                }
                Section("日期") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }
                Section("备注 (可选)") {
                    TextField("备注", text: $note)
                        .font(.system(.body, design: .rounded))
                }

                if let amt = Double(amount), amt > 0 {
                    Section {
                        gainPreview(amount: amt)
                    } header: {
                        Text("自由增长预览")
                    } footer: {
                        Text("这笔收入对自由天数的回血效应。")
                            .font(.system(.caption2, design: .rounded))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("添加收入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isValid)
                        .foregroundStyle(isValid ? Color.skyDeep : Color.inkFaint)
                        .fontWeight(.medium)
                }
            }
        }
    }

    // ============================================================================
    // MARK: - 自由增长预览
    // ============================================================================

    /// 预览组件: 2 行 GAIN 显示(收入只影响资产和自由天数,不影响日均消费)
    private func gainPreview(amount: Double) -> some View {
        // ===== 当前快照 =====
        let currentAssets = assetsArr.first?.total ?? 0
        let firstDate = assetsArr.first?.firstRecordDate
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)

        let totalExp = expenses.reduce(0) { $0 + $1.amount }
        let currentTotalInc = incomes.reduce(0) { $0 + $1.amount }
        let currentAvg = FreedomMath.dailyBurn(totalExpenses: totalExp, trackDays: days)
        let currentNetSavings = currentTotalInc - totalExp
        let currentFreedom = FreedomMath.freedomDays(assets: currentAssets,
                                                     netSavings: currentNetSavings,
                                                     dailyBurn: currentAvg)

        // ===== 如果加这一笔收入 =====
        let newAssets = currentAssets + amount
        let newNetSavings = currentNetSavings + amount
        let newFreedom = FreedomMath.freedomDays(assets: newAssets,
                                                 netSavings: newNetSavings,
                                                 dailyBurn: currentAvg)  // 日均不变

        let freedomGain: Double = (currentFreedom.isInfinite || newFreedom.isInfinite)
            ? 0
            : (newFreedom - currentFreedom)

        return VStack(alignment: .leading, spacing: 10) {
            gainRow(label: "GAIN 1 储蓄",
                    from: formatYuan(currentAssets),
                    to: formatYuan(newAssets),
                    delta: "+\(formatYuan(amount))")

            gainRow(label: "GAIN 2 自由天数",
                    from: FreedomMath.freedomDaysDisplay(currentFreedom),
                    to: FreedomMath.freedomDaysDisplay(newFreedom),
                    delta: currentFreedom.isInfinite
                        ? "—"
                        : "+\(String(format: "%.0f", freedomGain)) 天")
        }
        .padding(.vertical, 4)
    }

    /// 单行 GAIN: silverline 风 — kicker / mono from → to / delta skyDeep
    /// 跟 KILL 朱砂对称,GAIN 用深天空蓝(收入主色)
    private func gainRow(label: String, from: String, to: String, delta: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            KickerLabel(text: label)
            HStack {
                Text("\(from) → \(to)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.ink)
                Spacer()
                Text(delta)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color.skyDeep)
            }
        }
    }

    /// 格式化金额: 同 AddExpenseSheet 里的实现(为简化没抽公共,允许重复)
    private func formatYuan(_ value: Double, precision: Int = 0) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = precision
        f.maximumFractionDigits = precision
        let s = f.string(from: NSNumber(value: value)) ?? String(format: "%.\(precision)f", value)
        return "¥\(s)"
    }

    /// 输入有效性: 金额>0 + 来源非空
    private var isValid: Bool {
        guard let v = Double(amount), v > 0 else { return false }
        return !source.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 保存: 创建 Income + 资产加金额 + 维护 firstRecordDate
    private func save() {
        guard let amt = Double(amount), amt > 0 else { return }

        let income = Income(amount: amt, source: source, isPassive: isPassive,
                            note: note, date: date)
        modelContext.insert(income)

        let assets: UserAssets
        if let existing = assetsArr.first {
            assets = existing
        } else {
            assets = UserAssets(total: 0)
            modelContext.insert(assets)
        }
        assets.total += amt   // 收入: 加资产(和支出的 -= 对称)
        assets.updatedAt = .now

        if assets.firstRecordDate == nil || date < assets.firstRecordDate! {
            assets.firstRecordDate = date
        }

        dismiss()
    }
}

// ============================================================================
// MARK: - SimulateSheet (模拟一笔 - 决策预演,不写数据库)
// ============================================================================
// 设计动机:lead-wealth 的核心差异化——"要不要买"之前先预演。
// 关键差异(对比 AddExpenseSheet / AddIncomeSheet):
// - 没有"保存"按钮,只有"关闭"
// - Segmented 切换"模拟支出 / 模拟收入"
// - 顶部 banner 明确提示"模拟模式,不会真实记账"
// - 视觉用紫色(和真实记账的红/绿区分)
// - 完全 read-only 计算,不调用 modelContext.insert

struct SimulateSheet: View {

    @Environment(\.dismiss) private var dismiss

    // 同样需要 @Query 当前数据,实时计算影响
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var assetsArr: [UserAssets]

    // ===== 模拟状态 =====
    @State private var amount: String = ""
    @State private var mode: Mode = .expense

    enum Mode: String, CaseIterable, Identifiable {
        case expense = "模拟支出"
        case income = "模拟收入"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    bannerCard
                    modePicker
                    amountInput
                    if let amt = Double(amount), amt > 0 {
                        previewCard(amount: amt)
                    } else {
                        hintCard
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("模拟决策")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
            }
        }
    }

    // ============================================================================
    // MARK: - 子组件
    // ============================================================================

    /// 顶部 banner: silverline 风 — 极淡 sky wash 底 + 深蓝字
    private var bannerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Color.skyDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text("模拟模式")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                Text("不会扣资产,不会写入账本,只是看看决策影响。")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer()
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.skyFaint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sky.opacity(0.3), lineWidth: 1)
        )
    }

    private var modePicker: some View {
        Picker("模拟类型", selection: $mode) {
            ForEach(Mode.allCases) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    /// 金额输入:VaultCard silverline 风
    private var amountInput: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                KickerLabel(text: mode == .expense ? "假设花掉 (元)" : "假设收入 (元)")
                HStack(spacing: 6) {
                    Text("¥")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                }
            }
        }
    }

    /// 未输入金额时的占位提示
    private var hintCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.inkFaint)
            Text("输入金额 · 实时看决策影响")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color.inkMuted)
        }
        .padding(.vertical, Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    /// 影响预览:VaultCard silverline
    private func previewCard(amount: Double) -> some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: mode == .expense ? "戴维斯三杀预览" : "自由增长预览")

                if mode == .expense {
                    expensePreview(amount: amount)
                } else {
                    incomePreview(amount: amount)
                }

                Text(mode == .expense
                     ? "这笔消费对自由天数的传导效应。"
                     : "这笔收入对自由天数的回血效应。")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }

    // ============================================================================
    // MARK: - 预览计算(支出 / 收入)
    // ============================================================================

    private func expensePreview(amount: Double) -> some View {
        let currentAssets = assetsArr.first?.total ?? 0
        let firstDate = assetsArr.first?.firstRecordDate
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)

        let currentTotalExp = expenses.reduce(0) { $0 + $1.amount }
        let totalInc = incomes.reduce(0) { $0 + $1.amount }
        let currentAvg = FreedomMath.dailyBurn(totalExpenses: currentTotalExp, trackDays: days)
        let currentNetSavings = totalInc - currentTotalExp
        let currentFreedom = FreedomMath.freedomDays(assets: currentAssets,
                                                     netSavings: currentNetSavings,
                                                     dailyBurn: currentAvg)

        let newAssets = currentAssets - amount
        let newAvg = FreedomMath.dailyBurn(totalExpenses: currentTotalExp + amount, trackDays: days)
        let newNetSavings = currentNetSavings - amount
        let newFreedom = FreedomMath.freedomDays(assets: newAssets,
                                                 netSavings: newNetSavings,
                                                 dailyBurn: newAvg)

        let freedomLoss: Double = currentFreedom.isInfinite ? 0 : (currentFreedom - newFreedom)

        return VStack(alignment: .leading, spacing: 10) {
            impactRow(label: "KILL 1 储蓄",
                      from: formatYuan(currentAssets),
                      to: formatYuan(newAssets),
                      delta: "−\(formatYuan(amount))",
                      color: Color.vermillion)

            impactRow(label: "KILL 2 日均",
                      from: formatYuan(currentAvg, precision: 1),
                      to: formatYuan(newAvg, precision: 2),
                      delta: "+\(formatYuan(newAvg - currentAvg, precision: 2))",
                      color: Color.vermillion)

            impactRow(label: "KILL 3 自由天数",
                      from: FreedomMath.freedomDaysDisplay(currentFreedom),
                      to: FreedomMath.freedomDaysDisplay(newFreedom),
                      delta: currentFreedom.isInfinite ? "—" : "−\(String(format: "%.1f", freedomLoss)) 天",
                      color: Color.vermillion)
        }
    }

    private func incomePreview(amount: Double) -> some View {
        let currentAssets = assetsArr.first?.total ?? 0
        let firstDate = assetsArr.first?.firstRecordDate
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)

        let totalExp = expenses.reduce(0) { $0 + $1.amount }
        let currentTotalInc = incomes.reduce(0) { $0 + $1.amount }
        let currentAvg = FreedomMath.dailyBurn(totalExpenses: totalExp, trackDays: days)
        let currentNetSavings = currentTotalInc - totalExp
        let currentFreedom = FreedomMath.freedomDays(assets: currentAssets,
                                                     netSavings: currentNetSavings,
                                                     dailyBurn: currentAvg)

        let newAssets = currentAssets + amount
        let newNetSavings = currentNetSavings + amount
        let newFreedom = FreedomMath.freedomDays(assets: newAssets,
                                                 netSavings: newNetSavings,
                                                 dailyBurn: currentAvg)

        let freedomGain: Double = (currentFreedom.isInfinite || newFreedom.isInfinite)
            ? 0 : (newFreedom - currentFreedom)

        return VStack(alignment: .leading, spacing: 10) {
            impactRow(label: "GAIN 1 储蓄",
                      from: formatYuan(currentAssets),
                      to: formatYuan(newAssets),
                      delta: "+\(formatYuan(amount))",
                      color: Color.skyDeep)

            impactRow(label: "GAIN 2 自由天数",
                      from: FreedomMath.freedomDaysDisplay(currentFreedom),
                      to: FreedomMath.freedomDaysDisplay(newFreedom),
                      delta: currentFreedom.isInfinite
                          ? "—"
                          : "+\(String(format: "%.1f", freedomGain)) 天",
                      color: Color.skyDeep)
        }
    }

    /// 通用影响行: silverline 风 — kicker + mono from → to + delta
    private func impactRow(label: String, from: String, to: String,
                           delta: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            KickerLabel(text: label)
            HStack {
                Text("\(from) → \(to)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.ink)
                Spacer()
                Text(delta)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(color)
            }
        }
    }

    /// 格式化金额(和 AddExpenseSheet/AddIncomeSheet 一致,允许局部重复)
    private func formatYuan(_ value: Double, precision: Int = 0) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = precision
        f.maximumFractionDigits = precision
        let s = f.string(from: NSNumber(value: value)) ?? String(format: "%.\(precision)f", value)
        return "¥\(s)"
    }
}

// ============================================================================
// MARK: - Preview
// ============================================================================

#Preview {
    ContentView()
        .modelContainer(for: [
            Expense.self, Income.self, Device.self,
            PassiveSource.self, UserAssets.self
        ], inMemory: true)
}
