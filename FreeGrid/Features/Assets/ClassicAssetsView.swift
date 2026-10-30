// Assets 经典版：净值（按账户分段、调拨）、资产 / 现金 / 每月还款三个抽屉、被动收入。
// 设置 → 外观 → Assets 页面选「经典」时用它；默认是新版 `MoneyTimeAssetsView`。导出、导入、清空在 Settings 的数据管理页。

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ClassicAssetsView: View {
    @Query private var assetsArr: [UserAssets]
    @Query private var expenses: [Expense]              // 算 dailyBurn 用
    @Query private var passiveSources: [PassiveSource]  // 被动收入源
    @Query(sort: [SortDescriptor(\AssetItem.sortOrder), SortDescriptor(\AssetItem.createdAt)])
    private var assetItems: [AssetItem]                 // Pro 资产逐项：免费用户永远是空
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]             // Pro 现金账户
    @Query(sort: [SortDescriptor(\Loan.sortOrder), SortDescriptor(\Loan.createdAt)])
    private var loans: [Loan]                           // 固定支出和贷款
    @Environment(\.modelContext) private var modelContext
    /// 起步引导要圈出现金卡
    @Environment(AppGuide.self) private var guide

    @State private var saveError: String?
    @State private var showingPro = false

    // --- 调拨：从哪到哪 (拆过的一边要选哪一项 / 哪个账户) ---
    @State private var transferAmount: String = ""
    @State private var transferFrom: TransferStore.Place?
    @State private var transferTo: TransferStore.Place?
    @FocusState private var transferFocused: Bool   // decimalPad 无 return 键, 靠点空白处 / 下拉滚动收起

    /// 点净值下面那条线的一段，打开它所在的抽屉
    @AppStorage("assetsDrawerOpen", store: AppPreferences.store) private var assetsDrawerOpen = true
    @AppStorage("cashDrawerOpen", store: AppPreferences.store) private var cashDrawerOpen = true

    // --- 被动收入 ---
    @State private var showingAddPassive: Bool = false
    @State private var editingPassiveSource: PassiveSource? = nil
    @State private var pendingDeletePassive: PassiveSource? = nil

    // --- 自由天数口径 ---
    /// 每月花销：改了要马上重算（0 = 没填），钱包那一行出不出现看它
    @AppStorage(MonthlySpending.key, store: AppPreferences.store) private var monthlySpending = 0.0

    // --- 说明与调拨默认收起 ---
    @State private var showingExplain = false
    @State private var transferExpanded = false

    @Environment(\.tabActivity) private var tabActivity
    @Environment(\.tabDataClock) private var tabDataClock
    @State private var freeze = TabFreezeState()

    /// 在后台时冻住，切回来、或记完账空闲时再按最新的账重画（见 TabFreeze）
    var body: some View {
        TabFreeze(activity: tabActivity, clock: tabDataClock, state: freeze) { page }.equatable()
    }

    @ViewBuilder
    private var page: some View {
        // 读整本账的在这里算好：ScrollViewReader 里的内容会被单独重跑，在那里读 @Query 就冻不住了
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: passiveSources,
                                         assets: assetsArr.first, assetItems: assetItems,
                                         cashAccounts: cashAccounts, loans: ProFeatures.loansInEffect(loans),
                                         monthlySpending: monthlySpending)
        NavigationStack {
            ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                        .id(Self.topID)
                    VStack(spacing: 12) {
                        AssetDrawer()
                        CashDrawer()
                    }
                    .guideTarget(.buckets, in: guide)
                    .id(AppGuide.Target.buckets)
                    if MonthlySpending.showsRow(monthly: snapshot.monthlySpending, hasRecords: snapshot.hasRecords,
                                                gapDays: snapshot.burnGapDays) {
                        MonthlySpendingRow(gapDays: snapshot.burnGapDays)
                    }
                    LoanDrawer()
                        .guideTarget(.loans, in: guide)
                        .id(AppGuide.Target.loans)
                    passiveCard(snapshot)
                        .guideTarget(.passive, in: guide)
                        .id(AppGuide.Target.passive)
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
                guard !Task.isCancelled, !showingAddPassive, editingPassiveSource == nil else { return }
                withAnimation(.easeInOut(duration: 0.25)) { guide.start(.assets) }
            }
            // 讲到下面几张卡时它们可能在屏幕外，先滚过去
            .guideScroll(guide, tour: .assets, scroller: scroller, anchors: [
                .netWorth: (Self.topID, .top), .transfer: (Self.topID, .top),
                .buckets: (AppGuide.Target.buckets, .top),
                .loans: (AppGuide.Target.loans, .center), .passive: (AppGuide.Target.passive, .center),
            ])
            }
            .scrollContentBackground(.hidden)
            .dismissKeyboardOnScroll()
            .background(Color.paper)
            .navigationTitle("钱包")
            .saveErrorAlert($saveError)
            .proPaywall(isPresented: $showingPro, topic: assetItems.isEmpty ? .cash : .assets)
            .sheet(isPresented: $showingAddPassive) {
                PassiveSourceSheet(existing: nil) { name, monthly, interval in
                    try LedgerStore.savePassiveSource(nil, name: name, monthlyAmount: monthly, intervalMonths: interval, in: modelContext)
                }
            }
            .sheet(item: $editingPassiveSource) { source in
                PassiveSourceSheet(existing: source) { name, monthly, interval in
                    try LedgerStore.savePassiveSource(source, name: name, monthlyAmount: monthly, intervalMonths: interval, in: modelContext)
                }
            }
            .alert(
                "删除这个被动收入？",
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
                Text("\(src.name) · 每月 ¥\(FinancialFormatting.wholeNumber(src.monthlyAmount))\n删除后被动覆盖率会下降。")
            }
        }
    }

    private static let topID = "assets-top"

    // MARK: - Hero: 净值总览
    private var heroCard: some View {
        VaultCard(emphasis: .high, padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: String(localized: "Net Worth · 净值"))
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

                    strataBar
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .guideTarget(.netWorth, in: guide)

                if let updated = assetsArr.first?.updatedAt, currentNetWorth > 0 {
                    Text("上次更新 · \(Self.relativeFormatter.localizedString(for: updated, relativeTo: .now))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                } else {
                    Text("在下面的资产、现金里录入金额")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }

                if showingExplain {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Hairline()
                        Text("净值是你记下的资产加现金，自动算出来，没有扣掉还没还完的贷款。其中计入自由天数的部分叫可动用资产，自由天数按它算。资产（金色）是不打算马上花的钱，比如定期、股票；现金（蓝色）是随时能花的钱。记收入进现金，记支出从现金扣；两者之间挪钱用「调拨」。")
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

    /// 时间跟界面语言走 (「25分钟前」/「25 min. ago」)；不用系统地区，免得中文界面里冒出英文
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateTimeStyle = .named
        return formatter
    }()

    /// 净值按账户分段：一项资产或一个现金账户是一段，长短就是它占多少。金色是资产、蓝色是现金，
    /// 和首页格子的两种颜色是同一回事。点一段打开它所在的抽屉。
    /// 不计入自由天数的资产在这里照样全亮：这条线画的是净值，房子也是净值的一部分；算不算自由天数看抽屉里的方格。
    private struct Segment: Identifiable {
        let id: String
        let amount: Double
        let isCash: Bool
    }

    private var segments: [Segment] {
        let assetSegments: [Segment] = assetItems.isEmpty
            ? [Segment(id: "assets", amount: lockedAssetsAmount, isCash: false)]
            : assetItems.map { Segment(id: $0.id.uuidString, amount: $0.amount, isCash: false) }
        let cashSegments: [Segment] = cashAccounts.isEmpty
            ? [Segment(id: "cash", amount: cashAmount, isCash: true)]
            : cashAccounts.map { Segment(id: $0.id.uuidString, amount: $0.amount, isCash: true) }
        return (assetSegments + cashSegments).filter { $0.amount > 0 }
    }

    /// 有一桶是负数时比例没有意义, 不画。
    @ViewBuilder
    private var strataBar: some View {
        let parts = segments
        let total = parts.reduce(0) { $0 + $1.amount }
        if currentNetWorth > 0, lockedAssetsAmount >= 0, cashAmount >= 0, total > 0 {
            GeometryReader { geo in
                let gap: CGFloat = 2
                let usable = geo.size.width - gap * CGFloat(parts.count - 1)
                HStack(spacing: gap) {
                    ForEach(parts) { part in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(part.isCash ? Color.cashBlue : Color.assetGold)
                            .frame(width: max(3, usable * CGFloat(part.amount / total)))
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .contentShape(Rectangle().inset(by: -10))
                .onTapGesture { location in
                    // 点在哪一段：从左往右累加宽度
                    var x: CGFloat = 0
                    for part in parts {
                        x += max(3, usable * CGFloat(part.amount / total)) + gap
                        if location.x < x {
                            withAnimation(.snappy(duration: 0.34)) {
                                if part.isCash { cashDrawerOpen = true } else { assetsDrawerOpen = true }
                            }
                            return
                        }
                    }
                }
            }
            .frame(height: 3)
            .animation(.snappy(duration: 0.32), value: parts.map(\.amount))
            .accessibilityElement()
            .accessibilityLabel("资产占 \(FinancialFormatting.percentage(lockedAssetsAmount / currentNetWorth))，现金占 \(FinancialFormatting.percentage(cashAmount / currentNetWorth))")
        }
    }

    // MARK: - 被动收入卡片
    // 顶部 kicker + "+" / 大数字覆盖率 / 月入·日均 subtitle / 已有源列表(每行 × 删除, 点行编辑)
    private func passiveCard(_ snapshot: FinancialSnapshot) -> some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: String(localized: "Passive · 被动收入"))
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
                    .accessibilityLabel("添加被动收入")
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
                    Text(snapshot.passiveRatio >= 1 ? "已覆盖日均消费" : "覆盖日均消费")
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(snapshot.passiveRatio >= 1 ? Color.mossGreen : Color.inkFaint)
                }

                // subtitle: 月入 + 日均
                if !passiveSources.isEmpty {
                    HStack(spacing: 8) {
                        Text("被动收入 ¥\(FinancialFormatting.wholeNumber(snapshot.dailyPassive * 30))/月")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        Text("·")
                            .foregroundStyle(Color.inkFaint)
                        Text("¥\(String(format: "%.1f", snapshot.dailyPassive))/天")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                        if snapshot.dailyCost > 0 {
                            Text("·")
                                .foregroundStyle(Color.inkFaint)
                            Text("日均消费 ¥\(String(format: "%.1f", snapshot.dailyCost))")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Color.inkFaint)
                        }
                    }
                } else {
                    Text("还没有被动收入，点右上角 + 添加")
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
                        Text((s.intervalNote.map { $0 + " · " } ?? "") + String(localized: "¥\(FinancialFormatting.wholeNumber(s.monthlyAmount))/月 · ¥\(s.monthlyAmount.isFinite ? String(format: "%.1f", s.monthlyAmount / 30) : "—")/天"))
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
            .accessibilityLabel("删除这个被动收入")
        }
        .padding(.vertical, 6)
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
                if transferLocked {
                    lockedTransferNote
                } else {
                    transferForm
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }

    /// 拆过的一边没有 Pro：调拨要改其中某一项或某个账户的金额，这是 Pro 的事；先说清楚，再给出路
    private var lockedTransferNote: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("拆开以后，调拨要 Pro。也可以先合并成一个总数，再调拨。")
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

    private var transferLocked: Bool {
        (!assetItems.isEmpty && !ProFeatures.canManageAssetItems)
            || (!cashAccounts.isEmpty && !ProFeatures.canManageCashAccounts)
    }

    /// 调拨能选的地方：没拆的一边是那个总数，拆了的一边是各项 / 各账户
    private struct PlaceOption: Identifiable {
        let place: TransferStore.Place
        let name: String
        let amount: Double
        var id: TransferStore.Place { place }
    }

    private var cashPlaces: [PlaceOption] {
        cashAccounts.isEmpty
            ? [PlaceOption(place: .cashTotal, name: String(localized: "现金"), amount: cashAmount)]
            : cashAccounts.map { PlaceOption(place: .cashAccount($0.id), name: $0.name, amount: $0.amount) }
    }

    private var assetPlaces: [PlaceOption] {
        assetItems.isEmpty
            ? [PlaceOption(place: .assetsTotal, name: String(localized: "资产"), amount: lockedAssetsAmount)]
            : assetItems.map { PlaceOption(place: .assetItem($0.id), name: $0.name, amount: $0.amount) }
    }

    /// 选过的地方还在就用它，不在了（删了、合并了）就回到默认：现金第一个 → 资产第一个
    private var fromPlace: PlaceOption {
        let all = cashPlaces + assetPlaces
        return all.first { $0.place == transferFrom } ?? cashPlaces[0]
    }

    private var toPlace: PlaceOption {
        let all = cashPlaces + assetPlaces
        if let picked = all.first(where: { $0.place == transferTo }), picked.place != fromPlace.place { return picked }
        // 默认调进第一个算自由天数的资产项，不往房、车这类不计入的里调
        guard fromPlace.place.isCash else {
            let countedCash = Set(cashAccounts.filter(\.countsInFreedom).map { TransferStore.Place.cashAccount($0.id) })
            return cashPlaces.first { countedCash.contains($0.place) } ?? cashPlaces[0]
        }
        let counted = Set(assetItems.filter(\.countsInFreedom).map { TransferStore.Place.assetItem($0.id) })
        return assetPlaces.first { counted.contains($0.place) } ?? assetPlaces[0]
    }

    /// 从哪 → 到哪（右边的圆钮对调）→ 金额 → 确认
    private var transferForm: some View {
        let from = fromPlace
        let to = toPlace
        let entered = Double(transferAmount) ?? 0
        let available = max(0, from.amount)
        let uncountedDestination = TransferStore.uncountedDestinationName(from: from.place, to: to.place,
                                                                          assetItems: assetItems, cashAccounts: cashAccounts)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                placeMenu(selected: from, identifier: "transfer-from-menu") { transferFrom = $0 }
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .light))
                    .foregroundStyle(Color.inkFaint)
                placeMenu(selected: to, excluding: from.place, identifier: "transfer-to-menu") { transferTo = $0 }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        (transferFrom, transferTo) = (to.place, from.place)
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
                .accessibilityValue("\(from.name) → \(to.name)")
            }

            UnderlinedField(isFocused: transferFocused, accent: from.place.isCash ? .cashBlue : .assetGold) {
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
                        .accessibilityIdentifier("transfer-amount-field")
                }
            }

            // 超过可用金额时实际只会调走这一处有的, 提前说清楚
            VStack(alignment: .leading, spacing: 2) {
                Text(entered > available
                     ? "「\(from.name)」只有 ¥\(available.formatted(.number))，会全部调过去"
                     : "「\(from.name)」可用 ¥\(available.formatted(.number))")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(entered > available ? Color.flame : Color.inkFaint)
                if let name = uncountedDestination {
                    Text("「\(name)」未计入自由天数，调入后自由天数会减少")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.flame)
                }
            }

            VaultButton(title: String(localized: "确认调拨"), icon: "arrow.left.arrow.right", style: .secondary) {
                doTransfer(from: from.place, to: to.place)
            }
            .disabled(entered <= 0)
            .opacity(entered > 0 ? 1.0 : 0.4)
            .accessibilityIdentifier("confirm-transfer")
        }
        .padding(.top, Spacing.xs)
    }

    /// 一个小色块 + 名字，点开按「现金」「资产」两组选
    private func placeMenu(selected: PlaceOption, excluding: TransferStore.Place? = nil, identifier: String,
                           onPick: @escaping (TransferStore.Place) -> Void) -> some View {
        Menu {
            Section("现金") {
                ForEach(cashPlaces.filter { $0.place != excluding }) { option in
                    Button("\(option.name) · ¥\(option.amount.formatted(.number))") { onPick(option.place) }
                }
            }
            Section("资产") {
                ForEach(assetPlaces.filter { $0.place != excluding }) { option in
                    Button("\(option.name) · ¥\(option.amount.formatted(.number))") { onPick(option.place) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(selected.place.isCash ? Color.cashBlue : Color.assetGold)
                    .frame(width: 7, height: 7)
                Text(selected.name)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
            }
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - 调拨实现
    private func doTransfer(from: TransferStore.Place, to: TransferStore.Place) {
        guard let amount = Double(transferAmount), FinancialFormatting.validAmount(amount) else { return }
        do {
            try TransferStore.transfer(amount, from: from, to: to, in: modelContext)
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
