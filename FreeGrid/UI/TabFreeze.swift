// 底部四个 Tab 的后台冻结：看不见的页面不跟着账本重算，切回来、或记完账空闲下来时，再按最新的账重画。
// 记一笔时首页在走动画，另外三页要是同时把几千笔账重算一遍，保存那一下就会卡。

import SwiftUI

/// 这一页现在是不是选中的 Tab，以及空闲补算的口令。
/// 不在 TabView 里的页面（预览、单独打开的）用默认值：一直在前台
struct TabActivity: Equatable {
    var isActive = true
    /// 页面在后台时这个数变了，就补算一次（数据没变过就不用算）
    var refreshToken = 0
}

/// 页面会读到的东西变了几次：存账、改偏好、Pro 状态、重放引导、回到前台、换深浅色，都由 ContentView 加一。
/// 页面在后台时什么都不读，SwiftUI 也就不会再通知它这些变化；切回来时比一比这个数，就知道要不要重算。
/// 引用类型、不触发重画：加一不会让哪个页面重跑，重算时顺手写了偏好也不会绕回来
final class TabDataClock {
    private(set) var version = 0
    func tick() { version += 1 }
}

private struct TabActivityKey: EnvironmentKey {
    static let defaultValue = TabActivity()
}

private struct TabDataClockKey: EnvironmentKey {
    /// 不在 TabView 里时没有人加一，只看页面自己的变化
    static let defaultValue = TabDataClock()
}

extension EnvironmentValues {
    var tabActivity: TabActivity {
        get { self[TabActivityKey.self] }
        set { self[TabActivityKey.self] = newValue }
    }

    var tabDataClock: TabDataClock {
        get { self[TabDataClockKey.self] }
        set { self[TabDataClockKey.self] = newValue }
    }
}

/// 页面冻住的那份内容，以及什么时候该重算。页面用 @State 持有，跨多次 body 都是同一份。
/// 引用类型：在 body 里改它不会再触发重画
final class TabFreezeState {
    fileprivate(set) var content: Any?
    private var token = 0
    /// 上一次页面 body 跑的时候，前后台和口令是什么
    private var lastActivity: TabActivity?
    /// 前后台或口令刚变过，还没画
    private var switched = false
    /// 画好之后，页面自己看到数据变过
    private(set) var isStale = false
    /// 画的时候数据版本是多少
    private var renderedVersion = 0

    /// 页面 body 跑了一遍。前后台和口令没变，就是它读的 @Query、偏好或环境变了
    func pageDidUpdate(_ activity: TabActivity) {
        if lastActivity == activity {
            isStale = true
        } else {
            switched = true
        }
        lastActivity = activity
    }

    /// 这次要按最新的数据重算，还是沿用冻住的内容。还没画过时总要算
    func needsFreshContent(_ activity: TabActivity, version: Int) -> Bool {
        let wasSwitched = switched
        switched = false
        let tokenArrived = token != activity.refreshToken
        token = activity.refreshToken
        guard content != nil else { return true }
        let changed = isStale || renderedVersion != version
        if !activity.isActive {
            // 后台只在补算口令到了、而且数据变过时才算。其余时候（刚切走、读过的模型属性被 SwiftData 通知）
            // 交回冻住的内容、不读任何东西
            return tokenArrived && changed
        }
        // 刚切回前台：这期间什么都没变就沿用；在前台时什么变了都重算
        return !wasSwitched || changed
    }

    func didRender(_ content: Any, version: Int) {
        self.content = content
        isStale = false
        renderedVersion = version
    }
}

/// 页面在后台时沿用上一次画好的内容：不读账本，也不更新下面的子视图。
/// 用法：页面原来的 body 改名为 `page`，body 写成
/// `TabFreeze(activity: tabActivity, clock: tabDataClock, state: freeze) { page }.equatable()`，
/// `freeze` 是页面自己的 `@State private var freeze = TabFreezeState()`。
/// 读 @Query 的计算都要放在 `page` 的最外层算好再往下传：ScrollViewReader、GeometryReader 这类容器里的内容
/// 会被单独重跑，在那里读 @Query 就冻不住了。
/// 切回前台时，后台期间数据没变过就直接用冻住的那份，和以前切 Tab 不重算一样
struct TabFreeze<Content: View>: View, Equatable {
    let activity: TabActivity
    let clock: TabDataClock
    let state: TabFreezeState
    let content: () -> Content

    init(activity: TabActivity, clock: TabDataClock, state: TabFreezeState,
         @ViewBuilder content: @escaping () -> Content) {
        self.activity = activity
        self.clock = clock
        self.state = state
        self.content = content
        state.pageDidUpdate(activity)
    }

    /// 都在后台、口令也没变时算「没变」：页面因为 @Query 变了重跑 body，到这里就停下
    static func == (lhs: Self, rhs: Self) -> Bool {
        !rhs.activity.isActive && lhs.activity == rhs.activity
    }

    var body: some View {
        if !state.needsFreshContent(activity, version: clock.version), let frozen = state.content as? Content {
            return frozen
        }
        let fresh = content()
        state.didRender(fresh, version: clock.version)
        return fresh
    }
}
