// 2.0 的 Pro 介绍弹窗，新老用户各一版；什么时候弹、弹哪版看 ProIntro 和 ContentView。
// 新用户版温和：一张贴着内容高度的底部卡，一句话、三项、一个体验按钮，「以后再说」紧挨着。
// 老用户版要吸引人：整屏，先说免费的都还在，再逐项写 Pro 比免费版多了什么，底部能体验也能直接买断。
// 两版的「免费体验」都在这里直接开始，按钮下面是和购买页同一段体验条款。

import SwiftUI

extension View {
    /// 按 `audience` 弹出对应的一版；关掉时把它清回 nil。`onAppear`：真的出现在屏幕上时调用，用来记「弹过了」
    func proIntro(_ audience: Binding<ProIntro.Audience?>, onAppear: @escaping () -> Void) -> some View {
        let newcomer = Binding(
            get: { audience.wrappedValue == .newcomer },
            set: { if !$0 { audience.wrappedValue = nil } }
        )
        let returning = Binding(
            get: { audience.wrappedValue == .returning },
            set: { if !$0 { audience.wrappedValue = nil } }
        )
        #if os(iOS)
        return sheet(isPresented: newcomer) { NewcomerProIntro().onAppear(perform: onAppear) }
            .fullScreenCover(isPresented: returning) { ReturningProIntro().onAppear(perform: onAppear) }
        #else
        return sheet(isPresented: newcomer) { NewcomerProIntro().onAppear(perform: onAppear) }
            .sheet(isPresented: returning) {
                ReturningProIntro().onAppear(perform: onAppear).frame(width: 520, height: 720)
            }
        #endif
    }
}

// MARK: - 新用户：温和的一张卡

private struct NewcomerProIntro: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProStore.shared
    @State private var height: CGFloat = 480

    /// 挑三项最好懂的，文字直接用对照表上的「功能，Pro 那一格」
    private let highlights: [ProFeatures.Row] = ProFeatures.comparison.filter { row in
        [.categories, .assets, .loans].contains { row.topics.first == $0 }
    }

    var body: some View {
        Group {
            if store.isUnlocked {
                ProIntroWelcome { dismiss() }
            } else {
                content
            }
        }
        .padding(Spacing.xl)
        .padding(.top, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(iOS)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.paper)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        #else
        .background(Color.paper)
        .frame(width: 420)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro-intro-newcomer")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "FreeGrid Pro", color: .skyDeep)
                Text("Pro 可以免费体验 \(ProOffer.trialDays) 天")
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundStyle(Color.ink)
                Text("现在用的功能都免费，以后也是。\nPro 还能做这些：")
                    .font(.system(.subheadline, design: .rounded))
                    .lineSpacing(3)
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(highlights) { row in
                    HStack(spacing: Spacing.md) {
                        Image(systemName: row.symbol ?? "sparkles")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(Color.skyDeep)
                            .frame(width: 22)
                        Text("\(row.title)，\(ProIntroRow.text(row.pro))")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let prices = ProPrices.current(store) {
                ProIntroActions(prices: prices, secondary: .later { dismiss() })
            }
        }
    }
}

// MARK: - 老用户：整屏讲清楚 Pro 多了什么

private struct ReturningProIntro: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProStore.shared

    /// 两边都有的行不讲，只讲 Pro 多出来的
    private let gains = ProFeatures.comparison.filter { $0.pitch != nil }

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
                            gainsCard
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
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.mist))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// 每项三行：功能名；免费那格 → Pro 那格；一句为什么值得
    private var gainsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pro 比免费版多了这些")
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(Color.inkMuted)
                .padding(.vertical, Spacing.md)
            ForEach(gains) { row in
                Hairline()
                ProIntroRow(row: row)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.xs)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.mist))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let prices = ProPrices.current(store) {
            ProIntroActions(prices: prices, secondary: .purchase)
                .padding(.horizontal)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)
                .background(Color.paper)
                .overlay(alignment: .top) { Hairline() }
        }
    }
}

/// 老用户版里的一项
private struct ProIntroRow: View {
    let row: ProFeatures.Row

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: row.symbol ?? "sparkles")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Color.skyDeep)
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ink)
                HStack(spacing: 6) {
                    Text(Self.text(row.free))
                        .foregroundStyle(Color.inkFaint)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(Color.inkGhost)
                    Text(Self.text(row.pro))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.skyDeep)
                }
                .font(.system(size: 13, design: .rounded))
                if let pitch = row.pitch {
                    Text(pitch)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title)，免费：\(Self.text(row.free))，Pro：\(Self.text(row.pro))。\(row.pitch ?? "")")
    }

    static func text(_ cell: ProFeatures.Cell) -> String {
        switch cell {
        case .yes: return "有"
        case .no: return "没有"
        case .text(let text): return text
        }
    }
}

// MARK: - 共用：体验按钮、条款，和开始之后的那一屏

private struct ProIntroActions: View {
    enum Secondary {
        /// 新用户版：按钮下面一行「以后再说」
        case later(() -> Void)
        /// 老用户版：按钮下面可以直接买断（「以后再说」在左上角）
        case purchase
    }

    let prices: ProPrices
    let secondary: Secondary

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
            switch secondary {
            case .later(let action):
                Button(action: action) { secondaryLabel("以后再说", color: .inkMuted) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pro-intro-later")
            case .purchase:
                Button { Task { await buy() } } label: {
                    secondaryLabel("永久解锁 Pro · \(prices.special)", color: .skyDeep, weight: .medium)
                }
                .buttonStyle(.plain)
                .disabled(store.isWorking)
                .accessibilityIdentifier("pro-intro-purchase")
            }
            ProTrialTerms(prices: prices)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
        }
    }

    private func secondaryLabel(_ text: String, color: Color, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.system(.body, design: .rounded).weight(weight))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
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
