// Pro 购买页：一张免费和 Pro 的对照表，底部固定价格、购买、恢复购买。从设置和各个 Pro 功能的锁定页进入。
// 对照表的两列只放勾，字都留给左边的名字和说明，读起来不挤。

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

    /// 对照表右边两列的宽度：只放勾，窄一点就够
    private let freeWidth: CGFloat = 44
    private let proWidth: CGFloat = 56

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KickerLabel(text: "FreeGrid Pro", color: .skyDeep)
            Text(store.isUnlocked ? "Pro 已解锁" : "把自由，算得更完整")
                .font(.system(size: 30, weight: .light, design: .rounded))
                .foregroundStyle(Color.ink)
            Text(store.isUnlocked ? "谢谢你支持 FreeGrid，下面这些现在都是你的。" : "一次买断，永久拥有。账本照旧只在你的手机上。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(store.isUnlocked ? "pro-unlocked" : "pro-header")
    }

    // MARK: - 对照表

    /// 先列 Pro 专属，再列免费就有的。右边一列整列用一道细线框起来，是这一页唯一有颜色的块
    private var comparisonTable: some View {
        VStack(spacing: 0) {
            columnHeader
            groupLabel("Pro 专属")
            ForEach(ProFeatures.proRows) { row in
                tableRow(row)
            }
            groupLabel("免费就有")
            ForEach(ProFeatures.freeRows) { row in
                tableRow(row)
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

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            KickerLabel(text: "免费").frame(width: freeWidth)
            KickerLabel(text: "Pro", color: .skyDeep).frame(width: proWidth)
        }
        .frame(height: 44)
    }

    /// 组名写在左边，跟行之间隔一道细线；细线只画到 Pro 列前面
    private func groupLabel(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .padding(.leading, Spacing.sm)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.sm)
            Hairline().padding(.trailing, proWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableRow(_ row: ProFeatures.Row) -> some View {
        let highlighted = topic.map { row.topics.contains($0) } ?? false
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text(row.detail)
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Spacing.sm)
                .padding(.trailing, Spacing.xs)
                .padding(.vertical, 12)
                mark(row.inFree, pro: false).frame(width: freeWidth)
                mark(true, pro: true).frame(width: proWidth)
            }
            .background {
                if highlighted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.skyFaint)
                }
            }
            Hairline().padding(.trailing, proWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title)，\(row.detail)\(row.inFree ? "免费版和 Pro 都有" : "Pro 专属")")
    }

    @ViewBuilder
    private func mark(_ has: Bool, pro: Bool) -> some View {
        if has {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: pro ? .regular : .light))
                .foregroundStyle(pro ? Color.skyDeep : Color.inkFaint)
        } else {
            Text("—")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.inkGhost)
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
