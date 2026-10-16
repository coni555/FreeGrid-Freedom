// 资产页的两个抽屉：「资产」和「现金」。点标题展开或收起，展开后一行一个账户。
// 没拆分时只有一行（点它改总数）；拆成多项（Pro）后一项一行，最后一行是「添加」。
// 资产每行前面的方格 = 算不算进自由天数；现金每行前面的序号 = 扣款顺序，右边把手拖动调整。

import SwiftUI
import SwiftData

// MARK: - 抽屉外壳

/// 标题行常驻：色块、名字、几项、总数、展开箭头；下面是收起时也看得到的一行小字。展开后接各行。
struct AccountDrawer<Rows: View>: View {
    let title: String
    let color: Color
    var count: String? = nil
    /// nil 时标题行右边不放数字（还没加过的还款）
    let total: Double?
    /// 数字后面的小字，比如还款的「/月」
    var totalSuffix: String? = nil
    /// 色块挖一个孔：和首页格子上的还款日同一个记号
    var punched = false
    var subtitle: String? = nil
    @Binding var isOpen: Bool
    var headerID: String
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.34)) { isOpen.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Group {
                            if punched {
                                PunchedCell(cornerRadius: 1.5).fill(color, style: FillStyle(eoFill: true))
                            } else {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(color)
                            }
                        }
                        .frame(width: 8, height: 8)
                        KickerLabel(text: title, color: .inkMuted)
                        if let count {
                            Text(count)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.inkFaint)
                        }
                        Spacer(minLength: Spacing.sm)
                        if let total {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("¥" + total.formatted(.number))
                                    .font(.system(size: 24, weight: .light, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Color.ink)
                                if let totalSuffix {
                                    Text(totalSuffix)
                                        .font(.system(size: 13, weight: .light, design: .rounded))
                                        .foregroundStyle(Color.inkMuted)
                                }
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(.caption2, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.inkFaint)
                            .padding(.leading, 16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, Spacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(headerID)
            .accessibilityLabel(title)
            .accessibilityValue((total.map { "¥" + $0.formatted(.number) + (totalSuffix ?? "") + "，" } ?? "")
                                + (isOpen ? "已展开" : "已收起"))

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    rows
                }
                .padding(.horizontal, 20)
                .padding(.bottom, Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.mist))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 抽屉里的一行：左边一个记号，名字，金额。点整行进编辑。
struct DrawerRow<Leading: View, Trailing: View>: View {
    let name: String
    let amount: Double
    var dimmed = false
    var enabled = true
    /// 读屏念的名字；没给时就是 name
    var accessibilityName: String? = nil
    let identifier: String
    let onTap: () -> Void
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                leading
                Button(action: onTap) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(name)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(dimmed ? Color.inkMuted : Color.ink)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.sm)
                        Text("¥" + amount.formatted(.number))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(amount < 0 ? Color.flame : (dimmed ? Color.inkFaint : Color.inkMuted))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(height: DrawerMetrics.rowHeight - 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(enabled)
                .accessibilityLabel(accessibilityName ?? name)
                .accessibilityValue("¥" + amount.formatted(.number))
                .accessibilityIdentifier(identifier)
                trailing
            }
        }
    }
}

enum DrawerMetrics {
    static let rowHeight: CGFloat = 46
}

/// 抽屉最后一行：添加。没有 Pro 时带 PRO 字样，点了去购买页
struct DrawerAddRow: View {
    let title: String
    let showsPro: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            Button(action: action) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 19, alignment: .leading)
                    Text(title)
                        .font(.system(.subheadline, design: .rounded))
                    if showsPro {
                        Text("PRO")
                            .font(.system(.caption2, design: .monospaced))
                            .tracking(2)
                    }
                    Spacer()
                }
                .foregroundStyle(Color.skyDeep)
                .frame(height: DrawerMetrics.rowHeight - 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
        }
    }
}

/// 抽屉底部一行说明，或者退款后的两条出路
struct DrawerFooter: View {
    let text: String
    var locked = false
    var onPro: () -> Void = {}
    var onMerge: () -> Void = {}
    var mergeID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Hairline()
            Text(text)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            if locked {
                HStack(spacing: Spacing.lg) {
                    Button("了解 Pro", action: onPro)
                        .accessibilityIdentifier("\(mergeID)-pro")
                    Button("合并成一个总数", action: onMerge)
                        .accessibilityIdentifier(mergeID)
                }
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.skyDeep)
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, Spacing.sm)
    }
}

// MARK: - 拖动排序（两个抽屉共用）

/// 按住右边把手上下拖：记住拖的是哪一行、拖了多远，算出松手会落在第几位、经过的行让出多少
private struct DragReorder {
    var dragging: UUID?
    var offset: CGFloat = 0

    func dropIndex(in ids: [UUID]) -> Int? {
        guard let dragging, let from = ids.firstIndex(of: dragging) else { return nil }
        return max(0, min(ids.count - 1, from + Int((offset / DrawerMetrics.rowHeight).rounded())))
    }

    func shift(for index: Int, in ids: [UUID]) -> CGFloat {
        guard let dragging, let from = ids.firstIndex(of: dragging), let to = dropIndex(in: ids) else { return 0 }
        if from < to, (from + 1...to).contains(index) { return -DrawerMetrics.rowHeight }
        if from > to, (to..<from).contains(index) { return DrawerMetrics.rowHeight }
        return 0
    }
}

/// 每行右边的把手。读屏用户上下轻扫调整位置
private struct ReorderHandle: View {
    let id: UUID
    let index: Int
    let ids: [UUID]
    let label: String
    let identifier: String
    @Binding var reorder: DragReorder
    let onMove: (Int) -> Void

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .light))
            .foregroundStyle(Color.inkFaint)
            .frame(width: 36, height: DrawerMetrics.rowHeight - 1, alignment: .trailing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        reorder.dragging = id
                        reorder.offset = value.translation.height
                    }
                    .onEnded { _ in
                        let target = reorder.dropIndex(in: ids) ?? index
                        reorder = DragReorder()
                        if target != index { onMove(target) }
                    }
            )
            .accessibilityLabel(label)
            .accessibilityAdjustableAction { direction in
                onMove(direction == .increment ? index + 1 : index - 1)
            }
            .accessibilityIdentifier(identifier)
    }
}

private extension View {
    /// 被拖的那行跟着手指走、浮起来；其他行让位时有动画
    func reorderable(_ reorder: DragReorder, id: UUID, index: Int, ids: [UUID]) -> some View {
        let isDragging = reorder.dragging == id
        return self
            .background(Color.mist)
            .offset(y: isDragging ? reorder.offset : reorder.shift(for: index, in: ids))
            .zIndex(isDragging ? 1 : 0)
            .shadow(color: .black.opacity(isDragging ? 0.08 : 0), radius: 10, y: 4)
            .animation(isDragging ? nil : .snappy(duration: 0.22), value: reorder.dropIndex(in: ids))
    }
}

// MARK: - 资产抽屉

struct AssetDrawer: View {
    @Query(sort: [SortDescriptor(\AssetItem.sortOrder), SortDescriptor(\AssetItem.createdAt)])
    private var items: [AssetItem]
    @Query private var assetsArr: [UserAssets]
    @Environment(\.modelContext) private var modelContext
    @AppStorage(FreedomSettings.countsAssetsKey, store: AppPreferences.store) private var countsAssets = true
    @AppStorage("assetsDrawerOpen", store: AppPreferences.store) private var isOpen = true

    @State private var editingTotal = false
    @State private var splitAfterTotalSheet = false
    @State private var adding: AddingItem?
    @State private var editing: AssetItem?
    @State private var confirmingMerge = false
    @State private var showingPro = false
    @State private var saveError: String?
    @State private var reorder = DragReorder()

    struct AddingItem: Identifiable {
        let id = UUID()
        let initialSource: AssetItemStore.Source?
    }

    private var canManage: Bool { ProFeatures.canManageAssetItems }
    private var total: Double { assetsArr.first?.lockedAssets ?? 0 }
    private var counted: Double {
        items.isEmpty ? (countsAssets ? total : 0) : items.filter(\.countsInFreedom).reduce(0) { $0 + $1.amount }
    }

    private var subtitle: String? {
        guard total > 0 else { return nil }
        if counted >= total { return "全部计入自由天数" }
        return counted == 0 ? "不计入自由天数" : "计入自由天数 ¥\(counted.formatted(.number))"
    }

    var body: some View {
        AccountDrawer(title: "资产", color: .assetGold, count: items.isEmpty ? nil : "\(items.count) 项",
                      total: total, subtitle: subtitle, isOpen: $isOpen, headerID: "assets-drawer") {
            if items.isEmpty {
                // 没拆分：一行就是资产总数，方格是总开关
                DrawerRow(name: "资产", amount: total, dimmed: !countsAssets, accessibilityName: "编辑资产",
                          identifier: "edit-assets-total",
                          onTap: { editingTotal = true }) {
                    countsSquare(counted: countsAssets, name: "资产", identifier: "counts-assets-toggle") {
                        countsAssets.toggle()
                    }
                } trailing: { EmptyView() }
            } else {
                let ids = items.map(\.id)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        DrawerRow(name: item.name, amount: item.amount, dimmed: !item.countsInFreedom,
                                  enabled: canManage, identifier: "asset-item-\(item.name)",
                                  onTap: { editing = item }) {
                            countsSquare(counted: item.countsInFreedom, name: item.name,
                                         identifier: "asset-item-counts-\(item.name)") { toggle(item) }
                                .allowsHitTesting(canManage)
                        } trailing: {
                            if canManage && items.count > 1 {
                                ReorderHandle(id: item.id, index: index, ids: ids, label: "调整\(item.name)的位置",
                                              identifier: "reorder-\(item.name)", reorder: $reorder) { target in
                                    move(item, to: target)
                                }
                            }
                        }
                        .reorderable(reorder, id: item.id, index: index, ids: ids)
                    }
                }
                .sensoryFeedback(.selection, trigger: reorder.dropIndex(in: ids))
            }
            if canManage || items.isEmpty {
                DrawerAddRow(title: items.isEmpty ? "拆成多项" : "添加资产项", showsPro: !canManage,
                             identifier: "add-asset-item", action: startAdding)
            }
            if !items.isEmpty && !canManage {
                DrawerFooter(text: "逐项管理是 Pro 功能，各项照常计算，暂时只能查看。", locked: true,
                             onPro: { showingPro = true }, onMerge: { confirmingMerge = true },
                             mergeID: "merge-asset-items")
            } else {
                DrawerFooter(text: items.isEmpty
                             ? "点方格选资产算不算进自由天数。"
                             : "点方格选这一项算不算进自由天数，拖右边调整先后。")
            }
        }
        .saveErrorAlert($saveError)
        .sheet(isPresented: $editingTotal, onDismiss: {
            if splitAfterTotalSheet {
                splitAfterTotalSheet = false
                startAdding()
            }
        }) {
            EditBucketSheet(bucket: .assets, currentAmount: total, onSave: { value in
                try LedgerStore.updateAssets(in: modelContext) { assets in
                    assets.lockedAssets = value
                    assets.updatedAt = .now
                }
            }, onOpenItems: { splitAfterTotalSheet = true })
        }
        .sheet(item: $adding) { adding in
            AssetItemSheet(existing: nil, sources: sources, initialSource: adding.initialSource) {
                name, amount, counts, source in
                try AssetItemStore.save(nil, name: name, amount: amount, countsInFreedom: counts,
                                        source: source, totalCounts: countsAssets, in: modelContext)
                // 拆开以后由各项自己决定，总开关回到默认，免得以后合并回去时带着旧状态
                countsAssets = true
            }
        }
        .sheet(item: $editing) { item in
            AssetItemSheet(existing: item, onSave: { name, amount, counts, _ in
                try AssetItemStore.save(item, name: name, amount: amount, countsInFreedom: counts, in: modelContext)
            }, onDelete: {
                try AssetItemStore.delete(item, in: modelContext)
                // 删到一项不剩就回到总开关
                if (try? AssetItemStore.items(in: modelContext))?.isEmpty == true { countsAssets = true }
            })
        }
        .sheet(isPresented: $showingPro) { ProPaywallView() }
        .confirmationDialog("合并成一个总数？", isPresented: $confirmingMerge, titleVisibility: .visible) {
            Button("合并", role: .destructive) { merge() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("各项会删除，资产总数 ¥\(total.formatted(.number)) 不变，之后直接改总数。")
        }
    }

    /// 金色实心 = 计入（就是首页的金格），空心 = 只算净值
    private func countsSquare(counted: Bool, name: String, identifier: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(counted ? Color.assetGold : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .strokeBorder(counted ? Color.clear : Color.inkFaint, lineWidth: 1)
                )
                .frame(width: 9, height: 9)
                .frame(width: 19, height: DrawerMetrics.rowHeight - 1, alignment: .leading)
                .contentShape(Rectangle().inset(by: -8))
                .animation(.snappy(duration: 0.24), value: counted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)计入自由天数")
        .accessibilityValue(counted ? "计入" : "不计入")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier(identifier)
    }

    private var sources: [AssetItemSheet.SourceOption] {
        if items.isEmpty {
            return total > 0 ? [.init(source: .unsplitTotal, name: "资产", amount: total)] : []
        }
        return items.filter { $0.amount > 0 }.map { .init(source: .item($0.id), name: $0.name, amount: $0.amount) }
    }

    /// 没有 Pro 去购买页；拆分时默认从原来的总数里拆
    private func startAdding() {
        guard canManage else {
            showingPro = true
            return
        }
        adding = AddingItem(initialSource: items.isEmpty && total > 0 ? .unsplitTotal : nil)
    }

    private func move(_ item: AssetItem, to index: Int) {
        do { try AssetItemStore.move(item, to: index, in: modelContext) }
        catch { saveError = error.localizedDescription }
    }

    private func toggle(_ item: AssetItem) {
        do { try AssetItemStore.setCountsInFreedom(!item.countsInFreedom, for: item, in: modelContext) }
        catch { saveError = error.localizedDescription }
    }

    /// 合并回一个总数：只要有一项算着，总开关就开；一项都没算才关
    private func merge() {
        let anyCounted = items.contains { $0.countsInFreedom && $0.amount > 0 }
        do {
            try AssetItemStore.mergeIntoTotal(in: modelContext)
            countsAssets = anyCounted || total == 0
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - 现金抽屉

struct CashDrawer: View {
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var accounts: [CashAccount]
    @Query private var assetsArr: [UserAssets]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppGuide.self) private var guide
    @AppStorage("cashDrawerOpen", store: AppPreferences.store) private var isOpen = true

    @State private var editingTotal = false
    @State private var splitAfterTotalSheet = false
    @State private var adding: AddingAccount?
    @State private var editing: CashAccount?
    @State private var confirmingMerge = false
    @State private var showingPro = false
    @State private var saveError: String?
    @State private var reorder = DragReorder()

    struct AddingAccount: Identifiable {
        let id = UUID()
        let initialSource: CashAccountStore.Source?
    }

    private var canManage: Bool { ProFeatures.canManageCashAccounts }
    private var total: Double { assetsArr.first?.cash ?? 0 }

    private var subtitle: String? {
        accounts.count > 1 ? "记支出先扣「\(accounts[0].name)」" : nil
    }

    var body: some View {
        AccountDrawer(title: "现金", color: .cashBlue, count: accounts.isEmpty ? nil : "\(accounts.count) 个账户",
                      total: total, subtitle: subtitle, isOpen: $isOpen, headerID: "cash-drawer") {
            if accounts.isEmpty {
                DrawerRow(name: "现金", amount: total, accessibilityName: "编辑现金", identifier: "edit-cash-total",
                          onTap: { editingTotal = true }) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.cashBlue)
                        .frame(width: 9, height: 9)
                        .frame(width: 19, alignment: .leading)
                } trailing: { EmptyView() }
                .guideTarget(.cashCard, in: guide)
            } else {
                ZStack(alignment: .topLeading) {
                    // 序号竖着串成一条线：钱从上往下扣
                    if accounts.count > 1 {
                        Rectangle()
                            .fill(Color.cashBlue.opacity(0.45))
                            .frame(width: 1, height: DrawerMetrics.rowHeight * CGFloat(accounts.count - 1))
                            .padding(.leading, 9.5)
                            .padding(.top, DrawerMetrics.rowHeight / 2 + 0.5)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                            accountRow(account, index: index)
                        }
                    }
                }
                .sensoryFeedback(.selection, trigger: reorder.dropIndex(in: accounts.map(\.id)))
            }
            if canManage || accounts.isEmpty {
                DrawerAddRow(title: accounts.isEmpty ? "拆成多个账户" : "添加账户", showsPro: !canManage,
                             identifier: "add-cash-account", action: startAdding)
            }
            if !accounts.isEmpty && !canManage {
                DrawerFooter(text: "账户管理是 Pro 功能。记支出仍按这个顺序扣，暂时只能查看。", locked: true,
                             onPro: { showingPro = true }, onMerge: { confirmingMerge = true },
                             mergeID: "merge-cash-accounts")
            } else if accounts.isEmpty {
                DrawerFooter(text: "活期、微信、支付宝里随时能花的钱。")
            } else if accounts.count > 1 {
                DrawerFooter(text: "记支出整笔扣第一个够付的账户，拖右边调整先后。")
            }
        }
        .saveErrorAlert($saveError)
        .sheet(isPresented: $editingTotal, onDismiss: {
            if splitAfterTotalSheet {
                splitAfterTotalSheet = false
                startAdding()
            }
        }) {
            EditBucketSheet(bucket: .cash, currentAmount: total, onSave: { value in
                try LedgerStore.updateAssets(in: modelContext) { assets in
                    assets.cash = value
                    assets.updatedAt = .now
                }
            }, onOpenItems: { splitAfterTotalSheet = true })
        }
        .sheet(item: $adding) { adding in
            CashAccountSheet(existing: nil, sources: sources, initialSource: adding.initialSource) { name, amount, source in
                try CashAccountStore.save(nil, name: name, amount: amount, source: source, in: modelContext)
            }
        }
        .sheet(item: $editing) { account in
            CashAccountSheet(existing: account, onSave: { name, amount, _ in
                try CashAccountStore.save(account, name: name, amount: amount, in: modelContext)
            }, onDelete: {
                try CashAccountStore.delete(account, in: modelContext)
            })
        }
        .sheet(isPresented: $showingPro) { ProPaywallView() }
        .confirmationDialog("合并成一个总数？", isPresented: $confirmingMerge, titleVisibility: .visible) {
            Button("合并", role: .destructive) {
                do { try CashAccountStore.mergeIntoTotal(in: modelContext) }
                catch { saveError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("各账户会删除，现金总数 ¥\(total.formatted(.number)) 不变，之后直接改总数。")
        }
    }

    // MARK: - 一行账户

    private func accountRow(_ account: CashAccount, index: Int) -> some View {
        let ids = accounts.map(\.id)
        return DrawerRow(name: account.name, amount: account.amount, enabled: canManage,
                         identifier: "cash-account-\(account.name)", onTap: { editing = account }) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.skyDeep)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.mist))
                .overlay(Circle().stroke(Color.cashBlue, lineWidth: 1))
                .frame(width: 30, alignment: .leading)
                .accessibilityLabel("第 \(index + 1) 个扣")
        } trailing: {
            if canManage && accounts.count > 1 {
                ReorderHandle(id: account.id, index: index, ids: ids, label: "调整\(account.name)的扣款顺序",
                              identifier: "reorder-\(account.name)", reorder: $reorder) { target in
                    move(account, to: target)
                }
            }
        }
        .reorderable(reorder, id: account.id, index: index, ids: ids)
    }

    private func move(_ account: CashAccount, to index: Int) {
        do { try CashAccountStore.move(account, to: index, in: modelContext) }
        catch { saveError = error.localizedDescription }
    }

    private var sources: [CashAccountSheet.SourceOption] {
        if accounts.isEmpty {
            return total > 0 ? [.init(source: .unsplitTotal, name: "现金", amount: total)] : []
        }
        return accounts.filter { $0.amount > 0 }.map { .init(source: .account($0.id), name: $0.name, amount: $0.amount) }
    }

    private func startAdding() {
        guard canManage else {
            showingPro = true
            return
        }
        adding = AddingAccount(initialSource: accounts.isEmpty && total > 0 ? .unsplitTotal : nil)
    }
}
