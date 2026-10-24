// Pro 永久买断：向 App Store 读商品、开始试用、发起购买、恢复购买，并把结果记在本机。
// 账本不经过这里；解锁状态和试用开始时间只是本机偏好，不进备份。
//
// 三个商品都是非消耗型，要和 App Store Connect 里创建的一致：
// - 7 天试用：¥0。审核指南 3.1.1 规定买断类 App 的试用这样做，名字按「XX-day Trial」
// - 买断专属价 ¥19.90：开始试用起 14 天内（以及还没试用时）给这个
// - 买断原价 ¥29.90：试用开始满 14 天后给这个
// 两个买断商品买哪个都解锁 Pro；什么时候给哪个看 ProOffer。

import Foundation
import Observation
import StoreKit

@Observable
final class ProStore {
    static let shared = ProStore(defaults: AppPreferences.store)

    static let trialProductID = "cn.conilab.FreeGrid.pro.trial7"
    static let specialProductID = "cn.conilab.FreeGrid.pro.lifetime.special"
    /// 原价买断。沿用最早的商品 ID
    static let productID = "cn.conilab.FreeGrid.pro.lifetime"
    static let lifetimeProductIDs: Set<String> = [specialProductID, productID]

    static let unlockedKey = "proUnlocked"
    static let trialStartedKey = "proTrialStartedAt"
    static let previewKey = "proPreview"
    /// 上次看到时 Pro 能不能用。从能用变成不能用的那次，首页弹「回到免费版」
    static let wasUnlockedKey = "proWasUnlocked"
    /// 上次能用时是不是买断的。失效后据此写「Pro 已失效」（退款）还是「Pro 体验已结束」
    static let wasPurchasedKey = "proWasPurchased"

    /// 从 App Store 读到的商品。试用商品读不到时照样能买，只是不给试用
    struct Products {
        var trial: Product?
        var special: Product
        var regular: Product
    }

    enum ProductState {
        case loading
        case loaded(Products)
        /// 读不到商品（没网、商品还没上架）。不代表用户没买过
        case unavailable
    }

    enum PurchaseOutcome: Equatable {
        case purchased
        case cancelled
        /// 等待家长批准等情况，批准后由交易更新自动解锁
        case pending
        case failed(String)
    }

    enum RestoreOutcome: Equatable {
        case restored
        case nothingToRestore
        case cancelled
        case failed(String)
    }

    /// App Store 确认过的买断。上一次的结果存在本机，离线启动也能直接用
    private(set) var hasPurchased: Bool
    /// 试用从哪一刻开始，来自试用那笔交易；同样存在本机
    private(set) var offer: ProOffer
    private(set) var productState: ProductState = .loading
    /// 购买或恢复进行中，界面据此停用按钮
    private(set) var isWorking = false
    /// 界面用来判断试用和专属价是否到期的「现在」。到点时自动往前拨，界面跟着变
    private(set) var now: Date

    #if DEBUG
    /// 仅调试：不经过购买直接看 Pro 功能。Release 里没有这个开关
    var isPreviewing: Bool {
        didSet { defaults.set(isPreviewing, forKey: Self.previewKey) }
    }
    #endif

    var isTrialActive: Bool { !hasPurchased && offer.isTrialActive(at: now) }

    /// Pro 功能能不能用：买过、预览，或者在试用期内
    var isUnlocked: Bool { ownsPro || isTrialActive }

    /// Pro 刚从能用变成不能用（体验到期、退款）时返回 true，同一次变化只返回一次。
    /// 第一次装 2.0 的老用户记的是「不能用」，不会误报
    /// 启动后要先和 App Store 核对过一次：在别的设备上买断、这台还没同步时，体验到期那一刻不会误弹
    func takeLapse() -> Bool {
        guard hasCheckedEntitlements else { return false }
        let was = defaults.bool(forKey: Self.wasUnlockedKey)
        let unlocked = isUnlocked
        if was != unlocked { defaults.set(unlocked, forKey: Self.wasUnlockedKey) }
        if unlocked { defaults.set(ownsPro, forKey: Self.wasPurchasedKey) }
        return was && !unlocked
    }

    /// 失效是因为买断被撤销（退款），不是体验到期
    var lapsedFromPurchase: Bool { !isUnlocked && defaults.bool(forKey: Self.wasPurchasedKey) }

    /// 这次启动后和 App Store 核对过购买记录没有。测试里直接设
    var hasCheckedEntitlements = false

    /// 买断现在用专属价
    var hasSpecialPrice: Bool { offer.hasSpecialPrice(at: now) }

    /// 真的拥有 Pro（买过；调试时也包括直接预览）。试用中不算：界面要接着提供购买
    var ownsPro: Bool {
        #if DEBUG
        return hasPurchased || isPreviewing
        #else
        return hasPurchased
        #endif
    }

    private let defaults: UserDefaults
    private let clock: () -> Date
    private var updatesTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = clock
        now = clock()
        hasPurchased = defaults.bool(forKey: Self.unlockedKey)
        let started = defaults.object(forKey: Self.trialStartedKey) as? Date
        offer = ProOffer(trialStartedAt: started)
        #if DEBUG
        isPreviewing = defaults.bool(forKey: Self.previewKey)
        // 拍图和 UI 测试用：-proTrialDaysAgo 3 表示 3 天前开始的试用
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-proTrialDaysAgo"), index + 1 < arguments.count,
           let days = Double(arguments[index + 1]) {
            offer = ProOffer(trialStartedAt: now.addingTimeInterval(-days * 24 * 60 * 60))
        }
        #endif
    }

    /// App 启动时调用一次：监听之后到达的交易（退款、家长批准、别的设备上的购买），
    /// 再核对一遍当前权益并读商品价格。
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        scheduleTick()
        Task {
            await refreshEntitlement()
            await loadProducts()
        }
    }

    /// 以 App Store 的当前权益为准重新计算。退款后的交易带撤销日期，不算数。
    func refreshEntitlement() async {
        tick()
        #if DEBUG
        // UI 测试和拍图（-UseInMemoryStore）只认 -proPreview：模拟器里在 Xcode 测过的购买还留着，会让「没买」的样子出不来
        if ProcessInfo.processInfo.arguments.contains("-UseInMemoryStore") {
            hasCheckedEntitlements = true
            return
        }
        #endif
        defer { hasCheckedEntitlements = true }
        var owned = false
        var trialStartedAt: Date?
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement, transaction.revocationDate == nil else { continue }
            if Self.lifetimeProductIDs.contains(transaction.productID) { owned = true }
            if transaction.productID == Self.trialProductID { trialStartedAt = transaction.purchaseDate }
        }
        setPurchased(owned)
        // 试用记录读不到时（比如还没同步完）不清掉本机记的开始时间，免得同一个人又能再试一次
        if let trialStartedAt { setTrialStarted(trialStartedAt) }
    }

    func loadProducts() async {
        if case .loaded = productState { return }
        productState = .loading
        let ids = [Self.trialProductID, Self.specialProductID, Self.productID]
        let found = (try? await Product.products(for: ids)) ?? []
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let special = byID[Self.specialProductID], let regular = byID[Self.productID] {
            productState = .loaded(Products(trial: byID[Self.trialProductID], special: special, regular: regular))
        } else {
            productState = .unavailable
        }
    }

    /// 开始 7 天试用：向 App Store「买」那件 ¥0 的商品，交易时间就是试用开始的时间
    func startTrial() async -> PurchaseOutcome {
        guard case .loaded(let products) = productState, let trial = products.trial else {
            return .failed(String(localized: "暂时读不到免费体验，请检查网络后重试。"))
        }
        return await buy(trial) { [self] transaction in
            setTrialStarted(transaction.purchaseDate)
        }
    }

    /// 买断：专属价期内买专属价那件，过了买原价那件
    func purchase() async -> PurchaseOutcome {
        guard case .loaded(let products) = productState else {
            return .failed(String(localized: "暂时读不到商品，请检查网络后重试。"))
        }
        return await buy(hasSpecialPrice ? products.special : products.regular) { [self] transaction in
            setPurchased(transaction.revocationDate == nil)
        }
    }

    /// 向 App Store 重新同步购买记录，用于重装或换设备后找回 Pro
    func restore() async -> RestoreOutcome {
        guard !isWorking else { return .cancelled }
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
        await refreshEntitlement()
        return hasPurchased ? .restored : .nothingToRestore
    }

    private func buy(_ product: Product, onVerified: (Transaction) -> Void) async -> PurchaseOutcome {
        guard !isWorking else { return .cancelled }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                onVerified(transaction)
                await transaction.finish()
                return .purchased
            case .success(.unverified):
                return .failed(String(localized: "这笔购买没有通过 Apple 的校验，Pro 没有解锁。可以稍后点「恢复购买」再试。"))
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed(String(localized: "购买没有完成，请稍后再试。"))
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func setPurchased(_ purchased: Bool) {
        guard purchased != hasPurchased else { return }
        hasPurchased = purchased
        defaults.set(purchased, forKey: Self.unlockedKey)
    }

    private func setTrialStarted(_ date: Date) {
        guard offer.trialStartedAt != date else { return }
        offer = ProOffer(trialStartedAt: date)
        defaults.set(date, forKey: Self.trialStartedKey)
        scheduleTick()
    }

    /// 把「现在」拨到当前时间，并约好下一次：试用或专属价到点时界面要自己变。
    /// 回到前台时也调一次：挂在后台期间约好的那次可能没走
    func tick() {
        now = clock()
        scheduleTick()
    }

    private func scheduleTick() {
        tickTask?.cancel()
        guard let next = offer.nextChange(after: now) else { return }
        let wait = next.timeIntervalSince(now) + 1
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }
}
