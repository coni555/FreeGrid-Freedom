// Assets 页：按设置里选的样式，显示新版「钱与时间」或经典版。两版共用同一套行和弹窗，账本完全一样。
// 「钱与时间」是 Pro 的视图；没有 Pro 时不管存的是哪个，一律显示经典版。

import SwiftUI

enum AssetsLayout {
    /// 设置 → 外观 → Assets 页面。本机偏好，不进备份
    static let key = "assetsLayout"
    static let moneyTime = "moneyTime"
    static let classic = "classic"

    /// 实际显示哪一版：存的选择，再过一遍 Pro
    static func effective(_ stored: String) -> String {
        stored == classic || !ProFeatures.canUseMoneyTimeAssets ? classic : moneyTime
    }
}

struct AssetsView: View {
    @AppStorage(AssetsLayout.key, store: AppPreferences.store) private var layout = AssetsLayout.moneyTime

    var body: some View {
        if AssetsLayout.effective(layout) == AssetsLayout.classic {
            ClassicAssetsView()
        } else {
            MoneyTimeAssetsView()
        }
    }
}
