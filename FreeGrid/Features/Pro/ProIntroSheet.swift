// 老用户的 2.0 Pro 介绍：整屏，先说免费的都还在，再放购买页那张免费 / Pro 对照卡，底部能体验也能直接买断。
// 「免费体验」在这里直接开始，按钮下面是和购买页同一段体验条款。
// 新用户不弹（用户 2026-10-18）。什么时候弹看 ProIntro 和 ContentView。

import SwiftUI

extension View {
    /// 弹老用户的 Pro 介绍。`onAppear`：真的出现在屏幕上时调用，用来记「弹过了」
    func returningProIntro(isPresented: Binding<Bool>, onAppear: @escaping () -> Void) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) { ReturningProIntro().onAppear(perform: onAppear) }
        #else
        sheet(isPresented: isPresented) {
            ReturningProIntro().onAppear(perform: onAppear).frame(width: 520, height: 720)
        }
        #endif
    }
}

// MARK: - 页面

private struct ReturningProIntro: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.isUnlocked {
                    ProIntroWelcome { dismiss() }
                        .padding(Spacing.xl)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: Spacing.xl) {
                            header
                            freeNote
                            ProComparisonTable()
                        }
                        .padding(.horizontal)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.lg)
                    }
                    .scrollContentBackground(.hidden)
                    .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                }
            }
            .background(Color.paper)
            .inlineNavTitle()
            .toolbar {
                if !store.isUnlocked {
                    // 和购买页的「关闭」一个样子：没有玻璃底，一行淡字
                    if #available(iOS 26.0, macOS 26.0, *) {
                        ToolbarItem(placement: .cancellationAction) { laterButton }
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .cancellationAction) { laterButton }
                    }
                }
            }
        }
        .accessibilityIdentifier("pro-intro-returning")
    }

    private var laterButton: some View {
        Button { dismiss() } label: {
            Text("以后再说")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize()
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pro-intro-later")
    }

    private var header: some View {
        VStack(spacing: 0) {
            ProBrandLockup()
                .padding(.bottom, Spacing.lg)
            // 标题是设置页 Pro 卡上用户 2026-10-17 定的那句
            Text(ProFeatures.headline)
                .font(.system(size: 28, weight: .light, design: .rounded))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.bottom, Spacing.sm)
            Text("一次买断，不订阅。\n先免费体验 \(ProOffer.trialDays) 天，全部功能都打开。")
                .font(.system(.subheadline, design: .rounded))
                .lineSpacing(5)
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xs)
    }

    /// 先让老用户放心：免费的一样不少，2.0 的免费更新也有（AGENTS「宣发」：免费改动要标明所有用户都有）
    private var freeNote: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Color.mossGreen)
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text("你在用的功能都还在，一直免费。")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                Text("2.0 新增的固定支出、更稳的日均，免费版也有。")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.mist))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let prices = ProPrices.current(store) {
            ProIntroActions(prices: prices)
                .padding(.horizontal)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)
                .background(Color.paper)
                .overlay(alignment: .top) { Hairline() }
        }
    }
}

// MARK: - 底部和开始之后的那一屏

/// 体验按钮、直接买断、体验条款。「以后再说」在左上角
private struct ProIntroActions: View {
    let prices: ProPrices

    @State private var store = ProStore.shared
    /// 操作没成功时给用户的一句话
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 6) {
            if let notice {
                Text(notice)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("pro-intro-notice")
            }
            VaultButton(title: "免费体验 \(ProOffer.trialDays) 天", icon: "sparkles", verticalPadding: 11) {
                Task { await startTrial() }
            }
            .disabled(store.isWorking)
            .accessibilityIdentifier("pro-intro-start-trial")
            Button { Task { await buy() } } label: {
                Text("永久解锁 Pro · \(prices.special)")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.skyDeep)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isWorking)
            .accessibilityIdentifier("pro-intro-purchase")
            ProTrialTerms(prices: prices)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
        }
    }

    private func startTrial() async {
        switch await store.startTrial() {
        case .purchased, .cancelled: notice = nil
        case .pending: notice = "体验在等待批准，批准后会自动开始。"
        case .failed(let message): notice = message
        }
    }

    private func buy() async {
        switch await store.purchase() {
        case .purchased, .cancelled: notice = nil
        case .pending: notice = "这笔购买在等待批准，批准后 Pro 会自动解锁。"
        case .failed(let message): notice = message
        }
    }
}

/// 体验开始或买断之后，弹窗换成这一屏：先说结果，再说之后会怎样
private struct ProIntroWelcome: View {
    let onDone: () -> Void
    @State private var store = ProStore.shared

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Color.mossGreen)
            VStack(spacing: Spacing.sm) {
                Text(store.ownsPro ? "Pro 已解锁" : "体验已开始")
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.system(.subheadline, design: .rounded))
                    .lineSpacing(5)
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            VaultButton(title: "开始使用", verticalPadding: 11, action: onDone)
                .accessibilityIdentifier("pro-intro-done")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro-intro-welcome")
    }

    private var detail: String {
        if store.ownsPro { return "感谢你对 FreeGrid 的支持。\n愿你始终拥有选择的底气。" }
        let days = store.offer.trialEndsAt.map { ProOffer.daysLeft(until: $0, from: store.now) } ?? ProOffer.trialDays
        return "接下来 \(days) 天，Pro 的功能全部可用。\n到期自动恢复免费版，不扣费。"
    }
}
