// Assets 页：按设置里选的样式，显示新版「钱与时间」或经典版。两版共用同一套行和弹窗，账本完全一样。

import SwiftUI

enum AssetsLayout {
    /// 设置 → 外观 → Assets 页面。本机偏好，不进备份
    static let key = "assetsLayout"
    static let moneyTime = "moneyTime"
    static let classic = "classic"
}

struct AssetsView: View {
    @AppStorage(AssetsLayout.key, store: AppPreferences.store) private var layout = AssetsLayout.moneyTime

    var body: some View {
        if layout == AssetsLayout.classic {
            ClassicAssetsView()
        } else {
            MoneyTimeAssetsView()
        }
    }
}
