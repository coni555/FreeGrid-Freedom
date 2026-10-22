import SwiftUI

extension View {
    /// 主页面共用同一纸色；关闭 iOS 顶部会改变底色的系统滚动边缘效果。
    /// 不强制背景常显，保留原生大标题的显隐。
    @ViewBuilder
    func paperNavigationContent() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            toolbarBackground(Color.paper, for: .navigationBar)
                .scrollEdgeEffectHidden(true, for: .top)
        } else {
            toolbarBackground(Color.paper, for: .navigationBar)
        }
        #else
        self
        #endif
    }

    /// 放在 NavigationStack 外层，填满状态栏背后的区域，不覆盖导航栏里的标题。
    @ViewBuilder
    func paperNavigationBackground() -> some View {
        #if os(iOS)
        background(Color.paper.ignoresSafeArea())
        #else
        self
        #endif
    }
}
