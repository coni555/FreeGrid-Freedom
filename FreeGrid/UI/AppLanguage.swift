// 界面语言：设置 → 外观 →「语言」里直接选中文或 English，当场换，不跳 iOS 设置。
// 文字从 Localizable.xcstrings 取，中文原句就是 key。iOS 只在启动时挑一次语言，所以 String(localized:)、Text 查文字都改道到这里按当前选择取，日期这类按语言换写法的也在这里。

import Foundation
import ObjectiveC

enum AppLanguage {
    /// 根视图挂这个 key 的 @AppStorage：值一变整棵视图按新语言重建，算好存着的文字也跟着重算
    static let storageKey = "appLanguage"

    /// 当前界面用的是不是中文。没选过时跟 iOS 的语言走；系统选了别的语言、目录里没有时，iOS 会退回英文
    nonisolated static var isChinese: Bool { state.withLock { $0.isChinese } }

    /// 日期、周几、相对时间用的地区写法，和界面语言保持一致
    nonisolated static var locale: Locale {
        isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
    }

    /// 启动时装一次：之后 Bundle.main 查文字都先问这里
    static func install() {
        object_setClass(Bundle.main, LanguageBundle.self)
        apply(chinese: isChinese)
    }

    /// 这次打开后在设置里换过语言：重建后的首屏停在设置页，不跳回首页
    private(set) static var switchedInApp = false

    /// 设置里切换。AppleLanguages 记下选择，下次冷启动 iOS 也按它挑语言，和 iOS 设置里那一项是同一处
    static func select(chinese: Bool) {
        guard chinese != isChinese else { return }
        UserDefaults.standard.set([chinese ? "zh-Hans" : "en"], forKey: "AppleLanguages")
        apply(chinese: chinese)
        formatters.removeAllObjects()
        switchedInApp = true
        // 最后才写这个 key：根视图看到它变了就重建，那时文字已经换好
        UserDefaults.standard.set(chinese ? "zh-Hans" : "en", forKey: storageKey)
    }

    private static func apply(chinese: Bool) {
        let english = chinese ? nil : Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        state.withLock { $0 = State(isChinese: chinese, english: english) }
    }

    /// 按当前语言取一句。代码里的 `String(localized:)` 都走下面的同名重载到这里
    nonisolated static func string(_ value: String.LocalizationValue) -> String {
        if let english = state.withLock({ $0.english }) { return String(localized: value, bundle: english) }
        // 包里没有中文目录：查一张不存在的表，拿回中文原句（插值照常填好）。不查 Bundle.main，它停在启动时的语言
        return String(localized: value, table: sourceTable)
    }

    /// 带 Markdown 的句子（加粗、链接）按当前语言取
    nonisolated static func attributed(_ resource: LocalizedStringResource) -> AttributedString {
        if let english = state.withLock({ $0.english }) {
            return AttributedString(localized: resource.defaultValue, bundle: english)
        }
        return AttributedString(localized: resource.defaultValue, table: sourceTable)
    }

    /// 不存在的表名：查它一定落空，返回的就是中文原句
    private nonisolated static let sourceTable = "SourceChinese"

    /// 按模板写日期，例如 "MMMd"：中文「10月24日」，英文「Oct 24」
    nonisolated static func date(_ date: Date, template: String, calendar: Calendar = .current) -> String {
        let locale = locale
        let key = "\(locale.identifier)|\(template)|\(calendar.identifier)|\(calendar.timeZone.identifier)" as NSString
        if let cached = formatters.object(forKey: key) { return cached.string(from: date) }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters.setObject(formatter, forKey: key)
        return formatter.string(from: date)
    }

    /// 明细页一天一个段头，每次都新建格式器太慢
    nonisolated(unsafe) private static let formatters = NSCache<NSString, DateFormatter>()

    fileprivate struct State: @unchecked Sendable {
        var isChinese: Bool
        /// 英文目录；中文时为 nil，直接用 key
        var english: Bundle?
    }

    /// 后台算明细、搜索时也会读，所以加锁
    fileprivate nonisolated static let state = LockedState(
        State(isChinese: (Bundle.main.preferredLocalizations.first ?? "zh-Hans").hasPrefix("zh"), english: nil))
}

extension String {
    /// 盖过 Foundation 的同名方法：它只认启动时的语言，App 里换了语言它不知道。
    /// 带 table、comment 等参数的写法不会走到这里，项目里也别那样写
    nonisolated init(localized value: String.LocalizationValue) {
        self = AppLanguage.string(value)
    }
}

/// 换掉 Bundle.main 的类，让 SwiftUI 的 Text（中文原句当 key 的那些）按 App 里选的语言查
private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let state = AppLanguage.state.withLock { $0 }
        if let english = state.english {
            return english.localizedString(forKey: key, value: value, table: tableName)
        }
        // 中文是开发语言，包里没有中文目录：中文原句就是 key。不交给系统，免得 iPhone 是英文时查到英文
        if state.isChinese { return value.flatMap { $0.isEmpty ? nil : $0 } ?? key }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

/// iOS 17 没有 Mutex，用 NSLock 包一层
nonisolated final class LockedState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
