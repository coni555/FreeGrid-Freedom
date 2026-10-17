// 新版 Assets 的调拨：资产和现金两张标签中间那个圆钮打开它。
// 上面「从 → 到」两张小卡（点开选是哪一项 / 哪个账户），中间对调；下面填金额，实时写出调完之后两边各剩多少。

import SwiftUI
import SwiftData

struct TransferSheet: View {
    @Query(sort: [SortDescriptor(\AssetItem.sortOrder), SortDescriptor(\AssetItem.createdAt)])
    private var assetItems: [AssetItem]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    @Query private var assetsArr: [UserAssets]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var from: TransferStore.Place?
    @State private var to: TransferStore.Place?
    @State private var amount = ""
    @State private var saveError: String?
    @State private var showingPro = false
    @FocusState private var amountFocused: Bool

    private struct Option: Identifiable {
        let place: TransferStore.Place
        let name: String
        let amount: Double
        var id: TransferStore.Place { place }
    }

    private var cashOptions: [Option] {
        cashAccounts.isEmpty
            ? [Option(place: .cashTotal, name: "现金", amount: assetsArr.first?.cash ?? 0)]
            : cashAccounts.map { Option(place: .cashAccount($0.id), name: $0.name, amount: $0.amount) }
    }

    private var assetOptions: [Option] {
        assetItems.isEmpty
            ? [Option(place: .assetsTotal, name: "资产", amount: assetsArr.first?.lockedAssets ?? 0)]
            : assetItems.map { Option(place: .assetItem($0.id), name: $0.name, amount: $0.amount) }
    }

    /// 选过的还在就用它；默认从钱最多的现金账户调进第一个算自由天数的资产项
    private var source: Option {
        (cashOptions + assetOptions).first { $0.place == from }
            ?? cashOptions.max { $0.amount < $1.amount } ?? cashOptions[0]
    }

    private var destination: Option {
        let all = cashOptions + assetOptions
        if let picked = all.first(where: { $0.place == to }), picked.place != source.place { return picked }
        guard source.place.isCash else { return cashOptions[0] }
        let counted = Set(assetItems.filter(\.countsInFreedom).map { TransferStore.Place.assetItem($0.id) })
        return assetOptions.first { counted.contains($0.place) } ?? assetOptions[0]
    }

    private var locked: Bool {
        (!assetItems.isEmpty && !ProFeatures.canManageAssetItems)
            || (!cashAccounts.isEmpty && !ProFeatures.canManageCashAccounts)
    }

    private var entered: Double? {
        Double(amount).flatMap { FinancialFormatting.validAmount($0) ? $0 : nil }
    }

    /// 填的比来源里有的还多：不让调，提示里给出「调全部」
    private var exceeds: Bool {
        guard let entered else { return false }
        return entered > max(0, source.amount) + 0.005
    }

    private var canTransfer: Bool { entered != nil && !exceeds }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if locked { lockedNote } else { form }
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("调拨")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                if !locked {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确认") { transfer() }
                            .disabled(!canTransfer)
                            .foregroundStyle(canTransfer ? Color.skyDeep : Color.inkFaint)
                            .fontWeight(.medium)
                            .accessibilityIdentifier("confirm-transfer")
                    }
                }
            }
            .onAppear { amountFocused = !locked }
        }
        .saveErrorAlert($saveError)
        .sheet(isPresented: $showingPro) { ProPaywallView(topic: assetItems.isEmpty ? .cash : .assets) }
        .iosSheetDetents()
    }

    // MARK: - 表单

    private var form: some View {
        let from = source
        let to = destination
        let moved = entered ?? 0
        let uncounted = assetItems.first { TransferStore.Place.assetItem($0.id) == to.place && !$0.countsInFreedom }
        return VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(spacing: Spacing.sm) {
                placeCard(label: "从", option: from, excluding: nil, identifier: "transfer-from-menu") { self.from = $0 }
                Button {
                    withAnimation(.snappy(duration: 0.28)) { (self.from, self.to) = (to.place, from.place) }
                } label: {
                    // 方向箭头，点它对调（不用 ⇄：那是页面上调拨圆钮的记号）
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(Color.skyDeep)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("对调方向")
                .accessibilityIdentifier("transfer-swap")
                placeCard(label: "到", option: to, excluding: from.place, identifier: "transfer-to-menu") { self.to = $0 }
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                UnderlinedField(isFocused: amountFocused, accent: from.place.isCash ? .cashBlue : .assetGold) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("¥")
                            .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                        TextField("0", text: $amount)
                            .decimalKeyboard()
                            .focused($amountFocused)
                            .font(.system(size: 52, weight: .ultraLight, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.ink)
                            .minimumScaleFactor(0.5)
                            .accessibilityIdentifier("transfer-amount-field")
                    }
                }
                // 调完之后两边各剩多少；比来源里有的多时说实话，点一下就填成全部
                if exceeds {
                    Button {
                        amount = max(0, from.amount).formatted(
                            .number.grouping(.never).precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX")))
                    } label: {
                        Text("「\(from.name)」只有 ¥\(max(0, from.amount).formatted(.number))  ")
                            .foregroundStyle(Color.flame)
                        + Text("调全部").foregroundStyle(Color.skyDeep)
                    }
                    .buttonStyle(.plain)
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .accessibilityIdentifier("transfer-fill-all")
                } else {
                    Text(entered == nil
                         ? "「\(from.name)」可用 ¥\(max(0, from.amount).formatted(.number))"
                         : "之后：\(from.name) ¥\((from.amount - moved).formatted(.number)) · \(to.name) ¥\((to.amount + moved).formatted(.number))")
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                        .contentTransition(.numericText())
                }
                if let uncounted {
                    Text("「\(uncounted.name)」不计入自由天数，调进去自由天数会变少")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.flame)
                }
            }
        }
    }

    /// 一张小卡：「从」或「到」、色块、名字、余额；点开按现金、资产两组选
    private func placeCard(label: String, option: Option, excluding: TransferStore.Place?,
                           identifier: String, onPick: @escaping (TransferStore.Place) -> Void) -> some View {
        Menu {
            Section("现金") {
                ForEach(cashOptions.filter { $0.place != excluding }) { item in
                    Button("\(item.name) · ¥\(item.amount.formatted(.number))") { onPick(item.place) }
                }
            }
            Section("资产") {
                ForEach(assetOptions.filter { $0.place != excluding }) { item in
                    Button("\(item.name) · ¥\(item.amount.formatted(.number))") { onPick(item.place) }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                KickerLabel(text: label)
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(option.place.isCash ? Color.cashBlue : Color.assetGold)
                        .frame(width: 8, height: 8)
                    Text(option.name)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                }
                Text("¥" + option.amount.formatted(.number))
                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.mist))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityIdentifier(identifier)
    }

    private var lockedNote: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("资产或现金已经拆开，调拨要改其中某一项，需要 Pro。也可以先把它合并成一个总数，再调拨。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button("了解 Pro") { showingPro = true }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.skyDeep)
                .buttonStyle(.plain)
        }
    }

    private func transfer() {
        guard canTransfer, let value = entered else { return }
        do {
            try TransferStore.transfer(value, from: source.place, to: destination.place, in: modelContext)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
