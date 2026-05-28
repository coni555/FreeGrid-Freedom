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
    let count: Int
    let blueCells: Int
    let goldCells: Int

    @Environment(\.colorScheme) private var scheme

    /// 呼吸周期 (秒) — 2s 一来一回, 跟之前 .easeInOut(duration: 2.0) 行为一致
    private static let breathPeriod: TimeInterval = 2.0

    /// 从墙钟相位反算 breath ∈ [0, 1], 余弦形, 自然缓入缓出。
    /// 原 @State + onAppear + withAnimation(...).repeatForever() 在 iOS 17/18+
    /// 有 view-lifecycle 边界冻结的 regression, 改用 TimelineView(.animation)
    /// 函数式驱动 — 视图可见时刷帧, 不可见时系统自动暂停, 不存 @State, 不掉。
    private func breath(at date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        let phase = t.truncatingRemainder(dividingBy: Self.breathPeriod) / Self.breathPeriod
        // 0 → 1 → 0 余弦曲线 (半周期内从 0 上到 1, 下半周期再下到 0)
        return CGFloat(0.5 - 0.5 * cos(phase * 2 * .pi))
    }

    var body: some View {
        TimelineView(.animation) { context in
            let b = breath(at: context.date)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: unit.cellSize, maximum: unit.cellSize),
                                   spacing: unit.spacing)],
                spacing: unit.spacing
            ) {
                ForEach(0..<count, id: \.self) { i in
                    let isCurrent = (i == count - 1)
                    let isBlue = i >= blueCells
                    cell(isCurrent: isCurrent, isBlue: isBlue, breath: b)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(isCurrent: Bool, isBlue: Bool, breath: CGFloat) -> some View {
        let baseColor: Color = isBlue ? .assetBlue : .incomeGold
        let isDark = scheme == .dark

        let currentColor: Color = isDark
            ? (isBlue
                ? Color(red: 0.83, green: 0.92, blue: 1.00)
                : Color(red: 1.00, green: 0.92, blue: 0.65))
            : (isBlue
                ? Color(red: 0.20, green: 0.50, blue: 0.78)
                : Color(red: 0.72, green: 0.58, blue: 0.20))

        let innerGlowColor: Color = isDark
            ? Color.white
            : (isBlue
                ? Color(red: 0.15, green: 0.35, blue: 0.55)
                : Color(red: 0.55, green: 0.45, blue: 0.15))

        let innerOpacity: Double = isDark
            ? (0.5 + 0.3 * Double(breath))
            : (0.25 + 0.15 * Double(breath))
        let outerOpacity: Double = isDark
            ? (0.4 + 0.1 * Double(breath))
            : (0.30 + 0.10 * Double(breath))

        let peak: CGFloat = isDark ? 1.6 : 1.35
        let currentScale: CGFloat = 1.1 + (peak - 1.1) * breath
        let innerGlow: CGFloat = 4 + 3 * breath
        let outerGlow: CGFloat = 9 + 6 * breath

        if isCurrent {
            Rectangle()
                .fill(currentColor)
                .frame(width: unit.cellSize, height: unit.cellSize)
                .cornerRadius(unit.cellSize * 0.17)
                .shadow(color: innerGlowColor.opacity(innerOpacity), radius: innerGlow)
                .shadow(color: baseColor.opacity(outerOpacity), radius: outerGlow)
                .scaleEffect(currentScale)
                .zIndex(1)
        } else {
            Rectangle()
                .fill(baseColor)
                .frame(width: unit.cellSize, height: unit.cellSize)
                .cornerRadius(unit.cellSize * 0.11)
        }
    }
}

// ============================================================================
// MARK: - MeteorLayer (暗色模式天文台流星)
// ============================================================================
// 4 颗流星周期性飞过整屏背景, 拖尾用 LinearGradient 模拟 web 版 CSS .meteor
// (lead-wealth/app.html shoot keyframes). 用 TimelineView(.animation) 余弦相位
// 驱动 — 跟 LifeGrid 呼吸同套路, 不依赖 @State, 避免 iOS 17+ repeatForever 冻结。
// 装在 Dashboard background, isDarkMode 时显示。

private struct MeteorParam {
    let width: CGFloat
    let topRatio: CGFloat     // 起始 y / screenHeight
    let delay: TimeInterval   // 起跑延迟(秒)
    let duration: TimeInterval // 一个周期(秒)
}

private let meteorParams: [MeteorParam] = [
    .init(width: 90,  topRatio: 0.10, delay: 1.0, duration: 6.0),
    .init(width: 60,  topRatio: 0.30, delay: 3.5, duration: 8.0),
    .init(width: 110, topRatio: 0.20, delay: 6.0, duration: 5.0),
    .init(width: 45,  topRatio: 0.40, delay: 0.5, duration: 7.0),
]

struct MeteorLayer: View {
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    ForEach(0..<meteorParams.count, id: \.self) { i in
                        Meteor(param: meteorParams[i], time: t, screen: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Meteor: View {
    let param: MeteorParam
    let time: TimeInterval
    let screen: CGSize

    var body: some View {
        // phase 0->1 是一个周期
        let raw = (time - param.delay).truncatingRemainder(dividingBy: param.duration) / param.duration
        let p = CGFloat(raw < 0 ? raw + 1 : raw)

        let startX: CGFloat = -param.width
        let endX: CGFloat = screen.width + 50
        let x = startX + (endX - startX) * p
        let y = param.topRatio * screen.height + 30 * p   // 微微下沉, 模拟 web translateY(30px)

        // opacity 曲线匹配 web @keyframes shoot: 0->0.03 亮起到 0.9, 0.03->0.25 衰减到 0, 之后维持 0
        let opacity: Double = {
            if p < 0.03 { return 0.9 * Double(p / 0.03) }
            if p < 0.25 { return 0.9 * (1 - Double((p - 0.03) / 0.22)) }
            return 0
        }()

        return Rectangle()
            .fill(LinearGradient(
                colors: [
                    Color(red: 184.0/255, green: 216.0/255, blue: 255.0/255).opacity(0.8),
                    Color(red: 156.0/255, green: 195.0/255, blue: 255.0/255).opacity(0.3),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .frame(width: param.width, height: 1)
            .opacity(opacity)
            .offset(x: x, y: y)
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

    // ===== 撤销 Toast(刚刚记的一笔有 5 秒撤销窗口) =====
    /// 待撤销交易 ID, nil = 不显示 toast
    @State private var pendingUndoID: UUID? = nil
    /// toast 文案(含金额),已计算好
    @State private var pendingUndoLabel: String = ""
    /// 撤销的是支出还是收入(决定还原 cash 是 + 还是 −)
    @State private var pendingUndoIsExpense: Bool = true
    /// 5 秒倒计时 task,新 toast 进来时 cancel 旧的
    @State private var pendingUndoTimer: Task<Void, Never>? = nil

    // ===== 主题切换 (与 ContentView 共享同一 key) =====
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    /// Hero 布局偏好: "leading" (mockup hero-a, 副标左 + 数字右) 或 "vertical" (居中堆叠)
    @AppStorage("heroLayout") private var heroLayout: String = "leading"

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
            .background(
                ZStack {
                    Color.midnight
                    if isDarkMode {
                        MeteorLayer()
                    }
                }
                .ignoresSafeArea()
            )
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) {
                if pendingUndoID != nil {
                    undoToast
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseSheet(onSaved: { exp in
                    showUndoToast(id: exp.id, amount: exp.amount, isExpense: true)
                })
            }
            .sheet(isPresented: $showingAddIncome) {
                AddIncomeSheet(onSaved: { inc in
                    showUndoToast(id: inc.id, amount: inc.amount, isExpense: false)
                })
            }
            .sheet(isPresented: $showingSimulate) {
                SimulateSheet()
            }
        }
    }

    // ============================================================================
    // MARK: - 撤销 Toast UI + 逻辑
    // ============================================================================

    /// Toast bar: 1 个 dot + 文案 + 撤销链接, silverline mist 底
    private var undoToast: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(pendingUndoIsExpense ? Color.flame : Color.skyDeep)
                .frame(width: 6, height: 6)
            Text(pendingUndoLabel)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            Spacer()
            Button("撤销", action: undoLastTx)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.skyDeep)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous).fill(Color.mist)
        )
        .overlay(
            Capsule(style: .continuous).stroke(Color.hairlineSoft, lineWidth: 1)
        )
        .padding(.horizontal, Spacing.lg)
        .padding(.top, 6)
    }

    /// 启动 5 秒倒计时 toast(取消上一次 timer)
    private func showUndoToast(id: UUID, amount: Double, isExpense: Bool) {
        pendingUndoTimer?.cancel()

        let sign = isExpense ? "支出" : "收入"
        let formatted = amount.formatted(.number.precision(.fractionLength(0...0)))
        withAnimation(.spring(duration: 0.3)) {
            pendingUndoID = id
            pendingUndoLabel = "已记\(sign) ¥\(formatted)"
            pendingUndoIsExpense = isExpense
        }

        pendingUndoTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                pendingUndoID = nil
            }
        }
    }

    /// 撤销:按 ID 找到记录,删掉并还原 cash
    private func undoLastTx() {
        guard let id = pendingUndoID else { return }
        let assets = assetsArr.first

        if pendingUndoIsExpense {
            if let exp = expenses.first(where: { $0.id == id }) {
                assets?.cash += exp.amount
                modelContext.delete(exp)
            }
        } else {
            if let inc = incomes.first(where: { $0.id == id }) {
                assets?.cash -= inc.amount
                modelContext.delete(inc)
            }
        }
        assets?.updatedAt = .now

        pendingUndoTimer?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            pendingUndoID = nil
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

            // Hero 布局切换 toggle (leading 副标左数字右 ↔ vertical 居中堆叠)
            // 放在右侧 utility 区,跟左侧 dark mode toggle 形成两端 cluster
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    heroLayout = (heroLayout == "leading") ? "vertical" : "leading"
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.ink, lineWidth: 1)
                        .frame(width: 22, height: 22)
                    Image(systemName: heroLayout == "vertical"
                          ? "rectangle.split.1x2"
                          : "rectangle.split.2x1")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.sky)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(heroLayout == "vertical" ? "切换左右布局" : "切换居中堆叠布局")
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
            currentNetWorth: netWorth,
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
        }
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

            Text(freedomDaysDisplay)
                .font(.system(size: 110, weight: .ultraLight, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.ink)
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
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .padding(.vertical, -8)

            emphasized("你的", "自由", " 还能撑这么多\(heroSubUnit)", size: 18)

            if let d = deplete {
                Text("约 \(depleteDateString(d)) 见底")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .padding(.top, 2)
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
        let state = FreedomMath.gridState(lockedAssets: lockedAssets,
                                          cash: cashAmount,
                                          dailyBurn: dailyBurn)
        return VaultCard(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "Freedom Grid")
                    Spacer()
                    Text(gridSummary(state: state))
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.inkFaint)
                }

                if state.count == 0 {
                    emptyGridHint
                } else {
                    LifeGrid(unit: state.unit, count: state.count,
                             blueCells: state.blueDays, goldCells: state.yellowDays)
                        .padding(.vertical, Spacing.sm)
                }

                HStack(spacing: Spacing.lg) {
                    legendDot(color: .incomeGold, label: "资产")
                    legendDot(color: .assetBlue, label: "现金")
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

    private var userAssetsSingleton: UserAssets? {
        let a = assetsArr.first
        a?.migrateIfNeeded()
        return a
    }

    private var lockedAssets: Double {
        userAssetsSingleton?.lockedAssets ?? 0
    }

    private var cashAmount: Double {
        userAssetsSingleton?.cash ?? 0
    }

    private var netWorth: Double {
        lockedAssets + cashAmount
    }

    private var firstRecordDate: Date? {
        userAssetsSingleton?.firstRecordDate
    }

    private var totalExpenses: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    private var totalIncome: Double {
        incomes.reduce(0) { $0 + $1.amount }
    }

    private var trackDays: Int {
        guard let firstDate = firstRecordDate else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: firstDate, to: .now).day ?? 0
        return max(1, days + 1)
    }

    private var dailyBurn: Double {
        guard trackDays > 0 else { return 0 }
        return totalExpenses / Double(trackDays)
    }

    private var dailyPassive: Double {
        passiveSources.reduce(0) { $0 + $1.monthlyAmount / 30 }
    }

    private var passiveRatio: Double {
        guard dailyBurn > 0 else { return 0 }
        return dailyPassive / dailyBurn
    }

    private var freedomDays: Double {
        FreedomMath.freedomDays(netWorth: netWorth, dailyBurn: dailyBurn)
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
// 双桶: 资产(锁定/投资,金色) + 现金(可花,蓝色)。
// 净值 = 两桶之和(计算属性,无独立输入入口)。
// 用户点击桶卡片分别录入/修正,「调拨」用于桶间资金流转。
// 收入默认进现金,支出从现金扣。

struct AssetsView: View {
    @Query private var assetsArr: [UserAssets]
    @Environment(\.modelContext) private var modelContext

    // --- 双桶编辑 (sheet 模式) ---
    @State private var editingBucket: EditBucketSheet.Bucket? = nil

    // --- 调拨 ---
    @State private var transferAmount: String = ""
    @State private var transferDirection: TransferDirection = .cashToAssets

    enum TransferDirection: String, CaseIterable {
        case cashToAssets = "现金 → 资产"
        case assetsToCash = "资产 → 现金"
    }

    // --- 数据管理 ---
    @State private var showingFileImporter = false
    @State private var showingPurgeAlert = false
    @State private var importStatus: String? = nil
    @State private var pendingImport: DataIO.ImportPreview? = nil
    @State private var showingImportConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    bucketCards
                    if showEmptyHint { emptyHintCard }
                    transferCard
                    explainCard
                    dataManagementCard
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("Assets")
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("清空所有数据?", isPresented: $showingPurgeAlert) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { purgeData() }
            } message: {
                Text("将删除所有支出、收入、被动收入源、设备记录和资产数据。此操作不可撤销。")
            }
            .confirmationDialog(
                "导入策略",
                isPresented: $showingImportConfirm,
                titleVisibility: .visible
            ) {
                Button("替换当前净值") { commitImport(strategy: .replace) }
                Button("加到现金桶") { commitImport(strategy: .addToCash) }
                Button("只导入交易,不动净值") { commitImport(strategy: .skipAssets) }
                Button("取消", role: .cancel) { pendingImport = nil }
            } message: {
                if let p = pendingImport {
                    Text(importPreviewMessage(p))
                }
            }
            .sheet(item: $editingBucket) { bucket in
                EditBucketSheet(
                    bucket: bucket,
                    currentAmount: amountFor(bucket: bucket),
                    onSave: { newAmount in
                        applyBucketEdit(bucket: bucket, newAmount: newAmount)
                    }
                )
            }
        }
    }

    // MARK: - Hero: 净值总览
    private var heroCard: some View {
        VaultCard(emphasis: .high, padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "Net Worth · 净值")

                Text("¥" + currentNetWorth.formatted(.number))
                    .font(.system(size: 44, weight: .ultraLight, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .padding(.top, Spacing.xs)

                if let updated = assetsArr.first?.updatedAt, currentNetWorth > 0 {
                    Text("上次更新 · \(updated, format: .relative(presentation: .named))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                } else {
                    Text("点击下方桶卡片录入金额")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
            }
        }
    }

    // MARK: - 双桶: 资产 + 现金 (点击弹 sheet 编辑)
    private var bucketCards: some View {
        HStack(spacing: 12) {
            bucketCard(
                bucket: .assets,
                kicker: "资产",
                amount: lockedAssetsAmount,
                color: .incomeGold,
                icon: "lock.fill"
            )
            bucketCard(
                bucket: .cash,
                kicker: "现金",
                amount: cashAmount,
                color: .assetBlue,
                icon: "banknote"
            )
        }
    }

    private func bucketCard(bucket: EditBucketSheet.Bucket, kicker: String, amount: Double, color: Color, icon: String) -> some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundStyle(color)
                    KickerLabel(text: kicker)
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkFaint)
                }
                Text("¥" + amount.formatted(.number))
                    .font(.system(size: 24, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingBucket = bucket
        }
    }

    // MARK: - 空态提示
    private var showEmptyHint: Bool {
        currentNetWorth == 0
    }

    private var emptyHintCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 13))
                .foregroundStyle(Color.skyDeep)
            Text("点击上方桶卡片录入金额, 净值会自动相加")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
            Spacer()
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.skyFaint)
        )
    }

    // MARK: - 调拨
    private var transferCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "调拨")

                Picker("方向", selection: $transferDirection) {
                    ForEach(TransferDirection.allCases, id: \.self) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 6) {
                    Text("¥")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    TextField("0", text: $transferAmount)
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

                VaultButton(title: "确认调拨", icon: "arrow.left.arrow.right", style: .secondary) {
                    doTransfer()
                }
                .disabled(Double(transferAmount) == nil || (Double(transferAmount) ?? 0) <= 0)
                .opacity((Double(transferAmount) ?? 0) > 0 ? 1.0 : 0.4)
            }
        }
    }

    private var explainCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkFaint)
                Text("净值 · 资产 · 现金")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
            }

            Text("净值 = 资产 + 现金, 是自动相加的结果, 不能直接修改。资产 (金色) 是锁定的钱, 比如定期/股票/基金; 现金 (蓝色) 是可花的钱。收入默认进现金, 支出从现金扣。资产和现金之间用「调拨」移动。")
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

    // MARK: - 数据导入 (两步: preview → confirm → commit)
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importStatus = "未选择文件"
                return
            }
            guard url.startAccessingSecurityScopedResource() else {
                importStatus = "无法访问该文件"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let preview = try DataIO.previewJSON(data: data, context: modelContext)
                pendingImport = preview
                importStatus = nil
                showingImportConfirm = true
            } catch {
                importStatus = "✗ 解析失败: \(error.localizedDescription)"
            }
        case .failure(let error):
            importStatus = "✗ 文件读取失败: \(error.localizedDescription)"
        }
    }

    private func commitImport(strategy: DataIO.AssetsImportStrategy) {
        guard let preview = pendingImport else { return }
        do {
            let result = try DataIO.commitImport(preview: preview, strategy: strategy, context: modelContext)
            var lines: [String] = ["✓ 导入完成"]
            lines.append("支出 +\(result.expensesAdded) (\(preview.expensesSkipped) 重复跳过)")
            lines.append("收入 +\(result.incomesAdded) (\(preview.incomesSkipped) 重复跳过)")
            if result.passiveSourcesAdded > 0 {
                lines.append("被动源 +\(result.passiveSourcesAdded)")
            }
            switch strategy {
            case .replace:
                lines.append("净值已替换为 ¥\(Int(preview.jsonAssetsTotal))")
            case .addToCash:
                lines.append("现金 +¥\(Int(preview.jsonAssetsTotal))")
            case .skipAssets:
                lines.append("净值未变动")
            }
            importStatus = lines.joined(separator: "\n")
        } catch {
            importStatus = "✗ 写入失败: \(error.localizedDescription)"
        }
        pendingImport = nil
    }

    private func importPreviewMessage(_ p: DataIO.ImportPreview) -> String {
        let newExp = p.expensesNew.count
        let newInc = p.incomesNew.count
        let newPass = p.passiveSourcesNew.count
        var lines: [String] = []
        lines.append("新增 \(newExp) 笔支出 · \(newInc) 笔收入 · \(newPass) 个被动源")
        if p.expensesSkipped > 0 || p.incomesSkipped > 0 {
            lines.append("跳过重复: \(p.expensesSkipped) 支出 / \(p.incomesSkipped) 收入")
        }
        lines.append("")
        lines.append("JSON 净值: ¥\(Int(p.jsonAssetsTotal))")
        lines.append("当前: 资产 ¥\(Int(p.currentLockedAssets)) / 现金 ¥\(Int(p.currentCash))")
        return lines.joined(separator: "\n")
    }

    private func purgeData() {
        do {
            try DataIO.purgeAll(context: modelContext)
            editingBucket = nil
            transferAmount = ""
            importStatus = "✓ 已清空所有数据"
        } catch {
            importStatus = "✗ 清空失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 桶编辑 (sheet 回调)
    private func amountFor(bucket: EditBucketSheet.Bucket) -> Double {
        switch bucket {
        case .assets: return lockedAssetsAmount
        case .cash:   return cashAmount
        }
    }

    private func applyBucketEdit(bucket: EditBucketSheet.Bucket, newAmount: Double) {
        let assets = ensureUserAssets()
        switch bucket {
        case .assets: assets.lockedAssets = newAmount
        case .cash:   assets.cash = newAmount
        }
        assets.updatedAt = .now
    }

    // MARK: - 调拨实现
    private func doTransfer() {
        guard let amt = Double(transferAmount), amt > 0,
              let assets = assetsArr.first else { return }

        switch transferDirection {
        case .cashToAssets:
            let actual = min(amt, assets.cash)
            assets.cash -= actual
            assets.lockedAssets += actual
        case .assetsToCash:
            let actual = min(amt, assets.lockedAssets)
            assets.lockedAssets -= actual
            assets.cash += actual
        }
        assets.updatedAt = .now
        transferAmount = ""
    }

    // MARK: - 读写助手
    private var cashAmount: Double {
        assetsArr.first?.cash ?? 0
    }

    private var lockedAssetsAmount: Double {
        assetsArr.first?.lockedAssets ?? 0
    }

    private var currentNetWorth: Double {
        cashAmount + lockedAssetsAmount
    }

    private func ensureUserAssets() -> UserAssets {
        if let existing = assetsArr.first { return existing }
        let new = UserAssets(total: 0)
        new.firstRecordDate = .now
        modelContext.insert(new)
        return new
    }
}

// ============================================================================
// MARK: - EditBucketSheet (双桶金额编辑)
// ============================================================================
// 设计动机: AssetsView 双桶 (资产/现金) 的金额需要独立录入/修正。
// 历史上试过 inline 编辑 (TextField 嵌在并列卡片里), 视觉不明 + layout 抖动,
// 改成底部 sheet — 跟 AddIncomeSheet / AddExpenseSheet 一致风格, 编辑态彻底
// 跟主界面分离, 大数字输入 + 当前值参考 + silverline 卡片底, 心智成本低。
//
// 用法: AssetsView 持有 @State editingBucket: Bucket?, 点桶卡片 = set Bucket,
// .sheet(item:) 触发本 view, onSave 回调把新值写回 UserAssets。

struct EditBucketSheet: View {

    enum Bucket: String, Identifiable {
        case assets, cash
        var id: String { rawValue }
        var label: String { self == .assets ? "资产" : "现金" }
        var hint: String {
            self == .assets
                ? "锁定的钱 — 定期 / 股票 / 基金 / 不动产等"
                : "可花的钱 — 活期 / 钱包余额 / 微信支付宝"
        }
        var color: Color { self == .assets ? .incomeGold : .assetBlue }
        var icon: String { self == .assets ? "lock.fill" : "banknote" }
    }

    let bucket: Bucket
    let currentAmount: Double
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // ===== 当前金额参考 =====
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: 4) {
                            Image(systemName: bucket.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(bucket.color)
                            KickerLabel(text: "当前 \(bucket.label)")
                        }
                        Text("¥" + currentAmount.formatted(.number))
                            .font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkMuted)
                    }

                    // ===== 新金额输入 =====
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "新金额")

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("¥")
                                .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                            TextField("0", text: $amount)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 40, weight: .ultraLight, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.ink)
                                .focused($fieldFocused)
                                .submitLabel(.done)
                                .onSubmit { save() }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.skyDeep.opacity(0.45), lineWidth: 1)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.skyFaint.opacity(0.4))
                        )

                        // delta 预览: 写新金额后实时显示净值变化
                        if let new = Double(amount), new != currentAmount {
                            HStack(spacing: 4) {
                                Image(systemName: new > currentAmount ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 10))
                                Text("\(new > currentAmount ? "+" : "")\((new - currentAmount).formatted(.number)) 元")
                                    .font(.system(.caption, design: .rounded).monospacedDigit())
                            }
                            .foregroundStyle(new > currentAmount ? Color.skyDeep : Color.inkMuted)
                            .padding(.top, 2)
                        }
                    }

                    // ===== 说明 =====
                    Text(bucket.hint)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("编辑\(bucket.label)")
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
            .onAppear {
                // 不预填 — 用户看到"当前 ¥X"作为参考再录入新值, 心智更清晰。
                // 自动聚焦让键盘立即弹出, 减少点击次数。
                fieldFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var isValid: Bool {
        guard let v = Double(amount), v >= 0 else { return false }
        return true
    }

    private func save() {
        guard let v = Double(amount), v >= 0 else { return }
        onSave(v)
        dismiss()
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

    /// 导入结果统计, UI 用来展示反馈
    struct ImportResult {
        let expensesAdded: Int
        let incomesAdded: Int
        let passiveSourcesAdded: Int
        let assetsTotal: Double
        let firstRecordDate: Date?
    }

    /// 导入预览: previewJSON 算出来交给 UI, UI 弹确认对话框, 用户选 strategy 后调 commitImport
    struct ImportPreview {
        let expensesNew: [LumenDataJSON.ExpenseJSON]
        let expensesSkipped: Int
        let incomesNew: [LumenDataJSON.IncomeJSON]
        let incomesSkipped: Int
        let passiveSourcesNew: [LumenDataJSON.PassiveSourceJSON]
        let jsonAssetsTotal: Double
        let jsonAssetsUpdatedAt: Date?
        let jsonFirstRecordDate: Date?
        let currentCash: Double
        let currentLockedAssets: Double
    }

    /// 导入时如何对待 UserAssets (现金/资产桶):
    /// - replace: 用 JSON.total 整体替换, lockedAssets 清零, cash = JSON.total
    /// - addToCash: cash += JSON.total, lockedAssets 不动
    /// - skipAssets: 完全不动两桶, 只导入交易记录
    enum AssetsImportStrategy {
        case replace
        case addToCash
        case skipAssets
    }

    /// 第一步: 解析 JSON, 用 (date|amount|category-or-source|note) 做去重, 但不写入 context。
    static func previewJSON(data: Data, context: ModelContext) throws -> ImportPreview {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dump = try decoder.decode(LumenDataJSON.self, from: data)

        // ===== 现有数据的去重 key =====
        let existingExp = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let existingExpKeys = Set(existingExp.map {
            expenseKey(amount: $0.amount, date: $0.date, category: $0.category, note: $0.note)
        })

        let existingInc = (try? context.fetch(FetchDescriptor<Income>())) ?? []
        let existingIncKeys = Set(existingInc.map {
            incomeKey(amount: $0.amount, date: $0.date, source: $0.source, note: $0.note)
        })

        let existingPass = (try? context.fetch(FetchDescriptor<PassiveSource>())) ?? []
        let existingPassKeys = Set(existingPass.map { passiveKey(name: $0.name, monthlyAmount: $0.monthlyAmount) })

        // ===== 过滤 expenses =====
        var expensesNew: [LumenDataJSON.ExpenseJSON] = []
        var expSkipped = 0
        for e in dump.expenses ?? [] {
            let d = parseDate(e.date) ?? .now
            let k = expenseKey(amount: e.amount, date: d, category: e.category, note: e.note ?? "")
            if existingExpKeys.contains(k) {
                expSkipped += 1
            } else {
                expensesNew.append(e)
            }
        }

        // ===== 过滤 incomes =====
        var incomesNew: [LumenDataJSON.IncomeJSON] = []
        var incSkipped = 0
        for i in dump.incomes ?? [] {
            let d = parseDate(i.date) ?? .now
            let k = incomeKey(amount: i.amount, date: d, source: i.source, note: i.note ?? "")
            if existingIncKeys.contains(k) {
                incSkipped += 1
            } else {
                incomesNew.append(i)
            }
        }

        // ===== 过滤 passive sources =====
        var passNew: [LumenDataJSON.PassiveSourceJSON] = []
        for p in dump.passiveSources ?? [] {
            let k = passiveKey(name: p.name, monthlyAmount: p.monthlyAmount)
            if !existingPassKeys.contains(k) {
                passNew.append(p)
            }
        }

        let existingAssets = try? context.fetch(FetchDescriptor<UserAssets>()).first

        return ImportPreview(
            expensesNew: expensesNew,
            expensesSkipped: expSkipped,
            incomesNew: incomesNew,
            incomesSkipped: incSkipped,
            passiveSourcesNew: passNew,
            jsonAssetsTotal: dump.assets?.total ?? 0,
            jsonAssetsUpdatedAt: dump.assets?.updatedAt.flatMap { parseISO($0) },
            jsonFirstRecordDate: dump.firstRecordDate.flatMap { parseDate($0) },
            currentCash: existingAssets?.cash ?? 0,
            currentLockedAssets: existingAssets?.lockedAssets ?? 0
        )
    }

    /// 第二步: 接受 preview + 用户选的 strategy, 写入 context。
    /// expenses / incomes / passive 只插入 preview 里筛剩的 new 行 (跳过重复)。
    static func commitImport(
        preview: ImportPreview,
        strategy: AssetsImportStrategy,
        context: ModelContext
    ) throws -> ImportResult {
        // ===== expenses =====
        var expCount = 0
        for e in preview.expensesNew {
            let exp = Expense(
                amount: e.amount,
                category: e.category,
                note: e.note ?? "",
                date: parseDate(e.date) ?? .now
            )
            if let createdAt = e.createdAt, let d = parseISO(createdAt) {
                exp.createdAt = d
            }
            context.insert(exp)
            expCount += 1
        }

        // ===== incomes =====
        var incCount = 0
        for i in preview.incomesNew {
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

        // ===== passive sources =====
        var passCount = 0
        for p in preview.passiveSourcesNew {
            context.insert(PassiveSource(name: p.name, monthlyAmount: p.monthlyAmount))
            passCount += 1
        }

        // ===== UserAssets 按 strategy 处理 =====
        let existing = try? context.fetch(FetchDescriptor<UserAssets>()).first
        let userAssets: UserAssets
        if let existing = existing {
            userAssets = existing
        } else {
            userAssets = UserAssets(total: 0)
            context.insert(userAssets)
        }

        switch strategy {
        case .replace:
            // 净值整体替换 → firstRecordDate 也一并换成 JSON 的(不保留本地 baseline,
            // 否则会出现"净值是 JSON 的, 起算日是本地的"这种半新半旧状态)
            userAssets.lockedAssets = 0
            userAssets.cash = preview.jsonAssetsTotal
            userAssets.updatedAt = preview.jsonAssetsUpdatedAt ?? .now
            if let jsonDate = preview.jsonFirstRecordDate {
                userAssets.firstRecordDate = jsonDate
            }
        case .addToCash, .skipAssets:
            // 合并/跳过模式: 起算日取 (本地, JSON) 较早者, 本地为空时用 JSON
            if let jsonDate = preview.jsonFirstRecordDate {
                if let cur = userAssets.firstRecordDate {
                    userAssets.firstRecordDate = min(cur, jsonDate)
                } else {
                    userAssets.firstRecordDate = jsonDate
                }
            }
            if strategy == .addToCash {
                userAssets.cash += preview.jsonAssetsTotal
                userAssets.updatedAt = .now
            }
            // .skipAssets: 不动 cash / lockedAssets / updatedAt
        }

        return ImportResult(
            expensesAdded: expCount,
            incomesAdded: incCount,
            passiveSourcesAdded: passCount,
            assetsTotal: preview.jsonAssetsTotal,
            firstRecordDate: preview.jsonFirstRecordDate
        )
    }

    /// 清空所有数据(包括 UserAssets 单例)
    static func purgeAll(context: ModelContext) throws {
        try context.delete(model: Expense.self)
        try context.delete(model: Income.self)
        try context.delete(model: Device.self)
        try context.delete(model: PassiveSource.self)
        try context.delete(model: UserAssets.self)
    }

    // ===== 内部: 去重 key =====
    // 设计动机: web 版导出的 JSON 没有稳定 UUID, 反复导入同一文件会重复扣账。
    // 用 (date 精确到当地日, amount, category/source, note) 组合做幂等 key。
    // 同一天同金额同分类同备注的两笔, 视为重复 — 这在真实场景下误判率可接受。

    private static func expenseKey(amount: Double, date: Date, category: String, note: String) -> String {
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(day)|\(amount)|\(category)|\(note)"
    }

    private static func incomeKey(amount: Double, date: Date, source: String, note: String) -> String {
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(day)|\(amount)|\(source)|\(note)"
    }

    private static func passiveKey(name: String, monthlyAmount: Double) -> String {
        return "\(name)|\(monthlyAmount)"
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

    /// 分类二级筛选: nil 表示全部分类。仅在 filter == .expense 时有意义,
    /// 切到 .all / .income 时自动清空。
    @State private var selectedCategory: String? = nil

    /// 撤销 confirm: 点行右侧 × 时 set, alert 触发, 取消/确认后清空
    @State private var pendingDelete: TxKind? = nil

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
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, Spacing.sm)
                .onChange(of: filter) { _, newValue in
                    // 切出支出 tab 时清掉分类二级筛选
                    if newValue != .expense { selectedCategory = nil }
                }

                // ===== 分类汇总条 (仅支出 tab) =====
                if filter == .expense && !expenseCategoryTotals.isEmpty {
                    categoryChipRow
                        .padding(.bottom, Spacing.sm)
                }

                if filteredTransactions.isEmpty {
                    emptyState
                } else {
                    transactionList
                }
            }
            .background(Color.paper)
            .navigationTitle("History")
            .alert(
                "撤销这笔记录?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { tx in
                Button("撤销", role: .destructive) { confirmDelete(tx) }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: { tx in
                Text(deleteMessage(tx))
            }
        }
    }

    // ============================================================================
    // MARK: - 分类汇总条
    // ============================================================================

    /// 横滑 chip 列表: 首"全部"chip + 各分类 chip, 每 chip 显示分类名 + 总额
    private var categoryChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(
                    label: "全部",
                    amount: expenseCategoryTotals.reduce(0) { $0 + $1.total },
                    selected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }
                ForEach(expenseCategoryTotals, id: \.category) { item in
                    categoryChip(
                        label: item.category,
                        amount: item.total,
                        selected: selectedCategory == item.category
                    ) {
                        // 二次点击同一 chip = 取消选中
                        selectedCategory = (selectedCategory == item.category) ? nil : item.category
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func categoryChip(label: String, amount: Double, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(.caption2, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(selected ? Color.paper : Color.inkMuted)
                Text("¥" + amount.formatted(.number.precision(.fractionLength(0...0))))
                    .font(.system(.callout, design: .rounded).weight(.medium).monospacedDigit())
                    .foregroundStyle(selected ? Color.paper : Color.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.ink : Color.mist)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.hairlineSoft, lineWidth: selected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// 各支出分类总额,降序排列
    private var expenseCategoryTotals: [(category: String, total: Double)] {
        let grouped = Dictionary(grouping: expenses, by: { $0.category })
        return grouped
            .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
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

    /// 支出行:朱砂金额 + 分类 + 备注 + 日期 (silverline rounded), 右侧 × 触发撤销 alert
    private func expenseRow(_ e: Expense) -> some View {
        HStack(alignment: .top, spacing: 10) {
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
            deleteButton(for: .expense(e))
        }
        .padding(.vertical, 4)
    }

    /// 收入行:深天空蓝金额 + 来源 + 被动标签 + 备注 + 日期
    /// (silverline:跟"记收入"按钮同色统一)
    private func incomeRow(_ i: Income) -> some View {
        HStack(alignment: .top, spacing: 10) {
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
            deleteButton(for: .income(i))
        }
        .padding(.vertical, 4)
    }

    /// 行右侧 × 撤销按钮: silverline outline 圆, 点击 set pendingDelete 触发 alert
    private func deleteButton(for tx: TxKind) -> some View {
        Button {
            pendingDelete = tx
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.inkFaint)
                .frame(width: 22, height: 22)
                .background(
                    Circle().stroke(Color.hairlineSoft, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("撤销这笔")
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
            // selectedCategory != nil 时仅取该分类的支出(只可能在 filter == .expense 时发生)
            let exps = selectedCategory.map { cat in expenses.filter { $0.category == cat } } ?? expenses
            all.append(contentsOf: exps.map { .expense($0) })
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

    // ============================================================================
    // MARK: - 撤销 confirm 消息 + 执行
    // ============================================================================
    // 设计跟 lead-wealth deleteTx() 对齐: alert 文案显式列出"哪一天 / 类别 / 金额 /
    // 资产会反向 +/− XXX 元", 用户明确知道这次操作会改什么再确认。

    private func deleteMessage(_ tx: TxKind) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        switch tx {
        case .expense(let e):
            let dateStr = df.string(from: e.date)
            let amt = e.amount.formatted(.number.precision(.fractionLength(0...2)))
            let noteStr = e.note.isEmpty ? "" : " · \(e.note)"
            return """
            \(dateStr) · \(e.category)\(noteStr)
            −¥\(amt)

            现金会反向恢复 ¥\(amt)
            """
        case .income(let i):
            let dateStr = df.string(from: i.date)
            let amt = i.amount.formatted(.number.precision(.fractionLength(0...2)))
            let noteStr = i.note.isEmpty ? "" : " · \(i.note)"
            return """
            \(dateStr) · \(i.source)\(noteStr)
            +¥\(amt)

            现金会反向减少 ¥\(amt)
            """
        }
    }

    /// 确认撤销: 反向调整 cash + 删除记录 (跟 web 版 deleteTx 同 path)
    private func confirmDelete(_ tx: TxKind) {
        let assets = assetsArr.first
        switch tx {
        case .expense(let e):
            assets?.cash += e.amount
            modelContext.delete(e)
        case .income(let i):
            assets?.cash -= i.amount
            modelContext.delete(i)
        }
        assets?.updatedAt = .now
        pendingDelete = nil
    }
}

// ============================================================================
// MARK: - CheckView (财富自由自检清单)
// ============================================================================
// 8 项自检源自 lead-wealth web 版 SELF_CHECKS, 全部从现有 SwiftData @Query +
// FreedomMath helper 反推, 不引入新状态。每项即时计算, 数据变化自动重算。

struct CheckView: View {

    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]

    private struct ChecklistItem {
        let title: String
        let done: Bool
    }

    /// 8 项自检 — 顺序、阈值跟 web 版完全对齐
    private var items: [ChecklistItem] {
        let firstDate = assetsArr.first?.firstRecordDate
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)
        let totalExp = expenses.reduce(0) { $0 + $1.amount }
        let dailyBurn = FreedomMath.dailyBurn(totalExpenses: totalExp, trackDays: days)
        let netWorth = (assetsArr.first?.lockedAssets ?? 0) + (assetsArr.first?.cash ?? 0)
        let freedom = FreedomMath.freedomDays(netWorth: netWorth, dailyBurn: dailyBurn)
        let dailyPassive = FreedomMath.dailyPassive(sources: passiveSources)
        let passiveRatio = FreedomMath.passiveRatio(dailyPassive: dailyPassive, dailyBurn: dailyBurn)

        return [
            ChecklistItem(title: "记录天数超过 30 天", done: days >= 30),
            ChecklistItem(title: "了解自己的日均消费", done: days >= 7 && dailyBurn > 0),
            ChecklistItem(title: "记录了可变现资产", done: netWorth > 0),
            ChecklistItem(title: "自由天数超过 180 天", done: freedom >= 180),
            ChecklistItem(title: "自由天数超过 365 天", done: freedom >= 365),
            ChecklistItem(title: "有被动收入来源", done: !passiveSources.isEmpty),
            ChecklistItem(title: "被动覆盖率超过 50%", done: passiveRatio >= 0.5),
            ChecklistItem(title: "被动收入覆盖日常消费 (≥100%)", done: passiveRatio >= 1.0),
        ]
    }

    private var completedCount: Int { items.filter(\.done).count }
    private var progress: Double { Double(completedCount) / Double(items.count) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    heroCard
                    checklistCard
                    footnote
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("Check")
        }
    }

    // MARK: - Hero 进度卡

    private var heroCard: some View {
        VaultCard(emphasis: .high, padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "Freedom Checklist")

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(completedCount)")
                        .font(.system(size: 56, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                    Text("/ \(items.count)")
                        .font(.system(size: 22, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(.callout, design: .monospaced).monospacedDigit())
                        .foregroundStyle(Color.skyDeep)
                }

                // 进度长条 silverline 风
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.mist)
                        Capsule()
                            .fill(Color.skyDeep)
                            .frame(width: max(2, geo.size.width * progress))
                    }
                }
                .frame(height: 4)

                Text("达成项越多,离财富自由越近")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }

    // MARK: - 8 项列表卡

    private var checklistCard: some View {
        VaultCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    checklistRow(idx: idx, item: item)
                        .padding(.horizontal, Spacing.lg)
                    if idx < items.count - 1 {
                        Hairline().padding(.leading, Spacing.lg + 30)
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func checklistRow(idx: Int, item: ChecklistItem) -> some View {
        HStack(spacing: 12) {
            // 状态点: 达成 = sky 实心 + 勾, 未达成 = outline
            ZStack {
                Circle()
                    .stroke(item.done ? Color.skyDeep : Color.inkFaint.opacity(0.6), lineWidth: 1.2)
                    .frame(width: 18, height: 18)
                if item.done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.skyDeep)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(idx + 1). \(item.title)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(item.done ? Color.ink : Color.inkMuted)
                    .strikethrough(item.done, color: Color.inkFaint)
                Text(item.done ? "已达成" : "未达成")
                    .font(.system(.caption2, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(item.done ? Color.skyDeep : Color.inkFaint)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footnote: some View {
        Text("自检规则源自 lead-wealth · 数据从记录自动反推, 不需手动勾选")
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Color.inkFaint)
            .multilineTextAlignment(.center)
            .padding(.top, Spacing.xs)
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

    /// 保存成功回调 — DashboardView 用它显示 5 秒撤销 toast
    var onSaved: ((Expense) -> Void)? = nil

    // 预览需要读所有现有数据,实时算"如果加这一笔,自由天数变化"
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var assetsArr: [UserAssets]

    @State private var amount: String = ""
    @State private var category: String = "早餐"
    @State private var note: String = ""
    @State private var date: Date = .now

    /// 分类清单。"人情"/"日用" 用户反馈日常用不到,2026-05 移除。
    /// 旧记录里的"人情"/"日用"仍能在 History 正常显示,只是 Picker 选不到了。
    private let categories = ["早餐", "午餐", "晚餐", "购物", "交通", "娱乐",
                              "成长投资", "医疗", "其他"]

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

    private func impactPreview(amount: Double) -> some View {
        let currentNW = (assetsArr.first?.lockedAssets ?? 0) + (assetsArr.first?.cash ?? 0)
        let firstDate = assetsArr.first?.firstRecordDate
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)

        let currentTotalExp = expenses.reduce(0) { $0 + $1.amount }
        let currentAvg = FreedomMath.dailyBurn(totalExpenses: currentTotalExp, trackDays: days)
        let currentFreedom = FreedomMath.freedomDays(netWorth: currentNW, dailyBurn: currentAvg)

        let newNW = currentNW - amount
        let newAvg = FreedomMath.dailyBurn(totalExpenses: currentTotalExp + amount, trackDays: days)
        let newFreedom = FreedomMath.freedomDays(netWorth: newNW, dailyBurn: newAvg)

        let freedomLoss: Double = currentFreedom.isInfinite ? 0 : (currentFreedom - newFreedom)

        return VStack(alignment: .leading, spacing: 10) {
            killRow(label: "KILL 1 净值",
                    from: formatYuan(currentNW),
                    to: formatYuan(newNW),
                    delta: "−\(formatYuan(amount))")

            killRow(label: "KILL 2 日均",
                    from: formatYuan(currentAvg, precision: 1),
                    to: formatYuan(newAvg, precision: 2),
                    delta: "+\(formatYuan(newAvg - currentAvg, precision: 2))")

            // KILL 3: from/to 智能档跟 hero 一致 (42.7 年), delta 固定整数天直观 (−1 天)
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
        assets.cash -= amt
        assets.updatedAt = .now

        if assets.firstRecordDate == nil || date < assets.firstRecordDate! {
            assets.firstRecordDate = date
        }

        onSaved?(expense)
        dismiss()
    }
}

// ============================================================================
// MARK: - AddIncomeSheet (添加收入的模态弹窗)
// ============================================================================

struct AddIncomeSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// 保存成功回调 — DashboardView 用它显示 5 秒撤销 toast
    var onSaved: ((Income) -> Void)? = nil

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

    private func gainPreview(amount: Double) -> some View {
        let currentNW = (assetsArr.first?.lockedAssets ?? 0) + (assetsArr.first?.cash ?? 0)
        let firstDate = assetsArr.first?.firstRecordDate
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)

        let totalExp = expenses.reduce(0) { $0 + $1.amount }
        let currentAvg = FreedomMath.dailyBurn(totalExpenses: totalExp, trackDays: days)
        let currentFreedom = FreedomMath.freedomDays(netWorth: currentNW, dailyBurn: currentAvg)

        let newNW = currentNW + amount
        let newFreedom = FreedomMath.freedomDays(netWorth: newNW, dailyBurn: currentAvg)

        let freedomGain: Double = (currentFreedom.isInfinite || newFreedom.isInfinite)
            ? 0 : (newFreedom - currentFreedom)

        return VStack(alignment: .leading, spacing: 10) {
            gainRow(label: "GAIN 1 净值",
                    from: formatYuan(currentNW),
                    to: formatYuan(newNW),
                    delta: "+\(formatYuan(amount))")

            // from/to 智能档, delta 固定天 (跟 KILL 3 一致)
            gainRow(label: "GAIN 2 自由天数",
                    from: FreedomMath.freedomDaysDisplay(currentFreedom),
                    to: FreedomMath.freedomDaysDisplay(newFreedom),
                    delta: currentFreedom.isInfinite ? "—" : "+\(String(format: "%.0f", freedomGain)) 天")
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
        assets.cash += amt
        assets.updatedAt = .now

        if assets.firstRecordDate == nil || date < assets.firstRecordDate! {
            assets.firstRecordDate = date
        }

        onSaved?(income)
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
        let currentNW = (assetsArr.first?.lockedAssets ?? 0) + (assetsArr.first?.cash ?? 0)
        let firstDate = assetsArr.first?.firstRecordDate
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)

        let currentTotalExp = expenses.reduce(0) { $0 + $1.amount }
        let currentAvg = FreedomMath.dailyBurn(totalExpenses: currentTotalExp, trackDays: days)
        let currentFreedom = FreedomMath.freedomDays(netWorth: currentNW, dailyBurn: currentAvg)

        let newNW = currentNW - amount
        let newAvg = FreedomMath.dailyBurn(totalExpenses: currentTotalExp + amount, trackDays: days)
        let newFreedom = FreedomMath.freedomDays(netWorth: newNW, dailyBurn: newAvg)

        let freedomLoss: Double = currentFreedom.isInfinite ? 0 : (currentFreedom - newFreedom)

        return VStack(alignment: .leading, spacing: 10) {
            impactRow(label: "KILL 1 净值",
                      from: formatYuan(currentNW),
                      to: formatYuan(newNW),
                      delta: "−\(formatYuan(amount))",
                      color: Color.vermillion)

            impactRow(label: "KILL 2 日均",
                      from: formatYuan(currentAvg, precision: 1),
                      to: formatYuan(newAvg, precision: 2),
                      delta: "+\(formatYuan(newAvg - currentAvg, precision: 2))",
                      color: Color.vermillion)

            // from/to 智能档, delta 固定天
            impactRow(label: "KILL 3 自由天数",
                      from: FreedomMath.freedomDaysDisplay(currentFreedom),
                      to: FreedomMath.freedomDaysDisplay(newFreedom),
                      delta: currentFreedom.isInfinite ? "—" : "−\(String(format: "%.0f", freedomLoss)) 天",
                      color: Color.vermillion)
        }
    }

    private func incomePreview(amount: Double) -> some View {
        let currentNW = (assetsArr.first?.lockedAssets ?? 0) + (assetsArr.first?.cash ?? 0)
        let firstDate = assetsArr.first?.firstRecordDate
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)

        let totalExp = expenses.reduce(0) { $0 + $1.amount }
        let currentAvg = FreedomMath.dailyBurn(totalExpenses: totalExp, trackDays: days)
        let currentFreedom = FreedomMath.freedomDays(netWorth: currentNW, dailyBurn: currentAvg)

        let newNW = currentNW + amount
        let newFreedom = FreedomMath.freedomDays(netWorth: newNW, dailyBurn: currentAvg)

        let freedomGain: Double = (currentFreedom.isInfinite || newFreedom.isInfinite)
            ? 0 : (newFreedom - currentFreedom)

        return VStack(alignment: .leading, spacing: 10) {
            impactRow(label: "GAIN 1 净值",
                      from: formatYuan(currentNW),
                      to: formatYuan(newNW),
                      delta: "+\(formatYuan(amount))",
                      color: Color.skyDeep)

            // from/to 智能档, delta 固定天
            impactRow(label: "GAIN 2 自由天数",
                      from: FreedomMath.freedomDaysDisplay(currentFreedom),
                      to: FreedomMath.freedomDaysDisplay(newFreedom),
                      delta: currentFreedom.isInfinite ? "—" : "+\(String(format: "%.0f", freedomGain)) 天",
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
