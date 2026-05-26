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
// MARK: - LifeGrid (1825 格生命网格 View)
// ============================================================================
// 设计动机: 把"自由天数"这个数字可视化为格子。
// 不渲染 1825 个未亮格子(避免挫败感),只显示已点亮(资产蓝 + 收入金)。
// 网格随屏幕宽度自适应列数,行数随内容增长。
//
// 性能: LazyVGrid 懒加载,即使 1825 格也不卡。

struct LifeGrid: View {
    let blueDays: Int       // 资产蓝格
    let yellowDays: Int     // 收入金格

    /// 呼吸动画状态: 1.2 ↔ 1.4 之间循环,模拟"小灯泡发光呼吸"
    /// 比 web 版幅度更克制,避免光污染
    @State private var breatheScale: CGFloat = 1.2

    private let cellSize: CGFloat = 8
    private let spacing: CGFloat = 2

    private var totalLit: Int { blueDays + yellowDays }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: cellSize, maximum: cellSize),
                               spacing: spacing)],
            spacing: spacing
        ) {
            ForEach(0..<totalLit, id: \.self) { i in
                let isCurrent = (i == totalLit - 1)   // 最后一格 = current
                let isBlue = i < blueDays

                // 基础色 vs 当前态(中间值,不要太浅)
                let baseColor = isBlue ? Color(hex: "9cc3ff") : Color(hex: "ffd166")
                let currentColor = isBlue ? Color(hex: "b8d5f0") : Color(hex: "ffdc88")
                let glowColor = isBlue ? Color(hex: "9cc3ff") : Color(hex: "ffd166")

                Rectangle()
                    .fill(isCurrent ? currentColor : baseColor)
                    .frame(width: cellSize, height: cellSize)
                    .cornerRadius(1.5)
                    // 单层光晕:同色,半径小,克制不刺眼
                    .shadow(color: isCurrent ? glowColor.opacity(0.5) : .clear,
                            radius: isCurrent ? 3 : 0)
                    // 呼吸放大:current 格子在 1.2-1.4 之间微微动
                    .scaleEffect(isCurrent ? breatheScale : 1.0)
                    .zIndex(isCurrent ? 1 : 0)
            }
        }
        .onAppear {
            // 呼吸动画: 1.2 ↔ 1.4 循环,周期 1.6s
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breatheScale = 1.4
            }
        }
    }
}

// ============================================================================
// MARK: - ContentView (Tab 主框架)
// ============================================================================

struct ContentView: View {
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard          // Freedom Days 大数字
                    statCardsRow      // 三联卡
                    todayCard         // 今日 vs 日均对比
                    gridCard          // 1825 格生命网格(产品记忆点)
                    actionRow         // [添加支出] [添加收入] 双按钮
                    simulateButton    // [模拟一笔] 决策辅助
                }
                .padding()
            }
            .navigationTitle("FreeGrid")
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
    // MARK: - Hero & 三联卡 (UI 组件)
    // ============================================================================

    /// Hero 卡片: 大字显示 Freedom Days,配公式说明
    /// 设计动机: 这是 lead-wealth 的灵魂指标,放最顶 + 用最大字号
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Freedom Days")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(1.5)

            // Serif 字体匹配 lead-wealth web 版的 editorial 气质
            Text(freedomDaysDisplay)
                .font(.system(size: 56, weight: .light, design: .serif))

            Text("你的自由还能撑多久")
                .font(.callout)
                .foregroundColor(.secondary)

            Text("(资产 + 净储蓄) ÷ 日均消费")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    /// 三联卡: 横向并列 3 个指标
    private var statCardsRow: some View {
        HStack(spacing: 12) {
            statCard(title: "Daily Burn",
                     value: String(format: "%.0f", dailyBurn),
                     unit: "元/天")
            statCard(title: "Passive Ratio",
                     value: String(format: "%.0f%%", passiveRatio * 100),
                     unit: "被动覆盖")
            statCard(title: "Track Days",
                     value: "\(trackDays)",
                     unit: "持续追踪")
        }
    }

    /// 通用 stat 卡片样式
    private func statCard(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(1)
            Text(value)
                .font(.title2)
                .fontWeight(.medium)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(6)
    }

    /// 今日 vs 日均卡片:让用户即时感知今天花得多还是少
    /// 对应 lead-wealth web 版的 "Today vs Average"
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today vs Average")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.5)
                Spacer()
                // 右上角小字: "今日 X / 日均 Y (P%)"
                Text(String(format: "%.0f / %.0f (%.0f%%)",
                            todaySpending, dailyBurn, todayPercent * 100))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            // 主要文案:今日已花 + 对比文案
            Text(todayVsAvgText)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
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

    /// 生命网格卡片:1825 格可视化
    /// 设计动机: lead-wealth 的产品记忆点 — 把数字翻译成空间感
    /// 资产蓝 + 收入金 + 图例 + 文案
    /// 视觉: 深色背景让蓝色"发光",对应 web 版的设计语言
    private var gridCard: some View {
        let state = FreedomMath.gridState(assets: totalAssets,
                                          netSavings: netSavings,
                                          dailyBurn: dailyBurn)
        return VStack(alignment: .leading, spacing: 12) {
            // 标题行: 左标题 + 右总计
            HStack(alignment: .firstTextBaseline) {
                Text("Freedom Grid")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(1.5)
                Spacer()
                Text(gridSummary(state: state))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                    .monospacedDigit()
            }

            // 网格本身。没数据时显示提示文案
            if state.totalLit == 0 {
                emptyGridHint
            } else {
                LifeGrid(blueDays: state.blueDays, yellowDays: state.yellowDays)
            }

            // 图例: 蓝资产 + 金收入
            HStack(spacing: 16) {
                legendDot(color: Color(hex: "9cc3ff"), label: "资产")
                legendDot(color: Color(hex: "ffd166"), label: "收入")
                Spacer()
            }
            .padding(.top, 4)

            Text("每格 = 1 天自由 · 5 年上限 = 1825 格")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.35))
        }
        .padding()
        .background(Color(hex: "0e0e1c"))   // 深色底,模仿 web 版
        .cornerRadius(8)
    }

    /// 图例点: 一个色块 + 标签
    /// 在深色 gridCard 背景上使用,所以文字用白色透明
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 10, height: 10)
                .cornerRadius(1.5)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    /// 网格右上角的总计文案: "X 天 · 资产 Y / 收入 Z"
    /// 溢出 1825 时显示"已达上限"
    private func gridSummary(state: FreedomMath.GridState) -> String {
        if state.totalLit == 0 { return "等待支出数据" }
        if state.isOverflow {
            return "\(state.totalLit) 天 · 已达 5 年上限"
        }
        return "\(state.totalLit) 天 · 蓝 \(state.blueDays) / 金 \(state.yellowDays)"
    }

    /// 空网格时的友好提示
    private var emptyGridHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("记录第一笔支出后\n格子才能开始计算")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// 收支双按钮:左红支出 / 右绿收入
    /// 设计动机: 对称的视觉,符合"记账即认知,认知即决策"的产品哲学
    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                showingAddExpense = true
            } label: {
                Label("添加支出", systemImage: "minus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .tint(.red)
            .buttonStyle(.borderedProminent)

            Button {
                showingAddIncome = true
            } label: {
                Label("添加收入", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .tint(.green)
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 8)
    }

    /// 模拟按钮:决策辅助专用入口,视觉次于主操作
    /// 设计动机: "要不要买"在决策前先预演,不污染真实账本。
    /// 用 .bordered 而不是 .borderedProminent,视觉强度低于支出/收入。
    private var simulateButton: some View {
        Button {
            showingSimulate = true
        } label: {
            Label("模拟一笔(决策预演)", systemImage: "wand.and.stars")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .tint(.purple)
        .buttonStyle(.bordered)
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

    private var freedomDaysDisplay: String {
        if freedomDays.isInfinite { return "∞" }
        return String(format: "%.0f", freedomDays)
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

    /// Hero: 大字显示当前资产
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Assets")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(1.5)

            Text("¥" + currentAsset.formatted(.number))
                .font(.system(size: 44, weight: .light, design: .serif))

            if let updated = assetsArr.first?.updatedAt {
                Text("上次更新: \(updated, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("尚未设置")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    /// 编辑表单: 输入新值 → 更新按钮
    private var editForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("更新资产")
                .font(.headline)

            HStack {
                Text("¥")
                    .foregroundColor(.secondary)
                TextField("0", text: $newAmount)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }

            Button {
                updateAsset()
            } label: {
                Label(showSavedHint ? "已保存" : "更新", systemImage: showSavedHint ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    /// 说明卡片: 帮助用户理解"资产"的含义
    private var explainCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("什么算资产", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("可变现资产 = 存款 + 余额宝 + 货币基金等\"随时能用的钱\"。\n这是 Freedom Days 的基准:每次记账时会自动扣减(支出)/增加(收入),你也可以随时手动同步真实余额。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }

    // ============================================================================
    // MARK: - 数据管理卡片
    // ============================================================================
    // 导入 lead-wealth web 版的 JSON 备份 + 清空所有数据
    // 适用场景:从 web 版迁移历史数据 / 重置测试数据

    private var dataManagementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("数据管理", systemImage: "externaldrive")
                .font(.headline)

            // 导入按钮
            Button {
                showingFileImporter = true
            } label: {
                Label("从 JSON 导入", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)

            // 清空按钮(危险操作,红色 + 二次确认)
            Button(role: .destructive) {
                showingPurgeAlert = true
            } label: {
                Label("清空所有数据", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)

            // 操作结果反馈(成功/失败信息)
            if let status = importStatus {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
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
            .navigationTitle("History")
        }
    }

    // ============================================================================
    // MARK: - 列表渲染
    // ============================================================================

    private var transactionList: some View {
        List {
            // 顶部统计行: 共 X 笔 · 净 ¥X
            Section {
                HStack {
                    Text("共 \(filteredTransactions.count) 笔")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("净 \(netDisplay)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .font(.caption)
            }

            Section {
                ForEach(filteredTransactions) { tx in
                    transactionRow(tx)
                }
                .onDelete(perform: deleteTransactions)
            }
        }
    }

    /// 单行渲染:根据 enum 分发到 expense/income 两种样式
    @ViewBuilder
    private func transactionRow(_ tx: TxKind) -> some View {
        switch tx {
        case .expense(let e):
            expenseRow(e)
        case .income(let i):
            incomeRow(i)
        }
    }

    /// 支出行:红色金额 + 分类标签 + 备注 + 日期
    private func expenseRow(_ e: Expense) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(e.category)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if !e.note.isEmpty {
                    Text(e.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text(e.date, format: .dateTime.year().month().day())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("−¥" + e.amount.formatted(.number.precision(.fractionLength(0...2))))
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.red)
                .monospacedDigit()
        }
    }

    /// 收入行:绿色金额 + 来源 + 被动标签(如果是) + 备注 + 日期
    private func incomeRow(_ i: Income) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(i.source)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if i.isPassive {
                        Text("被动")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(3)
                    }
                }
                if !i.note.isEmpty {
                    Text(i.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text(i.date, format: .dateTime.year().month().day())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("+¥" + i.amount.formatted(.number.precision(.fractionLength(0...2))))
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.green)
                .monospacedDigit()
        }
    }

    /// 空状态:友好引导用户回 Dashboard 记账
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("还没有记录")
                .font(.title3)
            Text("回 Dashboard 添加第一笔支出或收入")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            VStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Check")
                    .font(.title2)
                Text("财富自由自检清单\n即将上线")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
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
                }

                // ===== 戴维斯三杀实时预览 =====
                // 设计动机: 这是 lead-wealth 的产品记忆点,把记账变成"决策辅助"。
                // 用户输入金额的瞬间看到三杀传导:储蓄变少 → 日均上涨 → 自由天数缩水
                // 只有金额有效(> 0)时显示,避免空预览占空间
                if let amt = Double(amount), amt > 0 {
                    Section {
                        impactPreview(amount: amt)
                    } header: {
                        Text("戴维斯三杀预览")
                    } footer: {
                        Text("这笔消费对自由天数的传导效应。还没保存,只是看看。")
                            .font(.caption2)
                    }
                }
            }
            .navigationTitle("添加支出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isAmountValid)
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

    /// 单行 KILL 显示:label + from → to + delta
    /// 设计:label 灰色小字,数值黑色等宽,delta 红色(支出场景)
    private func killRow(label: String, from: String, to: String, delta: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            HStack {
                Text("\(from) → \(to)")
                    .font(.callout)
                    .monospacedDigit()
                Spacer()
                Text(delta)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                    .monospacedDigit()
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
                }
                Section("来源") {
                    TextField("工资 / 投资 / 副业 / ...", text: $source)
                }
                Section {
                    Toggle("这是被动收入", isOn: $isPassive)
                } footer: {
                    // 解释什么是被动收入,帮助用户做出正确选择
                    Text("被动收入: 不需要持续工作就能稳定获得的收入(房租/股息/版税/利息)。\n勾选后会纳入「被动覆盖率」统计,这是财富自由的核心指标。")
                        .font(.caption2)
                }
                Section("日期") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }
                Section("备注 (可选)") {
                    TextField("备注", text: $note)
                }

                // ===== 自由增长预览 =====
                // 设计动机: 和支出的"戴维斯三杀"对称,但语义是正向的——
                // "这笔钱给你买回多少天自由"。绿色 + 加号,鼓励多记收入。
                if let amt = Double(amount), amt > 0 {
                    Section {
                        gainPreview(amount: amt)
                    } header: {
                        Text("自由增长预览")
                    } footer: {
                        Text("这笔收入对自由天数的回血效应。")
                            .font(.caption2)
                    }
                }
            }
            .navigationTitle("添加收入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isValid)
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

    /// 单行 GAIN 显示:绿色正向变化(和 KILL 的红色对称)
    private func gainRow(label: String, from: String, to: String, delta: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            HStack {
                Text("\(from) → \(to)")
                    .font(.callout)
                    .monospacedDigit()
                Spacer()
                Text(delta)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                    .monospacedDigit()
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
                VStack(spacing: 16) {
                    bannerCard         // 顶部"不会真实记账"提示
                    modePicker         // 支出/收入切换
                    amountInput        // 金额输入
                    if let amt = Double(amount), amt > 0 {
                        previewCard(amount: amt)   // 实时影响预览
                    } else {
                        hintCard       // 提示用户输入金额
                    }
                }
                .padding()
            }
            .navigationTitle("模拟决策")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // ============================================================================
    // MARK: - 子组件
    // ============================================================================

    /// 顶部 banner:明确提示这是模拟模式
    private var bannerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("模拟模式")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("不会扣资产,不会写入账本,只是看看决策影响。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(8)
    }

    /// 模式切换:Segmented
    private var modePicker: some View {
        Picker("模拟类型", selection: $mode) {
            ForEach(Mode.allCases) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    /// 金额输入(独立卡片样式,和 Sheet 整体一致)
    private var amountInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mode == .expense ? "假设花掉(元)" : "假设收入(元)")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            HStack {
                Text("¥")
                    .foregroundColor(.secondary)
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                    .font(.title3)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    /// 未输入金额时的占位提示
    private var hintCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.up")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("输入金额,实时看决策影响")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    /// 影响预览卡片:根据 mode 显示 KILL 或 GAIN
    private func previewCard(amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .expense ? "戴维斯三杀预览" : "自由增长预览")
                .font(.headline)

            if mode == .expense {
                expensePreview(amount: amount)
            } else {
                incomePreview(amount: amount)
            }

            Text(mode == .expense
                 ? "这笔消费对自由天数的传导效应。"
                 : "这笔收入对自由天数的回血效应。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
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
                      color: .red)

            impactRow(label: "KILL 2 日均",
                      from: formatYuan(currentAvg, precision: 1),
                      to: formatYuan(newAvg, precision: 2),
                      delta: "+\(formatYuan(newAvg - currentAvg, precision: 2))",
                      color: .red)

            impactRow(label: "KILL 3 自由天数",
                      from: FreedomMath.freedomDaysDisplay(currentFreedom),
                      to: FreedomMath.freedomDaysDisplay(newFreedom),
                      delta: currentFreedom.isInfinite ? "—" : "−\(String(format: "%.1f", freedomLoss)) 天",
                      color: .red)
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
                      color: .green)

            impactRow(label: "GAIN 2 自由天数",
                      from: FreedomMath.freedomDaysDisplay(currentFreedom),
                      to: FreedomMath.freedomDaysDisplay(newFreedom),
                      delta: currentFreedom.isInfinite
                          ? "—"
                          : "+\(String(format: "%.1f", freedomGain)) 天",
                      color: .green)
        }
    }

    /// 通用影响行:label + from → to + delta(支持红/绿配色)
    private func impactRow(label: String, from: String, to: String,
                           delta: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            HStack {
                Text("\(from) → \(to)")
                    .font(.callout)
                    .monospacedDigit()
                Spacer()
                Text(delta)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(color)
                    .monospacedDigit()
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
