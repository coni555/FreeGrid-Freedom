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
    @State private var storeBootstrap = StoreBootstrap()

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
                case .failed(let failure):
                    StoreRecoveryView(failure: failure) {
                        storeBootstrap.retry()
                    }
                }
            }
            #if os(macOS)
            .environment(menuActions)
            .frame(minWidth: 920, minHeight: 640)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandMenu("记账") {
                Button("记一笔支出") { menuActions.addExpense = true }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!storeBootstrap.isReady)
                Button("记一笔收入") { menuActions.addIncome = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!storeBootstrap.isReady)
            }
        }
        #endif
    }
}
