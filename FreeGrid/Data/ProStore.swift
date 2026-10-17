// Pro 永久买断：向 App Store 读商品、发起购买、恢复购买，并把「是否已解锁」记在本机。
// 账本不经过这里；解锁状态只是一个本机偏好，不进备份。

import Foundation
import Observation
import StoreKit

@Observable
final class ProStore {
    static let shared = ProStore(defaults: AppPreferences.store)

    /// 要和 App Store Connect 里创建的非消耗型商品一致
    static let productID = "cn.conilab.FreeGrid.pro.lifetime"
    static let unlockedKey = "proUnlocked"
    static let previewKey = "proPreview"

    enum ProductState {
        case loading
        case loaded(Product)
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

    /// App Store 确认过的购买。上一次的结果存在本机，离线启动也能直接用
    private(set) var hasPurchased: Bool
    private(set) var productState: ProductState = .loading
    /// 购买或恢复进行中，界面据此停用按钮
    private(set) var isWorking = false

    #if DEBUG
    /// 仅调试：不经过购买直接看 Pro 功能。Release 里没有这个开关
    var isPreviewing: Bool {
        didSet { defaults.set(isPreviewing, forKey: Self.previewKey) }
    }
    #endif

    var isUnlocked: Bool {
        #if DEBUG
        return hasPurchased || isPreviewing
        #else
        return hasPurchased
        #endif
    }

    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasPurchased = defaults.bool(forKey: Self.unlockedKey)
        #if DEBUG
        isPreviewing = defaults.bool(forKey: Self.previewKey)
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
        Task {
            await refreshEntitlement()
            await loadProduct()
        }
    }

    /// 以 App Store 的当前权益为准重新计算。退款后的交易带撤销日期，不算数。
    func refreshEntitlement() async {
        #if DEBUG
        // UI 测试和拍图（-UseInMemoryStore）只认 -proPreview：模拟器里在 Xcode 测过的购买还留着，会让「没买」的样子出不来
        if ProcessInfo.processInfo.arguments.contains("-UseInMemoryStore") { return }
        #endif
        var owned = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setPurchased(owned)
    }

    func loadProduct() async {
        if case .loaded = productState { return }
        productState = .loading
        let product = try? await Product.products(for: [Self.productID]).first
        productState = product.map(ProductState.loaded) ?? .unavailable
    }

    func purchase() async -> PurchaseOutcome {
        guard !isWorking else { return .cancelled }
        guard case .loaded(let product) = productState else {
            return .failed("暂时读不到商品，请检查网络后重试。")
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                setPurchased(transaction.revocationDate == nil)
                await transaction.finish()
                return .purchased
            case .success(.unverified):
                return .failed("这笔购买没有通过 Apple 的校验，Pro 没有解锁。可以稍后点「恢复购买」再试。")
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("购买没有完成，请稍后再试。")
            }
        } catch {
            return .failed(error.localizedDescription)
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

    private func setPurchased(_ purchased: Bool) {
        guard purchased != hasPurchased else { return }
        hasPurchased = purchased
        defaults.set(purchased, forKey: Self.unlockedKey)
    }
}
