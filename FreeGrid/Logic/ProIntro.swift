// 2.0 起的 Pro 介绍：只给老用户（从 1.x 升上来的），打开 2.0 时在首页弹一次卡片，先讲 2.0 的免费更新，再提一句 Pro。
// 新用户不弹这张（用户 2026-10-18：营销性太强，新用户先 pass 掉），改在记满 7 天时看「这一周的小结」，见 FirstWeekRecap。
// 新还是老，在第一次打开带这段代码的版本时就定下来：那时账本里已经有支出算老用户。
// 定下来就不再变，新用户记完第一笔也不会变成老用户、后来再被弹。
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

    /// 现在该不该弹。只弹老用户；
    /// 已经买了或已经开始过体验的不弹；读不到体验商品（没网）时先不弹，下次打开再看
    static func shouldOffer(audience: Audience, alreadyShown: Bool, ownsPro: Bool, hasStartedTrial: Bool,
                            canStartTrial: Bool) -> Bool {
        audience == .returning && !alreadyShown && !ownsPro && !hasStartedTrial && canStartTrial
    }

    /// 体验商品读到了没有。卡片上写着「可以先免费体验 7 天」，读不到就先不弹。
    /// 拍图和 UI 测试用 -proSamplePrices 当作读到了
    static func trialIsAvailable(_ store: ProStore) -> Bool {
        if case .loaded(let products) = store.productState { return products.trial != nil }
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-proSamplePrices")
        #else
        return false
        #endif
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
