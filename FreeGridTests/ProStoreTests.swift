import Foundation
import Testing
@testable import FreeGrid

/// 这里只测不需要 App Store 的部分。真实的购买、恢复和退款要在真机沙盒里验证：
/// 本机用 xcodebuild 跑测试时，storekitd 不接受本地的 StoreKit 测试配置。
@MainActor
@Suite(.serialized)
struct ProStoreTests {
    /// 用一份单独的偏好，不碰测试设备上 App 自己的设置；每个用例前后清空
    private func withDefaults(_ body: (UserDefaults) async throws -> Void) async rethrows {
        let name = "ProStoreTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }

    @Test func startsLockedOnAFreshInstall() async {
        await withDefaults { defaults in
            let store = ProStore(defaults: defaults)
            #expect(!store.hasPurchased)
            #expect(!store.isUnlocked)
        }
    }

    @Test func rememberedPurchaseUnlocksBeforeTheAppStoreAnswers() async {
        // 上次核对的结果存在本机：离线启动或商品读不到时，买过的用户不会被锁回去
        await withDefaults { defaults in
            defaults.set(true, forKey: ProStore.unlockedKey)
            let store = ProStore(defaults: defaults)
            #expect(store.hasPurchased)
            #expect(store.isUnlocked)
        }
    }

    @Test func purchaseWithoutALoadedProductFailsAndStaysLocked() async {
        await withDefaults { defaults in
            let store = ProStore(defaults: defaults)
            guard case .failed = await store.purchase() else {
                Issue.record("没读到商品时不应该发起购买")
                return
            }
            #expect(!store.hasPurchased)
            #expect(!store.isWorking)
        }
    }

    @Test func rememberedTrialUnlocksForSevenDaysThenLocks() async {
        // 试用开始时间存在本机：离线也知道还在不在试用期；到期后锁回去，买断回到第二个按钮
        await withDefaults { defaults in
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            defaults.set(start, forKey: ProStore.trialStartedKey)

            let during = ProStore(defaults: defaults, clock: { start.addingTimeInterval(3 * 86_400) })
            #expect(during.isTrialActive)
            #expect(during.isUnlocked)
            #expect(!during.ownsPro)
            #expect(during.hasSpecialPrice)

            let afterTrial = ProStore(defaults: defaults, clock: { start.addingTimeInterval(10 * 86_400) })
            #expect(!afterTrial.isUnlocked)
            #expect(afterTrial.hasSpecialPrice)

            let afterWindow = ProStore(defaults: defaults, clock: { start.addingTimeInterval(20 * 86_400) })
            #expect(!afterWindow.isUnlocked)
            #expect(!afterWindow.hasSpecialPrice)
        }
    }

    @Test func aPurchaseIsNotATrial() async {
        await withDefaults { defaults in
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            defaults.set(start, forKey: ProStore.trialStartedKey)
            defaults.set(true, forKey: ProStore.unlockedKey)
            let store = ProStore(defaults: defaults, clock: { start.addingTimeInterval(86_400) })
            #expect(store.ownsPro)
            #expect(!store.isTrialActive)
        }
    }

    @Test func startingATrialWithoutLoadedProductsFails() async {
        await withDefaults { defaults in
            let store = ProStore(defaults: defaults)
            guard case .failed = await store.startTrial() else {
                Issue.record("没读到试用商品时不应该开始试用")
                return
            }
            #expect(!store.offer.hasStartedTrial)
        }
    }

    #if DEBUG
    @Test func debugPreviewUnlocksWithoutTouchingThePurchaseRecord() async {
        await withDefaults { defaults in
            let store = ProStore(defaults: defaults)
            store.isPreviewing = true
            #expect(store.isUnlocked)
            #expect(!store.hasPurchased)
            #expect(!defaults.bool(forKey: ProStore.unlockedKey))
            // 开关记在本机，下次启动仍然是预览状态
            #expect(ProStore(defaults: defaults).isUnlocked)
        }
    }
    #endif
}
