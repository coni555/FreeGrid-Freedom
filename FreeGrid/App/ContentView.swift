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

    /// 2.0 的 Pro 介绍：老用户打开时在首页弹一次卡片，新用户不弹（规则在 ProIntro）。
    /// 新还是老在第一次打开时记下
    @AppStorage(ProIntro.audienceKey, store: AppPreferences.store) private var introAudience = ""
    @AppStorage(ProIntro.shownKey, store: AppPreferences.store) private var introShown = false
    @State private var showingReturningIntro = false
    /// 新用户记满 7 天时的「记账 7 天的小结」，弹一次（规则在 FirstWeekRecap）
    @AppStorage(FirstWeekRecap.shownKey, store: AppPreferences.store) private var recapShown = false
    @State private var weekRecap: FirstWeekRecap.Summary?

    // 起步引导走到哪一步由账本决定
    @Query private var expenses: [Expense]
    @Query private var assetsArr: [UserAssets]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    /// 体验结束或退款后弹一次「回到免费版」
    @State private var showingBackToFree = false
    /// 该弹「回到免费版」、还没真的出现过。别的弹层开着时它出不来，留着下次再弹
    @State private var backToFreePending = false

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
        // 打开 App 和回到前台时补扣到期的房租、月供
        .task {
            processDuePayments()
            // 早期开发版里资产拆分后总开关还管着各项；现在由各项自己决定，旧的「关」交给各项接手
            if !FreedomSettings.countsAssets, (try? AssetItemStore.adoptSwitchOff(in: modelContext)) == true {
                AppPreferences.store.set(true, forKey: FreedomSettings.countsAssetsKey)
            }
            if !ProIntro.isSuppressedForTesting, ProIntro.Audience(rawValue: introAudience) == nil {
                let expenseCount = (try? modelContext.fetchCount(FetchDescriptor<Expense>())) ?? 0
                introAudience = ProIntro.audience(hasExpenses: expenseCount > 0).rawValue
            }
            await offerProIntro()
            await offerWeekRecap()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            processDuePayments()
            checkProLapse()
            Task {
                await offerProIntro()
                await offerWeekRecap()
            }
        }
        // 第 7 天记下一笔时就弹，不用等下次打开
        .onChange(of: expenses.count) { Task { await offerWeekRecap() } }
        .task { checkProLapse() }
        // 体验到点、退款在 App 开着时也会发生
        .onChange(of: ProStore.shared.isUnlocked) { checkProLapse() }
        // 启动时先等和 App Store 核对完再判断
        .onChange(of: ProStore.shared.hasCheckedEntitlements) {
            processDuePayments()
            checkProLapse()
        }
        .sheet(isPresented: $showingBackToFree) {
            BackToFreeSheet().onAppear { backToFreePending = false }
        }
        .returningProIntro(isPresented: $showingReturningIntro) { introShown = true }
        .firstWeekRecap($weekRecap) { recapShown = true }
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

    /// 轮到了、首页也空着就弹老用户的卡片。
    /// 先停一下，让启动动画收干净，停完再看一遍。
    /// 卡片真的出现才记「弹过了」，没弹成的下次打开再试
    private func offerProIntro() async {
        guard !introShown, !showingReturningIntro, !ProIntro.isSuppressedForTesting,
              let audience = ProIntro.Audience(rawValue: introAudience), audience == .returning,
              selectedTab == .dashboard else { return }
        try? await Task.sleep(for: .seconds(1.2))
        let store = ProStore.shared
        await store.loadProducts()
        guard ProIntro.shouldOffer(audience: audience, alreadyShown: introShown, ownsPro: store.ownsPro,
                                   hasStartedTrial: store.offer.hasStartedTrial,
                                   canStartTrial: ProIntro.trialIsAvailable(store)),
              !showingReturningIntro, !showingBackToFree, selectedTab == .dashboard, guide.tour == nil,
              setupStep == nil
        else { return }
        // 卡片自己做出现的动画，弹层本身不滑入
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { showingReturningIntro = true }
        await releaseIfNotShown(shownKey: ProIntro.shownKey) { showingReturningIntro = false }
    }

    /// 新用户记满 7 天、首页空着就弹「记账 7 天的小结」。和老用户的卡片一样先停一下，停完再看一遍；
    /// 卡片真的出现才记「弹过了」
    private func offerWeekRecap() async {
        guard !recapShown, weekRecap == nil, !ProIntro.isSuppressedForTesting,
              ProIntro.Audience(rawValue: introAudience) == .newcomer, selectedTab == .dashboard,
              FirstWeekRecap.recordedDays(expenses) >= FirstWeekRecap.requiredDays else { return }
        try? await Task.sleep(for: .seconds(1.2))
        let store = ProStore.shared
        await store.loadProducts()
        guard FirstWeekRecap.shouldShow(audience: ProIntro.Audience(rawValue: introAudience), alreadyShown: recapShown,
                                        recordedDays: FirstWeekRecap.recordedDays(expenses)),
              weekRecap == nil, !showingReturningIntro, !showingBackToFree, selectedTab == .dashboard,
              guide.tour == nil, setupStep == nil
        else { return }
        let mentionsPro = FirstWeekRecap.mentionsPro(ownsPro: store.ownsPro, hasStartedTrial: store.offer.hasStartedTrial,
                                                     canStartTrial: ProIntro.trialIsAvailable(store))
        let summary = FirstWeekRecap.summary(expenses: expenses, snapshot: dashboardSnapshot(), mentionsPro: mentionsPro)
        // 卡片自己做出现的动画，弹层本身不滑入
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { weekRecap = summary }
        await releaseIfNotShown(shownKey: FirstWeekRecap.shownKey) { weekRecap = nil }
    }

    /// 首页正开着记账、模拟这类弹层时，这里的弹层出不来，标记却一直是 true，之后每一次都会被它挡掉。
    /// 等一会儿还没出现（`shownKey` 还没记上）就放下标记，下次回到前台或记下一笔时再试。
    /// 直接读偏好：启动时 .task 里拿着的这份 ContentView，@AppStorage 读到的还是旧值
    private func releaseIfNotShown(shownKey: String, release: () -> Void) async {
        try? await Task.sleep(for: .seconds(1))
        if !AppPreferences.store.bool(forKey: shownKey) { release() }
    }

    /// 补扣到期的房租、月供（没有 Pro 时贷款停用，不扣）。失败时什么都不改，下次再来。
    /// 先等和 App Store 核对过：本机记的 Pro 状态可能是旧的（换机重装、在别的设备上买的），
    /// 照旧状态停用的那几期会记成没扣成，之后不会再自动扣
    private func processDuePayments() {
        let store = ProStore.shared
        guard store.hasCheckedEntitlements else { return }
        // 从后台回来时「现在」可能还停在体验到期之前
        store.tick()
        try? LoanStore.processDue(pausesTermLoans: !ProFeatures.canManageLoans, in: modelContext)
    }

    /// 和首页同样的算法和输入，卡片上的日均、自由天数和首页一致。
    /// 只在要弹卡片时现取，不在这里多挂几个 @Query（不然每改一笔资产整个 TabView 都要重算）
    private func dashboardSnapshot() -> FinancialSnapshot {
        func all<Model: PersistentModel>(_ type: Model.Type) -> [Model] {
            (try? modelContext.fetch(FetchDescriptor<Model>())) ?? []
        }
        return FinancialSnapshot(expenses: expenses, passiveSources: all(PassiveSource.self), assets: assetsArr.first,
                                 assetItems: all(AssetItem.self), cashAccounts: all(CashAccount.self),
                                 loans: ProFeatures.loansInEffect(all(Loan.self)), countsAssets: FreedomSettings.countsAssets)
    }

    /// Pro 刚失效、账本里又有体验期间加的资产项、现金账户或贷款时，弹「回到免费版」。没有就只记下这次变化。
    /// 没弹出来（别的弹层开着）就留着，下次回到前台再弹
    private func checkProLapse() {
        if ProStore.shared.takeLapse() {
            let plan = BackToFreePlan(assetItems: (try? modelContext.fetch(FetchDescriptor<AssetItem>())) ?? [],
                                      cashAccounts: (try? modelContext.fetch(FetchDescriptor<CashAccount>())) ?? [],
                                      loans: (try? modelContext.fetch(FetchDescriptor<Loan>())) ?? [])
            backToFreePending = plan.hasProContent
        }
        guard backToFreePending, !showingBackToFree else { return }
        showingBackToFree = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            if backToFreePending { showingBackToFree = false }
        }
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
