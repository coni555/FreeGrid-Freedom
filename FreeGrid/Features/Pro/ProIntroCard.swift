// 老用户打开 2.0 时在首页弹的卡片（用户 2026-10-18 选的 A 版：不要整屏，弹一张卡）。
// 先讲 2.0 所有人都有的免费更新，分隔线下面才提一句 Pro；「知道了」和「看看 Pro」一样大，点「看看 Pro」才进购买页。
// 页面压暗，点卡片外面也能关。什么时候弹看 ProIntro 和 ContentView。

import SwiftUI

extension View {
    /// 在整页上面盖一层老用户的 2.0 卡片。`onAppear`：真的出现在屏幕上时调用，用来记「弹过了」
    func returningProIntro(isPresented: Binding<Bool>, onAppear: @escaping () -> Void) -> some View {
        modifier(ReturningProIntroPresenter(isPresented: isPresented, onAppear: onAppear))
    }
}

private struct ReturningProIntroPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let onAppear: () -> Void
    #if os(macOS)
    @State private var showingPaywall = false
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        // 用透明的整屏弹层：iOS 26 的 tab bar 浮在页面最上层，盖在页面上的 overlay 压不暗它。
        // 弹层本身不做滑入动画，压暗和卡片在里面自己动；「看看 Pro」在同一个弹层里换成购买页
        content.fullScreenCover(isPresented: $isPresented) {
            ProIntroCardLayer(onFinish: dismissWithoutAnimation, onLearnMore: nil)
                .presentationBackground(.clear)
                .onAppear(perform: onAppear)
        }
        #else
        content
            .overlay {
                if isPresented {
                    ProIntroCardLayer(onFinish: { isPresented = false },
                                      onLearnMore: { isPresented = false; showingPaywall = true })
                        .onAppear(perform: onAppear)
                }
            }
            .proPaywall(isPresented: $showingPaywall)
        #endif
    }

    private func dismissWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = false }
    }
}

/// 压暗的底和屏幕中间浮起的卡片。放中间而不是贴底：贴底会压在 iOS 26 浮起的 tab bar 上，露出半截标签。
/// 出现和收起的动画都在这里做
private struct ProIntroCardLayer: View {
    /// 卡片收完了，把这一层拿掉
    let onFinish: () -> Void
    /// nil：在这一层里直接换成购买页（iOS）
    let onLearnMore: (() -> Void)?

    @State private var showingCard = false
    @State private var showingPaywall = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if showingCard {
                Color.black.opacity(colorScheme == .dark ? 0.5 : 0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                ProIntroCard(onClose: close, onLearnMore: learnMore)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, Spacing.lg)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 24)))
            }
            if showingPaywall {
                ProPaywallView()
                    .background(Color.paper.ignoresSafeArea())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .bottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(duration: 0.45, bounce: 0.12)) { showingCard = true }
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.22)) { showingCard = false } completion: { onFinish() }
    }

    private func learnMore() {
        if let onLearnMore {
            withAnimation(.easeOut(duration: 0.22)) { showingCard = false } completion: { onLearnMore() }
        } else {
            withAnimation(.easeInOut(duration: 0.32)) {
                showingCard = false
                showingPaywall = true
            }
        }
    }
}

private struct ProIntroCard: View {
    let onClose: () -> Void
    let onLearnMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                KickerLabel(text: "FreeGrid 2.0")
                Text("这次更新了什么")
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
            }

            // 免费更新在前，写明所有人都有（AGENTS「宣发」）
            VStack(alignment: .leading, spacing: 12) {
                update("固定支出", "房租、订阅按到期日自动扣，自由天数不再跳水")
                update("日均更稳", "记账不满 90 天时，一笔大额不再让日均暴涨")
                Text("以上所有人都有，一直免费。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .padding(.leading, 32)
            }

            Hairline(color: .hairlineSoft)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("PRO")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color.skyDeep)
                        .padding(.leading, 8)
                        .padding(.trailing, 6)
                        .frame(height: 19)
                        .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
                        .accessibilityHidden(true)
                    Text("新增 Pro，一次买断")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                }
                Text("自定义分类、子账户、贷款与分期、导出自由卡。\n可以先免费体验 \(ProOffer.trialDays) 天，到期自动回到免费版。")
                    .font(.system(.footnote, design: .rounded))
                    .lineSpacing(3)
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                VaultButton(title: "知道了", style: .secondary, verticalPadding: 12, action: onClose)
                    .accessibilityIdentifier("pro-intro-close")
                VaultButton(title: "看看 Pro", verticalPadding: 12, action: onLearnMore)
                    .accessibilityIdentifier("pro-intro-learn-more")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.mist))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .accessibilityIdentifier("pro-intro-returning")
    }

    private func update(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Color.mossGreen)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
