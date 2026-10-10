// StoreKit 尚未接入：仅 Debug 开放 Pro 功能预览，Release 不授予收费权益。
import Foundation

enum ProFeatures {
    static var canCustomizeExpenseCategories: Bool {
        #if DEBUG
        return !UserDefaults.standard.bool(forKey: "disableProPreview")
        #else
        return false
        #endif
    }
}
