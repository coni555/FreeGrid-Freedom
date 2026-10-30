//
//  FreeGridApp.swift
//  FreeGrid
//
//  App 入口：先安全打开 SwiftData；失败时进入非破坏性恢复页。
//

import SwiftData
import SwiftUI

#if os(macOS)
/// macOS 菜单栏命令 → 根层 sheet 的桥(⌘N 记支出 / ⌘⇧N 记收入)
@Observable
final class MenuActions {
    var addExpense = false
    var addIncome = false
}
#endif

@main
struct FreeGridApp: App {
    init() {
        AppLanguage.install()
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UseInMemoryStore"), arguments.contains("-ResetExpenseCategories") {
            AppPreferences.store.removeObject(forKey: ExpenseCategoryStorage.key)
        }
        #endif
    }

    @State private var storeBootstrap = StoreBootstrap()
    /// 设置里换了语言就变：整棵视图按新语言重建
    @AppStorage(AppLanguage.storageKey) private var language = ""
    @AppStorage(MonthlyTracking.key, store: AppPreferences.store) private var storedTracking = ""
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
    @State private var menuActions = MenuActions()
    #endif

    var body: some Scene {
        WindowGroup {
            Group {
                switch storeBootstrap.state {
                case .loading:
                    ProgressView("正在打开本地数据…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.paper)
                case .ready(let container):
                    ContentView()
                        .modelContainer(container)
                        .id(language)
                case .failed(let failure):
                    StoreRecoveryView(failure: failure) {
                        storeBootstrap.retry()
                    }
                }
            }
            .environment(\.locale, AppLanguage.locale)
            #if os(macOS)
            .environment(menuActions)
            .frame(minWidth: 920, minHeight: 640)
            #endif
            // Pro 购买状态：启动时核对一次，回到前台再核对（退款会撤销 Pro）。
            // 单元测试宿主里不连 App Store，免得测试交易写进这台设备的偏好。
            .task {
                guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                ProStore.shared.start()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active,
                      ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                Task { await ProStore.shared.refreshEntitlement() }
            }
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandMenu("记账") {
                // 每月一个数不记单笔
                Button("记一笔支出") { menuActions.addExpense = true }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!storeBootstrap.isReady || MonthlyTracking.decode(storedTracking).isMonthly)
                Button("记一笔收入") { menuActions.addIncome = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!storeBootstrap.isReady || MonthlyTracking.decode(storedTracking).isMonthly)
            }
        }
        #endif
    }
}
