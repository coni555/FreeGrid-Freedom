// 四个 Tab 的装配入口；页面内容各自在 Features 中。

import SwiftUI
import SwiftData

private enum AppTab: Hashable {
    case dashboard
    case assets
    case history
    case settings
}

struct ContentView: View {
    /// 跨启动持久化主题选择：跟随系统时不指定，否则按 isDarkMode 固定浅色或深色
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage(AppTheme.followsSystemKey, store: AppPreferences.store) private var followsSystem = false
    @State private var selectedTab: AppTab = .dashboard

    /// 全 App 的指引；遮罩要盖住导航栏和 Tab 栏，所以由这里持有
    @State private var guide = AppGuide()
    @AppStorage("historyGuideCompleted", store: AppPreferences.store) private var historyGuideCompleted = false
    /// 起步引导点了「跳过引导」后不再出现
    @AppStorage("setupGuideCompleted", store: AppPreferences.store) private var setupGuideCompleted = false

    /// 2.0 的 Pro 介绍：新老用户各一版，只弹一次（规则在 ProIntro）。新还是老在第一次打开时记下
    @AppStorage(ProIntro.audienceKey, store: AppPreferences.store) private var introAudience = ""
    @AppStorage(ProIntro.shownKey, store: AppPreferences.store) private var introShown = false
    @State private var presentedIntro: ProIntro.Audience?

    // 起步引导走到哪一步由账本决定
    @Query private var expenses: [Expense]
    @Query private var assetsArr: [UserAssets]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
    @Environment(MenuActions.self) private var menuActions
    #endif

    var body: some View {
        #if os(macOS)
        @Bindable var actions = menuActions
        return tabView
            // 菜单栏 ⌘N / ⌘⇧N 在根层唤起快速记账(任意 Tab 下可用)
            .sheet(isPresented: $actions.addExpense) {
                AddExpenseSheet()
            }
            .sheet(isPresented: $actions.addIncome) {
                AddIncomeSheet()
            }
        #else
        return tabView
        #endif
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
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

            SettingsView(onReplayGuide: { tour in
                guide.requestReplay(tour)
                selectedTab = tab(for: tour)
            })
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .environment(guide)
        .overlay {
            if let tour = guide.tour, selectedTab == tab(for: tour) {
                GuideOverlay(guide: guide) { finished in
                    if finished == .history { historyGuideCompleted = true }
                    // 新用户讲完首页，起步这一段就结束了
                    if finished == .dashboard { Task { await offerProIntro() } }
                }
            } else if let step = setupStep {
                SetupGuideOverlay(
                    step: step, guide: guide,
                    onGoAssets: { selectedTab = .assets },
                    onGoDashboard: { selectedTab = .dashboard },
                    onSkip: { withAnimation(.easeInOut(duration: 0.25)) { setupGuideCompleted = true } }
                )
            }
        }
        // 新用户记完第一笔支出、起步引导结束后, 接着讲一遍首页
        .onChange(of: setupStep) { old, new in
            guard old == .expense, new == nil, !setupGuideCompleted else { return }
            setupGuideCompleted = true
            guide.requestReplay(.dashboard)
        }
        // Pro 每月还款：打开 App 和回到前台时补扣到期的月供。失败时什么都不改，下次再来
        .task {
            try? LoanStore.processDue(in: modelContext)
            // 早期开发版里资产拆分后总开关还管着各项；现在由各项自己决定，旧的「关」交给各项接手
            if !FreedomSettings.countsAssets, (try? AssetItemStore.adoptSwitchOff(in: modelContext)) == true {
                AppPreferences.store.set(true, forKey: FreedomSettings.countsAssetsKey)
            }
            if ProIntro.Audience(rawValue: introAudience) == nil {
                let expenseCount = (try? modelContext.fetchCount(FetchDescriptor<Expense>())) ?? 0
                introAudience = ProIntro.audience(hasExpenses: expenseCount > 0).rawValue
            }
            await offerProIntro()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            try? LoanStore.processDue(in: modelContext)
            // 新用户跳过起步引导后不马上弹，等下次回到 App
            Task { await offerProIntro() }
        }
        .proIntro($presentedIntro) { introShown = true }
        // tab 选中态吃 sky 主色,品牌一致
        .tint(Color.sky)
        // 用户在 topBar 切换 dark/light,全 app 自动重绘；跟随系统时交给系统
        .preferredColorScheme(followsSystem ? nil : (isDarkMode ? .dark : .light))
    }
}

extension ContentView {
    private func tab(for tour: AppGuide.Tour) -> AppTab {
        switch tour {
        case .dashboard: return .dashboard
        case .assets, .moneyTimeAssets: return .assets
        case .history: return .history
        case .settings: return .settings
        }
    }

    /// 屏幕空着、轮到了就弹 Pro 介绍。先停一下，让刚结束的讲解或启动时的动画收干净，停完再看一遍。
    /// 弹出来才记「弹过了」：被别的弹窗挡住没弹成时，下次打开 App 再试
    private func offerProIntro() async {
        guard !introShown, presentedIntro == nil, !ProIntro.isSuppressedForTesting,
              let audience = ProIntro.Audience(rawValue: introAudience) else { return }
        try? await Task.sleep(for: .seconds(1.2))
        let store = ProStore.shared
        await store.loadProducts()
        guard ProIntro.shouldOffer(audience: audience, alreadyShown: introShown, ownsPro: store.ownsPro,
                                   hasStartedTrial: store.offer.hasStartedTrial,
                                   canStartTrial: ProPrices.current(store)?.hasTrial == true,
                                   setupFinished: setupGuideCompleted || !expenses.isEmpty),
              presentedIntro == nil, selectedTab == .dashboard, guide.tour == nil, setupStep == nil else { return }
        presentedIntro = audience
    }

    /// 起步引导现在该显示哪一步；nil 表示不显示。
    /// 只给一笔支出都没有的新账本；在 History 和 Settings 里不拦着用户。
    private var setupStep: SetupGuideStep? {
        guard !setupGuideCompleted, guide.tour == nil, expenses.isEmpty else { return nil }
        let assets = assetsArr.first
        let hasMoney = ((assets?.cash ?? 0) + (assets?.lockedAssets ?? 0)) > 0
        switch (selectedTab, hasMoney) {
        case (.dashboard, false): return .welcome
        case (.assets, false): return .cash
        case (.assets, true): return .backHome
        case (.dashboard, true): return .expense
        default: return nil
        }
    }
}

#Preview {
    let container = try! StoreBootstrap.makeContainer(isStoredInMemoryOnly: true)
    ContentView()
        .modelContainer(container)
        #if os(macOS)
        .environment(MenuActions())
        #endif
}
