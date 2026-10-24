// 界面语言：跟 iOS「设置 → FreeGrid → 语言」走，App 里不另设开关。
// 文字从 Localizable.xcstrings 取，中文原句就是 key；这里只管日期这类要按语言换写法的地方。

import Foundation

enum AppLanguage {
    /// 当前界面用的是不是中文。系统选了别的语言、目录里没有时，iOS 会退回英文。
    /// 换语言时系统会重启 App，所以启动时算一次就够
    nonisolated static let isChinese: Bool =
        (Bundle.main.preferredLocalizations.first ?? "zh-Hans").hasPrefix("zh")

    /// 日期、周几、相对时间用的地区写法，和界面语言保持一致
    nonisolated static let locale: Locale =
        isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")

    /// 按模板写日期，例如 "MMMd"：中文「10月24日」，英文「Oct 24」
    nonisolated static func date(_ date: Date, template: String, calendar: Calendar = .current) -> String {
        let key = "\(template)|\(calendar.identifier)|\(calendar.timeZone.identifier)" as NSString
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
}
