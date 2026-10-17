// 设置与关于页面，提供自检详情入口。

import SwiftUI
import SwiftData
import StoreKit
#if os(iOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SettingsView: View {
    /// 在「使用指引」里选了一个讲解：切到对应页面并从头重放，由 ContentView 接手
    var onReplayGuide: (AppGuide.Tour) -> Void = { _ in }

    // 跟 ContentView / Dashboard 共享同一 key, 切换全 app 自动重绘
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage(AppTheme.followsSystemKey, store: AppPreferences.store) private var followsSystem = false
    /// 首页大数字的布局, 和 Dashboard 共享同一 key: "leading" 文字左数字右, "vertical" 居中堆叠
    @AppStorage("heroLayout") private var heroLayout: String = "leading"
    @AppStorage(AssetsLayout.key, store: AppPreferences.store) private var assetsLayout = AssetsLayout.moneyTime

    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]
    /// Pro 逐项开关：不计入自由天数的资产项
    @Query private var assetItems: [AssetItem]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    @Query private var loans: [Loan]

    @Environment(\.openURL) private var openURL
    /// 「Settings 怎么用」要圈出这一页上的位置
    @Environment(AppGuide.self) private var guide
    @State private var icpCopied = false
    @State private var showingPro = false
    /// 从外观里点了「钱与时间」进的购买页，标出那一行；从 Pro 卡进来时为空
    @State private var proTopic: ProFeatures.Topic?
    @State private var showingFreedomCard = false
    /// 一叠卡里现在抽出来的是哪张（look / ledger / about，空 = 都收着）。同一时间只开一张，下次进来还是它
    @SceneStorage("settingsOpenCard") private var openCard = "look"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 屏幕上能放卡的高度、自检卡的高度：都收着时按这两个数把卡叠铺开
    @State private var viewportHeight: CGFloat = 0
    @State private var coverHeight: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    /// 账本卡上写有几个分类
    @AppStorage(ExpenseCategoryStorage.key, store: AppPreferences.store) private var encodedCategories = ""
    /// 在 Assets 页改了口径，自检卡跟着重算
    @AppStorage(FreedomSettings.countsAssetsKey, store: AppPreferences.store) private var countsAssets = true

    private let icpNumber = "浙ICP备2026045014号-1A"
    private let privacyURL = URL(string: "https://github.com/coni555/FreeGrid-Freedom/blob/main/PRIVACY.md")!
    private let rateURL = URL(string: "https://apps.apple.com/app/id6781104287?action=write-review")!

    private var summary: FreedomSummary {
        FreedomChecklist.evaluate(expenses: expenses,
                                  passiveSources: passiveSources,
                                  assets: assetsArr.first,
                                  assetItems: assetItems,
                                  cashAccounts: cashAccounts,
                                  loans: loans,
                                  countsAssets: countsAssets)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // 一叠卡：自检在最前，后面每张藏在上一张背后、只露出下沿
                VStack(spacing: -SettingsDeck.tuck) {
                    checkCard
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { coverHeight = $0 }
                        .guideTarget(.check, in: guide)
                        .zIndex(6)
                    freedomCardCard
                        .zIndex(5)
                    // 没买时 Pro 紧跟在自由卡后面；买过了退到 FreeGrid 前面，不再占前排
                    if !proUnlocked {
                        proCard(depth: 1)
                            .zIndex(4.5)
                    }
                    lookCard(depth: proUnlocked ? 1 : 2)
                        .guideTarget(.appearance, in: guide)
                        .zIndex(4)
                    ledgerCard(depth: proUnlocked ? 2 : 3)
                        .guideTarget(.data, in: guide)
                        .zIndex(3)
                    if proUnlocked {
                        proCard(depth: 3)
                            .zIndex(2)
                    }
                    aboutCard
                        .zIndex(1)
                }
                .padding()
                .padding(.bottom, Spacing.lg)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("Settings")
            // 旧版本里 Pro 卡能抽出来，记下的 "pro" 现在没有对应的卡
            .onAppear { if openCard == "pro" { openCard = "" } }
            .proPaywall(isPresented: $showingPro, topic: proTopic)
            .sheet(isPresented: $showingFreedomCard) { FreedomCardSheet() }
            .sensoryFeedback(.selection, trigger: themeChoice)
            .sensoryFeedback(.selection, trigger: heroLayout)
            .sensoryFeedback(.selection, trigger: assetsLayout)
            // 「Settings 怎么用」: 等指引列表那一页退回来、位置排好再开始
            .task(id: guide.replays(of: .settings)) {
                guard guide.takeReplay(.settings) else { return }
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) { guide.start(.settings) }
            }
        }
    }

    /// 抽出或收回一张卡；同一时间只开一张。减弱动态效果时只淡入淡出
    private func toggle(_ card: String) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : SettingsDeck.spring) {
            openCard = openCard == card ? "" : card
        }
    }

    /// 展开的内容出现、消失的方式
    private var reveal: AnyTransition { .opacity }

    /// 收着的卡露出多高；都收着时铺满屏幕，抽出一张时都收回卡头的高度
    private var peek: CGFloat {
        SettingsDeck.peek(viewport: viewportHeight, cover: coverHeight, anyOpen: !openCard.isEmpty)
    }

    /// 卡叠铺开时，卡头下面写一行「里面有什么」
    private func detail(_ text: String) -> String? {
        peek >= SettingsDeck.detailPeek ? text : nil
    }

    // MARK: - 第 1 张：自检（封面，点了 push 完整自检）
    private var checkCard: some View {
        DeckCard(tucked: false) { checkRow }
    }

    private var checkRow: some View {
        let s = summary   // 整行只算一次 evaluate
        return NavigationLink {
            CheckView()
        } label: {
            HStack(spacing: Spacing.lg) {
                // 圆环进度
                ZStack {
                    Circle().stroke(Color.mist2, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: s.progress)
                        .stroke(Color.skyDeep, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    (Text("\(s.doneCount)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                     + Text("/\(s.total)")
                        .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit()))
                        .foregroundStyle(Color.ink)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("财富自由自检")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Color.ink)
                    if let stop = s.nextStopTitle {
                        Text("下一站 · \(stop)")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        if let remain = s.remainText {
                            Text(remain)
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(Color.skyDeep)
                        }
                    } else {
                        Text("已全部达成 🎉")
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.skyDeep)
                    }
                }

                Spacer(minLength: 0)
                chevron
            }
            .padding(20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 第 2 张：自由卡（全页唯一用材质的卡，材质就是用户现在的等级）
    private var freedomCardCard: some View {
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                                         assetItems: assetItems, cashAccounts: cashAccounts, loans: loans, countsAssets: countsAssets)
        let data = FreedomCardData(snapshot: snapshot, summary: summary)
        let material = FreedomCardMaterial.of(data.tier)
        let isFinite: Bool = { if case .finite = data.freedom { return true } else { return false } }()
        return DeckCard(fill: material.background,
                        edge: colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.08), peek: peek) {
            Button { showingFreedomCard = true } label: {
                DeckHeader(title: "我的自由卡", titleColor: material.ink) {
                    EmptyView()
                } trailing: {
                    Text(data.tier.label)
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(material.muted)
                    Spacer().frame(width: Spacing.xs)
                    DeckReading(value: data.daysText, unit: isFinite ? "天" : nil,
                                color: material.ink, unitColor: material.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("我的自由卡，\(data.tier.name)，\(data.daysText) 天")
            .accessibilityIdentifier("settings-freedom-card")
        }
    }

    private var proUnlocked: Bool { ProStore.shared.isUnlocked }

    // MARK: - 外观（默认抽出来；三行分段按钮）
    private func lookCard(depth: Int) -> some View {
        let isOpen = openCard == "look"
        return DeckCard(fill: AnyShapeStyle(SettingsDeck.paper(depth)), peek: peek) {
            VStack(spacing: 0) {
                Button { toggle("look") } label: {
                    DeckHeader(title: "外观", detail: isOpen ? nil : detail(lookSummary), isOpen: isOpen) {
                        EmptyView()
                    } trailing: {
                        ThemeGlyph(isDark: colorScheme == .dark)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-card-look")
                if isOpen {
                    VStack(spacing: 0) {
                        DeckDivider()
                        // 分段选择器 + 动画绑定: 切换经 withAnimation 让整页换色平滑过渡,
                        // 而非裸切 .preferredColorScheme 那种单帧硬重绘("突然卡顿")。
                        segmentRow("主题") {
                            Picker("主题", selection: themeBinding) {
                                Text("浅色").tag("light")
                                Text("深色").tag("dark")
                                Text("系统").tag("system")
                            }
                            .accessibilityIdentifier("theme-picker")
                        }
                        DeckDivider()
                        segmentRow("首页大数字") {
                            Picker("首页大数字", selection: heroLayoutBinding) {
                                Text("靠右").tag("leading")
                                Text("居中").tag("vertical")
                            }
                        }
                        DeckDivider()
                        // 新版「钱与时间」和经典的抽屉版，只换样子，账本和设置都一样。「钱与时间」是 Pro 的，没有 Pro 点了去购买页
                        segmentRow("Assets 页面") {
                            Picker("Assets 页面", selection: Binding(
                                get: { AssetsLayout.effective(assetsLayout) },
                                set: { newValue in
                                    if newValue == AssetsLayout.moneyTime && !ProFeatures.canUseMoneyTimeAssets {
                                        proTopic = .assetsView
                                        showingPro = true
                                        return
                                    }
                                    withAnimation(.easeInOut(duration: 0.25)) { assetsLayout = newValue }
                                }
                            )) {
                                Text("钱与时间").tag(AssetsLayout.moneyTime)
                                Text("经典").tag(AssetsLayout.classic)
                            }
                            .accessibilityIdentifier("assets-layout-picker")
                            // 「钱与时间」那一格的右上角挂一个小 PRO
                            .overlay(alignment: .topLeading) {
                                if !ProFeatures.canUseMoneyTimeAssets {
                                    HStack(spacing: 0) {
                                        Spacer(minLength: 0)
                                        ProBadge(fill: SettingsDeck.paper(depth))
                                    }
                                    .frame(width: 75)
                                    .offset(x: 4, y: -7)
                                    .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .padding(.bottom, Spacing.xs)
                    .transition(reveal)
                }
            }
        }
    }

    /// 外观卡收着时写的那一行：现在的三个选择
    private var lookSummary: String {
        [followsSystem ? "跟随系统" : (isDarkMode ? "深色" : "浅色"),
         heroLayout == "vertical" ? "居中" : "靠右",
         AssetsLayout.effective(assetsLayout) == AssetsLayout.classic ? "经典" : "钱与时间"].joined(separator: " · ")
    }

    /// 外观里的一行：左边名字，右边同样宽的分段按钮，三行右边缘对齐
    private func segmentRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color.ink)
            Spacer(minLength: Spacing.sm)
            control()
                .pickerStyle(.segmented)
                .frame(width: 150)
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(minHeight: 48)
    }

    private var heroLayoutBinding: Binding<String> {
        Binding(
            get: { heroLayout == "vertical" ? "vertical" : "leading" },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.25)) { heroLayout = newValue }
            }
        )
    }

    /// 主题绑定: setter 包在 withAnimation 里 — 切换时整页换色走 0.25s 缓动交叉淡入,
    /// 不是单帧硬重绘。这是消除"切主题突然卡顿"的关键。
    private var themeBinding: Binding<String> {
        Binding(
            get: { themeChoice },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.25)) {
                    followsSystem = newValue == "system"
                    if newValue != "system" { isDarkMode = newValue == "dark" }
                }
            }
        )
    }

    /// 「light」「dark」或「system」
    private var themeChoice: String { followsSystem ? "system" : (isDarkMode ? "dark" : "light") }

    // MARK: - 账本（读数是一共记了几笔）
    private func ledgerCard(depth: Int) -> some View {
        let isOpen = openCard == "ledger"
        let records = expenses.count + incomes.count
        return DeckCard(fill: AnyShapeStyle(SettingsDeck.paper(depth)), peek: peek) {
            VStack(spacing: 0) {
                Button { toggle("ledger") } label: {
                    DeckHeader(title: "账本", detail: isOpen ? nil : detail("\(categoryCount) 个分类 · 备份与恢复"), isOpen: isOpen) {
                        EmptyView()
                    } trailing: {
                        DeckReading(value: records.formatted(.number), unit: "笔")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-card-ledger")
                if isOpen {
                    VStack(spacing: 0) {
                        DeckDivider()
                        NavigationLink {
                            ExpenseCategoriesView()
                        } label: {
                            DeckRow(title: "支出分类") {
                                Text("\(categoryCount) 类")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(Color.inkFaint)
                                // 已经解锁就不必再标
                                if !ProStore.shared.isUnlocked {
                                    Text("PRO")
                                        .font(.system(size: 10, design: .monospaced))
                                        .tracking(2)
                                        .foregroundStyle(Color.skyDeep)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("expense-categories-settings")
                        DeckDivider()
                        // 导出、导入、清空集中在这一页
                        NavigationLink {
                            DataManagementView()
                        } label: {
                            DeckRow(title: "备份与恢复") { EmptyView() }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings-data")
                    }
                    .padding(.bottom, Spacing.xs)
                    .transition(reveal)
                }
            }
        }
    }

    /// 记支出时能选的分类有几个（月供扣款的分类是贷款名，不算）
    private var categoryCount: Int {
        ExpenseCategoryStorage.decode(encodedCategories)
            .including(expenses.filter { $0.loanID == nil }.map(\.category))
            .activeItems.count
    }

    // MARK: - Pro（和别的卡同一种纸，只多一道蓝竖线和一个描边的「看看」胶囊；点了直接弹出对照表，不抽出来）
    private func proCard(depth: Int) -> some View {
        DeckCard(fill: AnyShapeStyle(SettingsDeck.paper(depth)), peek: peek) {
            Button {
                proTopic = nil
                showingPro = true
            } label: {
                DeckHeader(title: "FreeGrid Pro",
                           detail: detail(proUnlocked ? "全部功能已解锁" : ProFeatures.headline)) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.skyDeep).frame(width: 3, height: 14)
                } trailing: {
                    if proUnlocked {
                        Text("PRO")
                            .font(.system(size: 10, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(Color.skyDeep)
                    } else {
                        // 卡面不写价格：设置页是看一眼的地方，钱留到购买页再说
                        Text("看看")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.skyDeep)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings-card-pro")
        }
    }

    // MARK: - 最后一张：FreeGrid（使用指引、关于、评价）
    private var aboutCard: some View {
        let isOpen = openCard == "about"
        return DeckCard(fill: AnyShapeStyle(SettingsDeck.paper(4)), peek: peek) {
            VStack(spacing: 0) {
                Button { toggle("about") } label: {
                    DeckHeader(title: "FreeGrid", detail: isOpen ? nil : detail("使用指引 · 关于 · 评价"), isOpen: isOpen) {
                        VStack(spacing: 1.5) {
                            HStack(spacing: 1.5) { logoCell(Color.inkFaint); logoCell(Color.assetGold) }
                            HStack(spacing: 1.5) { logoCell(Color.cashBlue); logoCell(Color.inkFaint) }
                        }
                        .accessibilityHidden(true)
                    } trailing: {
                        DeckReading(value: appVersion)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-card-about")
                if isOpen {
                    VStack(spacing: 0) {
                        DeckDivider()
                        guideRow
                        DeckDivider()
                        NavigationLink {
                            aboutPage
                        } label: {
                            DeckRow(title: "关于") { EmptyView() }
                        }
                        .buttonStyle(.plain)
                        DeckDivider()
                        Button { openURL(rateURL) } label: {
                            DeckRow(title: "评价与反馈", chevron: "arrow.up.right") { EmptyView() }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, Spacing.xs)
                    .transition(reveal)
                }
            }
        }
    }

    private func logoCell(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous).fill(color).frame(width: 5, height: 5)
    }

    // MARK: - 关于子页 (版本 / 隐私政策 / ICP) — 从「关于」push 进入
    /// 讲解要圈出页面上的数字和记录，账本为空时没有可圈的位置
    @ViewBuilder
    private var guideRow: some View {
        if expenses.isEmpty && incomes.isEmpty {
            DeckRow(title: "使用指引", titleColor: .inkFaint, chevron: nil) {
                Text("记一笔后可看")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        } else {
            NavigationLink {
                GuideListPage(onReplay: onReplayGuide)
            } label: {
                DeckRow(title: "使用指引") { EmptyView() }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("guide-list")
        }
    }

    private var aboutPage: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                settingsSection("") {
                    settingsRow(icon: "info.circle", title: "版本") {
                        Text(appVersion)
                            .font(.system(.subheadline, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkFaint)
                    }
                    rowDivider
                    settingsRow(icon: "lock.shield", title: "隐私政策",
                                action: { openURL(privacyURL) }) { chevron }
                    rowDivider
                    icpRow
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("关于")
        .inlineNavTitle()
    }

    // ICP 备案号: 等宽显示 + 点行复制(满足「App 内显著位置标注备案号」合规)
    private var icpRow: some View {
        Button {
            copyICP()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.inkMuted)
                    .frame(width: 26, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ICP 备案号")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text(icpNumber)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.inkFaint)
                        .textSelection(.enabled)
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: icpCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(icpCopied ? Color.mossGreen : Color.inkGhost)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 复用组件
    /// 一节: 小标题 + 圆角分组卡(行之间手动插 rowDivider)
    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !title.isEmpty {
                KickerLabel(text: title)
                    .padding(.leading, Spacing.lg)
            }
            VaultCard(padding: 0) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    /// 一行: 图标 + 标题 + 右侧 trailing。给 action 则整行可点。
    @ViewBuilder
    private func settingsRow<Trailing: View>(
        icon: String,
        title: String,
        iconColor: Color = .inkMuted,
        titleColor: Color = .ink,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let row = HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 26, alignment: .center)
            Text(title)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(titleColor)
            Spacer(minLength: Spacing.sm)
            trailing()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var rowDivider: some View {
        Hairline().padding(.leading, Spacing.lg + 26 + Spacing.md)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.inkGhost)
    }

    private func copyICP() {
        #if os(iOS)
        UIPasteboard.general.string = icpNumber
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(icpNumber, forType: .string)
        #endif
        withAnimation { icpCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { icpCopied = false }
        }
    }
}

/// 「使用指引」列表：点哪一个就跳到那一页从头讲一遍。
/// 单独成一个视图是为了拿到这一页自己的 dismiss：先退回 Settings 首页再开始讲，
/// 否则「Settings 怎么用」要圈的东西被这一页盖着。
private struct GuideListPage: View {
    let onReplay: (AppGuide.Tour) -> Void
    @Environment(\.dismiss) private var dismiss

    private let items: [(tour: AppGuide.Tour, icon: String, title: String, id: String)] = [
        (.dashboard, "chart.line.uptrend.xyaxis", "认识首页", "replay-dashboard-guide"),
        (.assets, "banknote", "Assets 怎么用", "replay-assets-guide"),
        (.history, "clock.arrow.circlepath", "History 怎么用", "replay-history-guide"),
        (.settings, "gearshape", "Settings 里有什么", "replay-settings-guide"),
    ]

    var body: some View {
        ScrollView {
            VaultCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Hairline().padding(.leading, Spacing.lg + 26 + Spacing.md)
                        }
                        Button {
                            dismiss()
                            onReplay(item.tour)
                        } label: {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.inkMuted)
                                    .frame(width: 26, alignment: .center)
                                Text(item.title)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.ink)
                                Spacer(minLength: Spacing.sm)
                                Image(systemName: "play")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.inkGhost)
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(item.id)
                    }
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("使用指引")
        .inlineNavTitle()
    }
}

/// 分段按钮角上的小 PRO：描边胶囊，底色和卡面一样，盖住分段按钮的边
private struct ProBadge: View {
    var fill: Color

    var body: some View {
        Text("PRO")
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Color.skyDeep)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 0.75))
    }
}
