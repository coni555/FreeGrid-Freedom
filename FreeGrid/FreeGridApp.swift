//
//  FreeGridApp.swift
//  FreeGrid
//
//  App 入口: 注册所有 SwiftData 模型到 ModelContainer。
//

import SwiftUI
import SwiftData

@main
struct FreeGridApp: App {
    /// ModelContainer 是 SwiftData 的核心容器,负责所有 @Model 类的持久化存储。
    /// 这里把 5 个核心业务模型一起注册——任何 @Query 都从这个 container 取数据。
    var sharedModelContainer: ModelContainer = {
        // Schema 声明: 把所有持久化模型列出来。
        // 新加 @Model 类时,必须在这里加一行,否则 SwiftData 不认识它。
        let schema = Schema([
            Expense.self,
            Income.self,
            Device.self,
            PassiveSource.self,
            UserAssets.self,
        ])

        // isStoredInMemoryOnly: false → 数据写入磁盘(真正持久化)。
        // 起步阶段不接 CloudKit,只在本机。后期升级 CloudKit 改一行配置即可。
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // 容器创建失败一般是 schema 迁移问题。开发阶段宁可早 crash 早暴露。
            // 上线后会换成更优雅的错误恢复(让用户重置数据库)。
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
