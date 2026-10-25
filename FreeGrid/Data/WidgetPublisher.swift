// 把小组件那份数写进共享容器，再请系统刷新小组件。只读账本，不改任何记录。
// 什么时候写：打开 App 补扣完到期的钱之后、离开 App 时（记账、改目标、换语言、Pro 变化都在这之前发生）。
// 平时开着 App 不跟着每一笔重算，免得记账时多一次整本账的计算。

import Foundation
import SwiftData
#if os(iOS)
import WidgetKit
#endif

enum WidgetPublisher {
    /// 读账本、算好、写文件。没有共享容器（macOS、没配 App Group 的构建）时什么也不做。
    /// 写失败只影响小组件，不打扰用户
    static func publish(in context: ModelContext, now: Date = .now) {
        #if os(iOS)
        guard let url = WidgetSnapshotFile.url else { return }
        #if DEBUG
        // UI 测试和拍图用的临时账本不写出去，免得盖掉这台设备上小组件的真数
        guard !ProcessInfo.processInfo.arguments.contains("-UseInMemoryStore") else { return }
        #endif
        guard let snapshot = snapshot(in: context, now: now),
              let data = try? WidgetSnapshotFile.encode(snapshot) else { return }
        // 内容没变就不写、不刷新：系统给小组件的刷新次数有限
        if let old = try? Data(contentsOf: url), WidgetSnapshotFile.decode(old)?.sameContent(as: snapshot) == true {
            return
        }
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func snapshot(in context: ModelContext, now: Date = .now) -> WidgetSnapshot? {
        do {
            let ledger = WidgetProjection.Ledger(
                expenses: try context.fetch(FetchDescriptor<Expense>()),
                passiveSources: try context.fetch(FetchDescriptor<PassiveSource>()),
                assets: try context.fetch(FetchDescriptor<UserAssets>()).first,
                assetItems: try context.fetch(FetchDescriptor<AssetItem>()),
                cashAccounts: try context.fetch(FetchDescriptor<CashAccount>()),
                loans: ProFeatures.loansInEffect(try context.fetch(FetchDescriptor<Loan>())),
                countsAssets: FreedomSettings.countsAssets)
            let goals = FreedomGoalStore.decode(AppPreferences.store.string(forKey: FreedomGoalStore.key) ?? "")
            return WidgetProjection.snapshot(ledger: ledger, goals: goals, proActive: ProFeatures.canSetGoals, now: now)
        } catch {
            return nil
        }
    }
}

extension WidgetSnapshot {
    /// 除了写的时刻，其余都一样。第一份的生效时间就是写的时刻，也不算
    func sameContent(as other: WidgetSnapshot) -> Bool {
        var lhs = self, rhs = other
        lhs.generatedAt = .distantPast
        rhs.generatedAt = .distantPast
        if !lhs.days.isEmpty, !rhs.days.isEmpty {
            lhs.days[0].date = .distantPast
            rhs.days[0].date = .distantPast
        }
        return lhs == rhs
    }
}
