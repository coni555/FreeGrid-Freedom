// 首页弹的介绍卡片共用的弹法：整页压暗，屏幕中间浮起一张卡，点卡片外面也能关；
// 卡片上点「看看 Pro」时收起卡片、打开购买页。
// 用它的有老用户的 2.0 更新说明（ProIntroCard）和新用户记满 7 天的小结（FirstWeekRecapCard）。

import SwiftUI

extension View {
    /// 在整页上面盖一层介绍卡片。`card` 拿到「关掉」和「看看 Pro」两个动作；
    /// `onAppear`：卡片真的出现在屏幕上时调用，用来记「弹过了」
    func introCard<Card: View>(isPresented: Binding<Bool>, onAppear: @escaping () -> Void,
                               @ViewBuilder card: @escaping (_ close: @escaping () -> Void,
                                                             _ learnMore: @escaping () -> Void) -> Card) -> some View {
        modifier(IntroCardPresenter(isPresented: isPresented, onAppear: onAppear, card: card))
    }
}

private struct IntroCardPresenter<Card: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onAppear: () -> Void
    let card: (_ close: @escaping () -> Void, _ learnMore: @escaping () -> Void) -> Card
    #if os(macOS)
    @State private var showingPaywall = false
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        // 用透明的整屏弹层：iOS 26 的 tab bar 浮在页面最上层，盖在页面上的 overlay 压不暗它。
        // 弹层本身不做滑入动画，压暗和卡片在里面自己动；「看看 Pro」在同一个弹层里换成购买页
        content.fullScreenCover(isPresented: $isPresented) {
            IntroCardLayer(onFinish: dismissWithoutAnimation, onLearnMore: nil, card: card)
                .presentationBackground(.clear)
                .onAppear(perform: onAppear)
        }
        #else
        content
            .overlay {
                if isPresented {
                    IntroCardLayer(onFinish: { isPresented = false },
                                   onLearnMore: { isPresented = false; showingPaywall = true }, card: card)
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
private struct IntroCardLayer<Card: View>: View {
    /// 卡片收完了，把这一层拿掉
    let onFinish: () -> Void
    /// nil：在这一层里直接换成购买页（iOS）
    let onLearnMore: (() -> Void)?
    let card: (_ close: @escaping () -> Void, _ learnMore: @escaping () -> Void) -> Card

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
                card(close, learnMore)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, 26)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.mist))
                    .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.hairline, lineWidth: 1))
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape, close)
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

/// 卡片底部的一对按钮：「知道了」和「看看 Pro」一样大。不提 Pro 时只有「知道了」
struct IntroCardButtons: View {
    var showsLearnMore = true
    let onClose: () -> Void
    let onLearnMore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VaultButton(title: "知道了", style: .secondary, verticalPadding: 12, action: onClose)
                .accessibilityIdentifier("intro-card-close")
            if showsLearnMore {
                VaultButton(title: "看看 Pro", verticalPadding: 12, action: onLearnMore)
                    .accessibilityIdentifier("intro-card-learn-more")
            }
        }
        .padding(.top, 2)
    }
}

/// 卡片里提 Pro 的那一段开头的小胶囊
struct IntroCardProTag: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(2)
            .foregroundStyle(Color.skyDeep)
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 19)
            .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
