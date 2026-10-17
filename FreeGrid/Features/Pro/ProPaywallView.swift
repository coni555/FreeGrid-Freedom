// Pro 购买页：一张免费和 Pro 的对照表，加上价格、购买、恢复购买。从设置和各个 Pro 功能的锁定页进入。

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    comparisonTable
                    if !store.isUnlocked {
                        purchaseSection
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
            Text(store.isUnlocked ? "Pro 已解锁" : "一次买断，永久使用")
                .font(.system(.title2, design: .rounded))
                .foregroundStyle(Color.ink)
            Text(store.isUnlocked ? "谢谢你支持 FreeGrid。右边一列现在都是你的。" : "免费的功能一直免费，Pro 只加新的。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(store.isUnlocked ? "pro-unlocked" : "pro-header")
    }

    // MARK: - 对照表

    private let freeWidth: CGFloat = 76
    private let proWidth: CGFloat = 92

    /// 每行一项功能，左列免费、右列 Pro。右列整列用一道细线框起来，是这一页唯一有颜色的东西
    private var comparisonTable: some View {
        VStack(spacing: 0) {
            tableRow(height: 44, highlighted: false) {
                Color.clear
            } free: {
                KickerLabel(text: "免费")
            } pro: {
                KickerLabel(text: "Pro", color: .skyDeep)
            }
            ForEach(ProFeatures.comparison) { row in
                rowDivider
                tableRow(height: 50, highlighted: topic != nil && row.topic == topic) {
                    Text(row.title)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } free: {
                    cell(row.free, pro: false)
                } pro: {
                    cell(row.pro, pro: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.title)，免费：\(spoken(row.free))，Pro：\(spoken(row.pro))")
            }
            rowDivider
            tableRow(height: 68, highlighted: false) {
                Text("价格")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
            } free: {
                Text("免费")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
            } pro: {
                priceCell
            }
        }
        // 底色垫在下面，细线框压在最上面：标出来的那一行不会把框盖断
        .background(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.skyDeep.opacity(0.05))
                .frame(width: proWidth)
        }
        .overlay(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.skyDeep, lineWidth: 1)
                .frame(width: proWidth)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro-comparison")
    }

    private func tableRow<Title: View, Free: View, Pro: View>(height: CGFloat, highlighted: Bool,
                                                              @ViewBuilder title: () -> Title,
                                                              @ViewBuilder free: () -> Free,
                                                              @ViewBuilder pro: () -> Pro) -> some View {
        HStack(spacing: 0) {
            title()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Spacing.sm)
            free().frame(width: freeWidth)
            pro().frame(width: proWidth)
        }
        .frame(minHeight: height)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.skyFaint)
            }
        }
    }

    /// 行间细线只画到 Pro 列前面，Pro 列里干干净净，像一张立在表上的卡
    private var rowDivider: some View {
        Hairline().padding(.trailing, proWidth)
    }

    @ViewBuilder
    private func cell(_ cell: ProFeatures.Cell, pro: Bool) -> some View {
        switch cell {
        case .yes:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(pro ? Color.skyDeep : Color.inkFaint)
        case .no:
            Text("—")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.inkGhost)
        case .text(let text):
            Text(text)
                .font(.system(size: 14, design: .rounded))
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

    /// Pro 列最底下一格：价格；已解锁写「已解锁」。价格用 App Store 返回的本地化文字，不在代码里写死
    @ViewBuilder
    private var priceCell: some View {
        if store.isUnlocked {
            Text("已解锁")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color.skyDeep)
        } else {
            switch store.productState {
            case .loading:
                ProgressView().controlSize(.small)
            case .loaded(let product):
                Text(product.displayPrice)
                    .font(.system(size: 20, weight: .light).monospacedDigit())
                    .foregroundStyle(Color.skyDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
                    .accessibilityIdentifier("pro-price")
            case .unavailable:
                Text("—")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color.inkGhost)
            }
        }
    }

    // MARK: - 购买

    private var purchaseSection: some View {
        VStack(spacing: Spacing.md) {
            if case .unavailable = store.productState {
                VStack(alignment: .leading, spacing: 3) {
                    Text("暂时读不到价格")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text("可能是网络不通。已经买过的话，点下面的「恢复购买」。")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.sm)
                VaultButton(title: "重试", icon: "arrow.clockwise", style: .secondary) {
                    Task { await store.loadProduct() }
                }
                .accessibilityIdentifier("pro-retry")
            } else {
                VaultButton(title: "解锁 Pro", icon: "lock.open") {
                    Task { await buy() }
                }
                .disabled(!canBuy)
                .opacity(canBuy ? 1 : 0.4)
                .accessibilityIdentifier("pro-purchase")
                Text("一次购买，没有订阅，不会自动续费。")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
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
        .padding(.top, Spacing.sm)
    }

    private var canBuy: Bool {
        guard case .loaded = store.productState else { return false }
        return !store.isWorking
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
