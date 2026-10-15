// 资产页面：净值、双桶、资产明细或总开关、被动收入、每月还款和调拨。导出、导入、清空在 Settings 的数据管理页。

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AssetsView: View {
    @Query private var assetsArr: [UserAssets]
    @Query private var expenses: [Expense]              // 算 dailyBurn 用
    @Query private var passiveSources: [PassiveSource]  // 被动收入源
    @Query(sort: [SortDescriptor(\AssetItem.sortOrder), SortDescriptor(\AssetItem.createdAt)])
    private var assetItems: [AssetItem]                 // Pro 资产逐项：免费用户永远是空
    @Query(sort: [SortDescriptor(\Loan.sortOrder), SortDescriptor(\Loan.createdAt)])
    private var loans: [Loan]                           // Pro 每月还款
    @Environment(\.modelContext) private var modelContext
    /// 起步引导要圈出现金卡
    @Environment(AppGuide.self) private var guide

    // --- 双桶编辑 (sheet 模式) ---
    @State private var saveError: String?
    @State private var editingBucket: EditBucketSheet.Bucket? = nil
    /// 拆成多项之后，调拨要选是哪一项
    @State private var transferItemID: UUID?

    // --- 调拨 ---
    @State private var transferAmount: String = ""
    @State private var transferDirection: TransferDirection = .cashToAssets
    @FocusState private var transferFocused: Bool   // decimalPad 无 return 键, 靠点空白处 / 下拉滚动收起

    enum TransferDirection: String, CaseIterable {
        case cashToAssets = "现金 → 资产"
        case assetsToCash = "资产 → 现金"
    }

    // --- 资产明细 (Pro) ---
    @State private var addingItem: AddingItem? = nil
    @State private var editingItem: AssetItem? = nil
    @State private var pendingDeleteItem: AssetItem? = nil
    @State private var confirmingMergeItems = false
    @State private var showingPro = false
    /// 在编辑资产的弹窗里点了「拆成多项」：等弹窗收起再开添加弹窗
    @State private var splitAfterBucketSheet = false

    /// 打开「添加资产项」：拆分时默认从原来的总数里拆
    struct AddingItem: Identifiable {
        let id = UUID()
        let initialSource: AssetItemStore.Source?
    }

    // --- 被动收入 ---
    @State private var showingAddPassive: Bool = false
    @State private var editingPassiveSource: PassiveSource? = nil
    @State private var pendingDeletePassive: PassiveSource? = nil

    // --- 每月还款 ---
    @State private var showingAddLoan = false
    @State private var editingLoan: Loan? = nil
    @State private var pendingDeleteLoan: Loan? = nil
    /// 没扣成的那一期，等用户选「从现金扣」还是「从别处还的」
    @State private var resolvingPayment: PendingPayment? = nil

    struct PendingPayment: Identifiable {
        let loan: Loan
        let dueDate: Date
        var id: String { "\(loan.id)-\(dueDate.timeIntervalSince1970)" }
    }

    // --- 自由天数口径 ---
    @AppStorage(FreedomSettings.countsAssetsKey, store: AppPreferences.store) private var countsAssets = true

    // --- 说明与调拨默认收起 ---
    @State private var showingExplain = false
    @State private var transferExpanded = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                        .id(Self.topID)
                    bucketCards
                        .guideTarget(.buckets, in: guide)
                    if assetItems.isEmpty { countsAssetsCard } else { holdingsCard }
                    if showEmptyHint { emptyHintCard }
                    passiveCard
                        .guideTarget(.passive, in: guide)
                    if ProFeatures.canManageLoans || !loans.isEmpty {
                        loansCard
                            .guideTarget(.loans, in: guide)
                    }
                }
                .padding()
                // 点击卡片之外的空白处收起调拨键盘(decimalPad 无 return 键)。
                // contentShape 让空白区也可命中; 子控件(按钮/Picker/输入框)优先级更高, 不受影响。
                .contentShape(Rectangle())
                .onTapGesture { transferFocused = false }
            }
            // 「Assets 怎么用」: 收起展开的东西、回到顶部, 等位置排好再开始
            .task(id: guide.replays(of: .assets)) {
                guard guide.takeReplay(.assets) else { return }
                transferExpanded = false
                showingExplain = false
                transferFocused = false
                scroller.scrollTo(Self.topID, anchor: .top)
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, editingBucket == nil, !showingAddPassive, editingPassiveSource == nil else { return }
                withAnimation(.easeInOut(duration: 0.25)) { guide.start(.assets) }
            }
            }
            .scrollContentBackground(.hidden)
            .dismissKeyboardOnScroll()
            .background(Color.paper)
            .navigationTitle("Assets")
            .saveErrorAlert($saveError)
            .sheet(item: $editingBucket, onDismiss: {
                if splitAfterBucketSheet {
                    splitAfterBucketSheet = false
                    startSplit()
                }
            }) { bucket in
                EditBucketSheet(
                    bucket: bucket,
                    currentAmount: amountFor(bucket: bucket),
                    onSave: { newAmount in
                        try applyBucketEdit(bucket: bucket, newAmount: newAmount)
                    },
                    onOpenItems: bucket == .assets ? { splitAfterBucketSheet = true } : nil
                )
            }
            .sheet(item: $addingItem) { adding in
                AssetItemSheet(existing: nil, sources: itemSources, initialSource: adding.initialSource) {
                    name, amount, counts, source in
                    try AssetItemStore.save(nil, name: name, amount: amount, countsInFreedom: counts,
                                            source: source, totalCounts: countsAssets, in: modelContext)
                    // 拆开以后由各项自己决定，总开关回到默认，免得以后合并回去时带着旧状态
                    countsAssets = true
                }
            }
            .sheet(item: $editingItem) { item in
                AssetItemSheet(existing: item) { name, amount, counts, _ in
                    try AssetItemStore.save(item, name: name, amount: amount, countsInFreedom: counts, in: modelContext)
                }
            }
            .sheet(isPresented: $showingPro) { ProPaywallView() }
            .alert(
                "删除这一项资产?",
                isPresented: Binding(
                    get: { pendingDeleteItem != nil },
                    set: { if !$0 { pendingDeleteItem = nil } }
                ),
                presenting: pendingDeleteItem
            ) { item in
                Button("删除", role: .destructive) { deleteItem(item) }
                Button("取消", role: .cancel) { pendingDeleteItem = nil }
            } message: { item in
                Text("\(item.name) · ¥\(item.amount.formatted(.number))\n资产总数会少这么多。")
            }
            .confirmationDialog("合并成一个总数？", isPresented: $confirmingMergeItems, titleVisibility: .visible) {
                Button("合并", role: .destructive) { mergeItems() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("各项会删除，资产总数 ¥\(lockedAssetsAmount.formatted(.number)) 不变，之后在资产页直接改总数。")
            }
            .sheet(isPresented: $showingAddPassive) {
                PassiveSourceSheet(existing: nil) { name, monthly in
                    try LedgerStore.savePassiveSource(nil, name: name, monthlyAmount: monthly, in: modelContext)
                }
            }
            .sheet(item: $editingPassiveSource) { source in
                PassiveSourceSheet(existing: source) { name, monthly in
                    try LedgerStore.savePassiveSource(source, name: name, monthlyAmount: monthly, in: modelContext)
                }
            }
            .alert(
                "删除这个被动收入源?",
                isPresented: Binding(
                    get: { pendingDeletePassive != nil },
                    set: { if !$0 { pendingDeletePassive = nil } }
                ),
                presenting: pendingDeletePassive
            ) { src in
                Button("删除", role: .destructive) {
                    do {
                        try LedgerStore.perform(in: modelContext) { modelContext.delete(src) }
                        pendingDeletePassive = nil
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                Button("取消", role: .cancel) { pendingDeletePassive = nil }
            } message: { src in
                Text("\(src.name) · 月入 ¥\(FinancialFormatting.wholeNumber(src.monthlyAmount))\n删除后被动覆盖率会下降。")
            }
            .sheet(isPresented: $showingAddLoan) { LoanSheet(existing: nil) }
            .sheet(item: $editingLoan) { LoanSheet(existing: $0) }
            .alert(
                "删除这笔每月还款?",
                isPresented: Binding(
                    get: { pendingDeleteLoan != nil },
                    set: { if !$0 { pendingDeleteLoan = nil } }
                ),
                presenting: pendingDeleteLoan
            ) { loan in
                Button("删除", role: .destructive) {
                    do {
                        try LoanStore.delete(loan, in: modelContext)
                        pendingDeleteLoan = nil
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                Button("取消", role: .cancel) { pendingDeleteLoan = nil }
            } message: { loan in
                Text("\(loan.name) · 每月 ¥\(FinancialFormatting.wholeNumber(loan.monthlyAmount))\n已经扣过的月供留在 History。")
            }
            .confirmationDialog(
                resolvingPayment.map { "\(Self.monthDay($0.dueDate))这期 ¥\(FinancialFormatting.wholeNumber($0.loan.monthlyAmount))" } ?? "",
                isPresented: Binding(
                    get: { resolvingPayment != nil },
                    set: { if !$0 { resolvingPayment = nil } }
                ),
                titleVisibility: .visible,
                presenting: resolvingPayment
            ) { payment in
                Button("从现金扣") { resolve(payment, fromCash: true) }
                Button("从别处还的，不动现金") { resolve(payment, fromCash: false) }
                Button("取消", role: .cancel) { resolvingPayment = nil }
            } message: { _ in
                Text("到期那天现金不够，没有自动扣。")
            }
        }
    }

    private static let topID = "assets-top"

    // MARK: - Hero: 净值总览
    private var heroCard: some View {
        VaultCard(emphasis: .high, padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "Net Worth · 净值")
                    Spacer()
                    // 净值、资产、现金的关系看懂一次就够了, 平时收在问号里
                    Button {
                        withAnimation(.snappy(duration: 0.32)) { showingExplain.toggle() }
                    } label: {
                        Image(systemName: showingExplain ? "questionmark.circle.fill" : "questionmark.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(showingExplain ? Color.skyDeep : Color.inkFaint)
                            .frame(width: 32, height: 32, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("assets-explain-toggle")
                    .accessibilityLabel("净值、资产和现金是什么")
                    .accessibilityValue(showingExplain ? "已展开" : "已收起")
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("¥" + currentNetWorth.formatted(.number))
                        .font(.system(size: 44, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    bucketRatioBar
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .guideTarget(.netWorth, in: guide)

                if let updated = assetsArr.first?.updatedAt, currentNetWorth > 0 {
                    Text("上次更新 · \(Self.relativeFormatter.localizedString(for: updated, relativeTo: .now))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                } else {
                    Text("点击下方桶卡片录入金额")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }

                if showingExplain {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Hairline()
                        Text("净值 = 资产 + 现金，是自动相加的结果，不能直接修改。资产（金色）是锁定的钱，比如定期、股票、基金；现金（蓝色）是可花的钱。收入默认进现金，支出从现金扣。资产和现金之间用「调拨」移动。")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }

                // 调拨是在资产和现金之间挪钱, 净值不变: 收在净值卡底部,
                // 和首页大数字卡里的趋势行是同一种交互 (一行摘要常驻, 点整行展开)
                Hairline().padding(.top, Spacing.xs)
                transferSection
            }
        }
    }

    /// 时间固定用中文 (「25分钟前」), 不跟系统语言走成英文
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateTimeStyle = .named
        return formatter
    }()

    /// 净值里资产和现金各占多少: 金色段是资产, 蓝色段是现金, 和首页格子的两种颜色是同一回事。
    /// 有一桶是负数时比例没有意义, 不画。
    @ViewBuilder
    private var bucketRatioBar: some View {
        if currentNetWorth > 0, lockedAssetsAmount >= 0, cashAmount >= 0 {
            GeometryReader { geo in
                let gap: CGFloat = (lockedAssetsAmount > 0 && cashAmount > 0) ? 3 : 0
                let assetsWidth = (geo.size.width - gap) * CGFloat(lockedAssetsAmount / currentNetWorth)
                HStack(spacing: gap) {
                    if lockedAssetsAmount > 0 {
                        Capsule().fill(Color.assetGold).frame(width: max(assetsWidth, 3))
                    }
                    if cashAmount > 0 {
                        Capsule().fill(Color.cashBlue)
                    }
                }
            }
            .frame(height: 3)
            .animation(.snappy(duration: 0.32), value: lockedAssetsAmount)
            .animation(.snappy(duration: 0.32), value: cashAmount)
            .accessibilityElement()
            .accessibilityLabel("资产占 \(FinancialFormatting.percentage(lockedAssetsAmount / currentNetWorth))，现金占 \(FinancialFormatting.percentage(cashAmount / currentNetWorth))")
        }
    }

    // MARK: - 自由天数口径: 资产算不算 (没拆分时)
    // 资产只有一个总数时，整笔算或整笔不算；想只算其中几项，拆成多项（Pro）后在资产明细里逐项选。
    private var countsAssetsCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Toggle(isOn: $countsAssets) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("资产计入自由天数")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Text(countsAssets ? "自由天数按资产加现金算。" : "自由天数只按现金算，资产仍在净值里。")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                    }
                }
                .tint(Color.skyDeep)
                .accessibilityIdentifier("counts-assets-toggle")

                Hairline()
                Button(action: startSplit) {
                    HStack(spacing: Spacing.sm) {
                        Text("只算其中几项？拆成多项")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        if !ProFeatures.canManageAssetItems {
                            Text("PRO")
                                .font(.system(.caption2, design: .monospaced))
                                .tracking(2)
                                .foregroundStyle(Color.skyDeep)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.inkGhost)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("split-assets-from-switch")
            }
        }
    }

    // MARK: - 资产明细 (拆成多项之后, 代替总开关)
    // 每一项前面一个方格：金色实心 = 算进自由天数（就是首页的金色格子），空心 = 只算净值。点方格切换，点名字编辑。
    private var holdingsCard: some View {
        let canManage = ProFeatures.canManageAssetItems
        let counted = assetItems.filter(\.countsInFreedom).reduce(0) { $0 + $1.amount }
        let allCounted = assetItems.allSatisfy(\.countsInFreedom)
        return VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "Holdings · 资产明细")
                    Spacer()
                    if canManage {
                        Button {
                            addingItem = AddingItem(initialSource: nil)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.skyDeep)
                                .frame(width: 24, height: 24)
                                .background(Circle().stroke(Color.skyDeep.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("添加资产项")
                        .accessibilityIdentifier("add-asset-item")
                    }
                }

                VStack(spacing: 0) {
                    ForEach(assetItems) { item in
                        holdingRow(item, canManage: canManage)
                        if item.id != assetItems.last?.id {
                            Hairline().padding(.leading, 4)
                        }
                    }
                }

                Hairline()
                if canManage {
                    Text(allCounted
                         ? "全部计入自由天数 · 点方格可以不算某一项"
                         : "计入自由天数 ¥\(counted.formatted(.number)) · 点方格切换")
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                        .accessibilityIdentifier("holdings-counted-summary")
                } else {
                    lockedHoldingsNote
                }
            }
        }
    }

    private func holdingRow(_ item: AssetItem, canManage: Bool) -> some View {
        let counts = item.countsInFreedom
        // 方格和名字的位置与被动收入、每月还款的行对齐（9pt 记号 + 10pt 间距）
        return HStack(spacing: 0) {
            Button {
                toggleCounts(item)
            } label: {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(counts ? Color.assetGold : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .strokeBorder(counts ? Color.clear : Color.inkFaint, lineWidth: 1)
                    )
                    .frame(width: 9, height: 9)
                    .frame(width: 19, height: 36, alignment: .leading)
                    // 记号很小，点按范围往外放一圈
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.plain)
            // 没有 Pro 时只看不改；不用 disabled，免得整行变灰看不清
            .allowsHitTesting(canManage)
            .accessibilityLabel("\(item.name)计入自由天数")
            .accessibilityValue(counts ? "计入" : "不计入")
            .accessibilityAddTraits(.isToggle)
            .accessibilityIdentifier("asset-item-counts-\(item.name)")

            Button {
                if canManage { editingItem = item }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(counts ? Color.ink : Color.inkMuted)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.sm)
                    Text("¥" + item.amount.formatted(.number))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(counts ? Color.inkMuted : Color.inkFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(canManage)
            .accessibilityIdentifier("asset-item-\(item.name)")

            if canManage {
                Button {
                    pendingDeleteItem = item
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                        .frame(width: 22, height: 22)
                        .background(Circle().stroke(Color.hairlineSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .accessibilityLabel("删除\(item.name)")
                .accessibilityIdentifier("delete-asset-item-\(item.name)")
            }
        }
        .padding(.vertical, 2)
        .animation(.snappy(duration: 0.24), value: counts)
    }

    /// 拆过但没有 Pro：各项照常算，只是不能改；给出两条路
    private var lockedHoldingsNote: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("逐项管理是 Pro 功能，各项照常计算，暂时只能查看。")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.lg) {
                Button("了解 Pro") { showingPro = true }
                    .accessibilityIdentifier("open-pro-from-assets")
                Button("合并成一个总数") { confirmingMergeItems = true }
                    .accessibilityIdentifier("merge-asset-items")
            }
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(Color.skyDeep)
            .buttonStyle(.plain)
        }
    }

    /// 可以从中拆出新一项的地方：没拆过时是原来的总数，拆过以后是各项
    private var itemSources: [AssetItemSheet.SourceOption] {
        if assetItems.isEmpty {
            return lockedAssetsAmount > 0
                ? [.init(source: .unsplitTotal, name: "资产", amount: lockedAssetsAmount)] : []
        }
        return assetItems.filter { $0.amount > 0 }
            .map { .init(source: .item($0.id), name: $0.name, amount: $0.amount) }
    }

    /// 「拆成多项」：有 Pro 时直接加第一项（默认从原来的总数里拆），没有时看 Pro
    private func startSplit() {
        guard ProFeatures.canManageAssetItems else {
            showingPro = true
            return
        }
        addingItem = AddingItem(initialSource: lockedAssetsAmount > 0 && assetItems.isEmpty ? .unsplitTotal : nil)
    }

    private func toggleCounts(_ item: AssetItem) {
        do { try AssetItemStore.setCountsInFreedom(!item.countsInFreedom, for: item, in: modelContext) }
        catch { saveError = error.localizedDescription }
    }

    private func deleteItem(_ item: AssetItem) {
        do {
            try AssetItemStore.delete(item, in: modelContext)
            pendingDeleteItem = nil
            // 删到一项不剩就回到总开关；它在拆分期间不起作用，回到默认的开
            if (try? AssetItemStore.items(in: modelContext))?.isEmpty == true { countsAssets = true }
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// 合并回一个总数：只要有一项算着，总开关就开；一项都没算才关
    private func mergeItems() {
        let anyCounted = assetItems.contains { $0.countsInFreedom && $0.amount > 0 }
        do {
            try AssetItemStore.mergeIntoTotal(in: modelContext)
            countsAssets = anyCounted || lockedAssetsAmount == 0
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - 双桶: 资产 + 现金 (点击弹 sheet 编辑)
    private var bucketCards: some View {
        HStack(spacing: 12) {
            bucketCard(
                bucket: .assets,
                kicker: "资产",
                amount: lockedAssetsAmount,
                color: .assetGold,
                icon: "lock.fill"
            )
            bucketCard(
                bucket: .cash,
                kicker: "现金",
                amount: cashAmount,
                color: .cashBlue,
                icon: "banknote"
            )
            .guideTarget(.cashCard, in: guide)
        }
    }

    private func bucketCard(bucket: EditBucketSheet.Bucket, kicker: String, amount: Double, color: Color, icon: String) -> some View {
        // 资产已经拆成多项时，总数是各项相加，在下面的资产明细里改，这张卡不再能点
        let splitIntoItems = bucket == .assets && !assetItems.isEmpty
        return Button {
            editingBucket = bucket
        } label: {
            VaultCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 11))
                            .foregroundStyle(color)
                        KickerLabel(text: splitIntoItems ? "\(kicker) · \(assetItems.count) 项" : kicker)
                        Spacer()
                        if !splitIntoItems {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                    Text("¥" + amount.formatted(.number))
                        .font(.system(size: 24, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!splitIntoItems)
        .accessibilityIdentifier(bucket == .assets ? "assets-bucket-card" : "cash-bucket-card")
        .accessibilityLabel(splitIntoItems ? kicker : "编辑\(kicker)")
        // Button 会把 label 里的 Text 合并成一个元素,再被 accessibilityLabel 整体顶掉;
        // 金额得单独挂回 value,否则 VoiceOver 只念"编辑现金",听不到余额。
        .accessibilityValue("¥" + amount.formatted(.number))
    }

    // MARK: - 空态提示
    private var showEmptyHint: Bool {
        currentNetWorth == 0
    }

    private var emptyHintCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 13))
                .foregroundStyle(Color.skyDeep)
            Text("点击上方桶卡片录入金额, 净值会自动相加")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
            Spacer()
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.skyFaint)
        )
    }

    // MARK: - 被动收入卡片
    // 顶部 kicker + "+" / 大数字覆盖率 / 月入·日均 subtitle / 已有源列表(每行 × 删除, 点行编辑)
    private var passiveCard: some View {
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: passiveSources,
                                         assets: assetsArr.first, assetItems: assetItems)
        return VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "Passive · 被动收入")
                    Spacer()
                    Button {
                        showingAddPassive = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.skyDeep)
                            .frame(width: 24, height: 24)
                            .background(Circle().stroke(Color.skyDeep.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加被动收入源")
                }

                // 大数字: 覆盖率
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(FinancialFormatting.wholeNumber((snapshot.passiveRatio * 100).rounded()))
                        .font(.system(size: 44, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(snapshot.passiveRatio >= 1 ? Color.mossGreen : Color.ink)
                    Text("%")
                        .font(.system(size: 20, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                    Spacer()
                    Text(snapshot.passiveRatio >= 1 ? "已覆盖日常消费" : "覆盖日常消费")
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(snapshot.passiveRatio >= 1 ? Color.mossGreen : Color.inkFaint)
                }

                // subtitle: 月入 + 日均
                if !passiveSources.isEmpty {
                    HStack(spacing: 8) {
                        Text("月入 ¥\(FinancialFormatting.wholeNumber(snapshot.dailyPassive * 30))")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        Text("·")
                            .foregroundStyle(Color.inkFaint)
                        Text("日均 ¥\(String(format: "%.1f", snapshot.dailyPassive))")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        if snapshot.dailyBurn > 0 {
                            Text("·")
                                .foregroundStyle(Color.inkFaint)
                            Text("日均消费 ¥\(String(format: "%.1f", snapshot.dailyBurn))")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                } else {
                    Text("还没有被动收入源, 点击右上 + 添加")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }

                // 源列表
                if !passiveSources.isEmpty {
                    Hairline()
                    ForEach(passiveSources) { source in
                        passiveSourceRow(source)
                        if source.id != passiveSources.last?.id {
                            Hairline().padding(.leading, 4)
                        }
                    }
                }
            }
        }
    }

    private func passiveSourceRow(_ s: PassiveSource) -> some View {
        HStack(spacing: 10) {
            Button {
                editingPassiveSource = s
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mossGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.ink)
                        Text("¥\(FinancialFormatting.wholeNumber(s.monthlyAmount))/月 · ¥\(s.monthlyAmount.isFinite ? String(format: "%.1f", s.monthlyAmount / 30) : "—")/天")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.inkFaint)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                pendingDeletePassive = s
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
                    .frame(width: 22, height: 22)
                    .background(Circle().stroke(Color.hairlineSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除这个被动源")
        }
        .padding(.vertical, 6)
    }

    // MARK: - 每月还款 (Pro)

    private var loansCard: some View {
        let payments = expenses.filter { $0.loanID != nil }
        let statuses = loans.map { LoanSchedule.status(of: $0, payments: payments) }
        let active = zip(loans, statuses).filter { !$0.1.isPaidOff }
        let monthlyTotal = active.reduce(0) { $0 + $1.0.monthlyAmount }
        let nextDue = active.compactMap { $0.1.nextDue }.min()
        return VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "Repay · 每月还款")
                    Spacer()
                    if ProFeatures.canManageLoans {
                        Button {
                            showingAddLoan = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.skyDeep)
                                .frame(width: 24, height: 24)
                                .background(Circle().stroke(Color.skyDeep.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("添加每月还款")
                        .accessibilityIdentifier("add-loan-button")
                    }
                }

                if loans.isEmpty {
                    Text("有房贷车贷？点右上 + 添加")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(FinancialFormatting.wholeNumber(monthlyTotal))
                            .font(.system(size: 44, weight: .ultraLight, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.ink)
                        Text("/月")
                            .font(.system(size: 20, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        Spacer()
                        if let nextDue {
                            Text("下次 \(Self.monthDay(nextDue))")
                                .font(.system(.caption2, design: .monospaced))
                                .tracking(0.5)
                                .foregroundStyle(Color.inkFaint)
                        }
                    }

                    Hairline()
                    ForEach(Array(zip(loans, statuses)), id: \.0.id) { loan, status in
                        loanRow(loan, status: status)
                        if loan.id != loans.last?.id {
                            Hairline().padding(.leading, 4)
                        }
                    }
                }
            }
        }
    }

    private func loanRow(_ loan: Loan, status: LoanSchedule.Status) -> some View {
        VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 10) {
            Button {
                if ProFeatures.canManageLoans { editingLoan = loan }
            } label: {
                HStack(spacing: 10) {
                    // 和首页格子上的还款日同一个记号
                    PunchedCell(cornerRadius: 1.5)
                        .fill(status.isPaidOff ? Color.inkGhost : Color.cashBlue, style: FillStyle(eoFill: true))
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(loan.name)
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(status.isPaidOff ? Color.inkMuted : Color.ink)
                            Spacer()
                            Text("−¥\(FinancialFormatting.wholeNumber(loan.monthlyAmount))/月")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(status.isPaidOff ? Color.inkFaint : Color.inkMuted)
                        }
                        if status.pending.isEmpty {
                            Text(status.isPaidOff ? "已还清" : "每月 \(loan.dueDay) 日 · 还剩 \(status.remaining) 期")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("loan-row")

            Button {
                pendingDeleteLoan = loan
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
                    .frame(width: 22, height: 22)
                    .background(Circle().stroke(Color.hairlineSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除这笔每月还款")
        }
            if let due = status.pending.first {
                Button {
                    resolvingPayment = PendingPayment(loan: loan, dueDate: due)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(Self.monthDay(due))这期没扣：现金不够")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        Text("处理")
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .foregroundStyle(Color.skyDeep)
                        Spacer()
                    }
                    .padding(.leading, 19)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("loan-pending")
            }
        }
        .padding(.vertical, 6)
    }

    private func resolve(_ payment: PendingPayment, fromCash: Bool) {
        do {
            try LoanStore.resolvePending(payment.loan, dueDate: payment.dueDate, fromCash: fromCash, in: modelContext)
            resolvingPayment = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// 「11月14日」
    static func monthDay(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)月\(parts.day ?? 0)日"
    }

    // MARK: - 调拨 (净值卡底部, 默认收起)
    @ViewBuilder
    private var transferSection: some View {
        Button {
            withAnimation(.snappy(duration: 0.32)) { transferExpanded.toggle() }
            if !transferExpanded { transferFocused = false }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("调拨")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                Spacer()
                Text("资产 ⇄ 现金")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
                    .rotationEffect(.degrees(transferExpanded ? 180 : 0))
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .guideTarget(.transfer, in: guide)
        .accessibilityIdentifier("transfer-toggle")
        .accessibilityLabel("调拨，在资产和现金之间移动")
        .accessibilityValue(transferExpanded ? "已展开" : "已收起")

        if transferExpanded {
            Group {
                if !assetItems.isEmpty && !ProFeatures.canManageAssetItems {
                    lockedTransferNote
                } else {
                    transferForm
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }

    /// 拆成多项之后没有 Pro：调拨要改某一项的金额，这是 Pro 的事；先说清楚，再给出路
    private var lockedTransferNote: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("资产已经拆成多项，调拨要改其中某一项，需要 Pro。也可以在下面的资产明细里合并成一个总数，再用原来的调拨。")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button { showingPro = true } label: {
                Text("了解 Pro")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.skyDeep)
                    .padding(.vertical, Spacing.xs)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Spacing.xs)
    }

    /// 有资产项时调拨的资产一端落在哪一项；只有一项时不用选
    private var transferItem: AssetItem? {
        guard !assetItems.isEmpty else { return nil }
        return assetItems.first { $0.id == transferItemID } ?? assetItems.first
    }

    /// 从哪一桶到哪一桶 (右边的圆钮对调方向) → 金额 → 确认
    private var transferForm: some View {
        let fromCash = transferDirection == .cashToAssets
        let assetSide = transferItem?.name ?? "资产"
        let available = max(0, fromCash ? cashAmount : (transferItem?.amount ?? lockedAssetsAmount))
        let entered = Double(transferAmount) ?? 0
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                transferBucketLabel(isCash: fromCash)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(Color.inkFaint)
                transferBucketLabel(isCash: !fromCash)
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        transferDirection = fromCash ? .assetsToCash : .cashToAssets
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.skyDeep)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.hairline, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("transfer-swap")
                .accessibilityLabel("对调方向")
                .accessibilityValue(transferDirection.rawValue)
            }

            if assetItems.count > 1 {
                HStack(spacing: Spacing.sm) {
                    Text("资产项")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    Spacer()
                    Picker("资产项", selection: Binding(
                        get: { transferItem?.id },
                        set: { transferItemID = $0 }
                    )) {
                        ForEach(assetItems) { item in
                            Text("\(item.name)\(item.countsInFreedom ? "" : " · 未计入") · ¥\(item.amount.formatted(.number))").tag(Optional(item.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.skyDeep)
                    .accessibilityIdentifier("transfer-item-picker")
                }
            }

            UnderlinedField(isFocused: transferFocused, accent: fromCash ? .cashBlue : .assetGold) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("¥")
                        .font(.system(size: 22, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    TextField("0", text: $transferAmount)
                        .decimalKeyboard()
                        .focused($transferFocused)
                        .font(.system(size: 32, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .minimumScaleFactor(0.5)
                }
            }

            // 超过可用金额时实际只会调走这一桶里有的, 提前说清楚
            VStack(alignment: .leading, spacing: 2) {
                Text(entered > available
                     ? "\(fromCash ? "现金" : assetSide)只有 ¥\(available.formatted(.number))，会全部调过去"
                     : "\(fromCash ? "现金" : assetSide)可用 ¥\(available.formatted(.number))")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(entered > available ? Color.flame : Color.inkFaint)
                if let item = transferItem, !item.countsInFreedom {
                    Text("「\(item.name)」未计入自由天数\(fromCash ? "，调入后自由天数会减少" : "")")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.flame)
                }
            }

            VaultButton(title: "确认调拨", icon: "arrow.left.arrow.right", style: .secondary) {
                doTransfer()
            }
            .disabled(entered <= 0)
            .opacity(entered > 0 ? 1.0 : 0.4)
        }
        .padding(.top, Spacing.xs)
    }

    private func transferBucketLabel(isCash: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isCash ? "banknote" : "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(isCash ? Color.cashBlue : Color.assetGold)
            Text(isCash ? "现金" : "资产")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.ink)
        }
    }

    // MARK: - 桶编辑 (sheet 回调)
    private func amountFor(bucket: EditBucketSheet.Bucket) -> Double {
        switch bucket {
        case .assets: return lockedAssetsAmount
        case .cash:   return cashAmount
        }
    }

    private func applyBucketEdit(bucket: EditBucketSheet.Bucket, newAmount: Double) throws {
        // 资产拆成多项后总数是各项之和，不能绕过各项直接改
        if bucket == .assets, !assetItems.isEmpty { throw AssetItemError.hasItems }
        try LedgerStore.updateAssets(in: modelContext) { assets in
            switch bucket {
            case .assets: assets.lockedAssets = newAmount
            case .cash:   assets.cash = newAmount
            }
            assets.updatedAt = .now
        }
    }

    // MARK: - 调拨实现
    private func doTransfer() {
        guard let amt = Double(transferAmount), FinancialFormatting.validAmount(amt),
              let assets = assetsArr.first,
              assets.cash.isFinite, assets.lockedAssets.isFinite else { return }

        do {
            if let item = transferItem {
                // 有资产项：现金和选中的那一项之间调拨，资产总数跟着各项走
                guard ProFeatures.canManageAssetItems else { throw AssetItemError.hasItems }
                try AssetItemStore.transfer(transferDirection == .cashToAssets ? .cashToItem : .itemToCash,
                                            amount: amt, item: item, in: modelContext)
            } else {
                try LedgerStore.updateAssets(in: modelContext) { assets in
                    switch transferDirection {
                    case .cashToAssets:
                        let actual = min(amt, max(0, assets.cash))
                        assets.cash -= actual
                        assets.lockedAssets += actual
                    case .assetsToCash:
                        let actual = min(amt, max(0, assets.lockedAssets))
                        assets.lockedAssets -= actual
                        assets.cash += actual
                    }
                    assets.updatedAt = .now
                }
            }
            transferAmount = ""
            transferFocused = false
            withAnimation(.snappy(duration: 0.32)) { transferExpanded = false }
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - 读写助手
    private var cashAmount: Double {
        assetsArr.first?.cash ?? 0
    }

    private var lockedAssetsAmount: Double {
        assetsArr.first?.lockedAssets ?? 0
    }

    private var currentNetWorth: Double {
        cashAmount + lockedAssetsAmount
    }

}
