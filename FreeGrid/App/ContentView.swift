// 四个 Tab 的装配入口；页面内容各自在 Features 中。

import SwiftUI
import SwiftData
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
    /// 在设置里换完语言、整棵视图重建后回到设置页
    @State private var selectedTab: AppTab = AppLanguage.switchedInApp ? .settings : .dashboard

    /// 全 App 的指引；遮罩要盖住导航栏和 Tab 栏，所以由这里持有
    @State private var guide = AppGuide()
    @AppStorage("historyGuideCompleted", store: AppPreferences.store) private var historyGuideCompleted = false
    /// 起步引导点了「跳过引导」后不再出现
    @AppStorage("setupGuideCompleted", store: AppPreferences.store) private var setupGuideCompleted = false
    /// 起步引导第 3 步可以改填每月花销，填完和记完第一笔一样，引导结束
    @AppStorage(MonthlySpending.key, store: AppPreferences.store) private var monthlySpending = 0.0
    @State private var showingMonthlySpending = false

    /// 2.0 的 Pro 介绍：老用户打开时在首页弹一次卡片，新用户不弹（规则在 ProIntro）。
    /// 新还是老在第一次打开时记下
    @AppStorage(ProIntro.audienceKey, store: AppPreferences.store) private var introAudience = ""
    @AppStorage(ProIntro.shownKey, store: AppPreferences.store) private var introShown = false
    @State private var showingReturningIntro = false
    /// 新用户记满 7 天时的「记账 7 天的小结」，弹一次（规则在 FirstWeekRecap）
    @AppStorage(FirstWeekRecap.shownKey, store: AppPreferences.store) private var recapShown = false
    @State private var weekRecap: FirstWeekRecap.Summary?

    // 起步引导走到哪一步由账本决定。只要知道有没有支出：取一笔就够。
    // 不挂整本账：这里一取数，SwiftData 会通知所有看过这些支出的页面，记一笔时首页就要多算一遍。
    // 新用户的 7 天小结要整本账时，用 allExpenses() 现取
    @Query(ContentView.anyExpense) private var firstExpenses: [Expense]
    @Query private var assetsArr: [UserAssets]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    /// 体验结束或退款后弹一次「回到免费版」
    @State private var showingBackToFree = false
    /// 该弹「回到免费版」、还没真的出现过。别的弹层开着时它出不来，留着下次再弹
    @State private var backToFreePending = false
    /// 正在试着弹，别再开一轮
    @State private var presentingBackToFree = false
    /// 没有 Pro 时点了看板、目标小组件：打开购买页
    @State private var showingWidgetPro = false
    /// 后台 Tab 的补算口令：记完账空闲下来后逐页加一，那一页按最新的账重画一次（见 TabFreeze）
    @State private var refreshTokens: [AppTab: Int] = [:]
    @State private var catchUp: Task<Void, Never>?
    /// 页面会读到的东西变了几次，后台页面切回来时比一比（见 TabDataClock）
    @State private var dataClock = TabDataClock()
    /// 跟随系统深浅色时，系统换了也算变化
    @Environment(\.colorScheme) private var colorScheme

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
            StableTab(activity: activity(.dashboard), clock: dataClock) { DashboardView() }.equatable()
                .tabItem {
                    Label("首页", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(AppTab.dashboard)

            StableTab(activity: activity(.assets), clock: dataClock) { AssetsView() }.equatable()
                .tabItem {
                    Label("钱包", systemImage: "banknote")
                }
                .tag(AppTab.assets)

            StableTab(activity: activity(.history), clock: dataClock) { HistoryView() }.equatable()
                .tabItem {
                    Label("明细", systemImage: "clock.arrow.circlepath")
                }
                .tag(AppTab.history)

            // 不传闭包：闭包每次都算「变了」，外壳就拦不住重算
            StableTab(activity: activity(.settings), clock: dataClock) { SettingsView() }.equatable()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
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
                    onFillMonthlySpending: { showingMonthlySpending = true },
                    onSkip: { withAnimation(.easeInOut(duration: 0.25)) { setupGuideCompleted = true } }
                )
            }
        }
        .sheet(isPresented: $showingMonthlySpending) { MonthlySpendingSheet() }
        // 设置 → 使用指引里选了一个讲解：切到它讲的那一页
        .onChange(of: guide.replayRequests) { old, new in
            dataClock.tick()
            if let tour = new.first(where: { $0.value > old[$0.key, default: 0] })?.key {
                selectedTab = tab(for: tour)
            }
        }
        // 新用户记完第一笔支出（或填完每月花销）、起步引导结束后, 接着讲一遍首页
        .onChange(of: setupStep) { old, new in
            guard old == .expense, new == nil, !setupGuideCompleted else { return }
            setupGuideCompleted = true
            guide.requestReplay(.dashboard)
        }
        .onChange(of: reviewPresentationAllowed, initial: true) { _, allowed in
            ReviewInvitationStore.shared.presentationAllowed = allowed
            discardReviewIfBlocked()
        }
        .onChange(of: reviewFormPresented, initial: true) { _, presented in
            ReviewInvitationStore.shared.formPresented = presented
        }
        .onChange(of: ReviewInvitationStore.shared.opportunity?.id) { discardReviewIfBlocked() }
        // 打开 App 和回到前台时补扣到期的房租、月供
        .task {
            processDuePayments()
            // 打开 App 就给小组件写一份；和 App Store 核对 Pro 的结果有变化时下面再写
            WidgetPublisher.publish(in: modelContext)
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
            // 隔了一夜再回来，「今天」也变了
            dataClock.tick()
            processDuePayments()
            checkProLapse()
            Task {
                await offerProIntro()
                await offerWeekRecap()
            }
        }
        .task { checkProLapse() }
        // 体验到点、退款在 App 开着时也会发生
        .onChange(of: ProStore.shared.isUnlocked) { checkProLapse() }
        // 启动时先等和 App Store 核对完再判断
        .onChange(of: ProStore.shared.hasCheckedEntitlements) {
            processDuePayments()
            checkProLapse()
            // 核对完 Pro 再写一份：体验到期、退款后 Pro 小组件跟着变
            WidgetPublisher.publish(in: modelContext)
        }
        .background { tabFreezeSignals }
        // 离开 App 时再写一份：这次打开记的账、改的目标、换的语言都在里面
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { WidgetPublisher.publish(in: modelContext) }
        }
        // 点小组件打开 App：没有 Pro 时点的是 Pro 小组件就去购买页，其余回首页
        .onOpenURL { url in
            guard url.scheme == WidgetLink.scheme else { return }
            selectedTab = .dashboard
            if url.host() == WidgetLink.pro.host(), !ProFeatures.canSetGoals { showingWidgetPro = true }
        }
        .proPaywall(isPresented: $showingWidgetPro, topic: .widgets)
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

/// 四个 Tab 的根页面只从 ContentView 拿「在不在前台」。包一层外壳：
/// 切 Tab 时 ContentView 重画，只有前后台变了的两页往下传，其余页面不跟着把几千笔账重算一遍；
/// 页面自己的数据（@Query、@AppStorage）和环境变了照常刷新，在后台时由页面里的 TabFreeze 挡住
private struct StableTab<Content: View>: View, Equatable {
    let activity: TabActivity
    let clock: TabDataClock
    @ViewBuilder let content: () -> Content

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.activity == rhs.activity }

    var body: some View {
        content()
            .environment(\.tabActivity, activity)
            .environment(\.tabDataClock, clock)
    }
}

extension ContentView {
    /// 既有介绍、小结和引导优先；这次记账被挡住就跳过，不在关弹层后紧接着邀请。
    private var reviewPresentationAllowed: Bool {
        guard selectedTab == .dashboard, scenePhase == .active,
              !showingReturningIntro, weekRecap == nil, !showingBackToFree, !backToFreePending,
              guide.tour == nil, setupStep == nil else { return false }
        if !ProIntro.isSuppressedForTesting {
            let audience = ProIntro.Audience(rawValue: introAudience)
            if audience == .newcomer, !recapShown,
               FirstWeekRecap.recordedDays(allExpenses()) >= FirstWeekRecap.requiredDays { return false }
            if audience == .returning, !introShown,
               !ProStore.shared.ownsPro, !ProStore.shared.offer.hasStartedTrial { return false }
        }
        return true
    }

    private func discardReviewIfBlocked() {
        guard !reviewPresentationAllowed, let id = ReviewInvitationStore.shared.opportunity?.id else { return }
        // TabView 离屏时可能不再运行首页的 task，取消机会必须在根层完成。
        ReviewInvitationStore.shared.discard(id)
    }

    private var reviewFormPresented: Bool {
        #if os(macOS)
        menuActions.addExpense || menuActions.addIncome
        #else
        false
        #endif
    }

    /// 后台页面要知道的变化（见 TabFreeze）。单独挂一个看不见的视图，免得根层那串修饰符太长、编译器算不过来
    private var tabFreezeSignals: some View {
        Color.clear
            // 账本存过一次：后台的页面先不动，等空闲下来再逐页补算，切过去时就不用现算。
            // 第 7 天记下一笔时，小结也不用等下次打开就弹
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                dataClock.tick()
                scheduleCatchUp()
                Task { await offerWeekRecap() }
            }
            // 偏好（资产计不计入、目标、首页卡片、深浅色……）、Pro 状态、系统深浅色变了：后台页面切回来时重算
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: RunLoop.main)) { _ in dataClock.tick() }
            // 首页点「本月花销」：明细页自己回到本月，这里切过去
            .onReceive(NotificationCenter.default.publisher(for: .showThisMonthInHistory)) { _ in selectedTab = .history }
            .onChange(of: ProStore.shared.isUnlocked) { dataClock.tick() }
            .onChange(of: colorScheme) { dataClock.tick() }
    }

    private func activity(_ tab: AppTab) -> TabActivity {
        TabActivity(isActive: selectedTab == tab, refreshToken: refreshTokens[tab, default: 0])
    }

    /// 最后一次存账 3 秒后，后台的三页一页一页补算，中间隔一会儿，免得挤在同一帧里卡一下。
    /// 有表单开着（正在记下一笔、改一笔、模拟）就先不算，等它关上 1.5 秒后再算：补算时 SwiftData 会顺带叫醒首页和开着的表单，
    /// 正在输入时主线程被占满，点金额栏会像没反应。还没打开过的页面加了口令也不会建出来
    private func scheduleCatchUp() {
        catchUp?.cancel()
        catchUp = Task {
            try? await Task.sleep(for: .seconds(3))
            for tab in [AppTab.dashboard, .assets, .history, .settings] where tab != selectedTab {
                await waitUntilNoSheet()
                guard !Task.isCancelled else { return }
                refreshTokens[tab, default: 0] += 1
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// 等到没有表单开着；刚关上的再等 1.5 秒，让收起的动画走完、也看看是不是马上又要记下一笔
    private func waitUntilNoSheet() async {
        var hadSheet = false
        while !Task.isCancelled {
            if Self.isShowingSheet {
                hadSheet = true
            } else if hadSheet {
                hadSheet = false
                try? await Task.sleep(for: .seconds(1.5))
                continue
            } else {
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private static var isShowingSheet: Bool {
        #if os(iOS)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .contains { $0.presentedViewController != nil }
        #else
        NSApplication.shared.keyWindow?.attachedSheet != nil
        #endif
    }

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
              FirstWeekRecap.recordedDays(allExpenses()) >= FirstWeekRecap.requiredDays else { return }
        try? await Task.sleep(for: .seconds(1.2))
        let store = ProStore.shared
        await store.loadProducts()
        let expenses = allExpenses()
        guard FirstWeekRecap.shouldShow(audience: ProIntro.Audience(rawValue: introAudience), alreadyShown: recapShown,
                                        recordedDays: FirstWeekRecap.recordedDays(expenses)),
              weekRecap == nil, !showingReturningIntro, !showingBackToFree, selectedTab == .dashboard,
              guide.tour == nil, setupStep == nil
        else { return }
        let mentionsPro = FirstWeekRecap.mentionsPro(ownsPro: store.ownsPro, hasStartedTrial: store.offer.hasStartedTrial,
                                                     canStartTrial: ProIntro.trialIsAvailable(store))
        let summary = FirstWeekRecap.summary(expenses: expenses, snapshot: dashboardSnapshot(expenses), mentionsPro: mentionsPro)
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
    private func dashboardSnapshot(_ expenses: [Expense]) -> FinancialSnapshot {
        func all<Model: PersistentModel>(_ type: Model.Type) -> [Model] {
            (try? modelContext.fetch(FetchDescriptor<Model>())) ?? []
        }
        return FinancialSnapshot(expenses: expenses, passiveSources: all(PassiveSource.self), assets: assetsArr.first,
                                 assetItems: all(AssetItem.self), cashAccounts: all(CashAccount.self),
                                 loans: ProFeatures.loansInEffect(all(Loan.self)), countsAssets: FreedomSettings.countsAssets)
    }

    /// 只取一笔支出，用来判断账本是不是空的
    private static var anyExpense: FetchDescriptor<Expense> {
        var descriptor = FetchDescriptor<Expense>()
        descriptor.fetchLimit = 1
        return descriptor
    }

    private func allExpenses() -> [Expense] {
        (try? modelContext.fetch(FetchDescriptor<Expense>())) ?? []
    }

    /// Pro 刚失效、账本里又有体验期间加的资产项、现金账户或贷款时，弹「回到免费版」。没有就只记下这次变化。
    private func checkProLapse() {
        if ProStore.shared.takeLapse() {
            let plan = BackToFreePlan(assetItems: (try? modelContext.fetch(FetchDescriptor<AssetItem>())) ?? [],
                                      cashAccounts: (try? modelContext.fetch(FetchDescriptor<CashAccount>())) ?? [],
                                      loans: (try? modelContext.fetch(FetchDescriptor<Loan>())) ?? [])
            backToFreePending = plan.hasProContent
        }
        guard backToFreePending, !showingBackToFree, !presentingBackToFree else { return }
        presentingBackToFree = true
        Task {
            await presentBackToFree()
            presentingBackToFree = false
        }
    }

    /// 弹出来（sheet 的 onAppear 清掉 pending）才算数。刚启动时首页还没进窗口，或者别的弹层开着，sheet 会出不来：
    /// 收回开关，隔一会儿再试，最多三次；还不行就留着，下次回到前台再弹
    private func presentBackToFree() async {
        for attempt in 0..<3 {
            try? await Task.sleep(for: .milliseconds(attempt == 0 ? 300 : 1_000))
            guard backToFreePending, !showingBackToFree else { return }
            showingBackToFree = true
            try? await Task.sleep(for: .seconds(1))
            guard backToFreePending else { return }
            showingBackToFree = false
        }
    }

    /// 起步引导现在该显示哪一步；nil 表示不显示。
    /// 只给一笔支出都没有、也没填每月花销的新账本；在 History 和 Settings 里不拦着用户。
    private var setupStep: SetupGuideStep? {
        guard !setupGuideCompleted, guide.tour == nil, firstExpenses.isEmpty,
              MonthlySpending.valid(monthlySpending) == nil else { return nil }
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
