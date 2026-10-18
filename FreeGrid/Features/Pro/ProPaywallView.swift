// Pro 购买页：整屏弹出，居中的标题，一张铺满宽度的免费 / Pro 对照卡，底部固定试用、价格、购买、恢复购买。
// 试用和专属价什么时候给、给到哪天，规则在 ProOffer。
// 从设置和各个 Pro 功能的锁定页进入，都用 `.proPaywall(isPresented:topic:)`。

import StoreKit
import SwiftUI

struct ProPaywallView: View {
    /// 从哪个功能进来的，对照表上标出那一行；从设置进来时为空
    var topic: ProFeatures.Topic?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var store = ProStore.shared
    /// 购买或恢复之后给用户的一句话结果
    @State private var notice: String?
    /// 点了哪一行的 ⓘ
    @State private var infoRow: ProFeatures.Row?

    private let privacyURL = URL(string: "https://github.com/coni555/FreeGrid-Freedom/blob/main/PRIVACY.md")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// 对照卡右边两列的宽度：放得下五个字
    private let freeWidth: CGFloat = 80
    private let proWidth: CGFloat = 96

    var body: some View {
        NavigationStack {
            ScrollView {
                // 间距收紧：底部购买栏有三行说明，对照表要在大多数 iPhone 上一屏露全
                VStack(spacing: Spacing.lg) {
                    header
                    comparisonTable
                    #if DEBUG
                    previewCard
                    #endif
                }
                .padding(.horizontal)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .inlineNavTitle()
            .toolbar {
                // 关闭按钮不要系统那块玻璃底：触控区域不变，只剩一行淡字
                if #available(iOS 26.0, macOS 26.0, *) {
                    ToolbarItem(placement: .cancellationAction) { closeButton }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .cancellationAction) { closeButton }
                }
            }
            .task { await store.loadProducts() }
            .sheet(item: $infoRow) { row in
                if let info = row.info { InfoSheet(info: info) }
            }
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Text("关闭")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pro-close")
    }

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            brandLockup
                .padding(.bottom, Spacing.xs)
            // 标题和副标题是用户 2026-10-17 定的原话
            Text(store.ownsPro ? "关于自由，故事继续" : "让自由，有迹可循")
                .font(.system(size: 30, weight: .light, design: .rounded))
                .foregroundStyle(Color.ink)
            if store.ownsPro {
                VStack(spacing: Spacing.md) {
                    Text("感谢你对 FreeGrid 的支持。")
                    Text("愿你始终拥有选择的底气。")
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
            } else {
                Text("记录金钱的流向，看见时间的价值。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(store.ownsPro ? "pro-unlocked" : "pro-header")
    }

    /// 品牌一行：FreeGrid 加一个描边的 PRO 胶囊，靠字本身立住，不加图标。
    /// 超细大字放英文字标会显得单薄，所以名字用半粗
    private var brandLockup: some View {
        HStack(spacing: 10) {
            Text("FreeGrid")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ink)
            Text("PRO")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color.skyDeep)
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: 24)
                .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FreeGrid Pro")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 对照卡

    /// 一张卡铺满宽度：左边功能名，右边免费、Pro 两列。Pro 列垫一块淡蓝，不画高高的细框
    private var comparisonTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                KickerLabel(text: "免费").frame(width: freeWidth)
                KickerLabel(text: "Pro", color: .skyDeep).frame(width: proWidth)
            }
            .frame(height: 40)
            ForEach(ProFeatures.comparison) { row in
                rowDivider
                tableRow(row)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .background(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.skyDeep.opacity(0.08))
                .frame(width: proWidth)
                .padding(.vertical, Spacing.sm)
                .padding(.trailing, Spacing.md)
        }
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.mist))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro-comparison")
    }

    /// 行间细线只画到 Pro 列前面，淡蓝那一块里干干净净
    private var rowDivider: some View {
        Hairline().padding(.trailing, proWidth)
    }

    private func tableRow(_ row: ProFeatures.Row) -> some View {
        let highlighted = topic.map { row.topics.contains($0) } ?? false
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                // 从哪个功能点进来，那一行前面一道蓝竖线（和设置页 Pro 卡同一个记号），不把整行涂蓝
                if highlighted {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color.skyDeep).frame(width: 3, height: 14)
                        .accessibilityHidden(true)
                }
                Text(row.title)
                    .font(.system(size: 15, weight: highlighted ? .medium : .regular, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityLabel("\(row.title)，免费：\(spoken(row.free))，Pro：\(spoken(row.pro))")
                if row.info != nil {
                    // 低调的说明入口：和小字一个颜色，点击区域比图标大一圈
                    Button { infoRow = row } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(Color.inkFaint)
                            .frame(width: 24, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityLabel("\(row.title)说明")
                    .accessibilityIdentifier("pro-info-\(row.title)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Spacing.xs)
            cell(row.free, pro: false).frame(width: freeWidth).accessibilityHidden(true)
            cell(row.pro, pro: true).frame(width: proWidth).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func cell(_ cell: ProFeatures.Cell, pro: Bool) -> some View {
        switch cell {
        case .yes:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: pro ? .regular : .light))
                .foregroundStyle(pro ? Color.skyDeep : Color.inkFaint)
        case .no:
            Text("—")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.inkGhost)
        case .text(let text):
            Text(text)
                .font(.system(size: 14, weight: pro ? .medium : .regular, design: .rounded))
                .foregroundStyle(pro ? Color.skyDeep : Color.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func spoken(_ cell: ProFeatures.Cell) -> String {
        switch cell {
        case .yes: return "有"
        case .no: return "没有"
        case .text(let text): return text
        }
    }

    // MARK: - 底部：试用、价格和购买，滚到哪都在

    /// 底栏尽量矮：按钮矮一档、各行间距 6，让对照表在一屏里露全（用户 2026-10-18 真机上嫌高）
    private var bottomBar: some View {
        VStack(spacing: 6) {
            if let notice {
                Text(notice)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pro-notice")
            }
            if store.ownsPro {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color.mossGreen)
                    Text("Pro 已解锁")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
            } else if let prices {
                offerStatus
                if showsTrialButton {
                    VaultButton(title: "免费体验 \(ProOffer.trialDays) 天", icon: "sparkles", verticalPadding: 11) {
                        Task { await startTrial() }
                    }
                    .disabled(store.isWorking)
                    .accessibilityIdentifier("pro-start-trial")
                    Button { Task { await buy() } } label: {
                        Text("永久解锁 Pro · \(prices.special)")
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.skyDeep)
                            .frame(minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isWorking)
                    .accessibilityIdentifier("pro-purchase")
                } else {
                    VaultButton(title: "永久解锁 Pro · \(store.hasSpecialPrice ? prices.special : prices.regular)", icon: "lock.open",
                                verticalPadding: 11) {
                        Task { await buy() }
                    }
                    .disabled(store.isWorking)
                    .opacity(store.isWorking ? 0.4 : 1)
                    .accessibilityIdentifier("pro-purchase")
                }
                priceNote(prices)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("pro-price-note")
            } else if case .unavailable = store.productState {
                offerStatus
                Text("暂时读不到价格，可能是网络不通。已经买过的话，点「恢复购买」。")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VaultButton(title: "重试", icon: "arrow.clockwise", style: .secondary) {
                    Task { await store.loadProducts() }
                }
                .accessibilityIdentifier("pro-retry")
            } else {
                ProgressView()
                    .frame(minHeight: 52)
            }
            HStack(spacing: Spacing.lg) {
                if !store.ownsPro {
                    Button { Task { await restore() } } label: { footerLabel("恢复购买") }
                        .buttonStyle(.plain)
                        .disabled(store.isWorking)
                        .accessibilityIdentifier("pro-restore")
                }
                Button { openURL(privacyURL) } label: { footerLabel("隐私政策") }
                    .buttonStyle(.plain)
                Button { openURL(termsURL) } label: { footerLabel("使用条款") }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xs)
        .background(Color.paper)
        .overlay(alignment: .top) { Hairline() }
    }

    /// 试用开始后，按钮上方一行小字：试用还剩几天，或者试用已经结束。
    /// 不用等宽大写小标签：那种字距是给英文的，中文会被拉散
    @ViewBuilder
    private var offerStatus: some View {
        if let trialEnd = store.offer.trialEndsAt {
            Text(store.isTrialActive
                 ? "体验中 · 还剩 \(ProOffer.daysLeft(until: trialEnd, from: store.now)) 天"
                 : "体验已结束")
                .font(.system(.footnote, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(store.isTrialActive ? Color.skyDeep : Color.inkMuted)
                .accessibilityIdentifier("pro-trial-status")
        }
    }

    /// 按钮下面的小字。开始体验之前，审核指南 3.1.1 要求写清：体验多久、到期少了什么、之后要付多少。
    /// 开始体验前的三行是用户 2026-10-18 定的原话，只调换行和字号：前两句并成一行，价格那句一行；字放大或美元写法放不下时略缩小，不折行
    @ViewBuilder
    private func priceNote(_ prices: Prices) -> some View {
        if showsTrialButton {
            VStack(spacing: 1) {
                Text("体验期满自动恢复免费版，无自动扣费。所有记账数据都会完整保留。")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("开启体验后 \(ProOffer.specialPriceDays) 天内，享 \(prices.special) 买断优惠价，之后恢复 \(prices.regular)。")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else if let end = store.offer.specialPriceEndsAt, store.hasSpecialPrice {
            Text("买断优惠价还剩 \(ProOffer.daysLeft(until: end, from: store.now)) 天，之后恢复 \(prices.regular) · 不会自动续费")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text("一次购买 · 永久使用 · 不会自动续费")
        }
    }

    private func footerLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.inkFaint)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
    }

    /// 两档买断价，用 App Store 返回的本地化文字，不在代码里写死
    private struct Prices {
        var special: String
        var regular: String
        var hasTrial: Bool
    }

    private var prices: Prices? {
        if case .loaded(let products) = store.productState {
            return Prices(special: products.special.displayPrice, regular: products.regular.displayPrice,
                          hasTrial: products.trial != nil)
        }
        #if DEBUG
        // 模拟器里用 simctl 启动读不到商品；拍图时用 -proSamplePrices 看有价格的样子（按钮点了会提示读不到商品）
        if ProcessInfo.processInfo.arguments.contains("-proSamplePrices") {
            return Prices(special: "¥19.90", regular: "¥29.90", hasTrial: true)
        }
        #endif
        return nil
    }

    /// 没试用过的人先给试用，买断退到第二个按钮
    private var showsTrialButton: Bool {
        !store.offer.hasStartedTrial && (prices?.hasTrial ?? false)
    }

    #if DEBUG
    /// 模拟器里用 simctl 启动时读不到商品，靠这个开关看解锁后的样子
    private var previewCard: some View {
        VaultCard {
            Toggle(isOn: $store.isPreviewing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("调试：直接预览 Pro")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text("只在开发构建里出现，不经过购买。")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                }
            }
            .tint(Color.skyDeep)
            .accessibilityIdentifier("pro-preview-toggle")
        }
    }
    #endif

    private func startTrial() async {
        switch await store.startTrial() {
        case .purchased: notice = nil
        case .cancelled: notice = nil
        case .pending: notice = "体验在等待批准，批准后会自动开始。"
        case .failed(let message): notice = message
        }
    }

    private func buy() async {
        switch await store.purchase() {
        case .purchased: notice = nil
        case .cancelled: notice = nil
        case .pending: notice = "这笔购买在等待批准，批准后 Pro 会自动解锁。"
        case .failed(let message): notice = message
        }
    }

    private func restore() async {
        switch await store.restore() {
        case .restored: notice = nil
        case .cancelled: notice = nil
        case .nothingToRestore: notice = "这个 Apple 账户下没有找到 Pro 的购买记录。"
        case .failed(let message): notice = message
        }
    }
}

/// 对照表某一行的说明：标题一句，正文两三段，底部一个「知道了」。iOS 上弹窗高度贴着内容，不留一大块空白
private struct InfoSheet: View {
    let info: ProFeatures.Info
    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            KickerLabel(text: "FreeGrid Pro", color: .skyDeep)
            Text(info.title)
                .font(.system(size: 24, weight: .light, design: .rounded))
                .foregroundStyle(Color.ink)
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(info.body, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("知道了") { dismiss() }
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Color.skyDeep)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.sm)
                .accessibilityIdentifier("pro-info-close")
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
        .frame(width: 420, height: 360)
        #endif
    }
}

extension View {
    /// 打开购买页：iOS 上整屏弹出（显得开阔，像大多数 App 的升级页），macOS 没有整屏弹出，用普通的 sheet
    func proPaywall(isPresented: Binding<Bool>, topic: ProFeatures.Topic? = nil) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) { ProPaywallView(topic: topic) }
        #else
        sheet(isPresented: isPresented) { ProPaywallView(topic: topic) }
        #endif
    }
}
