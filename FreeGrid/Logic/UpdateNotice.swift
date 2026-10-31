// 大版本的更新公告：老用户更新后进 App，在首页弹一张卡片讲这版新了什么，每台设备每个版本弹一次（用户 2026-10-31 定）。
// 第一次打开这个版本时账本是空的，就没有什么要告诉他的：直接记成看过，之后记了账也不会再弹。
// 账本里有东西就留着不记，等卡片真的出现才记。下个大版本改 `version` 和卡片内容；小修小补不改，不弹。
// 这里只管判断；屏幕上空不空、能不能弹，由 ContentView 看。

import Foundation

enum UpdateNotice {
    static let version = "2.2"
    static let seenKey = "updateNoticeSeen"

    static func isDue(seen: String?) -> Bool {
        seen != version
    }

    /// 打开 App 时：还没看过这版、账本又是空的，记成看过
    static func skipsForEmptyLedger(seen: String?, hasContent: Bool) -> Bool {
        isDue(seen: seen) && !hasContent
    }

    /// 单元测试不判断。UI 测试和拍图每次都是新的临时偏好，不拦着的话有账本的用例都会弹；要测或拍这张卡时加 -updateNotice
    static var isSuppressedForTesting: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UseInMemoryStore") && !arguments.contains("-updateNotice")
        #else
        return false
        #endif
    }
}
