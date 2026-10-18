// 本机偏好存在哪。正常运行就是系统的 UserDefaults；
// Debug 下带 -UseInMemoryStore 启动（UI 测试、拍图）时换成一份临时偏好，
// 测试里切开关、改分类都不会碰这台设备上的真实偏好。
// 临时偏好默认每次启动清空；要测「重启后还在」时第二次启动再加 -KeepScratchPreferences。

import Foundation

enum AppPreferences {
    static let store: UserDefaults = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UseInMemoryStore"),
           let scratch = UserDefaults(suiteName: scratchSuite) {
            if !ProcessInfo.processInfo.arguments.contains("-KeepScratchPreferences") {
                scratch.removePersistentDomain(forName: scratchSuite)
            }
            seed(scratch, from: ProcessInfo.processInfo.arguments)
            return scratch
        }
        #endif
        return .standard
    }()

    #if DEBUG
    private static let scratchSuite = "cn.conilab.FreeGrid.scratch-preferences"

    /// 临时偏好读不到系统的启动参数，所以把测试要用的几个按名字抄进来：`-key value`
    private static let launchArgumentKeys = [
        ProStore.previewKey,
        ProStore.wasUnlockedKey,
        ProStore.wasPurchasedKey,
        FreedomSettings.countsAssetsKey,
        "historyGuideCompleted",
        "setupGuideCompleted",
        "assetsLayout",
        "assetsUnit",
    ]

    private static func seed(_ defaults: UserDefaults, from arguments: [String]) {
        for (index, argument) in arguments.enumerated() where index + 1 < arguments.count {
            guard argument.hasPrefix("-"), launchArgumentKeys.contains(String(argument.dropFirst())) else { continue }
            let value = arguments[index + 1]
            let key = String(argument.dropFirst())
            switch value.uppercased() {
            case "YES", "TRUE": defaults.set(true, forKey: key)
            case "NO", "FALSE": defaults.set(false, forKey: key)
            default: defaults.set(value, forKey: key)
            }
        }
    }
    #endif
}
