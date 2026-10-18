// 「回到免费版」：体验结束或退款后，逐项写清体验期间加的东西现在怎样，能合并的当场合并，贷款引导删除。
// Pro 刚失效时首页弹一次（`ProStore.takeLapse`），之后从购买页对照表下面再打开。
// 文案按用户 2026-10-18 给的参考文风：先一句状态，再一句做什么、结果是什么。

import StoreKit
import SwiftUI
import SwiftData

struct BackToFreeSheet: View {
    @Query(sort: [SortDescriptor(\AssetItem.sortOrder), SortDescriptor(\AssetItem.createdAt)])
    private var assetItems: [AssetItem]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    @Query(sort: [SortDescriptor(\Loan.sortOrder), SortDescriptor(\Loan.createdAt)]) private var loans: [Loan]
    @Query private var expenses: [Expense]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirming: Step?
    @State private var showingPro = false
    @State private var saveError: String?

    private enum Step: String, Identifiable {
        case mergeAssets, mergeCash, deleteLoans
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
                        if !plan.hasProContent { finished }
                    }
                    others
                    VStack(spacing: Spacing.md) {
                        // 都调整完就没有可保留的了
                        if plan.hasProContent { proCard }
                        VaultButton(title: "继续使用免费版") { dismiss() }
                            .accessibilityIdentifier("back-to-free-done")
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
        .task { await ProStore.shared.loadProducts() }
        .proPaywall(isPresented: $showingPro, offersBackToFree: false)
        .saveErrorAlert($saveError)
        .confirmationDialog(confirmTitle, isPresented: Binding(
            get: { confirming != nil }, set: { if !$0 { confirming = nil } }
        ), titleVisibility: .visible, presenting: confirming) { step in
            Button(step == .deleteLoans ? "删除" : "合并", role: .destructive) { run(step) }
            Button("取消", role: .cancel) {}
        } message: { step in
            switch step {
            case .mergeAssets: Text("资产总额 ¥\(lockedAssets.formatted(.number)) 保持不变。")
            case .mergeCash: Text("现金总额 ¥\(cash.formatted(.number)) 保持不变。")
            case .deleteLoans: Text("已记的还款保留在 History。")
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KickerLabel(text: "FreeGrid", color: .skyDeep)
                .padding(.bottom, Spacing.xs)
            Text(ProStore.shared.offer.hasStartedTrial ? "Pro 体验已结束" : "Pro 已失效")
                .font(.system(size: 26, weight: .light, design: .rounded))
                .foregroundStyle(Color.ink)
            Text("账本和体验期间添加的数据都已保留。你可以继续免费使用 FreeGrid，部分 Pro 功能已暂停。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 三张卡

    private var assetsCard: some View {
        var lines = ["把各项合并为一个资产总额，金额不变。"]
        if !plan.excludedAssets.isEmpty {
            lines.append("\(Self.quoted(plan.excludedAssets))目前未计入自由天数。合并后资产统一计入，之后可整体选择是否计入。")
        }
        return card(title: "资产", count: "\(plan.assetItems.count) 项", names: plan.assetItems,
                    status: "合并后可继续编辑", lines: lines, change: change(mergingAssets: true),
                    action: Action(title: "合并资产", id: "back-to-free-merge-assets") { confirming = .mergeAssets })
    }

    private var cashCard: some View {
        var lines = ["把各账户合并为一个现金总额，余额不变。收支直接计入现金。"]
        if !plan.excludedCash.isEmpty {
            lines.append("\(Self.quoted(plan.excludedCash))目前未计入自由天数，合并后现金全部计入。")
        }
        return card(title: "现金", count: "\(plan.cashAccounts.count) 个账户", names: plan.cashAccounts,
                    status: "合并后可继续编辑", lines: lines, change: change(mergingAssets: false),
                    action: Action(title: "合并账户", id: "back-to-free-merge-cash") { confirming = .mergeCash })
    }

    private var loansCard: some View {
        card(title: "贷款", count: "\(plan.loans.count) 笔", names: plan.loans, status: "已停用",
             lines: ["不再自动记账，也不计入自由天数。免费版不支持贷款，建议删除；已记的还款保留在 History。"],
             change: nil,
             action: Action(title: "删除贷款", id: "back-to-free-delete-loans", color: .flame) { confirming = .deleteLoans })
    }

    private struct Action {
        let title: String
        let id: String
        var color: Color = .skyDeep
        let run: () -> Void
    }

    private func card(title: String, count: String, names: [String], status: String, lines: [String],
                      change: String?, action: Action) -> some View {
        VaultCard(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(title)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.ink)
                        Text(count)
                            .font(.system(.footnote, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkFaint)
                    }
                    Spacer(minLength: Spacing.sm)
                    Button(action: action.run) {
                        Text(action.title)
                            .font(.system(.footnote, design: .rounded).weight(.medium))
                            .foregroundStyle(action.color)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .overlay(Capsule().stroke(action.color, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(action.id)
                }
                Text(names.joined(separator: " · "))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(status)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                    .padding(.top, Spacing.xs)
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

    /// 买 Pro 的那张卡：和购买页对照表 Pro 列同一种淡蓝底，细蓝线描边。点了进购买页，在那里买或开始体验。
    /// 放在「继续使用免费版」上面但不挡它：主按钮仍是免费版
    private var proCard: some View {
        Button { showingPro = true } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    KickerLabel(text: "FreeGrid Pro", color: .skyDeep)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.skyDeep)
                }
                Text(plan.keepLine)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let price {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(price.now)
                            .font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.skyDeep)
                        if let was = price.was {
                            Text(was)
                                .font(.system(.footnote, design: .rounded).monospacedDigit())
                                .strikethrough()
                                .foregroundStyle(Color.inkFaint)
                        }
                        Text(price.was == nil ? "一次买断" : "买断优惠价")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                    }
                    .padding(.top, Spacing.xs)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.skyDeep.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.skyDeep.opacity(0.45), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("back-to-free-pro")
    }

    /// 现在买要多少：优惠期内给优惠价和划掉的原价。读不到商品时不写价格
    private var price: (now: String, was: String?)? {
        let store = ProStore.shared
        if case .loaded(let products) = store.productState {
            return store.hasSpecialPrice
                ? (products.special.displayPrice, products.regular.displayPrice)
                : (products.regular.displayPrice, nil)
        }
        #if DEBUG
        // 和购买页一样：模拟器里读不到商品，拍图时用示例价格
        if ProcessInfo.processInfo.arguments.contains("-proSamplePrices") {
            return store.hasSpecialPrice ? ("¥19.90", "¥29.90") : ("¥29.90", nil)
        }
        #endif
        return nil
    }

    /// 都调整完：和购买页「Pro 已解锁」同一种写法
    private var finished: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.mossGreen)
            Text("已调整完成，可以正常使用免费版。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("back-to-free-finished")
    }

    private var others: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("其他功能")
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(Color.inkMuted)
            ForEach([("支出分类", "体验期间设置的分类继续可用，修改需 Pro。"),
                     ("资产视图", "恢复经典视图。"),
                     ("自由卡", "可以查看，分享需 Pro。")], id: \.0) { name, text in
                (Text(name + "：").foregroundStyle(Color.inkMuted) + Text(text).foregroundStyle(Color.inkFaint))
                    .font(.system(.footnote, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 数字

    private var lockedAssets: Double { assetsArr.first?.lockedAssets ?? 0 }
    private var cash: Double { assetsArr.first?.cash ?? 0 }

    private var confirmTitle: String {
        switch confirming {
        case .mergeAssets: return "合并 \(plan.assetItems.count) 项资产？"
        case .mergeCash: return "合并 \(plan.cashAccounts.count) 个现金账户？"
        case .deleteLoans: return "删除 \(plan.loans.count) 笔贷款？"
        case nil: return ""
        }
    }

    /// 合并后自由天数会变时写一行「自由天数 146 天 → 26.5 年」；不变就不写。停用的贷款本来就不算
    private func change(mergingAssets: Bool) -> String? {
        let loansInEffect = ProFeatures.loansInEffect(loans)
        let before = FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                                       assetItems: assetItems, cashAccounts: cashAccounts, loans: loansInEffect).freedom
        let after = BackToFreePlan.freedomAfterMerging(
            assets: mergingAssets, cash: !mergingAssets, expenses: expenses, passiveSources: passiveSources,
            assets: assetsArr.first, assetItems: assetItems, cashAccounts: cashAccounts, loans: loansInEffect)
        let beforeText = FreedomMath.freedomDescription(before)
        let afterText = FreedomMath.freedomDescription(after)
        guard beforeText != afterText else { return nil }
        return "自由天数 \(beforeText) → \(afterText)"
    }

    private static func quoted(_ names: [String]) -> String {
        names.map { "「\($0)」" }.joined(separator: "、")
    }

    private func run(_ step: Step) {
        do {
            switch step {
            case .mergeAssets: try AssetItemStore.mergeIntoTotalKeepingSwitch(in: modelContext)
            case .mergeCash: try CashAccountStore.mergeIntoTotal(in: modelContext)
            case .deleteLoans:
                for loan in loans where !loan.isOngoing { try LoanStore.delete(loan, in: modelContext) }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}
