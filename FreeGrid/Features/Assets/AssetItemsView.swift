// Pro 资产逐项记录：把资产桶拆成一项一项（房、车、定期、基金…），总数是各项相加。
// 没有 Pro 时只给锁定页；已经拆好的项不删、不藏，只是不能再增删改。

import SwiftUI
import SwiftData

struct AssetItemsView: View {
    @Query(sort: [SortDescriptor(\AssetItem.sortOrder), SortDescriptor(\AssetItem.createdAt)])
    private var items: [AssetItem]
    @Query private var assetsArr: [UserAssets]
    @Environment(\.modelContext) private var modelContext

    @State private var adding = false
    @State private var editing: AssetItem?
    @State private var pendingDelete: AssetItem?
    @State private var confirmingMerge = false
    @State private var showingPro = false
    @State private var saveError: String?

    private var canManage: Bool { ProFeatures.canManageAssetItems }
    private var total: Double { assetsArr.first?.lockedAssets ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerCard
                if canManage {
                    VaultButton(title: "添加资产项", icon: "plus") { adding = true }
                        .accessibilityIdentifier("add-asset-item")
                }
                if !items.isEmpty { itemList }
                if !items.isEmpty {
                    Text(canManage
                         ? "资产总数是各项相加。在资产页调拨时，选择钱从哪一项出、进哪一项。"
                         : "每一项的名称和金额都还在。")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.horizontal, Spacing.sm)
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("资产明细")
        .inlineNavTitle()
        .saveErrorAlert($saveError)
        // 第一次进来：原来的资产总数自动变成一项「资产」，净值和自由天数不变
        .task {
            guard canManage else { return }
            do { try AssetItemStore.migrateIfNeeded(in: modelContext) }
            catch { saveError = error.localizedDescription }
        }
        .sheet(isPresented: $adding) {
            AssetItemSheet(existing: nil) { name, amount in
                try AssetItemStore.save(nil, name: name, amount: amount, in: modelContext)
            }
        }
        .sheet(item: $editing) { item in
            AssetItemSheet(existing: item) { name, amount in
                try AssetItemStore.save(item, name: name, amount: amount, in: modelContext)
            }
        }
        .sheet(isPresented: $showingPro) { ProPaywallView() }
        .confirmationDialog("删除「\(pendingDelete?.name ?? "")」？",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let item = pendingDelete { delete(item) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("资产总数会减少 ¥\((pendingDelete?.amount ?? 0).formatted(.number))。")
        }
        .confirmationDialog("合并成一个总数？", isPresented: $confirmingMerge, titleVisibility: .visible) {
            Button("合并", role: .destructive) { merge() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("各项会删除，资产总数 ¥\(total.formatted(.number)) 不变，之后在资产页直接改总数。")
        }
    }

    // MARK: - 顶部卡

    private var headerCard: some View {
        VaultCard(emphasis: .high, padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "FREEGRID PRO · 资产")
                    Spacer()
                    if !items.isEmpty {
                        Text("\(items.count) 项")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.inkFaint)
                    }
                }
                Text("¥" + total.formatted(.number))
                    .font(.system(size: 44, weight: .ultraLight, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("asset-items-total")
                if canManage {
                    Text("房、车、定期、基金……一项一项记，总数自动相加。")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                } else {
                    lockedNotes
                }
            }
        }
    }

    @ViewBuilder
    private var lockedNotes: some View {
        if items.isEmpty {
            Text("逐项记录资产是 Pro 功能。现在的资产总数照常使用，不受影响。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("你之前拆好的每一项都还在，金额照常计入资产。没有 Pro 时不能增删改；想回到只改总数，可以先把它们合并成一个总数。")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        VaultButton(title: "了解 FreeGrid Pro", icon: "sparkles") { showingPro = true }
            .accessibilityIdentifier("open-pro-from-assets")
        if !items.isEmpty {
            VaultButton(title: "合并成一个总数", icon: "arrow.triangle.merge", style: .secondary) {
                confirmingMerge = true
            }
            .accessibilityIdentifier("merge-asset-items")
        }
    }

    // MARK: - 列表

    private var itemList: some View {
        VaultCard(padding: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Hairline().padding(.horizontal, Spacing.lg) }
                    row(item)
                }
            }
        }
    }

    private func row(_ item: AssetItem) -> some View {
        HStack(spacing: Spacing.sm) {
            Button {
                if canManage { editing = item }
            } label: {
                HStack(spacing: Spacing.md) {
                    Text(item.name)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.sm)
                    Text("¥" + item.amount.formatted(.number))
                        .font(.system(.body, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canManage)
            .accessibilityIdentifier("asset-item-\(item.name)")
            if canManage {
                Button {
                    pendingDelete = item
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.flame)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除\(item.name)")
                .accessibilityIdentifier("delete-asset-item-\(item.name)")
            }
        }
        .padding(.leading, Spacing.lg)
        .padding(.trailing, canManage ? Spacing.sm : Spacing.lg)
        .padding(.vertical, canManage ? Spacing.xs : Spacing.md)
    }

    // MARK: - 写入

    private func delete(_ item: AssetItem) {
        do { try AssetItemStore.delete(item, in: modelContext) }
        catch { saveError = error.localizedDescription }
    }

    private func merge() {
        do { try AssetItemStore.mergeIntoTotal(in: modelContext) }
        catch { saveError = error.localizedDescription }
    }
}
