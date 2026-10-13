// Pro 购买页：列出权益和价格，购买、恢复购买。从设置和各个 Pro 功能的锁定页进入。

import StoreKit
import SwiftUI

struct ProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var store = ProStore.shared
    /// 购买或恢复之后给用户的一句话结果
    @State private var notice: String?

    private let privacyURL = URL(string: "https://github.com/coni555/FreeGrid-Freedom/blob/main/PRIVACY.md")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    benefitsCard
                    if store.isUnlocked {
                        unlockedCard
                    } else {
                        purchaseCard
                    }
                    if let notice {
                        Text(notice)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Spacing.sm)
                            .accessibilityIdentifier("pro-notice")
                    }
                    footer
                    #if DEBUG
                    previewCard
                    #endif
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("FreeGrid Pro")
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KickerLabel(text: "FreeGrid Pro")
            Text("一次买断，永久使用")
                .font(.system(.title2, design: .rounded))
                .foregroundStyle(Color.ink)
            Text("记账、资产、自由天数、模拟、历史和备份一直免费。Pro 只包含新增的功能。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.sm)
    }

    private var benefitsCard: some View {
        VaultCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(ProFeatures.benefits.enumerated()), id: \.element.id) { index, benefit in
                    if index > 0 { Hairline().padding(.leading, Spacing.lg + 26 + Spacing.md) }
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Image(systemName: benefit.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.skyDeep)
                            .frame(width: 26, alignment: .center)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(benefit.title)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.ink)
                            Text(benefit.detail)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Color.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private var purchaseCard: some View {
        VaultCard(emphasis: .high) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "永久版")
                switch store.productState {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 56)
                case .loaded(let product):
                    // 价格用 App Store 返回的本地化文字，不在代码里写死
                    Text(product.displayPrice)
                        .font(.system(size: 44, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .accessibilityIdentifier("pro-price")
                    Text("一次购买，没有订阅，不会自动续费。")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                    VaultButton(title: "解锁 Pro", icon: "lock.open") {
                        Task { await buy() }
                    }
                    .disabled(store.isWorking)
                    .opacity(store.isWorking ? 0.4 : 1)
                    .accessibilityIdentifier("pro-purchase")
                case .unavailable:
                    Text("暂时读不到价格")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text("可能是网络不通。已经买过的话，点下面的「恢复购买」。")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    VaultButton(title: "重试", icon: "arrow.clockwise", style: .secondary) {
                        Task { await store.loadProduct() }
                    }
                    .accessibilityIdentifier("pro-retry")
                }
                Button {
                    Task { await restore() }
                } label: {
                    Text("恢复购买")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.isWorking)
                .accessibilityIdentifier("pro-restore")
            }
        }
    }

    private var unlockedCard: some View {
        VaultCard(emphasis: .high) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.mossGreen)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pro 已解锁")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text("谢谢你支持 FreeGrid。")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("pro-unlocked")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("购买和恢复通过 Apple 完成。账本仍然只保存在这台设备上。")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.lg) {
                linkButton("隐私政策", url: privacyURL)
                linkButton("使用条款", url: termsURL)
            }
        }
        .padding(.horizontal, Spacing.sm)
    }

    private func linkButton(_ title: String, url: URL) -> some View {
        Button { openURL(url) } label: {
            Text(title)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.skyDeep)
                .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
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
