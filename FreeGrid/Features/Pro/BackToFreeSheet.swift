// 「回到免费版」：体验结束或退款后，一条条说清体验期间加的东西现在怎样、要不要整理，能合并的当场合并。
// Pro 刚失效时首页弹一次（`ProStore.takeLapse`），之后从购买页对照表下面再打开。

import SwiftUI
import SwiftData

struct BackToFreeSheet: View {
    @Query(sort: [SortDescriptor(\AssetItem.sortOrder), SortDescriptor(\AssetItem.createdAt)])
    private var assetItems: [AssetItem]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    @Query(sort: \Loan.sortOrder) private var loans: [Loan]
    @Query private var expenses: [Expense]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirming: Bucket?
    @State private var showingPro = false
    @State private var saveError: String?

    private enum Bucket: String, Identifiable {
        case assets, cash
        var id: String { rawValue }
    }

    private var plan: BackToFreePlan {
        BackToFreePlan(assetItems: assetItems, cashAccounts: cashAccounts, loans: loans)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    VStack(spacing: Spacing.md) {
                        if !plan.assetItems.isEmpty { assetsCard }
                        if !plan.cashAccounts.isEmpty { cashCard }
                        if !plan.loans.isEmpty { loansCard }
                        if !plan.hasProContent {
                            // 和购买页「Pro 已解锁」同一种写法
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundStyle(Color.mossGreen)
                                Text("都整理好了，现在就是免费版。")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color.ink)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("back-to-free-finished")
                        }
                    }
                    Text("分类、视图和自由卡不用管：旧账保留原来的分类，Assets 换回经典视图，自由卡照常能看。")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: Spacing.md) {
                        VaultButton(title: "好了", style: .secondary) { dismiss() }
                            .accessibilityIdentifier("back-to-free-done")
                        // 都合并完就没有可保留的了
                        if plan.hasProContent {
                            Button("想保留这些，买断 Pro") { showingPro = true }
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Color.skyDeep)
                                .buttonStyle(.plain)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("back-to-free-pro")
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .inlineNavTitle()
        }
        .accessibilityIdentifier("back-to-free-sheet")
        .proPaywall(isPresented: $showingPro, offersBackToFree: false)
        .saveErrorAlert($saveError)
        .confirmationDialog("合并成一个总数？", isPresented: Binding(
            get: { confirming != nil }, set: { if !$0 { confirming = nil } }
        ), titleVisibility: .visible, presenting: confirming) { bucket in
            Button("合并", role: .destructive) { merge(bucket) }
            Button("取消", role: .cancel) {}
        } message: { bucket in
            Text(bucket == .assets
                 ? "各项会删除，资产总数 ¥\(lockedAssets.formatted(.number)) 不变。"
                 : "各账户会删除，现金总数 ¥\(cash.formatted(.number)) 不变。")
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KickerLabel(text: "FreeGrid", color: .skyDeep)
                .padding(.bottom, Spacing.xs)
            Text(ProStore.shared.offer.hasStartedTrial ? "免费体验结束了" : "Pro 已不可用")
                .font(.system(size: 26, weight: .light, design: .rounded))
                .foregroundStyle(Color.ink)
            Text("体验期间加的内容都还在，照常计算，只是不能再改。不买断也能继续用，整理一下就好。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 三张卡

    private var assetsCard: some View {
        var lines = ["合并成一个总数，总额 ¥\(lockedAssets.formatted(.number)) 不变，之后直接改总数。"]
        if !plan.excludedAssets.isEmpty {
            lines.append("\(Self.quoted(plan.excludedAssets))现在不计入自由天数，合并后资产整体计入。")
        }
        return itemCard(title: "资产", count: "\(plan.assetItems.count) 项", names: plan.assetItems,
                        lines: lines, change: change(mergingAssets: true),
                        action: ("合并", "back-to-free-merge-assets", { confirming = .assets }))
    }

    private var cashCard: some View {
        var lines = ["合并成一个总数，总额 ¥\(cash.formatted(.number)) 不变，记支出直接从现金扣。"]
        if !plan.excludedCash.isEmpty {
            lines.append("\(Self.quoted(plan.excludedCash))现在不计入自由天数，合并后现金全部计入。")
        }
        return itemCard(title: "现金", count: "\(plan.cashAccounts.count) 个账户", names: plan.cashAccounts,
                        lines: lines, change: change(mergingAssets: false),
                        action: ("合并", "back-to-free-merge-cash", { confirming = .cash }))
    }

    private var loansCard: some View {
        itemCard(title: "贷款", count: "\(plan.loans.count) 笔", names: plan.loans,
                 lines: ["不用处理，照常按期自动扣。不想要了，在 Assets 里点那一行删除。"],
                 change: nil, action: nil)
    }

    private func itemCard(title: String, count: String, names: [String], lines: [String], change: String?,
                          action: (title: String, id: String, run: () -> Void)?) -> some View {
        VaultCard(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                    Text(count)
                        .font(.system(.footnote, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                    Spacer(minLength: Spacing.sm)
                    if let action {
                        Button(action: action.run) {
                            Text(action.title)
                                .font(.system(.footnote, design: .rounded).weight(.medium))
                                .foregroundStyle(Color.skyDeep)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(action.id)
                    }
                }
                Text(names.joined(separator: " · "))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let change {
                    Text(change)
                        .font(.system(.footnote, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .padding(.top, Spacing.xs)
                }
            }
        }
    }

    // MARK: - 数字

    private var lockedAssets: Double { assetsArr.first?.lockedAssets ?? 0 }
    private var cash: Double { assetsArr.first?.cash ?? 0 }

    /// 合并后自由天数会变时写一行「合并后自由天数 146 天 → 3.2 年」；不变就不写
    private func change(mergingAssets: Bool) -> String? {
        let before = FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                                       assetItems: assetItems, cashAccounts: cashAccounts, loans: loans).freedom
        let after = BackToFreePlan.freedomAfterMerging(
            assets: mergingAssets, cash: !mergingAssets, expenses: expenses, passiveSources: passiveSources,
            assets: assetsArr.first, assetItems: assetItems, cashAccounts: cashAccounts, loans: loans)
        let beforeText = FreedomMath.freedomDescription(before)
        let afterText = FreedomMath.freedomDescription(after)
        guard beforeText != afterText else { return nil }
        return "合并后自由天数 \(beforeText) → \(afterText)"
    }

    private static func quoted(_ names: [String]) -> String {
        names.map { "「\($0)」" }.joined(separator: "、")
    }

    private func merge(_ bucket: Bucket) {
        do {
            switch bucket {
            case .assets: try AssetItemStore.mergeIntoTotalKeepingSwitch(in: modelContext)
            case .cash: try CashAccountStore.mergeIntoTotal(in: modelContext)
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}
