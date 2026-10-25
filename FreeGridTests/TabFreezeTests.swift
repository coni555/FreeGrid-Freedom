import Testing
@testable import FreeGrid

/// 后台 Tab 冻结：什么时候沿用冻住的页面，什么时候按最新的数据重算。
/// 顺序模拟 SwiftUI 的调用：页面 body 跑一遍（pageDidUpdate），接着冻结层的 body 问要不要重算；
/// `version` 是 ContentView 在存账、改偏好、Pro 变化时加一的那个数
@MainActor
struct TabFreezeTests {
    private let front = TabActivity(isActive: true, refreshToken: 0)
    private let back = TabActivity(isActive: false, refreshToken: 0)

    /// 先在前台画一次
    private func rendered(version: Int = 0) -> TabFreezeState {
        let state = TabFreezeState()
        state.pageDidUpdate(front)
        #expect(state.needsFreshContent(front, version: version))
        state.didRender("页面", version: version)
        return state
    }

    @Test func switchingAwayAndBackWithoutChangesReusesThePage() {
        let state = rendered()
        state.pageDidUpdate(back)
        #expect(!state.needsFreshContent(back, version: 0))
        state.pageDidUpdate(front)
        #expect(!state.needsFreshContent(front, version: 0))
    }

    @Test func ledgerChangesWhileHiddenWaitUntilThePageComesBack() {
        let state = rendered()
        state.pageDidUpdate(back)
        #expect(!state.needsFreshContent(back, version: 0))
        // 记了一笔：页面的 @Query 变了，body 又跑一遍；冻结层这时不会被叫到
        state.pageDidUpdate(back)
        #expect(state.isStale)
        state.pageDidUpdate(front)
        #expect(state.needsFreshContent(front, version: 1))
    }

    /// 在钱包页关掉「资产计入」：首页在后台什么都没读，收不到偏好变化，只有版本号变了
    @Test func aChangeTheHiddenPageNeverHeardOfStillRedrawsIt() {
        let state = rendered()
        state.pageDidUpdate(back)
        #expect(!state.needsFreshContent(back, version: 0))
        state.pageDidUpdate(front)
        #expect(state.needsFreshContent(front, version: 1))
        state.didRender("关掉资产后的页面", version: 1)
        // 再切走、再改回来，同样要重算
        state.pageDidUpdate(back)
        #expect(!state.needsFreshContent(back, version: 1))
        state.pageDidUpdate(front)
        #expect(state.needsFreshContent(front, version: 2))
    }

    @Test func swiftDataWakeUpsWhileHiddenNeverRecompute() {
        let state = rendered()
        state.pageDidUpdate(back)
        #expect(!state.needsFreshContent(back, version: 0))
        // 别的页面重新取数，SwiftData 顺带通知到这里：不重算，值也没变
        #expect(!state.needsFreshContent(back, version: 0))
        state.pageDidUpdate(front)
        #expect(!state.needsFreshContent(front, version: 0))
    }

    @Test func idleCatchUpRecomputesOnlyWhenSomethingChanged() {
        let state = rendered()
        state.pageDidUpdate(back)
        #expect(!state.needsFreshContent(back, version: 0))
        let firstCatchUp = TabActivity(isActive: false, refreshToken: 1)
        state.pageDidUpdate(firstCatchUp)
        #expect(!state.needsFreshContent(firstCatchUp, version: 0))

        // 存了一笔，版本加一；补算口令到了才算
        #expect(!state.needsFreshContent(firstCatchUp, version: 1))
        let secondCatchUp = TabActivity(isActive: false, refreshToken: 2)
        state.pageDidUpdate(secondCatchUp)
        #expect(state.needsFreshContent(secondCatchUp, version: 1))
        state.didRender("补算后的页面", version: 1)
        // 补算过了，切回来直接用
        let comeBack = TabActivity(isActive: true, refreshToken: 2)
        state.pageDidUpdate(comeBack)
        #expect(!state.needsFreshContent(comeBack, version: 1))
    }

    @Test func theFrontPageAlwaysFollowsItsData() {
        let state = rendered()
        state.pageDidUpdate(front)
        #expect(state.needsFreshContent(front, version: 0))
        state.didRender("页面", version: 0)
        // 在前台时读过的模型属性变了，冻结层自己被叫醒：照常重算
        #expect(state.needsFreshContent(front, version: 0))
    }

    @Test func aPageNeverDrawnIsAlwaysComputed() {
        let state = TabFreezeState()
        state.pageDidUpdate(back)
        #expect(state.needsFreshContent(back, version: 0))
    }
}
