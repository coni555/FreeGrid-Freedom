// 全 App 的指引：压暗页面、圈出位置、逐步说明。
// 两种：看着学的讲解（每页一个），和带新用户做完头两步的起步引导。

import SwiftUI

/// 页面把要圈出的位置的屏幕坐标报上来，遮罩据此开洞。
@MainActor
@Observable
final class AppGuide {
    /// 看着学的讲解，各属于一个页面。Assets 两版长得不一样，各讲各的：
    /// 经典版（免费用户只有这一版）是 `assets`，「钱与时间」（Pro）是 `moneyTimeAssets`。
    /// 重看时两版都用 `assets` 这一个请求，由当时显示的那一版决定讲哪套。
    enum Tour: Hashable {
        case dashboard, assets, moneyTimeAssets, history, settings
    }

    enum Target: Hashable {
        // History
        case month, row, tools
        // 首页
        case number, grid, repaymentDays, simulate, trend, cards
        // Assets
        case netWorth, unitSwitch, transfer, buckets, passive, loans
        // Settings
        case check, freedomCard, pro, appearance, data, about
        // 起步引导里要用户真的去点的两处
        case cashCard, expenseButton
    }

    struct Step: Equatable {
        let target: Target
        let text: String
        /// 这一步教的是左滑，圈内加一个向左移动的箭头
        var showsSwipe = false
    }

    static func steps(for tour: Tour) -> [Step] {
        switch tour {
        case .dashboard:
            return [
                Step(target: .number, text: String(localized: "按现在的花法，你的财富还能撑这么多天。\n下面写着大约能撑到哪一天。")),
                // 顺序跟屏幕从上到下走：大数字、它下面的趋势行、格子、模拟、小卡
                Step(target: .trend, text: String(localized: "点这一行，展开或收起最近几周的变化。")),
                Step(target: .grid, text: String(localized: "一格是一天；天数多了，会换成一月或一年。\n金色来自资产，蓝色来自现金，钱花掉格子就少。")),
                // 只有填了贷款、格子上有孔时才出现
                Step(target: .repaymentDays, text: String(localized: "有孔的格子是还款日。\n最后面那个淡色的孔，是钱撑不到的下一次还款。")),
                Step(target: .simulate, text: String(localized: "花钱之前先来这里试一下，\n看这一笔会熄灭几格。")),
                // 记过一笔支出才有小卡
                Step(target: .cards, text: String(localized: "下面的小卡放哪些、什么顺序由你定。\n按住一张拖动换位置，点「编辑卡片」增减。")),
            ]
        case .assets:
            return [
                Step(target: .netWorth, text: String(localized: "净值 = 资产 + 现金，自动相加。\n下面这条线里，金色是资产，蓝色是现金。")),
                Step(target: .transfer, text: String(localized: "钱在资产和现金之间挪，用调拨，净值不变。\n点这一行展开。")),
                Step(target: .buckets, text: String(localized: "资产是定期、股票这类不打算马上花的钱，现金是随时能花的。\n点一行改金额；资产前面的方格，管它算不算进自由天数。")),
                Step(target: .loans, text: String(localized: "房租、水电、会员这类固定支出加在这里。\n到日子自动记一笔，自由天数会提前留出这笔钱。")),
                Step(target: .passive, text: String(localized: "租金、利息这类不靠上班的收入加在这里。\n它覆盖开销时，首页显示 ∞。")),
            ]
        // 顺序跟屏幕从上到下走：净值、单位、两张标签、调拨、每月的进和出
        case .moneyTimeAssets:
            return [
                Step(target: .netWorth, text: String(localized: "净值 = 资产 + 现金。\n下面这条线一段是一个账户，点一段跳到它那一边。")),
                Step(target: .unitSwitch, text: String(localized: "切到钟，整页的金额换成「够日常花几天」，\n大数字就是你的自由天数。")),
                Step(target: .buckets, text: String(localized: "点「资产」或「现金」切换，一个账户一行。\n点一行修改；点前面的方格或序号，选它算不算进自由天数。")),
                Step(target: .transfer, text: String(localized: "中间的圆钮是调拨：\n钱在资产和现金之间挪，净值不变。")),
                Step(target: .passive, text: String(localized: "「进」是租金、利息这类不靠上班的收入。\n它覆盖开销时，首页显示 ∞。")),
                Step(target: .loans, text: String(localized: "「出」是房租、会员这类固定支出，和房贷、车贷。\n到日子自动记一笔，自由天数会提前留出这笔钱。")),
            ]
        case .settings:
            return [
                Step(target: .check, text: String(localized: "九个里程碑，看你离财富自由走到了哪一步。\n点进去看每一项，也可以加一个自己的目标。")),
                Step(target: .freedomCard, text: String(localized: "你的自由卡：30 天银卡，180 天香槟金，一年黑卡。\n点开看整张卡。")),
                // 只有还没买 Pro 时才出现
                Step(target: .pro, text: String(localized: "Pro 一次买断，不订阅，可以先免费体验 7 天。\n点「了解 Pro」，看免费版和 Pro 各有什么。")),
                Step(target: .appearance, text: String(localized: "下面几张卡，点卡头抽出来，再点一下收回。\n「外观」里换深浅色、首页大数字的位置和钱包页的样式。")),
                Step(target: .data, text: String(localized: "「账本」里管支出分类和备份。\n换手机前，先在这里导出一份 JSON 备份。")),
                Step(target: .about, text: String(localized: "想再看一遍这些讲解，或者查使用说明，\n都在「FreeGrid」这张卡里。")),
            ]
        case .history:
            return [
                Step(target: .month, text: String(localized: "点月份，跳到任意一个月。\n旁边的箭头可以前后翻月。")),
                Step(target: .row, text: String(localized: "点一行，修改金额、分类、日期或备注。")),
                Step(target: .row, text: String(localized: "向左滑一行，撤销这笔。"), showsSwipe: true),
                Step(target: .tools, text: String(localized: "这里搜索全部记录。\n想只看某一类，点卡片里「N 笔」那一行展开，再点那一类。")),
            ]
        }
    }

    var frames: [Target: CGRect] = [:]
    /// 正在播的讲解；nil 表示没有
    private(set) var tour: Tour?
    private(set) var index: Int?
    /// 设置页「使用指引」每点一次加一，对应页面据此从头重放
    private(set) var replayRequests: [Tour: Int] = [:]
    /// 每个讲解已经播到第几次请求；页面每次重新出现都会再问一遍，靠它保证一次请求只播一遍
    @ObservationIgnored private var servedReplays: [Tour: Int] = [:]

    /// 当前屏幕上找不到位置的步骤直接跳过，例如这个月还没有记录时没有「行」。
    var availableSteps: [Step] {
        guard let tour else { return [] }
        return Self.steps(for: tour).filter { frames[$0.target] != nil }
    }

    var current: Step? {
        guard let index, availableSteps.indices.contains(index) else { return nil }
        return availableSteps[index]
    }

    func replays(of tour: Tour) -> Int { replayRequests[tour, default: 0] }

    func requestReplay(_ tour: Tour) { replayRequests[tour, default: 0] += 1 }

    /// 取走一次还没播的重放请求；没有新请求时返回 false
    func takeReplay(_ tour: Tour) -> Bool {
        let requested = replays(of: tour)
        guard requested > servedReplays[tour, default: 0] else { return false }
        servedReplays[tour] = requested
        return true
    }

    func start(_ tour: Tour) {
        guard index == nil else { return }
        self.tour = tour
        if availableSteps.isEmpty { self.tour = nil } else { index = 0 }
    }

    /// 返回 true 表示讲解已经走完
    func advance() -> Bool {
        guard let index else { return true }
        if index + 1 < availableSteps.count {
            self.index = index + 1
            return false
        }
        stop()
        return true
    }

    func back() {
        if let index, index > 0 { self.index = index - 1 }
    }

    func stop() {
        index = nil
        tour = nil
    }

    /// 目标从屏幕上消失后丢掉旧位置，免得圈在空白处
    func forget(_ target: Target) {
        frames[target] = nil
    }

    func report(_ target: Target, _ frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        if frames[target] != frame { frames[target] = frame }
    }
}

extension View {
    /// 把这个视图在屏幕上的位置报给指引。`hiddenTop`：顶上被别的东西盖住的那一截（设置页叠着的卡），不圈进去
    func guideTarget(_ target: AppGuide.Target, in guide: AppGuide, hiddenTop: CGFloat = 0) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            var visible = frame
            visible.origin.y += hiddenTop
            visible.size.height -= hiddenTop
            guide.report(target, visible)
        }
    }

    /// 讲解走到一处不在屏幕里的位置时，把它滚到眼前。`anchors` 给出每一处滚到哪个 id、停在屏幕哪儿
    func guideScroll(_ guide: AppGuide, tour: AppGuide.Tour, scroller: ScrollViewProxy,
                     anchors: [AppGuide.Target: (id: AnyHashable, at: UnitPoint)]) -> some View {
        onChange(of: guide.tour == tour ? guide.current?.target : nil) { _, target in
            guard let target, let anchor = anchors[target] else { return }
            withAnimation(.easeInOut(duration: 0.35)) { scroller.scrollTo(anchor.id, anchor: anchor.at) }
        }
    }
}

/// 看着学的讲解。盖在整个窗口上（包括导航栏和底部 Tab），所以挂在 ContentView 而不是页面内部。
struct GuideOverlay: View {
    let guide: AppGuide
    /// 走完或跳过时告诉外面是哪一个讲解结束了
    let onFinish: (AppGuide.Tour) -> Void

    @State private var swipeOffset: CGFloat = 0

    var body: some View {
        if let step = guide.current, let target = guide.frames[step.target] {
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                let hole = target
                    .offsetBy(dx: -origin.x, dy: -origin.y)
                    .insetBy(dx: -8, dy: -6)
                let total = guide.availableSteps.count
                let number = (guide.index ?? 0) + 1

                ZStack(alignment: .topLeading) {
                    // 压暗全屏，在目标位置开洞
                    Rectangle()
                        .fill(Color.black.opacity(0.55))
                        .overlay(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .frame(width: hole.width, height: hole.height)
                                .offset(x: hole.minX, y: hole.minY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                        .frame(width: hole.width, height: hole.height)
                        .offset(x: hole.minX, y: hole.minY)

                    if step.showsSwipe {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(Color.skyDeep)
                            .offset(x: hole.midX + 30 + swipeOffset, y: hole.midY - 10)
                            .onAppear {
                                swipeOffset = 0
                                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                                    swipeOffset = -90
                                }
                            }
                    }

                    bubble(step: step, number: number, total: total)
                        .frame(width: min(proxy.size.width - 2 * Spacing.xl, 320))
                        .position(bubbleCenter(hole: hole, in: proxy.size))
                }
                .contentShape(Rectangle())
                // 点空白处只往下走；最后一步要点「知道了」才关，误触不会直接结束
                .onTapGesture { if number < total { next() } }
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func bubble(step: AppGuide.Step, number: Int, total: Int) -> some View {
        VaultCard(emphasis: .high, padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(step.text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("guide-text")
                HStack {
                    Text("\(number) / \(total)")
                        .font(.kicker)
                        .foregroundStyle(Color.inkFaint)
                    if number < total {
                        Button("跳过") { finish() }
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                            .buttonStyle(.plain)
                            .padding(.leading, Spacing.sm)
                            .accessibilityIdentifier("guide-skip")
                    }
                    Spacer()
                    if number > 1 {
                        Button("上一步") {
                            withAnimation(.easeInOut(duration: 0.25)) { guide.back() }
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .buttonStyle(.plain)
                        .padding(.trailing, Spacing.md)
                        .accessibilityIdentifier("guide-back")
                    }
                    Button { next() } label: {
                        Text(number < total ? "下一步" : "知道了")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.skyDeep)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, 6)
                            .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("guide-next")
                }
            }
        }
    }

    /// 说明放在目标下方；目标在屏幕下半部时放到上方
    private func bubbleCenter(hole: CGRect, in size: CGSize) -> CGPoint {
        let half: CGFloat = 70
        let below = hole.maxY + Spacing.lg + half
        let y = hole.midY < size.height / 2 ? below : hole.minY - Spacing.lg - half
        return CGPoint(x: size.width / 2, y: min(max(y, half + 60), size.height - half - 60))
    }

    private func next() {
        let tour = guide.tour
        var done = false
        withAnimation(.easeInOut(duration: 0.25)) { done = guide.advance() }
        if done, let tour { onFinish(tour) }
    }

    private func finish() {
        let tour = guide.tour
        withAnimation(.easeInOut(duration: 0.25)) { guide.stop() }
        if let tour { onFinish(tour) }
    }
}

// ============================================================================
// MARK: - 起步引导: 带新用户记下第一笔钱和第一笔支出
// ============================================================================

/// 走到哪一步完全由账本和当前页面决定，不单独存进度：
/// 中途退出、或者用户自己先做了某一步，回来时都会接上。
enum SetupGuideStep: Equatable {
    /// 首页，还没记过钱：讲清楚大数字是什么，带去 Assets
    case welcome
    /// Assets，还没记过钱：圈出现金卡，让用户自己点
    case cash
    /// Assets，钱记好了：带回首页
    case backHome
    /// 首页，有钱没支出：圈出记支出，让用户自己点
    case expense

    var number: Int {
        switch self {
        case .welcome: return 1
        case .cash, .backHome: return 2
        case .expense: return 3
        }
    }
}

/// 和讲解不同：圈里是真的可以点的，用户点下去就是在操作；圈外的地方点不动。
struct SetupGuideOverlay: View {
    let step: SetupGuideStep
    let guide: AppGuide
    let onGoAssets: () -> Void
    let onGoDashboard: () -> Void
    /// 第 3 步不想记账的人：改填每月花销，填完引导也就结束了
    let onFillMonthlySpending: () -> Void
    let onSkip: () -> Void

    private var target: AppGuide.Target? {
        switch step {
        case .welcome: return .number
        case .cash: return .cashCard
        case .backHome: return nil
        case .expense: return .expenseButton
        }
    }

    /// 这一步的圈里能不能点穿
    private var holeIsTappable: Bool { step == .cash || step == .expense }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let hole = target.flatMap { guide.frames[$0] }?
                .offsetBy(dx: -origin.x, dy: -origin.y)
                .insetBy(dx: -8, dy: -6)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .overlay(alignment: .topLeading) {
                        if let hole {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .frame(width: hole.width, height: hole.height)
                                .offset(x: hole.minX, y: hole.minY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                    .allowsHitTesting(false)

                // 压暗层只管画。挡点击的是下面这几块透明的板:
                // 能点的那两步在圈的四周各放一块, 圈本身不盖任何东西, 点击直接落到真正的按钮上
                tapBlockers(around: holeIsTappable ? hole : nil, in: proxy.size)

                if let hole {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                        .frame(width: hole.width, height: hole.height)
                        .offset(x: hole.minX, y: hole.minY)
                        .allowsHitTesting(false)
                }

                bubble
                    .frame(width: min(proxy.size.width - 2 * Spacing.xl, 320))
                    .position(bubbleCenter(hole: hole, in: proxy.size))
            }
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    @ViewBuilder
    private func tapBlockers(around hole: CGRect?, in size: CGSize) -> some View {
        if let hole {
            blocker(CGRect(x: 0, y: 0, width: size.width, height: max(0, hole.minY)))
            blocker(CGRect(x: 0, y: hole.maxY, width: size.width, height: max(0, size.height - hole.maxY)))
            blocker(CGRect(x: 0, y: hole.minY, width: max(0, hole.minX), height: hole.height))
            blocker(CGRect(x: hole.maxX, y: hole.minY, width: max(0, size.width - hole.maxX), height: hole.height))
        } else {
            blocker(CGRect(origin: .zero, size: size))
        }
    }

    private func blocker(_ rect: CGRect) -> some View {
        Color.black.opacity(0.001)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .onTapGesture {}
            .accessibilityHidden(true)
    }

    private var text: String {
        switch step {
        case .welcome: return String(localized: "FreeGrid 算的是：按现在的花法，你的钱还能撑多少天。\n先告诉它你有多少钱。")
        case .cash: return String(localized: "活期、微信、支付宝里随时能花的钱，填在「现金」。\n点一下这一行。")
        case .backHome: return String(localized: "记下了。\n再回首页记一笔支出，格子就会点亮。")
        case .expense: return String(localized: "记一笔今天的支出，多少都行。\n点「记支出」。")
        }
    }

    private var bubble: some View {
        VaultCard(emphasis: .high, padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("setup-guide-text")
                if step == .expense {
                    Button(action: onFillMonthlySpending) {
                        HStack(spacing: Spacing.xs) {
                            Text("不想每天记账？记下这个月花了多少")
                                .font(.system(.caption, design: .rounded))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(Color.skyDeep)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("setup-guide-monthly-spending")
                }
                HStack {
                    Text("\(step.number) / 3")
                        .font(.kicker)
                        .foregroundStyle(Color.inkFaint)
                    Button("跳过引导", action: onSkip)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .buttonStyle(.plain)
                        .padding(.leading, Spacing.sm)
                        .accessibilityIdentifier("setup-guide-skip")
                    Spacer()
                    switch step {
                    case .welcome:
                        actionButton("去记下", identifier: "setup-guide-go-assets", action: onGoAssets)
                    case .backHome:
                        actionButton("回首页", identifier: "setup-guide-go-home", action: onGoDashboard)
                    case .cash, .expense:
                        EmptyView()   // 这两步的下一步就是点圈里的东西
                    }
                }
            }
        }
    }

    private func actionButton(_ title: LocalizedStringKey, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.skyDeep)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 6)
                .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// 说明放在目标下方；目标在屏幕下半部时放到上方；没有目标时放在屏幕中间
    private func bubbleCenter(hole: CGRect?, in size: CGSize) -> CGPoint {
        guard let hole else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let half: CGFloat = step == .expense ? 92 : 70
        let below = hole.maxY + Spacing.lg + half
        let y = hole.midY < size.height / 2 ? below : hole.minY - Spacing.lg - half
        return CGPoint(x: size.width / 2, y: min(max(y, half + 60), size.height - half - 60))
    }
}
