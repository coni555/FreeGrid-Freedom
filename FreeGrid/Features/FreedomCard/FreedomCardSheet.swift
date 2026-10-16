// 自由卡：设置页那一行、首页的升级提示、长按首页大数字，都打开这一页。
// 上面是卡（晃手机有一道光跟着走），下面是材质等级、持卡人昵称、显不显示金额，最后是分享（Pro）。

import SwiftUI
import SwiftData
#if canImport(CoreMotion) && os(iOS)
import CoreMotion
#endif

struct FreedomCardSheet: View {
    @Query private var expenses: [Expense]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]
    @Query private var assetItems: [AssetItem]
    @Query private var loans: [Loan]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(FreedomSettings.countsAssetsKey, store: AppPreferences.store) private var countsAssets = true
    @AppStorage("freedomCardHolder", store: AppPreferences.store) private var holder = ""
    @AppStorage("freedomCardShowsMoney", store: AppPreferences.store) private var showsMoney = false
    @AppStorage(FreedomCardPrompt.highestSeenKey, store: AppPreferences.store) private var highestSeen = -1

    @State private var tilt = CardTilt()
    @State private var cardImage: Image?
    @State private var posterImage: Image?
    @State private var showingPro = false
    @FocusState private var holderFocused: Bool

    private var data: FreedomCardData {
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                                         assetItems: assetItems, loans: loans, countsAssets: countsAssets)
        let summary = FreedomChecklist.evaluate(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                                                assetItems: assetItems, loans: loans, countsAssets: countsAssets)
        return FreedomCardData(snapshot: snapshot, summary: summary)
    }

    var body: some View {
        let data = data
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    FreedomCardView(data: data, holder: holder, showsMoney: showsMoney, tilt: tilt.value)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: 22, y: 14)
                        .padding(.top, Spacing.sm)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in tilt.drag(value.translation) }
                            .onEnded { _ in tilt.release() })

                    ladder(current: data.tier)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "持卡人")
                        UnderlinedField(isFocused: holderFocused) {
                            TextField("你的昵称", text: Binding(get: { holder }, set: { holder = String($0.prefix(12)) }))
                                .font(.system(.title3, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .focused($holderFocused)
                                .submitLabel(.done)
                                .accessibilityIdentifier("freedom-card-holder")
                        }
                    }

                    Toggle(isOn: $showsMoney.animation(.snappy(duration: 0.3))) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("显示净值")
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.ink)
                            Text("默认只写天数和比例，不露金额，可以放心发。")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Color.inkMuted)
                        }
                    }
                    .tint(Color.skyDeep)
                    .accessibilityIdentifier("freedom-card-shows-money")

                    shareButtons
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .background(Color.paper)
            .navigationTitle("自由卡")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Color.skyDeep)
                        .fontWeight(.medium)
                }
            }
            .sheet(isPresented: $showingPro) { ProPaywallView() }
            // 看过这张卡：首页那行升级提示到这个等级为止
            .onAppear {
                highestSeen = max(highestSeen, data.tier.rawValue)
                tilt.start()
            }
            .onDisappear { tilt.stop() }
            // 卡面内容一变就重新画两张图，点分享时直接用
            .task(id: RenderKey(data: data, holder: holder, showsMoney: showsMoney, dark: colorScheme == .dark)) {
                render(data)
            }
        }
    }

    // MARK: - 等级

    /// 五种材质排成一行，当前这张亮着；下面一句说什么时候升级
    private func ladder(current: FreedomCardTier) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                ForEach(FreedomCardTier.allCases, id: \.self) { tier in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(FreedomCardMaterial.of(tier).background)
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(tier == current ? Color.skyDeep : Color.hairline, lineWidth: tier == current ? 1.5 : 1))
                            .aspectRatio(85.6 / 54, contentMode: .fit)
                        Text(tier.threshold)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(tier == current ? Color.ink : Color.inkFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(tier == current ? 1 : 0.55)
                }
            }
            Text("卡的材质跟着自由天数变：30 天银卡，180 天香槟金，1 年黑卡；被动收入盖住全部开销是 ∞ 卡。")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("现在是\(current.name)")
    }

    // MARK: - 分享

    @ViewBuilder
    private var shareButtons: some View {
        if ProFeatures.canShareFreedomCard {
            HStack(spacing: Spacing.md) {
                shareLink(image: cardImage, title: "分享卡片", icon: "creditcard", identifier: "share-freedom-card")
                shareLink(image: posterImage, title: "分享海报", icon: "rectangle.portrait", identifier: "share-freedom-poster")
            }
        } else {
            VaultButton(title: "分享卡片和海报 · Pro", icon: "square.and.arrow.up") { showingPro = true }
                .accessibilityIdentifier("share-freedom-card-pro")
        }
    }

    @ViewBuilder
    private func shareLink(image: Image?, title: String, icon: String, identifier: String) -> some View {
        if let image {
            ShareLink(item: image, preview: SharePreview("FreeGrid 自由卡", image: image)) {
                Label(title, systemImage: icon)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.skyDeep)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .accessibilityIdentifier(identifier)
        } else {
            ProgressView().frame(maxWidth: .infinity).frame(height: 48)
        }
    }

    private struct RenderKey: Equatable {
        let data: FreedomCardData
        let holder: String
        let showsMoney: Bool
        let dark: Bool
    }

    /// 导出的图：卡片 1080 宽（带一圈留白），海报 1080 × 1920。跟着当前深浅色
    @MainActor
    private func render(_ data: FreedomCardData) {
        let scheme = colorScheme
        let card = FreedomCardView(data: data, holder: holder, showsMoney: showsMoney)
            .padding(24)
            .frame(width: 360)
            .background(Color.paper)
            .environment(\.colorScheme, scheme)
        let poster = FreedomPosterView(data: data, holder: holder, showsMoney: showsMoney)
            .frame(width: 360)
            .environment(\.colorScheme, scheme)
        cardImage = Self.image(of: card)
        posterImage = Self.image(of: poster)
    }

    @MainActor
    private static func image<V: View>(of view: V) -> Image? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let cgImage = renderer.cgImage else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}

// MARK: - 晃手机

/// 卡的倾斜量（-1…1）。iPhone 上跟着手机的姿态走；也可以用手指按住拖
@Observable
final class CardTilt {
    private(set) var value: CGSize = .zero
    private var dragging = false
    #if canImport(CoreMotion) && os(iOS)
    private let motion = CMMotionManager()
    #endif

    func start() {
        #if canImport(CoreMotion) && os(iOS)
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let attitude = data?.attitude, !self.dragging else { return }
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.8)) {
                self.value = CGSize(width: max(-1, min(1, attitude.roll / 0.6)),
                                    height: max(-1, min(1, (attitude.pitch - 0.7) / 0.6)))
            }
        }
        #endif
    }

    func stop() {
        #if canImport(CoreMotion) && os(iOS)
        motion.stopDeviceMotionUpdates()
        #endif
    }

    func drag(_ translation: CGSize) {
        dragging = true
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
            value = CGSize(width: max(-1, min(1, translation.width / 160)), height: max(-1, min(1, translation.height / 120)))
        }
    }

    func release() {
        dragging = false
        withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { value = .zero }
    }
}
