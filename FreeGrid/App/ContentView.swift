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

#Preview {
    let container = try! StoreBootstrap.makeContainer(isStoredInMemoryOnly: true)
    ContentView()
        .modelContainer(container)
        #if os(macOS)
        .environment(MenuActions())
        #endif
}
