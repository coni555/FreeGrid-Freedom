// 设置与关于页面，提供自检详情入口。

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SettingsView: View {
    // 跟 ContentView / Dashboard 共享同一 key, 切换全 app 自动重绘
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    @Query private var expenses: [Expense]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]

    @Environment(\.openURL) private var openURL
    @State private var icpCopied = false

    private let icpNumber = "浙ICP备2026045014号-1A"
    private let privacyURL = URL(string: "https://github.com/coni555/FreeGrid-Freedom/blob/main/PRIVACY.md")!
    private let rateURL = URL(string: "https://apps.apple.com/app/id6781104287?action=write-review")!

    private var summary: FreedomSummary {
        FreedomChecklist.evaluate(expenses: expenses,
                                  passiveSources: passiveSources,
                                  assets: assetsArr.first)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    checkCard
                    appearanceSection
                    aboutSupportSection
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("Settings")
        }
    }

    // MARK: - 自检收缩卡 → push 完整自检子页
    private var checkCard: some View {
        let s = summary   // 整张卡只算一次 evaluate
        return NavigationLink {
            CheckView()
        } label: {
            VaultCard(emphasis: .high) {
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
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.inkGhost)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 分组
    private var appearanceSection: some View {
        settingsSection("外观") {
            settingsRow(icon: "moon", title: "主题") {
                // 分段选择器 + 动画绑定: 切换经 withAnimation 让整页换色平滑过渡,
                // 而非裸切 .preferredColorScheme 那种单帧硬重绘("突然卡顿")。
                // 跟 Dashboard 顶栏切换同款 0.25s 缓动, 且不像 Menu 那样有收起动画叠加。
                Picker("主题", selection: themeBinding) {
                    Text("浅色").tag(false)
                    Text("深色").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
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

    /// 关于(进子页) + 评价与反馈(跳 App Store)。无标题分组 —— 顶层保持精简,
    /// 后续加新功能时也按"入口行 → push 子页"这套模式往这里 / 新卡里加。
    private var aboutSupportSection: some View {
        settingsSection("") {
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

    // MARK: - 关于子页 (版本 / 隐私政策 / ICP) — 从「关于」push 进入
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
                Text(title)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .padding(.leading, Spacing.md)
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
