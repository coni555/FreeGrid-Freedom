// 资产页面：净值、双桶、被动收入和调拨。导出、导入、清空在 Settings 的数据管理页。

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AssetsView: View {
    @Query private var assetsArr: [UserAssets]
    @Query private var expenses: [Expense]              // 算 dailyBurn 用
    @Query private var passiveSources: [PassiveSource]  // 被动收入源
    @Environment(\.modelContext) private var modelContext
    /// 起步引导要圈出现金卡
    @Environment(AppGuide.self) private var guide

    // --- 双桶编辑 (sheet 模式) ---
    @State private var saveError: String?
    @State private var editingBucket: EditBucketSheet.Bucket? = nil

    // --- 调拨 ---
    @State private var transferAmount: String = ""
    @State private var transferDirection: TransferDirection = .cashToAssets
    @FocusState private var transferFocused: Bool   // decimalPad 无 return 键, 靠点空白处 / 下拉滚动收起

    enum TransferDirection: String, CaseIterable {
        case cashToAssets = "现金 → 资产"
        case assetsToCash = "资产 → 现金"
    }

    // --- 被动收入 ---
    @State private var showingAddPassive: Bool = false
    @State private var editingPassiveSource: PassiveSource? = nil
    @State private var pendingDeletePassive: PassiveSource? = nil

    // --- 自由天数口径 ---
    @AppStorage(FreedomSettings.countsAssetsKey) private var countsAssets = true
    /// 方案原型：开关放在这一页还是设置里，用户选定后删掉
    @AppStorage("assetSwitchPlacement") private var assetSwitchPlacement = "assets"

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
                    if assetSwitchPlacement == "assets" { countsAssetsCard }
                    if showEmptyHint { emptyHintCard }
                    passiveCard
                        .guideTarget(.passive, in: guide)
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
            .sheet(item: $editingBucket) { bucket in
                EditBucketSheet(
                    bucket: bucket,
                    currentAmount: amountFor(bucket: bucket),
                    onSave: { newAmount in
                        try applyBucketEdit(bucket: bucket, newAmount: newAmount)
                    }
                )
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

    // MARK: - 自由天数口径: 资产算不算
    private var countsAssetsCard: some View {
        VaultCard {
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
        Button {
            editingBucket = bucket
        } label: {
            VaultCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 11))
                            .foregroundStyle(color)
                        KickerLabel(text: kicker)
                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.inkFaint)
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
        .accessibilityLabel("编辑\(kicker)")
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
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first)
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
            transferForm
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }

    /// 从哪一桶到哪一桶 (右边的圆钮对调方向) → 金额 → 确认
    private var transferForm: some View {
        let fromCash = transferDirection == .cashToAssets
        let available = max(0, fromCash ? cashAmount : lockedAssetsAmount)
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
            Text(entered > available
                 ? "\(fromCash ? "现金" : "资产")只有 ¥\(available.formatted(.number))，会全部调过去"
                 : "\(fromCash ? "现金" : "资产")可用 ¥\(available.formatted(.number))")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(entered > available ? Color.flame : Color.inkFaint)

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
