// Pro 购买页：整屏弹出，居中的标题，一张铺满宽度的免费 / Pro 对照卡，底部固定价格、购买、恢复购买。
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

    private let privacyURL = URL(string: "https://github.com/coni555/FreeGrid-Freedom/blob/main/PRIVACY.md")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// 对照卡右边两列的宽度：放得下五个字
    private let freeWidth: CGFloat = 80
    private let proWidth: CGFloat = 96

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("pro-close")
                }
            }
            .task { await store.loadProduct() }
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            KickerLabel(text: "FreeGrid Pro", color: .skyDeep)
            Text(store.isUnlocked ? "Pro 已解锁" : "让自由天数，更接近真实")
                .font(.system(size: 30, weight: .light, design: .rounded))
                .foregroundStyle(Color.ink)
            Text(store.isUnlocked ? "谢谢你支持 FreeGrid，右边一列现在都是你的。" : "把每月还款、各个账户和难变现的资产都算清楚，看见你真正能自由的天数。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(store.isUnlocked ? "pro-unlocked" : "pro-header")
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
            .frame(height: 48)
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
            Text(row.title)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Spacing.xs)
            cell(row.free, pro: false).frame(width: freeWidth)
            cell(row.pro, pro: true).frame(width: proWidth)
        }
        .frame(minHeight: 52)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.skyFaint)
                    .padding(.horizontal, -Spacing.xs)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title)，免费：\(spoken(row.free))，Pro：\(spoken(row.pro))")
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

    // MARK: - 底部：价格和购买，滚到哪都在

    private var bottomBar: some View {
        VStack(spacing: Spacing.sm) {
            if let notice {
                Text(notice)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pro-notice")
            }
            if store.isUnlocked {
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
            } else if case .unavailable = store.productState {
                Text("暂时读不到价格，可能是网络不通。已经买过的话，点「恢复购买」。")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VaultButton(title: "重试", icon: "arrow.clockwise", style: .secondary) {
                    Task { await store.loadProduct() }
                }
                .accessibilityIdentifier("pro-retry")
            } else {
                VaultButton(title: purchaseTitle, icon: "lock.open") {
                    Task { await buy() }
                }
                .disabled(!canBuy)
                .opacity(canBuy ? 1 : 0.4)
                .accessibilityIdentifier("pro-purchase")
                Text("一次购买 · 没有订阅 · 不会自动续费")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
            }
            HStack(spacing: Spacing.lg) {
                if !store.isUnlocked {
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
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .background(Color.paper)
        .overlay(alignment: .top) { Hairline() }
    }

    private func footerLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.inkFaint)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
    }

    /// 「永久解锁 · ¥18」：价格用 App Store 返回的本地化文字，不在代码里写死
    private var purchaseTitle: String {
        if case .loaded(let product) = store.productState {
            return "永久解锁 · \(product.displayPrice)"
        }
        return "永久解锁"
    }

    private var canBuy: Bool {
        guard case .loaded = store.productState else { return false }
        return !store.isWorking
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
