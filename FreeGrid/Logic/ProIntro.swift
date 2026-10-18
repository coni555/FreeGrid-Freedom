// 2.0 起的 Pro 介绍：每台设备只弹一次，新老用户各一版（用户 2026-10-18 定）。
// - 新用户：起步引导结束后，第一次进 Settings 时弹正常的购买页。
//   不在引导刚走完时弹（用户：太降低好感度）
// - 老用户（从 1.x 升上来）：打开 2.0 时弹整屏介绍，着重讲 Pro 比免费版多了什么
// 新还是老，在第一次打开带这段代码的版本时就定下来：那时账本里已经有支出算老用户。
// 定下来就不再变，新用户记完第一笔也不会变成老用户。
// 这里只管判断；屏幕上空不空、能不能弹，由 ContentView 看。

import Foundation

enum ProIntro {
    enum Audience: String {
        case newcomer, returning
    }

    static let audienceKey = "proIntroAudience"
    static let shownKey = "proIntroShown"

    /// 第一次打开时账本里有没有支出。没有支出的人会走起步引导，和起步引导的判断一致
    static func audience(hasExpenses: Bool) -> Audience {
        hasExpenses ? .returning : .newcomer
    }

    /// 现在该不该弹。
    /// 已经买了或已经开始过体验的不弹；读不到体验商品（没网）时先不弹，下次打开再看。
    /// 新用户要等起步引导结束（走完、跳过，或者自己记过支出）。在哪一页弹由 ContentView 管
    static func shouldOffer(audience: Audience, alreadyShown: Bool, ownsPro: Bool, hasStartedTrial: Bool,
                            canStartTrial: Bool, setupFinished: Bool) -> Bool {
        guard !alreadyShown, !ownsPro, !hasStartedTrial, canStartTrial else { return false }
        switch audience {
        case .newcomer: return setupFinished
        case .returning: return true
        }
    }

    /// 单元测试的宿主就是 App 本身，用的是这台设备的真实偏好：不判断、不弹，免得把新老用户记错。
    /// UI 测试和拍图（-UseInMemoryStore）每次都是新的临时偏好，不拦着的话每个用例都会弹；要测或拍这个弹窗时加 -proIntro
    static var isSuppressedForTesting: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UseInMemoryStore") && !arguments.contains("-proIntro")
        #else
        return false
        #endif
    }
}
