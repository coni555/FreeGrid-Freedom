// 设置与关于页面，提供自检详情入口。

import SwiftUI
import SwiftData
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
    /// 首页大数字的布局, 和 Dashboard 共享同一 key: "leading" 文字左数字右, "vertical" 居中堆叠
    @AppStorage("heroLayout") private var heroLayout: String = "leading"
    @AppStorage(AssetsLayout.key, store: AppPreferences.store) private var assetsLayout = AssetsLayout.moneyTime

    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]
    /// Pro 逐项开关：不计入自由天数的资产项
    @Query private var assetItems: [AssetItem]
    @Query private var loans: [Loan]

    @Environment(\.openURL) private var openURL
    /// 「Settings 怎么用」要圈出这一页上的位置
    @Environment(AppGuide.self) private var guide
    @State private var icpCopied = false
    @State private var showingPro = false
    @State private var showingFreedomCard = false
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
                                  loans: loans,
                                  countsAssets: countsAssets)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // 四张卡：你走到哪了 → 外观 → 账本 → FreeGrid，最下面一行版本号
                VStack(spacing: Spacing.xl) {
                    freedomCard
                        .guideTarget(.check, in: guide)
                    appearanceSection
                        .guideTarget(.appearance, in: guide)
                    ledgerSection
                        .guideTarget(.data, in: guide)
                    freeGridSection
                    footer
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPro) { ProPaywallView() }
            .sheet(isPresented: $showingFreedomCard) { FreedomCardSheet() }
            // 「Settings 怎么用」: 等指引列表那一页退回来、位置排好再开始
            .task(id: guide.replays(of: .settings)) {
                guard guide.takeReplay(.settings) else { return }
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) { guide.start(.settings) }
            }
        }
    }

    // MARK: - 第一张卡：自检（push 完整自检子页）+ 自由卡
    /// 自检是「走到哪了」，自由卡是「把这一刻拿出去晒」，放进同一张卡，上下两个入口
    private var freedomCard: some View {
        VaultCard(emphasis: .high, padding: 0) {
            VStack(spacing: 0) {
                checkRow
                Hairline().padding(.leading, Spacing.lg)
                freedomCardRow
            }
        }
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

    /// 左边是当前材质的小卡，和上面的圆环同宽对齐
    private var freedomCardRow: some View {
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                                         assetItems: assetItems, loans: loans, countsAssets: countsAssets)
        let tier = FreedomCardTier.tier(for: snapshot.freedom)
        return Button { showingFreedomCard = true } label: {
            HStack(spacing: Spacing.lg) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(FreedomCardMaterial.of(tier).background)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.hairline, lineWidth: 1))
                    .frame(width: 56, height: 35)
                Text("我的自由卡")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.ink)
                Spacer(minLength: Spacing.sm)
                Text(tier.name)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                chevron
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-freedom-card")
    }

    // MARK: - 分组
    /// 主题用两张小预览选，其余两项是菜单：一年改不了几次，不占一整排分段按钮
    private var appearanceSection: some View {
        settingsSection("外观") {
            HStack(spacing: Spacing.xl) {
                themeTile(dark: false)
                themeTile(dark: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)
            rowDivider
            settingsRow(icon: "rectangle.split.2x1", title: "首页大数字") {
                Menu {
                    Picker("首页大数字", selection: heroLayoutBinding) {
                        Text("靠右").tag("leading")
                        Text("居中").tag("vertical")
                    }
                } label: {
                    menuValue(heroLayoutBinding.wrappedValue == "vertical" ? "居中" : "靠右")
                }
                .accessibilityIdentifier("hero-layout-picker")
            }
            rowDivider
            // 新版「钱与时间」和经典的抽屉版，只换样子，账本和设置都一样
            settingsRow(icon: "square.split.1x2", title: "Assets 页面") {
                let isClassic = assetsLayout == AssetsLayout.classic
                Menu {
                    Picker("Assets 页面", selection: Binding(
                        get: { isClassic ? AssetsLayout.classic : AssetsLayout.moneyTime },
                        set: { newValue in withAnimation(.easeInOut(duration: 0.25)) { assetsLayout = newValue } }
                    )) {
                        Text("钱与时间").tag(AssetsLayout.moneyTime)
                        Text("经典").tag(AssetsLayout.classic)
                    }
                } label: {
                    menuValue(isClassic ? "经典" : "钱与时间")
                }
                .accessibilityIdentifier("assets-layout-picker")
            }
        }
    }

    /// 菜单行右边：当前值 + 上下箭头，箭头和别的行的 › 对齐
    private func menuValue(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.inkGhost)
        }
        .contentShape(Rectangle())
    }

    /// 一张缩小的首页：大数字卡 + 几排格子，按浅色或深色画；选中的那张描一圈蓝
    private func themeTile(dark: Bool) -> some View {
        let selected = isDarkMode == dark
        return Button { themeBinding.wrappedValue = dark } label: {
            VStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.surfaceHi)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.hairline, lineWidth: 0.5))
                        .overlay(alignment: .bottomTrailing) {
                            Text("148")
                                .font(.system(size: 17, weight: .ultraLight, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .padding(.trailing, 5)
                        }
                        .frame(height: 30)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(5), spacing: 2), count: 8), spacing: 2) {
                        ForEach(0..<40, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(index < 22 ? Color.assetGold : index < 34 ? Color.cashBlue : Color.mist2)
                                .frame(width: 5, height: 5)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(width: 66, height: 100)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.paper))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.hairline, lineWidth: 1))
                .environment(\.colorScheme, dark ? .dark : .light)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.skyDeep, lineWidth: 1.5)
                        .padding(-3)
                        .opacity(selected ? 1 : 0)
                )
                Text(dark ? "深色" : "浅色")
                    .font(.system(.subheadline, design: .rounded).weight(selected ? .medium : .regular))
                    .foregroundStyle(selected ? Color.skyDeep : Color.inkMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dark ? "深色" : "浅色")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(dark ? "theme-dark" : "theme-light")
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
    private var themeBinding: Binding<Bool> {
        Binding(
            get: { isDarkMode },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.25)) { isDarkMode = newValue }
            }
        )
    }

    /// 支出分类 + 备份与恢复：都是账本本身的事
    private var ledgerSection: some View {
        settingsSection("账本") {
            NavigationLink {
                ExpenseCategoriesView()
            } label: {
                settingsRow(icon: "list.bullet", title: "支出分类") {
                    // 已经解锁就不必再标
                    if !ProStore.shared.isUnlocked {
                        Text("PRO")
                            .font(.system(.caption2, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(Color.skyDeep)
                    }
                    chevron
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("expense-categories-settings")
            rowDivider
            // 导出、导入、清空集中在这一页
            NavigationLink {
                DataManagementView()
            } label: {
                settingsRow(icon: "externaldrive", title: "备份与恢复") { chevron }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings-data")
        }
    }

    /// 和 App 本身有关的：Pro、使用指引、关于、评价
    private var freeGridSection: some View {
        settingsSection("FreeGrid") {
            settingsRow(icon: "sparkles", title: "FreeGrid Pro",
                        action: { showingPro = true }) {
                Text(ProStore.shared.isUnlocked ? "已解锁" : "永久买断")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                chevron
            }
            .accessibilityIdentifier("settings-pro")
            rowDivider
            guideRow
            rowDivider
            NavigationLink {
                aboutPage
            } label: {
                settingsRow(icon: "info.circle", title: "关于") { chevron }
            }
            .buttonStyle(.plain)
            rowDivider
            settingsRow(icon: "star", title: "评价与反馈",
                        action: { openURL(rateURL) }) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.inkGhost)
            }
        }
    }

    /// 页底：FreeGrid 的 2×2 小格子记号和版本号
    private var footer: some View {
        HStack(spacing: Spacing.sm) {
            VStack(spacing: 1.5) {
                HStack(spacing: 1.5) { footerMark(Color.inkFaint); footerMark(Color.assetGold) }
                HStack(spacing: 1.5) { footerMark(Color.cashBlue); footerMark(Color.inkFaint) }
            }
            KickerLabel(text: "FreeGrid \(appVersion)")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.lg)
        .accessibilityElement(children: .combine)
    }

    private func footerMark(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous).fill(color).frame(width: 5, height: 5)
    }

    // MARK: - 关于子页 (版本 / 隐私政策 / ICP) — 从「关于」push 进入
    /// 讲解要圈出页面上的数字和记录，账本为空时没有可圈的位置
    @ViewBuilder
    private var guideRow: some View {
        if expenses.isEmpty && incomes.isEmpty {
            settingsRow(icon: "questionmark.circle", title: "使用指引",
                        iconColor: .inkGhost, titleColor: .inkFaint) {
                Text("记一笔后可看")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        } else {
            NavigationLink {
                GuideListPage(onReplay: onReplayGuide)
            } label: {
                settingsRow(icon: "questionmark.circle", title: "使用指引") { chevron }
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
