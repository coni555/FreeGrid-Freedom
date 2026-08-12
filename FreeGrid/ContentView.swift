//
//  ContentView.swift
//  FreeGrid
//
//  Phase 2 架构: TabView 4 Tab 主框架。
//  - Dashboard: Freedom Days + 三联卡 + 收支记录按钮
//  - Assets: 资产总额管理(Freedom Days 的基准)
//  - History: 历史记录(占位,下一轮实现)
//  - Settings: 设置(顶部自检收缩卡 + 外观/关于/支持)
//
//  设计原则:
//  - 每个 Tab 独立 NavigationStack,各自的 navigationTitle
//  - 数据通过 @Query 自动反应式同步,任何 Tab 改数据,其他 Tab 数字自动更新
//  - Sheet 表单(添加支出/收入)用模态弹窗,符合 iOS 原生交互
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers   // 提供 .json UTType,供 fileImporter 使用
#if os(iOS)
import UIKit                    // iOS: 导出分享面板 UIActivityViewController + UIPasteboard
#elseif canImport(AppKit)
import AppKit                   // macOS: NSPasteboard(复制 ICP 备案号)
#endif

// ============================================================================
// MARK: - Color(hex:) (颜色扩展)
// ============================================================================
// SwiftUI 没有内置 hex 颜色构造器,加一个方便用 早期 web 版的色板
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
// (早期 web 版 shoot keyframes). 用 TimelineView(.animation) 余弦相位
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

private enum AppTab: Hashable {
    case dashboard
    case assets
    case history
    case settings
}

struct ContentView: View {
    /// 跨启动持久化主题选择
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @State private var selectedTab: AppTab = .dashboard

    #if os(macOS)
    @Environment(MenuActions.self) private var menuActions
    #endif

    var body: some View {
        #if os(macOS)
        @Bindable var actions = menuActions
        return tabView
            // 菜单栏 ⌘N / ⌘⇧N 在根层唤起快速记账(任意 Tab 下可用)
            .sheet(isPresented: $actions.addExpense) {
                AddExpenseSheet(onSaved: { _ in })
            }
            .sheet(isPresented: $actions.addIncome) {
                AddIncomeSheet(onSaved: { _ in })
            }
        #else
        return tabView
        #endif
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            DashboardView(onOpenAssets: {
                selectedTab = .assets
            })
                .tabItem {
                    Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(AppTab.dashboard)

            AssetsView()
                .tabItem {
                    Label("Assets", systemImage: "banknote")
                }
                .tag(AppTab.assets)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(AppTab.history)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
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
// 对应 早期 web 版的 Dashboard tab
// 核心: Hero (Freedom Days) + 三联卡 + 收支按钮

struct DashboardView: View {

    let onOpenAssets: () -> Void

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

    /// 首次引导的一次性闸门:存款与支出齐备过一次即永久落闸
    @AppStorage("onboardingCompleted") private var onboardingCompleted: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    topBar           // 圆点 + FreeGrid + 副标
                    heroSection      // Freedom Days 巨大数字 hero
                    if needsOnboarding {
                        onboardingPrompt // 存款与支出齐备后自动消失
                    }
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
            .hideNavBar()
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
            .onAppear { latchOnboardingIfSatisfied() }
            .onChange(of: onboardingSatisfied) { _, _ in latchOnboardingIfSatisfied() }
        }
    }

    /// 只单向落闸,不会再打开——净值以后跌回 0 以下也不重新弹引导。
    private func latchOnboardingIfSatisfied() {
        if onboardingSatisfied { onboardingCompleted = true }
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
        let formatted = amount.formatted(.number.precision(.fractionLength(0...2)))
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
                assets?.firstRecordDate = FreedomMath.earliestExpenseDate(
                    expenses.filter { $0.id != id }
                )
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

            VStack(alignment: .leading, spacing: 1) {
                Text("FreeGrid")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                Text("通往财富自由之路")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }

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
            firstRecordDate: firstRecordDate,
            dailyPassive: dailyPassive
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
                switch freedomState {
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

            switch freedomState {
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
    private var statsRow: some View {
        HStack(spacing: Spacing.md) {
            statCard(label: "Daily",
                     value: dailyBurn.isFinite ? String(format: "%.1f", dailyBurn) : "—",
                     unit: "元/天")
            statCard(label: "Passive",
                     value: FinancialFormatting.percentage(passiveRatio),
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
                        Text(todaySpending.isFinite ? String(format: "¥%.1f", todaySpending) : "¥—")
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
                        Text(dailyBurn.isFinite ? String(format: "¥%.1f", dailyBurn) : "¥—")
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
        guard dailyBurn.isFinite, dailyBurn > 0, todaySpending.isFinite else {
            return "等待有效日均数据"
        }
        if todaySpending == 0 {
            return "今日尚未消费"
        }
        // 当天净额为负(退款/冲正大于消费)时,"低于日均 N%" 会算出 100% 以上的
        // 荒唐数字。这种日子本来就不是"省钱",单独说清楚。
        if todaySpending < 0 {
            return "今日净退款 ¥\(String(format: "%.1f", -todaySpending))"
        }
        let diffPct = FinancialFormatting.clampedInteger(
            abs((1 - todayPercent) * 100),
            range: 0...9_999
        )
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
        guard dailyBurn.isFinite, dailyBurn > 0, todaySpending.isFinite else {
            return "还没有有效日均数据,先检查或补充支出记录。"
        }
        let today = todaySpending
        let avg = dailyBurn
        let todayText = FinancialFormatting.wholeNumber(today)
        let avgText = FinancialFormatting.wholeNumber(avg)
        if today == 0 {
            return "今日尚未消费 · 日均 ¥\(avgText)"
        }
        if today < 0 {
            return "今日净退款 ¥\(FinancialFormatting.wholeNumber(-today)) · 日均 ¥\(avgText)"
        }
        let diff = today - avg
        let pct = FinancialFormatting.wholeNumber(abs(diff) / avg * 100)
        if today > avg {
            return "今日已花 ¥\(todayText) · 日均 ¥\(avgText) · 高于日均 \(pct)%"
        } else {
            return "今日已花 ¥\(todayText) · 日均 ¥\(avgText) · 低于日均 \(pct)%"
        }
    }

    /// Freedom Grid:1825 格可视化,作为 hero 卡片之一,占大空间
    /// 设计动机:这是 FreeGrid 的产品记忆点,在暗底上每格"发光"质感
    private var gridSection: some View {
        let state = FreedomMath.gridState(lockedAssets: lockedAssets,
                                          cash: cashAmount,
                                          dailyBurn: dailyBurn,
                                          dailyPassive: dailyPassive)
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
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.inkFaint)
            Text(gridEmptyText)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }

    private var gridEmptyText: String {
        switch freedomState {
        case .invalidData: return "数据异常, 检查金额后再生成网格"
        case .insufficientData:
            return needsSavings
                ? "先记下你有多少钱，再记一笔支出，网格开始点亮"
                : "记录第一笔支出后, 网格开始点亮"
        case .finite, .covered: return "当前净值还没有可点亮的自由格"
        }
    }

    /// 首次使用的两步引导：先建立存款净值，再用第一笔支出建立日均消费。
    /// 两类数据齐备后 @Query 自动更新，入口随即消失，不长期挤占品牌主视觉。
    private var onboardingPrompt: some View {
        Button {
            if needsSavings {
                onOpenAssets()
            } else {
                showingAddExpense = true
            }
        } label: {
            VaultCard(emphasis: .high, padding: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: needsSavings ? "banknote.fill" : "minus.circle.fill")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(needsSavings ? Color.assetBlue : Color.flame)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(onboardingTitle)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Text(onboardingDetail)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                    }

                    Spacer(minLength: Spacing.xs)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkFaint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(onboardingTitle)
        .accessibilityHint(needsSavings ? "前往资产页面，选择资产或现金录入" : "打开支出记录表单")
    }

    private var needsSavings: Bool {
        netWorth <= 0
    }

    /// 存款 + 支出同时齐备过一次,引导就算走完。
    private var onboardingSatisfied: Bool {
        !needsSavings && !expenses.isEmpty
    }

    /// 引导是一次性的:走完就永久关掉。
    /// 不能只看 `needsSavings`——记支出会把现金扣成负数(cash 无下限),
    /// 老用户净值跌到 0 以下时这张卡会重新常驻,那正是被否决过的常驻卡形态。
    private var needsOnboarding: Bool {
        !onboardingCompleted && !onboardingSatisfied
    }

    /// 文案刻意不用"存款":点进去是 Assets 页,资产和现金都能填,
    /// 说"存款"会让用户以为只收现金。
    private var onboardingTitle: String {
        if needsSavings {
            return expenses.isEmpty ? "先记下你有多少钱" : "还差一步:记下你有多少钱"
        }
        return "再记一笔支出"
    }

    private var onboardingDetail: String {
        if needsSavings {
            return expenses.isEmpty
                ? "定期、股票、现金都算，记完再记一笔支出，格子就会点亮"
                : "已经有支出了，补上手里的钱，格子就能点亮"
        }
        return "已经知道你有多少钱了，再建立日均消费，格子就能点亮"
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
    // 早期 web 版的业务函数 1:1 Swift 复刻
    // 用 computed property,SwiftUI 自动追踪依赖,@Query 数据变化时自动重算

    private var userAssetsSingleton: UserAssets? {
        assetsArr.first
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
        FreedomMath.earliestExpenseDate(expenses)
    }

    private var totalExpenses: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    private var totalIncome: Double {
        incomes.reduce(0) { $0 + $1.amount }
    }

    private var trackDays: Int {
        FreedomMath.trackDays(firstRecordDate: firstRecordDate)
    }

    private var dailyBurn: Double {
        FreedomMath.dailyBurn(totalExpenses: totalExpenses, trackDays: trackDays)
    }

    private var dailyPassive: Double {
        passiveSources.reduce(0) { $0 + $1.monthlyAmount / 30 }
    }

    private var passiveRatio: Double {
        FreedomMath.passiveRatio(dailyPassive: dailyPassive, dailyBurn: dailyBurn)
    }

    private var freedomState: FreedomState {
        FreedomMath.freedomState(
            netWorth: netWorth,
            dailyBurn: dailyBurn,
            dailyPassive: dailyPassive,
            hasExpenses: !expenses.isEmpty
        )
    }

    private var freedomDays: Double {
        switch freedomState {
        case .finite(let days): return days
        case .covered: return .infinity
        case .insufficientData, .invalidData: return .nan
        }
    }

    private var isFreedomCovered: Bool {
        if case .covered = freedomState { return true }
        return false
    }

    /// 三档无后缀 hero 数字: 日整数 / 月整数 / 年1位小数 / ∞
    private var freedomDaysDisplay: String {
        FreedomMath.freedomDaysDisplay(freedomState)
    }

    /// hero 副标单位:跟数字档位同步
    private var heroSubUnit: String {
        switch freedomState {
        case .covered: return "久"
        case .finite(let days) where days < 365: return "天"
        case .finite(let days) where days < 3650: return "月"
        case .finite: return "年"
        case .insufficientData, .invalidData: return ""
        }
    }

    /// hero kicker 文案:跟数字档位同步
    private var heroKickerText: String {
        switch freedomState {
        case .covered: return "Freedom"
        case .finite(let days) where days < 365: return "Freedom Days"
        case .finite(let days) where days < 3650: return "Freedom Months"
        case .finite: return "Freedom Years"
        case .insufficientData: return "Freedom Pending"
        case .invalidData: return "Data Check"
        }
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

/// 导出分享: 点导出按钮 → 按需生成临时文件 → 系统分享面板(存 Files / AirDrop / 邮件)
struct ExportShareItem: Identifiable { let id = UUID(); let url: URL }

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#else
/// macOS: 用 SwiftUI 原生 ShareLink 呈现系统分享(文件已生成,分享或完成)。
struct ShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("导出文件已生成")
                .font(.headline)
            Text(url.lastPathComponent)
                .font(.callout)
                .foregroundStyle(.secondary)
            ShareLink("分享…", item: url)
                .buttonStyle(.borderedProminent)
            Button("完成") { dismiss() }
        }
        .padding(40)
        .frame(minWidth: 320)
    }
}
#endif

struct AssetsView: View {
    @Query private var assetsArr: [UserAssets]
    @Query private var expenses: [Expense]              // 算 dailyBurn 用
    @Query private var passiveSources: [PassiveSource]  // 被动收入源
    @Environment(\.modelContext) private var modelContext

    // --- 双桶编辑 (sheet 模式) ---
    @State private var editingBucket: EditBucketSheet.Bucket? = nil

    // --- 调拨 ---
    @State private var transferAmount: String = ""
    @State private var transferDirection: TransferDirection = .cashToAssets
    @FocusState private var transferFocused: Bool   // decimalPad 无 return 键, 靠点空白处 / 下拉滚动收起

    enum TransferDirection: String, CaseIterable {
        case cashToAssets = "现金 → 资产"
        case assetsToCash = "资产 → 现金"
    }

    // --- 被动收入 ---
    @State private var showingAddPassive: Bool = false
    @State private var editingPassiveSource: PassiveSource? = nil
    @State private var pendingDeletePassive: PassiveSource? = nil

    // --- 数据管理 ---
    @State private var showingFileImporter = false
    @State private var showingPurgeAlert = false
    @State private var importStatus: String? = nil
    @State private var pendingImport: DataIO.ImportPreview? = nil
    @State private var showingImportReview = false

    // --- 数据导出 (按需: 点按钮才序列化 + 弹分享, 平时切页面不碰) ---
    @State private var shareItem: ExportShareItem? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    bucketCards
                    if showEmptyHint { emptyHintCard }
                    passiveCard
                    transferCard
                    explainCard
                    dataManagementCard
                }
                .padding()
                // 点击卡片之外的空白处收起调拨键盘(decimalPad 无 return 键)。
                // contentShape 让空白区也可命中; 子控件(按钮/Picker/输入框)优先级更高, 不受影响。
                .contentShape(Rectangle())
                .onTapGesture { transferFocused = false }
            }
            .scrollContentBackground(.hidden)
            .dismissKeyboardOnScroll()
            .background(Color.paper)
            .navigationTitle("Assets")
            .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
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
            .sheet(isPresented: $showingImportReview) {
                if let p = pendingImport {
                    ImportReviewSheet(preview: p) { strategy, categoryMap in
                        commitImport(strategy: strategy, categoryMap: categoryMap)
                    } onCancel: {
                        pendingImport = nil
                    }
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
            .sheet(isPresented: $showingAddPassive) {
                PassiveSourceSheet(existing: nil) { name, monthly in
                    let new = PassiveSource(name: name, monthlyAmount: monthly)
                    modelContext.insert(new)
                }
            }
            .sheet(item: $editingPassiveSource) { source in
                PassiveSourceSheet(existing: source) { name, monthly in
                    source.name = name
                    source.monthlyAmount = monthly
                }
            }
            .alert(
                "删除这个被动收入源?",
                isPresented: Binding(
                    get: { pendingDeletePassive != nil },
                    set: { if !$0 { pendingDeletePassive = nil } }
                ),
                presenting: pendingDeletePassive
            ) { src in
                Button("删除", role: .destructive) {
                    modelContext.delete(src)
                    pendingDeletePassive = nil
                }
                Button("取消", role: .cancel) { pendingDeletePassive = nil }
            } message: { src in
                Text("\(src.name) · 月入 ¥\(FinancialFormatting.wholeNumber(src.monthlyAmount))\n删除后被动覆盖率会下降。")
            }
        }
    }

    // MARK: - 被动收入 computed
    private var dailyBurnAssetsView: Double {
        let firstDate = FreedomMath.earliestExpenseDate(expenses)
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)
        let total = expenses.reduce(0) { $0 + $1.amount }
        return FreedomMath.dailyBurn(totalExpenses: total, trackDays: days)
    }

    private var totalMonthlyPassive: Double {
        passiveSources.reduce(0) { $0 + $1.monthlyAmount }
    }

    private var dailyPassiveAssetsView: Double {
        FreedomMath.dailyPassive(sources: passiveSources)
    }

    private var passiveRatioAssetsView: Double {
        FreedomMath.passiveRatio(dailyPassive: dailyPassiveAssetsView, dailyBurn: dailyBurnAssetsView)
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
        Button {
            editingBucket = bucket
        } label: {
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("编辑\(kicker)")
        // Button 会把 label 里的 Text 合并成一个元素,再被 accessibilityLabel 整体顶掉;
        // 金额得单独挂回 value,否则 VoiceOver 只念"编辑现金",听不到余额。
        .accessibilityValue("¥" + amount.formatted(.number))
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

    // MARK: - 被动收入卡片
    // 顶部 kicker + "+" / 大数字覆盖率 / 月入·日均 subtitle / 已有源列表(每行 × 删除, 点行编辑)
    private var passiveCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "Passive · 被动收入")
                    Spacer()
                    Button {
                        showingAddPassive = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.skyDeep)
                            .frame(width: 24, height: 24)
                            .background(Circle().stroke(Color.skyDeep.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加被动收入源")
                }

                // 大数字: 覆盖率
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(FinancialFormatting.wholeNumber((passiveRatioAssetsView * 100).rounded()))
                        .font(.system(size: 44, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(passiveRatioAssetsView >= 1 ? Color.mossGreen : Color.ink)
                    Text("%")
                        .font(.system(size: 20, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                    Spacer()
                    Text(passiveRatioAssetsView >= 1 ? "已覆盖日常消费" : "覆盖日常消费")
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(passiveRatioAssetsView >= 1 ? Color.mossGreen : Color.inkFaint)
                }

                // subtitle: 月入 + 日均
                if !passiveSources.isEmpty {
                    HStack(spacing: 8) {
                        Text("月入 ¥\(FinancialFormatting.wholeNumber(totalMonthlyPassive))")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        Text("·")
                            .foregroundStyle(Color.inkFaint)
                        Text("日均 ¥\(String(format: "%.1f", dailyPassiveAssetsView))")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        if dailyBurnAssetsView > 0 {
                            Text("·")
                                .foregroundStyle(Color.inkFaint)
                            Text("日均消费 ¥\(String(format: "%.1f", dailyBurnAssetsView))")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                } else {
                    Text("还没有被动收入源, 点击右上 + 添加")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }

                // 源列表
                if !passiveSources.isEmpty {
                    Hairline()
                    ForEach(passiveSources) { source in
                        passiveSourceRow(source)
                        if source.id != passiveSources.last?.id {
                            Hairline().padding(.leading, 4)
                        }
                    }
                }
            }
        }
    }

    private func passiveSourceRow(_ s: PassiveSource) -> some View {
        HStack(spacing: 10) {
            Button {
                editingPassiveSource = s
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mossGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.ink)
                        Text("¥\(FinancialFormatting.wholeNumber(s.monthlyAmount))/月 · ¥\(s.monthlyAmount.isFinite ? String(format: "%.1f", s.monthlyAmount / 30) : "—")/天")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.inkFaint)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                pendingDeletePassive = s
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
                    .frame(width: 22, height: 22)
                    .background(Circle().stroke(Color.hairlineSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除这个被动源")
        }
        .padding(.vertical, 6)
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
                        .decimalKeyboard()
                        .focused($transferFocused)
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

                // 导出: 两个紧凑按钮并排(CSV / JSON 是一对)
                HStack(spacing: Spacing.sm) {
                    compactDataButton("导出 CSV", icon: "tablecells") { exportNow(.csv) }
                    compactDataButton("导出 JSON", icon: "curlybraces") { exportNow(.json) }
                }
                Text("CSV 用 Excel / Numbers 打开,JSON 可回导备份")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)

                // 导入
                compactDataButton("从 JSON 导入", icon: "square.and.arrow.down") {
                    showingFileImporter = true
                }

                if let status = importStatus {
                    Text(status)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 清空: 分隔线 + 弱化的危险操作(不抢工具按钮的视觉权重)
                Rectangle().fill(Color.hairlineSoft).frame(height: 1)
                    .padding(.vertical, Spacing.xs)
                Button {
                    showingPurgeAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 12))
                        Text("清空所有数据").font(.system(.subheadline, design: .rounded))
                    }
                    .foregroundStyle(Color.flame)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 紧凑数据按钮(比 VaultButton 矮、描边更淡;并排或单列都适配)
    private func compactDataButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13))
                Text(title).font(.system(.subheadline, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(Color.ink)
            .overlay(Capsule().stroke(Color.ink.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 数据导出 (按需: 点按钮才序列化, 写临时文件 → 弹分享面板)
    enum ExportFormat { case csv, json }

    private func exportNow(_ format: ExportFormat) {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = stamp.string(from: .now)
        let nonce = UUID().uuidString.prefix(8)

        do {
            let data: Data
            let name: String
            switch format {
            case .csv:
                data = try DataIO.exportCSV(context: modelContext)
                name = "FreeGrid-记账-\(timestamp)-\(nonce).csv"
            case .json:
                data = try DataIO.exportJSON(context: modelContext)
                name = "FreeGrid-备份-\(timestamp)-\(nonce).json"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            importStatus = nil
            shareItem = ExportShareItem(url: url)
        } catch {
            importStatus = "✗ 导出失败: \(error.localizedDescription)"
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
            Task {
                guard url.startAccessingSecurityScopedResource() else {
                    importStatus = "无法访问该文件"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let validated = try await Task.detached(priority: .userInitiated) {
                        let data = try ImportValidator.loadData(from: url)
                        return try ImportValidator.validate(data: data)
                    }.value
                    let preview = try DataIO.preview(validated: validated, context: modelContext)
                    pendingImport = preview
                    importStatus = nil
                    showingImportReview = true
                } catch {
                    importStatus = "✗ 解析失败: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            importStatus = "✗ 文件读取失败: \(error.localizedDescription)"
        }
    }

    private func commitImport(strategy: DataIO.AssetsImportStrategy, categoryMap: [String: String] = [:]) {
        guard let preview = pendingImport else { return }
        do {
            let result = try DataIO.commitImport(preview: preview, strategy: strategy, categoryMap: categoryMap, context: modelContext)
            var lines: [String] = ["✓ 导入完成"]
            lines.append("支出 +\(result.expensesAdded) (\(preview.expensesSkipped) 重复跳过)")
            lines.append("收入 +\(result.incomesAdded) (\(preview.incomesSkipped) 重复跳过)")
            if result.devicesAdded > 0 {
                lines.append("设备 +\(result.devicesAdded)")
            }
            if result.passiveSourcesAdded > 0 {
                lines.append("被动源 +\(result.passiveSourcesAdded)")
            }
            switch strategy {
            case .replace:
                lines.append("净值已替换为 ¥\(FinancialFormatting.wholeNumber(preview.jsonAssetsTotal))")
            case .addToCash:
                lines.append("现金 +¥\(FinancialFormatting.wholeNumber(preview.jsonAssetsTotal))")
            case .skipAssets:
                lines.append("净值未变动")
            }
            importStatus = lines.joined(separator: "\n")
        } catch {
            importStatus = "✗ 写入失败: \(error.localizedDescription)"
        }
        pendingImport = nil
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
        guard let amt = Double(transferAmount), FinancialFormatting.validAmount(amt),
              let assets = assetsArr.first,
              assets.cash.isFinite, assets.lockedAssets.isFinite else { return }

        switch transferDirection {
        case .cashToAssets:
            let actual = min(amt, max(0, assets.cash))
            assets.cash -= actual
            assets.lockedAssets += actual
        case .assetsToCash:
            let actual = min(amt, max(0, assets.lockedAssets))
            assets.lockedAssets -= actual
            assets.cash += actual
        }
        assets.updatedAt = .now
        transferAmount = ""
        transferFocused = false   // 调拨完成顺手收键盘
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
                                .decimalKeyboard()
                                .accessibilityIdentifier("bucket-amount-field")
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
                        if let new = Double(amount),
                           FinancialFormatting.validAmount(new, allowsZero: true),
                           new != currentAmount {
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
            .inlineNavTitle()
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
        .iosSheetDetents()
    }

    private var isValid: Bool {
        guard let value = Double(amount) else { return false }
        return FinancialFormatting.validAmount(value, allowsZero: true)
    }

    private func save() {
        guard let value = Double(amount),
              FinancialFormatting.validAmount(value, allowsZero: true) else { return }
        onSave(value)
        dismiss()
    }
}

// ============================================================================
// MARK: - PassiveSourceSheet (被动收入源 新增 / 编辑)
// ============================================================================
// 跟 EditBucketSheet 同 silverline 风。existing == nil 是"新增"语义,
// existing != nil 是"编辑"语义, 复用同一个 view 减少代码重复。
// onSave 接 (name, monthlyAmount), 父 view 决定 insert 还是 mutate。

struct PassiveSourceSheet: View {

    let existing: PassiveSource?
    let onSave: (String, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var monthly: String = ""
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { existing != nil }
    private var title: String { isEditing ? "编辑被动源" : "添加被动源" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // 名字
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "名称")
                        TextField("房租 / 股息 / 利息 / 副业 ...", text: $name)
                            .font(.system(.title3, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .focused($nameFocused)
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
                    }

                    // 月入
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "月入 (元 / 月)")
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("¥")
                                .font(.system(size: 28, weight: .ultraLight, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                            TextField("0", text: $monthly)
                                .decimalKeyboard()
                                .font(.system(size: 36, weight: .ultraLight, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.ink)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.mossGreen.opacity(0.45), lineWidth: 1)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.mossGreen.opacity(0.08))
                        )

                        // 日均预览
                        if let m = Double(monthly), FinancialFormatting.validAmount(m) {
                            Text("≈ ¥\(String(format: "%.1f", m / 30)) / 天")
                                .font(.system(.caption, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.mossGreen)
                                .padding(.top, 2)
                        }
                    }

                    // 说明
                    Text("被动收入: 不需要持续工作就能稳定获得的收入。每月固定金额, 按 ÷ 30 转日均, 用来计算「被动覆盖率」。")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(title)
            .inlineNavTitle()
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
                if let e = existing {
                    name = e.name
                    monthly = String(format: "%g", e.monthlyAmount)
                }
                nameFocused = !isEditing  // 新增聚焦名字, 编辑不自动弹键盘
            }
        }
        .iosSheetDetents()
    }

    private var isValid: Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n.count <= FinancialLimits.nameCharacters,
              let monthlyAmount = Double(monthly) else { return false }
        return FinancialFormatting.validAmount(monthlyAmount)
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n.count <= FinancialLimits.nameCharacters,
              let monthlyAmount = Double(monthly),
              FinancialFormatting.validAmount(monthlyAmount) else { return }
        onSave(n, monthlyAmount)
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
// MARK: - ExpenseCategory (支出分类:权威列表 + 导入归一)
// ============================================================================
// 单一来源:AddExpenseSheet 的 Picker 和 导入分类对齐都引用这里, 避免两套词表打架。
// 设计哲学:手动记账只能选 canonical;导入是唯一会混进外来分类的口子, 在导入边界
// 用 suggest() 归一到 canonical → 数据层永远只存这 9 个, 分析层(汇总条/图表)
// 不可能再冒出选不到的分类。raw 标签若被改写, 压进 note 留底。

enum ExpenseCategory {
    /// 权威分类(记账 Picker + 一切分析口径的唯一标准)
    static let canonical = ["早餐", "午餐", "晚餐", "购物", "交通", "娱乐",
                            "成长投资", "医疗", "其他"]

    /// 兜底分类(归一不出来时的默认)
    static let fallback = "其他"

    /// 外来标签 → canonical 的高置信别名表(只放"几乎不会错"的)。
    /// 英文 key 走小写匹配(早期 web 旧版分类键);中文 key 精确匹配。
    /// 拿不准的(food / 订阅 / 日用 / 人情 …)故意不放, 让它们落到 needs-review,
    /// 由用户在导入预览里手动归类 —— 这就是"稳"的含义。
    static let aliases: [String: String] = [
        "transport": "交通", "transportation": "交通",
        "shopping": "购物", "shop": "购物",
        "entertainment": "娱乐",
        "medical": "医疗", "health": "医疗",
        "other": "其他", "others": "其他", "misc": "其他",
        "growth": "成长投资", "investment": "成长投资",
        "数码": "购物",   // 经用户确认:电子产品并入购物
    ]

    /// 归一建议。已是 canonical → 原样(known);命中别名 → canonical(known);
    /// 都不命中 → fallback 但 known=false(需用户在预览里确认)。
    static func suggest(_ raw: String) -> (canonical: String, known: Bool) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonical.contains(t) { return (t, true) }
        if let mapped = aliases[t] ?? aliases[t.lowercased()] { return (mapped, true) }
        return (fallback, false)
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        MonthlySummaryView()
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
            }
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
                Text("¥" + amount.formatted(.number.precision(.fractionLength(0...2))))
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
                // 注: 旧的"被动"绿色标签已移除 — 被动收入概念整体迁到 Assets · PassiveSource
                Text(i.source)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
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
    // 设计跟 早期 web 版 deleteTx() 对齐: alert 文案显式列出"哪一天 / 类别 / 金额 /
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
            assets?.firstRecordDate = FreedomMath.earliestExpenseDate(
                expenses.filter { $0.id != e.id }
            )
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
// 8 项自检源自 早期 web 版 SELF_CHECKS, 全部从现有 SwiftData @Query +
// FreedomMath helper 反推, 不引入新状态。每项即时计算, 数据变化自动重算。

// ============================================================================
// MARK: - MonthlySummaryView (月度汇总: 每月总支出/收入 + 月内分类明细)
// ============================================================================
// 从 History 导航栏进入。区别于 History 全时段的"分类汇总条", 这里按月切分。
// 月卡显示 支出/收入/净; 点开看当月各分类支出(占比条 + %)。

struct MonthlySummaryView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @State private var expanded: Set<String> = []

    struct MonthlyStat: Identifiable {
        let id: String          // "2026-05"
        let label: String       // "2026年5月"
        let totalExpense: Double
        let totalIncome: Double
        var net: Double { totalIncome - totalExpense }
        let categories: [(category: String, total: Double)]  // 月内支出分类, 降序
    }

    var body: some View {
        ScrollView {
            if monthlyStats.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "calendar")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.inkFaint)
                    Text("还没有可汇总的记录")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(monthlyStats) { monthCard($0) }
                }
                .padding()
            }
        }
        .background(Color.paper)
        .navigationTitle("月度汇总")
        .inlineNavTitle()
    }

    @ViewBuilder
    private func monthCard(_ stat: MonthlyStat) -> some View {
        let isExpanded = expanded.contains(stat.id)
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded { expanded.remove(stat.id) } else { expanded.insert(stat.id) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text(stat.label)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Text("净 " + signed(stat.net))
                                .font(.system(.callout, design: .rounded).weight(.medium).monospacedDigit())
                                .foregroundStyle(stat.net >= 0 ? Color.mossGreen : Color.flame)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.inkFaint)
                        }
                        HStack(spacing: Spacing.xl) {
                            amountStat("支出", stat.totalExpense, Color.ink)
                            amountStat("收入", stat.totalIncome, Color.incomeGold)
                        }
                    }
                }
                .buttonStyle(.plain)

                if isExpanded && !stat.categories.isEmpty {
                    Rectangle().fill(Color.hairlineSoft).frame(height: 1)
                    let maxCat = stat.categories.first?.total ?? 1
                    VStack(spacing: Spacing.sm) {
                        ForEach(stat.categories, id: \.category) { c in
                            categoryRow(c.category, c.total, maxCat: maxCat, monthTotal: stat.totalExpense)
                        }
                    }
                }
            }
        }
    }

    private func amountStat(_ label: String, _ amount: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.inkFaint)
            Text("¥" + amount.formatted(.number.precision(.fractionLength(0...2))))
                .font(.system(.title3, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func categoryRow(_ name: String, _ total: Double, maxCat: Double, monthTotal: Double) -> some View {
        let pct = monthTotal > 0 ? total / monthTotal : 0
        return HStack(spacing: Spacing.sm) {
            Text(name)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.mist)
                    Capsule().fill(Color.assetBlue)
                        .frame(width: max(4, geo.size.width * (maxCat > 0 ? total / maxCat : 0)))
                }
            }
            .frame(height: 8)
            Text("¥" + total.formatted(.number.precision(.fractionLength(0...2))))
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.ink)
                .frame(width: 56, alignment: .trailing)
            Text(pct.formatted(.percent.precision(.fractionLength(0...0))))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.inkFaint)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func signed(_ v: Double) -> String {
        (v >= 0 ? "+¥" : "−¥") + abs(v).formatted(.number.precision(.fractionLength(0...2)))
    }

    /// 按 年-月 分组聚合; 月内再按分类聚合支出。最近的月在前。
    private var monthlyStats: [MonthlyStat] {
        let cal = Calendar.current
        func key(_ d: Date) -> String {
            let c = cal.dateComponents([.year, .month], from: d)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
        var expByMonth: [String: [Expense]] = [:]
        var incByMonth: [String: Double] = [:]
        var keys = Set<String>()
        for e in expenses { let k = key(e.date); keys.insert(k); expByMonth[k, default: []].append(e) }
        for i in incomes  { let k = key(i.date); keys.insert(k); incByMonth[k, default: 0] += i.amount }

        return keys.sorted(by: >).map { k in
            let exps = expByMonth[k] ?? []
            let cats = Dictionary(grouping: exps, by: { $0.category })
                .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
                .sorted { $0.total > $1.total }
            let parts = k.split(separator: "-")
            let label = "\(parts[0])年\(Int(parts[1]) ?? 0)月"
            return MonthlyStat(
                id: k, label: label,
                totalExpense: exps.reduce(0) { $0 + $1.amount },
                totalIncome: incByMonth[k] ?? 0,
                categories: cats
            )
        }
    }
}

// ============================================================================
// MARK: - SettingsView (设置 — 顶部自检收缩卡 + 分组列表)
// ============================================================================
// 替换原 Check tab。顶部把「财富自由自检」收成一张卡(点开 push CheckView 完整子页),
// 下面是 iOS 分组列表(外观/关于/支持)。配色全用 DesignSystem 的 dynamic token,
// 自动适配深/浅。数据导入导出仍在 Assets, 本页不含。

struct SettingsView: View {
    // 跟 ContentView / Dashboard 共享同一 key, 切换全 app 自动重绘
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    @Query private var expenses: [Expense]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]

    @Environment(\.openURL) private var openURL
    @State private var icpCopied = false

    private let icpNumber = "浙ICP备2026045014号-1A"
    private let privacyURL = URL(string: "https://github.com/coni555/FreeGrid-Freedom/blob/main/PRIVACY.md")!
    private let rateURL = URL(string: "https://apps.apple.com/app/id6781104287?action=write-review")!

    private var summary: FreedomSummary {
        FreedomChecklist.evaluate(expenses: expenses,
                                  passiveSources: passiveSources,
                                  assets: assetsArr.first)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    checkCard
                    appearanceSection
                    aboutSupportSection
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("Settings")
        }
    }

    // MARK: - 自检收缩卡 → push 完整自检子页
    private var checkCard: some View {
        let s = summary   // 整张卡只算一次 evaluate
        return NavigationLink {
            CheckView()
        } label: {
            VaultCard(emphasis: .high) {
                HStack(spacing: Spacing.lg) {
                    // 圆环进度
                    ZStack {
                        Circle().stroke(Color.mist2, lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: s.progress)
                            .stroke(Color.skyDeep, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        (Text("\(s.doneCount)")
                            .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                         + Text("/\(s.total)")
                            .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit()))
                            .foregroundStyle(Color.ink)
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("财富自由自检")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.ink)
                        if let stop = s.nextStopTitle {
                            Text("下一站 · \(stop)")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Color.inkMuted)
                            if let remain = s.remainText {
                                Text(remain)
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundStyle(Color.skyDeep)
                            }
                        } else {
                            Text("已全部达成 🎉")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(Color.skyDeep)
                        }
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.inkGhost)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 分组
    private var appearanceSection: some View {
        settingsSection("外观") {
            settingsRow(icon: "moon", title: "主题") {
                // 分段选择器 + 动画绑定: 切换经 withAnimation 让整页换色平滑过渡,
                // 而非裸切 .preferredColorScheme 那种单帧硬重绘("突然卡顿")。
                // 跟 Dashboard 顶栏切换同款 0.25s 缓动, 且不像 Menu 那样有收起动画叠加。
                Picker("主题", selection: themeBinding) {
                    Text("浅色").tag(false)
                    Text("深色").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    /// 主题绑定: setter 包在 withAnimation 里 — 切换时整页换色走 0.25s 缓动交叉淡入,
    /// 不是单帧硬重绘。这是消除"切主题突然卡顿"的关键。
    private var themeBinding: Binding<Bool> {
        Binding(
            get: { isDarkMode },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.25)) { isDarkMode = newValue }
            }
        )
    }

    /// 关于(进子页) + 评价与反馈(跳 App Store)。无标题分组 —— 顶层保持精简,
    /// 后续加新功能时也按"入口行 → push 子页"这套模式往这里 / 新卡里加。
    private var aboutSupportSection: some View {
        settingsSection("") {
            NavigationLink {
                aboutPage
            } label: {
                settingsRow(icon: "info.circle", title: "关于") { chevron }
            }
            .buttonStyle(.plain)
            rowDivider
            settingsRow(icon: "star", title: "评价与反馈",
                        action: { openURL(rateURL) }) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.inkGhost)
            }
        }
    }

    // MARK: - 关于子页 (版本 / 隐私政策 / ICP) — 从「关于」push 进入
    private var aboutPage: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                settingsSection("") {
                    settingsRow(icon: "info.circle", title: "版本") {
                        Text(appVersion)
                            .font(.system(.subheadline, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkFaint)
                    }
                    rowDivider
                    settingsRow(icon: "lock.shield", title: "隐私政策",
                                action: { openURL(privacyURL) }) { chevron }
                    rowDivider
                    icpRow
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("关于")
        .inlineNavTitle()
    }

    // ICP 备案号: 等宽显示 + 点行复制(满足「App 内显著位置标注备案号」合规)
    private var icpRow: some View {
        Button {
            copyICP()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.inkMuted)
                    .frame(width: 26, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ICP 备案号")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text(icpNumber)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.inkFaint)
                        .textSelection(.enabled)
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: icpCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(icpCopied ? Color.mossGreen : Color.inkGhost)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 复用组件
    /// 一节: 小标题 + 圆角分组卡(行之间手动插 rowDivider)
    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .padding(.leading, Spacing.md)
            }
            VaultCard(padding: 0) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    /// 一行: 图标 + 标题 + 右侧 trailing。给 action 则整行可点。
    @ViewBuilder
    private func settingsRow<Trailing: View>(
        icon: String,
        title: String,
        iconColor: Color = .inkMuted,
        titleColor: Color = .ink,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let row = HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 26, alignment: .center)
            Text(title)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(titleColor)
            Spacer(minLength: Spacing.sm)
            trailing()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var rowDivider: some View {
        Hairline().padding(.leading, Spacing.lg + 26 + Spacing.md)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.inkGhost)
    }

    private func copyICP() {
        #if os(iOS)
        UIPasteboard.general.string = icpNumber
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(icpNumber, forType: .string)
        #endif
        withAnimation { icpCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { icpCopied = false }
        }
    }
}

struct CheckView: View {

    @Query private var expenses: [Expense]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]

    /// 8 项自检 + 汇总 — 逻辑统一在 FreedomChecklist, collapsed 卡与本页共用
    private var summary: FreedomSummary {
        FreedomChecklist.evaluate(expenses: expenses,
                                  passiveSources: passiveSources,
                                  assets: assetsArr.first)
    }

    // 作为 Settings 顶部自检卡 push 进来的子页 — 不自带 NavigationStack(用父级的)
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                heroCard
                checklistCard
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("财富自由自检")
        .inlineNavTitle()
    }

    // MARK: - Hero 进度卡

    private var heroCard: some View {
        VaultCard(emphasis: .high, padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "Freedom Checklist")

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(summary.doneCount)")
                        .font(.system(size: 56, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                    Text("/ \(summary.total)")
                        .font(.system(size: 22, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                    Spacer()
                    Text(FinancialFormatting.percentage(summary.progress))
                        .font(.system(.callout, design: .monospaced).monospacedDigit())
                        .foregroundStyle(Color.skyDeep)
                }

                // 进度长条 silverline 风
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.mist)
                        Capsule()
                            .fill(Color.skyDeep)
                            .frame(width: max(2, geo.size.width * summary.progress))
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
                ForEach(Array(summary.items.enumerated()), id: \.element.id) { idx, item in
                    checklistRow(item: item)
                        .padding(.horizontal, Spacing.lg)
                    if idx < summary.items.count - 1 {
                        Hairline().padding(.leading, Spacing.lg + 30)
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private func checklistRow(item: FreedomCheckItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
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
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text("\(item.id). \(item.title)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(item.done ? Color.ink : Color.inkMuted)
                    .strikethrough(item.done, color: Color.inkFaint)

                if item.done {
                    Text("已达成")
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.skyDeep)
                } else {
                    // 量化项(1/4/5/7/8): 细进度条 + 当前/目标; 二元项(2/3/6): 跳过
                    if let p = item.progress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.mist2)
                                Capsule()
                                    .fill(Color.skyDeep)
                                    .frame(width: max(2, geo.size.width * p))
                            }
                        }
                        .frame(height: 4)
                        Text(item.detail)
                            .font(.system(.caption2, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(Color.inkFaint)
                    }
                    // 怎么前进
                    Text("怎么前进 · \(item.hint)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    @Query private var passiveSources: [PassiveSource]

    @State private var amount: String = ""
    @State private var category: String = "早餐"
    @State private var note: String = ""
    @State private var date: Date = .now

    /// 分类清单 = 权威 canonical(单一来源 ExpenseCategory.canonical)。
    /// "人情"/"日用" 已不在清单(2026-05 移除);旧记录仍能在 History 正常显示。
    private let categories = ExpenseCategory.canonical

    var body: some View {
        NavigationStack {
            Form {
                Section("金额 (元)") {
                    TextField("0.00", text: $amount)
                        .decimalKeyboard()
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
                    DatePicker("日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section("备注 (可选)") {
                    TextField("备注", text: $note)
                        .font(.system(.body, design: .rounded))
                }

                // ===== 戴维斯三杀实时预览 =====
                if let amt = Double(amount), FinancialFormatting.validAmount(amt) {
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
            .inlineNavTitle()
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
        let firstDate = FreedomMath.earliestExpenseDate(expenses)
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)
        let newFirstDate = min(firstDate ?? date, date)
        let newDays = FreedomMath.trackDays(firstRecordDate: newFirstDate)
        let dailyPassive = FreedomMath.dailyPassive(sources: passiveSources)

        let currentTotalExp = expenses.reduce(0) { $0 + $1.amount }
        let currentAvg = FreedomMath.dailyBurn(totalExpenses: currentTotalExp, trackDays: days)
        let currentFreedom = FreedomMath.freedomState(
            netWorth: currentNW,
            dailyBurn: currentAvg,
            dailyPassive: dailyPassive,
            hasExpenses: !expenses.isEmpty
        )

        let newNW = currentNW - amount
        let newAvg = FreedomMath.dailyBurn(totalExpenses: currentTotalExp + amount, trackDays: newDays)
        let newFreedom = FreedomMath.freedomState(
            netWorth: newNW,
            dailyBurn: newAvg,
            dailyPassive: dailyPassive,
            hasExpenses: true
        )

        let freedomLoss: String
        if case .finite(let currentDays) = currentFreedom,
           case .finite(let newDays) = newFreedom,
           let daysLost = FinancialFormatting.integer(
               max(0, currentDays - newDays),
               rounded: .toNearestOrAwayFromZero
           ) {
            freedomLoss = "−\(daysLost) 天"
        } else {
            freedomLoss = "—"
        }

        return VStack(alignment: .leading, spacing: 10) {
            killRow(label: "KILL 1 净值",
                    from: formatYuan(currentNW),
                    to: formatYuan(newNW),
                    delta: "−\(formatYuan(amount))")

            killRow(label: "KILL 2 日均",
                    from: formatYuan(currentAvg, precision: 1),
                    to: formatYuan(newAvg, precision: 2),
                    delta: currentAvg.isFinite
                        ? "+\(formatYuan(newAvg - currentAvg, precision: 2))"
                        : "—")

            // KILL 3: from/to 智能档跟 hero 一致 (42.7 年), delta 固定整数天直观 (−1 天)
            killRow(label: "KILL 3 自由天数",
                    from: FreedomMath.freedomDaysDisplay(currentFreedom),
                    to: FreedomMath.freedomDaysDisplay(newFreedom),
                    delta: freedomLoss)
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
    private func formatYuan(_ value: Double, precision: Int? = nil) -> String {
        guard value.isFinite else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        // 默认档(precision=nil): 整数干净显示, 有小数才补到最多 2 位 —— 与流水列表口径一致,
        // 避免 3.5 / 4.5 被舍成 4(原来 min=max=0 用银行家舍入, 两者都进 4)。
        f.minimumFractionDigits = precision ?? 0
        f.maximumFractionDigits = precision ?? 2
        let s = f.string(from: NSNumber(value: value)) ?? String(format: "%.\(precision ?? 2)f", value)
        return "¥\(s)"
    }

    private var isAmountValid: Bool {
        guard let value = Double(amount),
              FinancialFormatting.validAmount(value),
              note.count <= FinancialLimits.noteCharacters,
              Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: .now) else {
            return false
        }
        let resultingCash = (assetsArr.first?.cash ?? 0) - value
        return resultingCash.isFinite && abs(resultingCash) <= FinancialLimits.maximumAmount
    }

    /// 保存: 创建 Expense + 同步扣资产 (KILL 1) + 维护 firstRecordDate
    private func save() {
        guard isAmountValid, let amt = Double(amount) else { return }

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
        assets.firstRecordDate = min(FreedomMath.earliestExpenseDate(expenses) ?? date, date)

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
    @Query private var passiveSources: [PassiveSource]

    @State private var amount: String = ""
    @State private var source: String = ""
    @State private var note: String = ""
    @State private var date: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section("金额 (元)") {
                    TextField("0.00", text: $amount)
                        .decimalKeyboard()
                        .font(.system(.body, design: .rounded).monospacedDigit())
                }
                Section("来源") {
                    TextField("工资 / 投资 / 副业 / ...", text: $source)
                        .font(.system(.body, design: .rounded))
                }
                Section("日期") {
                    DatePicker("日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section("备注 (可选)") {
                    TextField("备注", text: $note)
                        .font(.system(.body, design: .rounded))
                }

                if let amt = Double(amount), FinancialFormatting.validAmount(amt) {
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
            .inlineNavTitle()
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
        let firstDate = FreedomMath.earliestExpenseDate(expenses)
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)
        let dailyPassive = FreedomMath.dailyPassive(sources: passiveSources)

        let totalExp = expenses.reduce(0) { $0 + $1.amount }
        let currentAvg = FreedomMath.dailyBurn(totalExpenses: totalExp, trackDays: days)
        let currentFreedom = FreedomMath.freedomState(
            netWorth: currentNW,
            dailyBurn: currentAvg,
            dailyPassive: dailyPassive,
            hasExpenses: !expenses.isEmpty
        )

        let newNW = currentNW + amount
        let newFreedom = FreedomMath.freedomState(
            netWorth: newNW,
            dailyBurn: currentAvg,
            dailyPassive: dailyPassive,
            hasExpenses: !expenses.isEmpty
        )

        let freedomGain: String
        if case .finite(let currentDays) = currentFreedom,
           case .finite(let newDays) = newFreedom,
           let daysGained = FinancialFormatting.integer(
               max(0, newDays - currentDays),
               rounded: .toNearestOrAwayFromZero
           ) {
            freedomGain = "+\(daysGained) 天"
        } else {
            freedomGain = "—"
        }

        return VStack(alignment: .leading, spacing: 10) {
            gainRow(label: "GAIN 1 净值",
                    from: formatYuan(currentNW),
                    to: formatYuan(newNW),
                    delta: "+\(formatYuan(amount))")

            // from/to 智能档, delta 固定天 (跟 KILL 3 一致)
            gainRow(label: "GAIN 2 自由天数",
                    from: FreedomMath.freedomDaysDisplay(currentFreedom),
                    to: FreedomMath.freedomDaysDisplay(newFreedom),
                    delta: freedomGain)
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
    private func formatYuan(_ value: Double, precision: Int? = nil) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        // 默认档(precision=nil): 整数干净显示, 有小数才补到最多 2 位 —— 与流水列表口径一致,
        // 避免 3.5 / 4.5 被舍成 4(原来 min=max=0 用银行家舍入, 两者都进 4)。
        f.minimumFractionDigits = precision ?? 0
        f.maximumFractionDigits = precision ?? 2
        let s = f.string(from: NSNumber(value: value)) ?? String(format: "%.\(precision ?? 2)f", value)
        return "¥\(s)"
    }

    /// 输入有效性: 金额、来源、备注和日期都必须落在备份可表示边界内。
    private var isValid: Bool {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(amount),
              FinancialFormatting.validAmount(value),
              !trimmedSource.isEmpty,
              trimmedSource.count <= FinancialLimits.nameCharacters,
              note.count <= FinancialLimits.noteCharacters,
              Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: .now) else {
            return false
        }
        let resultingCash = (assetsArr.first?.cash ?? 0) + value
        return resultingCash.isFinite && abs(resultingCash) <= FinancialLimits.maximumAmount
    }

    /// 保存: 创建 Income + 资产加金额；收入不启动支出追踪基线。
    private func save() {
        guard isValid, let amt = Double(amount) else { return }
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)

        // isPassive 字段保留(JSON 兼容)但新建一律 false — 被动收入改由 PassiveSource 模型承载
        let income = Income(amount: amt, source: trimmedSource, isPassive: false,
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

        onSaved?(income)
        dismiss()
    }
}

// ============================================================================
// MARK: - ImportReviewSheet (导入预览 + 分类对齐 + 净值策略)
// ============================================================================
// "稳"方案:导入前把这批数据的非标准支出分类摊出来 —— 自动归一的可改、没把握的高亮,
// 用户确认后才落库 → 数据层永远只存 canonical 分类。净值策略也搬进来一并确认。
// 取代旧的 confirmationDialog(三个策略按钮),因为分类对齐需要列表式可编辑 UI。

struct ImportReviewSheet: View {
    let preview: DataIO.ImportPreview
    let onCommit: (DataIO.AssetsImportStrategy, [String: String]) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DataIO.CategoryMapEntry]
    @State private var strategy: DataIO.AssetsImportStrategy = .skipAssets

    init(preview: DataIO.ImportPreview,
         onCommit: @escaping (DataIO.AssetsImportStrategy, [String: String]) -> Void,
         onCancel: @escaping () -> Void) {
        self.preview = preview
        self.onCommit = onCommit
        self.onCancel = onCancel
        _entries = State(initialValue: preview.categoryEntries)
    }

    private var reviewCount: Int { entries.filter { $0.needsReview }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    summaryCard
                    if !entries.isEmpty { categoryCard }
                    strategyCard
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("导入预览")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel(); dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        let map = Dictionary(uniqueKeysWithValues: entries.map { ($0.raw, $0.canonical) })
                        onCommit(strategy, map)
                        dismiss()
                    }
                    .fontWeight(.medium)
                    .foregroundStyle(Color.skyDeep)
                }
            }
        }
    }

    // ===== 摘要 =====
    private var summaryCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                KickerLabel(text: "导入预览")
                summaryRow("新增支出", "\(preview.expensesNew.count) 笔")
                summaryRow("新增收入", "\(preview.incomesNew.count) 笔")
                if preview.devicesNew.count > 0 {
                    summaryRow("新增设备", "\(preview.devicesNew.count) 个")
                }
                if preview.passiveSourcesNew.count > 0 {
                    summaryRow("新增被动源", "\(preview.passiveSourcesNew.count) 个")
                }
                let existingDuplicates = preview.expenseDuplicates.existing
                    + preview.incomeDuplicates.existing
                    + preview.deviceDuplicates.existing
                    + preview.passiveSourceDuplicates.existing
                let fileDuplicates = preview.expenseDuplicates.inFile
                    + preview.incomeDuplicates.inFile
                    + preview.deviceDuplicates.inFile
                    + preview.passiveSourceDuplicates.inFile
                if existingDuplicates > 0 {
                    summaryRow("库内重复", "\(existingDuplicates) 条")
                }
                if fileDuplicates > 0 {
                    summaryRow("文件内重复", "\(fileDuplicates) 条")
                }
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color.inkMuted)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Color.ink)
        }
    }

    // ===== 分类对齐 =====
    private var categoryCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "分类对齐")
                    Spacer()
                    if reviewCount > 0 {
                        Text("\(reviewCount) 个待确认")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.flame)
                    }
                }
                Text("这些分类不在你的标准分类里(导入数据带来的)。已自动归类的可改,标橙的请确认。")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)

                ForEach($entries) { $entry in
                    Hairline()
                    categoryRow($entry)
                }
            }
        }
    }

    private func categoryRow(_ entry: Binding<DataIO.CategoryMapEntry>) -> some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if entry.wrappedValue.needsReview {
                        Circle().fill(Color.flame).frame(width: 6, height: 6)
                    }
                    Text(entry.wrappedValue.raw)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                }
                Text("\(entry.wrappedValue.count) 笔 · ¥\(FinancialFormatting.wholeNumber(entry.wrappedValue.total))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkGhost)
            Picker("", selection: entry.canonical) {
                ForEach(ExpenseCategory.canonical, id: \.self) { c in
                    Text(c).tag(c)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.skyDeep)
        }
    }

    // ===== 净值策略 =====
    private var strategyCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "净值处理")
                summaryRow("备份资产桶", "¥\(money(preview.importedAssets.lockedAssets))")
                summaryRow("备份现金桶", "¥\(money(preview.importedAssets.cash))")
                summaryRow("备份净值", "¥\(money(preview.importedAssets.total))")
                Hairline()
                strategyOption(.skipAssets, "只导入交易", "不动现有现金 / 资产桶")
                Hairline()
                strategyOption(
                    .replace,
                    "替换双桶",
                    "资产 ¥\(money(preview.importedAssets.lockedAssets)) + 现金 ¥\(money(preview.importedAssets.cash))"
                )
                Hairline()
                strategyOption(
                    .addToCash,
                    "加到现金",
                    "现金桶 +¥\(money(preview.importedAssets.total))"
                )
            }
        }
    }

    private func money(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func strategyOption(_ s: DataIO.AssetsImportStrategy, _ title: String, _ desc: String) -> some View {
        Button {
            strategy = s
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: strategy == s ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(strategy == s ? Color.skyDeep : Color.inkGhost)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                    Text(desc)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// ============================================================================
// MARK: - SimDemoGrid (模拟决策的格子推演动画)
// ============================================================================
// 设计动机:早期 web 版核心体感——"这笔花出去,自由的格子要熄灭几格"。
// 把抽象的"−16 天"翻译成肉眼可见的格子级联熄灭(支出)/ 点亮(收入)。
//
// 移植自 早期 web 版 `animateGridTransition()`(Canvas 版),做了三处简化:
//   1. 砍掉镜头推近(camera zoom)—— 小 sheet 上会眩晕,且非核心体感
//   2. 辉光用 SwiftUI .shadow 替代 Canvas radialGradient
//   3. 不照搬定长 1825 日格,沿用 App 自适应档(日/月/年),锁定"当前态"的档位
//
// 动画驱动:跟 LifeGrid 呼吸同套路——TimelineView(.animation) + 纯函数(elapsed),
// 不用 withAnimation(...).repeatForever()(iOS 17+ 有 view-lifecycle 冻结 regression)。
// 单一渲染路径 gridFrame(elapsed:):idle 喂 -1(停在旧态),done 喂大值(停在新态),
// playing 喂真实 elapsed —— 三态共用一套逐格分类逻辑。

/// 演示三态:静止(旧态)/ 播放中 / 落定(新态)
enum SimDemoPhase: Equatable {
    case idle
    case playing(Date)
    case done
}

/// 计时:级联窗口 span(所有格子起跑时刻铺开的区间)+ 单格 envelope 时长 cellDur。
/// span 随 delta 增大而拉长并 cap,避免大 delta 拖沓。
/// 方向区分:点亮(收入)刻意放慢 —— 增格是"赚回自由"的奖励时刻,逐格慢点更有满足感;
/// 熄灭(支出)保持利落。grid 渲染和 sheet 落定计时器共用这一份,保证 totalDur 一致。
func simDemoTiming(delta: Int, ignite: Bool) -> (span: Double, cellDur: Double, total: Double) {
    if ignite {
        let cellDur = 0.72
        let span = min(3.0, max(0.5, 0.18 * Double(delta)))
        return (span, cellDur, span + cellDur)
    } else {
        let cellDur = 0.55
        let span = min(1.6, max(0.25, 0.10 * Double(delta)))
        return (span, cellDur, span + cellDur)
    }
}

struct SimDemoGrid: View {
    let unit: FreedomMath.GridUnit
    let oldCount: Int
    let newCount: Int
    /// 蓝格(锁定资产)数 —— 旧态/新态分别,边界外即金格(现金)
    let oldBlue: Int
    let newBlue: Int
    let phase: SimDemoPhase

    @Environment(\.colorScheme) private var scheme

    private var total: Int { max(oldCount, newCount) }
    private var delta: Int { abs(newCount - oldCount) }
    private var isIgnite: Bool { newCount > oldCount }

    var body: some View {
        Group {
            switch phase {
            case .idle:
                gridFrame(elapsed: -1)            // 停在旧态
            case .done:
                gridFrame(elapsed: 9999)          // 停在新态
            case .playing(let start):
                TimelineView(.animation) { ctx in
                    gridFrame(elapsed: ctx.date.timeIntervalSince(start))
                }
            }
        }
    }

    @ViewBuilder
    private func gridFrame(elapsed: Double) -> some View {
        let timing = simDemoTiming(delta: delta, ignite: isIgnite)
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: unit.cellSize, maximum: unit.cellSize),
                               spacing: unit.spacing)],
            spacing: unit.spacing
        ) {
            ForEach(0..<total, id: \.self) { i in
                cell(index: i, elapsed: elapsed, timing: timing)
            }
        }
    }

    /// 单格:稳定区直接满亮;过渡区按 envelope 点燃/熄灭。
    @ViewBuilder
    private func cell(index i: Int, elapsed: Double,
                      timing: (span: Double, cellDur: Double, total: Double)) -> some View {
        let stableCount = min(oldCount, newCount)

        if i < stableCount {
            // 稳定区:始终满亮,用新态配色
            // 配色跟 Dashboard LifeGrid 一致:前段(资产/blue 计数)= 金 incomeGold,后段(现金)= 蓝 assetBlue
            // 注:token 命名历史遗留反了 —— "blue" 计数其实渲染成金色。详见 DesignSystem 注释。
            litCell(base: i < newBlue ? .incomeGold : .assetBlue, opacity: 1, scale: 1, glow: 0, glowColor: .clear)
        } else {
            // 过渡区:计算该格在级联里的顺序 k → 本地进度 lt ∈ [0,1]
            let k: Int = isIgnite ? (i - oldCount) : (oldCount - 1 - i)
            let startK = delta <= 1 ? 0 : (Double(k) / Double(delta - 1)) * timing.span
            let lt = min(1, max(0, (elapsed - startK) / timing.cellDur))

            if isIgnite {
                let base: Color = i < newBlue ? .incomeGold : .assetBlue
                let e = envelope(lt, attack: 0.12, release: 1.4)
                let opacity = 0.14 + 0.86 * easeOut(min(1, lt / 0.30))
                litCell(base: base, opacity: opacity, scale: 1 + 0.20 * e,
                        glow: e * 0.9, glowColor: base)
            } else {
                let base: Color = i < oldBlue ? .incomeGold : .assetBlue
                let e = envelope(lt, attack: 0.16, release: 1.4)
                let opacity = 1 - 0.86 * easeOut(min(1, lt / 0.55))
                // 熄灭用 flame 焰光 —— 贴合 App "支出 = 朱砂" 语义
                litCell(base: base, opacity: opacity, scale: 1 + 0.12 * e,
                        glow: e * 0.8, glowColor: .flame)
            }
        }
    }

    private func litCell(base: Color, opacity: Double, scale: CGFloat,
                         glow: Double, glowColor: Color) -> some View {
        Rectangle()
            .fill(base.opacity(opacity))
            .frame(width: unit.cellSize, height: unit.cellSize)
            .cornerRadius(unit.cellSize * 0.13)
            .shadow(color: glowColor.opacity(glow * 0.9),
                    radius: unit.cellSize * 0.8 * glow)
            .scaleEffect(scale)
            .zIndex(glow > 0.01 ? 1 : 0)
    }

    // ===== envelope helpers(移植 早期 web 版 _eoq / _env)=====

    /// ease-out quart:1-(1-t)^4,收尾绵软
    private func easeOut(_ t: Double) -> Double {
        let c = min(1, max(0, t))
        return 1 - pow(1 - c, 4)
    }

    /// attack-release 包络:t<attack 缓入到 1,之后按 release 指数衰减回 0。
    /// 给辉光/缩放脉冲用 —— 点亮瞬间鼓一下再落定。
    private func envelope(_ t: Double, attack: Double, release: Double) -> Double {
        if t >= 1 { return 0 }
        if t < attack { return easeOut(t / attack) }
        return pow(1 - (t - attack) / (1 - attack), release)
    }
}

// ============================================================================
// MARK: - SimulateSheet (模拟一笔 - 决策预演,不写数据库)
// ============================================================================
// 设计动机:早期 web 版的核心差异化——"要不要买"之前先预演。
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
    @Query private var passiveSources: [PassiveSource]

    // ===== 模拟状态 =====
    @State private var amount: String = ""
    @State private var mode: Mode = .expense
    /// 格子推演动画三态
    @State private var demoPhase: SimDemoPhase = .idle

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
                    if let amt = Double(amount), FinancialFormatting.validAmount(amt) {
                        previewCard(amount: amt)
                        gridDemoCard(amount: amt)
                    } else {
                        hintCard
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            // 金额或模式一变,演示回到静止态(旧网格),让用户重新观察这一笔
            .onChange(of: amount) { _, _ in demoPhase = .idle }
            .onChange(of: mode) { _, _ in demoPhase = .idle }
            .navigationTitle("模拟决策")
            .inlineNavTitle()
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
                        .decimalKeyboard()
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
    // MARK: - 格子推演卡(动画演示)
    // ============================================================================

    /// 把"自由天数 from→to"翻译成可见的格子级联熄灭(支出)/ 点亮(收入)。
    @ViewBuilder
    private func gridDemoCard(amount: Double) -> some View {
        let o = outcome(amount: amount)
        // 锁定"当前态"档位渲染两态 —— 保证格子语义在动画全程一致
        let unit = gridUnit(for: o.currentFreedom)
        let oldCount = cellCount(freedomDays: o.currentFreedom, unit: unit)
        let newCount = cellCount(freedomDays: o.newFreedom, unit: unit)
        let oldBlue = blueCells(count: oldCount, locked: o.lockedAssets, netWorth: o.currentNW)
        let newBlue = blueCells(count: newCount, locked: o.lockedAssets, netWorth: o.newNW)
        let delta = abs(newCount - oldCount)
        let isExpense = mode == .expense

        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "格子推演")
                    Spacer()
                    Text("\(oldCount) → \(newCount) \(unit.label)")
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.inkFaint)
                }

                if isInvalid(o.currentFreedom) || isInvalid(o.newFreedom) {
                    Text("现有财务数据异常, 暂时不能推演自由格。")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.sm)
                } else if isInsufficient(o.currentFreedom) && isInsufficient(o.newFreedom) {
                    Text("先记一笔支出后, 才能推演自由格。")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.sm)
                } else if delta == 0 {
                    Text(isExpense ? "不足一格 —— 还在当日预算内, 这笔不削自由。"
                                   : "不足一格 —— 这笔还不够点亮一格自由。")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.sm)
                } else {
                    SimDemoGrid(unit: unit, oldCount: oldCount, newCount: newCount,
                                oldBlue: oldBlue, newBlue: newBlue, phase: demoPhase)
                        .padding(.vertical, Spacing.xs)

                    HStack(spacing: 6) {
                        Image(systemName: isExpense ? "flame" : "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(isExpense ? Color.flame : Color.skyDeep)
                        Text(isExpense ? "熄灭 \(delta) 格 · 每格 1 \(unit.label)自由"
                                       : "点亮 \(delta) 格 · 每格 1 \(unit.label)自由")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                        Spacer()
                    }

                    demoButton(delta: delta, isExpense: isExpense)
                }
            }
        }
    }

    /// 演示 / 推演中 / 重播 三态按钮
    private func demoButton(delta: Int, isExpense: Bool) -> some View {
        let title: String
        let isPlaying: Bool
        switch demoPhase {
        case .idle:    title = isExpense ? "演示这笔熄灭哪几格" : "演示这笔点亮哪几格"; isPlaying = false
        case .playing: title = "推演中…"; isPlaying = true
        case .done:    title = "重播"; isPlaying = false
        }
        return VaultButton(title: title,
                           icon: demoPhase == .done ? "arrow.counterclockwise" : "play.fill",
                           style: isExpense ? .destructive : .primary) {
            playDemo(delta: delta)
        }
        .disabled(isPlaying)
        .opacity(isPlaying ? 0.5 : 1)
    }

    /// 触发一次推演:置 playing,计时到 totalDur 后落定到 done(停在新态)
    private func playDemo(delta: Int) {
        let start = Date()
        demoPhase = .playing(start)
        let total = simDemoTiming(delta: delta, ignite: mode == .income).total
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(total))
            if case .playing(let s) = demoPhase, s == start {
                demoPhase = .done
            }
        }
    }

    // ===== freedomDays → 格子换算(沿用 FreedomMath.gridState 档位规则)=====

    private func gridUnit(for state: FreedomState) -> FreedomMath.GridUnit {
        switch state {
        case .covered:
            return .year
        case .finite(let days) where days >= 3650:
            return .year
        case .finite(let days) where days >= 365:
            return .month
        case .finite, .insufficientData, .invalidData:
            return .day
        }
    }

    private func cellCount(freedomDays state: FreedomState, unit: FreedomMath.GridUnit) -> Int {
        switch state {
        case .covered:
            return unit.maxCells
        case .insufficientData, .invalidData:
            return 0
        case .finite(let days):
            let divisor: Double
            switch unit {
            case .day: divisor = 1
            case .month: divisor = 30.44
            case .year: divisor = 365.25
            }
            return FinancialFormatting.gridCount(
                days: days,
                divisor: divisor,
                maximum: unit.maxCells
            )
        }
    }

    private func blueCells(count: Int, locked: Double, netWorth: Double) -> Int {
        FinancialFormatting.assetCellSplit(
            count: count,
            lockedAssets: locked,
            netWorth: netWorth
        ).blue
    }

    private func isInvalid(_ state: FreedomState) -> Bool {
        if case .invalidData = state { return true }
        return false
    }

    private func isInsufficient(_ state: FreedomState) -> Bool {
        if case .insufficientData = state { return true }
        return false
    }

    // ============================================================================
    // MARK: - 预览计算(支出 / 收入)
    // ============================================================================

    /// 一次模拟的完整结果 —— preview 表格和格子推演共用一份, 保证数字一致。
    private struct SimOutcome {
        let lockedAssets: Double
        let currentNW: Double
        let newNW: Double
        let currentAvg: Double
        let newAvg: Double
        let currentFreedom: FreedomState
        let newFreedom: FreedomState
    }

    private func outcome(amount: Double) -> SimOutcome {
        let locked = assetsArr.first?.lockedAssets ?? 0
        let cash = assetsArr.first?.cash ?? 0
        let currentNW = locked + cash
        let firstDate = FreedomMath.earliestExpenseDate(expenses)
        let days = FreedomMath.trackDays(firstRecordDate: firstDate)
        let dailyPassive = FreedomMath.dailyPassive(sources: passiveSources)
        let totalExp = expenses.reduce(0) { $0 + $1.amount }
        let currentAvg = FreedomMath.dailyBurn(totalExpenses: totalExp, trackDays: days)
        let currentFreedom = FreedomMath.freedomState(
            netWorth: currentNW,
            dailyBurn: currentAvg,
            dailyPassive: dailyPassive,
            hasExpenses: !expenses.isEmpty
        )

        let newNW: Double
        let newAvg: Double
        let newHasExpenses: Bool
        if mode == .expense {
            let newFirstDate = min(firstDate ?? Date.now, Date.now)
            let newDays = FreedomMath.trackDays(firstRecordDate: newFirstDate)
            newNW = currentNW - amount
            newAvg = FreedomMath.dailyBurn(totalExpenses: totalExp + amount, trackDays: newDays)
            newHasExpenses = true
        } else {
            newNW = currentNW + amount
            newAvg = currentAvg   // 收入不改日均消费
            newHasExpenses = !expenses.isEmpty
        }
        let newFreedom = FreedomMath.freedomState(
            netWorth: newNW,
            dailyBurn: newAvg,
            dailyPassive: dailyPassive,
            hasExpenses: newHasExpenses
        )

        return SimOutcome(lockedAssets: locked, currentNW: currentNW, newNW: newNW,
                          currentAvg: currentAvg, newAvg: newAvg,
                          currentFreedom: currentFreedom, newFreedom: newFreedom)
    }

    private func expensePreview(amount: Double) -> some View {
        let o = outcome(amount: amount)
        let freedomLoss: String
        if case .finite(let currentDays) = o.currentFreedom,
           case .finite(let newDays) = o.newFreedom,
           let daysLost = FinancialFormatting.integer(
               max(0, currentDays - newDays),
               rounded: .toNearestOrAwayFromZero
           ) {
            freedomLoss = "−\(daysLost) 天"
        } else {
            freedomLoss = "—"
        }

        return VStack(alignment: .leading, spacing: 10) {
            impactRow(label: "KILL 1 净值",
                      from: formatYuan(o.currentNW),
                      to: formatYuan(o.newNW),
                      delta: "−\(formatYuan(amount))",
                      color: Color.vermillion)

            impactRow(label: "KILL 2 日均",
                      from: formatYuan(o.currentAvg, precision: 1),
                      to: formatYuan(o.newAvg, precision: 2),
                      delta: o.currentAvg.isFinite
                          ? "+\(formatYuan(o.newAvg - o.currentAvg, precision: 2))"
                          : "—",
                      color: Color.vermillion)

            // from/to 智能档, delta 固定天
            impactRow(label: "KILL 3 自由天数",
                      from: FreedomMath.freedomDaysDisplay(o.currentFreedom),
                      to: FreedomMath.freedomDaysDisplay(o.newFreedom),
                      delta: freedomLoss,
                      color: Color.vermillion)
        }
    }

    private func incomePreview(amount: Double) -> some View {
        let o = outcome(amount: amount)
        let freedomGain: String
        if case .finite(let currentDays) = o.currentFreedom,
           case .finite(let newDays) = o.newFreedom,
           let daysGained = FinancialFormatting.integer(
               max(0, newDays - currentDays),
               rounded: .toNearestOrAwayFromZero
           ) {
            freedomGain = "+\(daysGained) 天"
        } else {
            freedomGain = "—"
        }

        return VStack(alignment: .leading, spacing: 10) {
            impactRow(label: "GAIN 1 净值",
                      from: formatYuan(o.currentNW),
                      to: formatYuan(o.newNW),
                      delta: "+\(formatYuan(amount))",
                      color: Color.skyDeep)

            // from/to 智能档, delta 固定天
            impactRow(label: "GAIN 2 自由天数",
                      from: FreedomMath.freedomDaysDisplay(o.currentFreedom),
                      to: FreedomMath.freedomDaysDisplay(o.newFreedom),
                      delta: freedomGain,
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
    private func formatYuan(_ value: Double, precision: Int? = nil) -> String {
        // 零支出账本打开"模拟一笔"时 currentAvg 是 NaN,不挡会渲染成 "¥NaN"。
        guard value.isFinite else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        // 默认档(precision=nil): 整数干净显示, 有小数才补到最多 2 位 —— 与流水列表口径一致,
        // 避免 3.5 / 4.5 被舍成 4(原来 min=max=0 用银行家舍入, 两者都进 4)。
        f.minimumFractionDigits = precision ?? 0
        f.maximumFractionDigits = precision ?? 2
        let s = f.string(from: NSNumber(value: value)) ?? String(format: "%.\(precision ?? 2)f", value)
        return "¥\(s)"
    }
}

// ============================================================================
// MARK: - Preview
// ============================================================================

#Preview {
    let container = try! StoreBootstrap.makeContainer(isStoredInMemoryOnly: true)
    ContentView()
        .modelContainer(container)
}
