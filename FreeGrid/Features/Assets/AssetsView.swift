// 资产页面：双桶、调拨、被动收入及数据管理。

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AssetsView: View {
    @Query private var assetsArr: [UserAssets]
    @Query private var expenses: [Expense]              // 算 dailyBurn 用
    @Query private var passiveSources: [PassiveSource]  // 被动收入源
    @Environment(\.modelContext) private var modelContext

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

    // --- 数据管理 ---
    @State private var showingFileImporter = false
    @State private var showingPurgeAlert = false
    @State private var importStatus: String? = nil
    @State private var pendingImport: DataIO.ImportPreview? = nil
    @State private var showingImportReview = false

    // --- 数据导出 (按需: 点按钮才序列化 + 弹分享, 平时切页面不碰) ---
    @State private var shareItem: ExportShareItem? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    bucketCards
                    if showEmptyHint { emptyHintCard }
                    passiveCard
                    transferCard
                    explainCard
                    dataManagementCard
                }
                .padding()
                // 点击卡片之外的空白处收起调拨键盘(decimalPad 无 return 键)。
                // contentShape 让空白区也可命中; 子控件(按钮/Picker/输入框)优先级更高, 不受影响。
                .contentShape(Rectangle())
                .onTapGesture { transferFocused = false }
            }
            .scrollContentBackground(.hidden)
            .dismissKeyboardOnScroll()
            .background(Color.paper)
            .navigationTitle("Assets")
            .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .saveErrorAlert($saveError)
            .alert("清空所有数据?", isPresented: $showingPurgeAlert) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { purgeData() }
            } message: {
                Text("将删除所有支出、收入、被动收入源、设备记录和资产数据。此操作不可撤销。")
            }
            .sheet(isPresented: $showingImportReview) {
                if let p = pendingImport {
                    ImportReviewSheet(preview: p) { strategy, categoryMap in
                        commitImport(strategy: strategy, categoryMap: categoryMap)
                    } onCancel: {
                        pendingImport = nil
                    }
                }
            }
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

    // MARK: - Hero: 净值总览
    private var heroCard: some View {
        VaultCard(emphasis: .high, padding: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "Net Worth · 净值")

                Text("¥" + currentNetWorth.formatted(.number))
                    .font(.system(size: 44, weight: .ultraLight, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .padding(.top, Spacing.xs)

                if let updated = assetsArr.first?.updatedAt, currentNetWorth > 0 {
                    Text("上次更新 · \(updated, format: .relative(presentation: .named))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                } else {
                    Text("点击下方桶卡片录入金额")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
            }
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

    // MARK: - 调拨
    private var transferCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "调拨")

                Picker("方向", selection: $transferDirection) {
                    ForEach(TransferDirection.allCases, id: \.self) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 6) {
                    Text("¥")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    TextField("0", text: $transferAmount)
                        .decimalKeyboard()
                        .focused($transferFocused)
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.hairline, lineWidth: 1)
                        )
                }

                VaultButton(title: "确认调拨", icon: "arrow.left.arrow.right", style: .secondary) {
                    doTransfer()
                }
                .disabled(Double(transferAmount) == nil || (Double(transferAmount) ?? 0) <= 0)
                .opacity((Double(transferAmount) ?? 0) > 0 ? 1.0 : 0.4)
            }
        }
    }

    private var explainCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkFaint)
                Text("净值 · 资产 · 现金")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
            }

            Text("净值 = 资产 + 现金, 是自动相加的结果, 不能直接修改。资产 (金色) 是锁定的钱, 比如定期/股票/基金; 现金 (蓝色) 是可花的钱。收入默认进现金, 支出从现金扣。资产和现金之间用「调拨」移动。")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.skyFaint)
        )
    }

    private var dataManagementCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: 6) {
                    KickerLabel(text: "Data")
                    Spacer()
                    Image(systemName: "externaldrive")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkFaint)
                }

                // 导出: 两个紧凑按钮并排(CSV / JSON 是一对)
                HStack(spacing: Spacing.sm) {
                    compactDataButton("导出 CSV", icon: "tablecells") { exportNow(.csv) }
                    compactDataButton("导出 JSON", icon: "curlybraces") { exportNow(.json) }
                }
                Text("CSV 用 Excel / Numbers 打开,JSON 可回导备份")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)

                // 导入
                compactDataButton("从 JSON 导入", icon: "square.and.arrow.down") {
                    showingFileImporter = true
                }

                if let status = importStatus {
                    Text(status)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 清空: 分隔线 + 弱化的危险操作(不抢工具按钮的视觉权重)
                Rectangle().fill(Color.hairlineSoft).frame(height: 1)
                    .padding(.vertical, Spacing.xs)
                Button {
                    showingPurgeAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 12))
                        Text("清空所有数据").font(.system(.subheadline, design: .rounded))
                    }
                    .foregroundStyle(Color.flame)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 紧凑数据按钮(比 VaultButton 矮、描边更淡;并排或单列都适配)
    private func compactDataButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13))
                Text(title).font(.system(.subheadline, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(Color.ink)
            .overlay(Capsule().stroke(Color.ink.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 数据导出 (按需: 点按钮才序列化, 写临时文件 → 弹分享面板)
    enum ExportFormat { case csv, json }

    private func exportNow(_ format: ExportFormat) {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = stamp.string(from: .now)
        let nonce = UUID().uuidString.prefix(8)

        do {
            let data: Data
            let name: String
            switch format {
            case .csv:
                data = try DataIO.exportCSV(context: modelContext)
                name = "FreeGrid-记账-\(timestamp)-\(nonce).csv"
            case .json:
                data = try DataIO.exportJSON(context: modelContext)
                name = "FreeGrid-备份-\(timestamp)-\(nonce).json"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            importStatus = nil
            shareItem = ExportShareItem(url: url)
        } catch {
            importStatus = "✗ 导出失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 数据导入 (两步: preview → confirm → commit)
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importStatus = "未选择文件"
                return
            }
            Task {
                guard url.startAccessingSecurityScopedResource() else {
                    importStatus = "无法访问该文件"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let validated = try await Task.detached(priority: .userInitiated) {
                        let data = try ImportValidator.loadData(from: url)
                        return try ImportValidator.validate(data: data)
                    }.value
                    let preview = try DataIO.preview(validated: validated, context: modelContext)
                    pendingImport = preview
                    importStatus = nil
                    showingImportReview = true
                } catch {
                    importStatus = "✗ 解析失败: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            importStatus = "✗ 文件读取失败: \(error.localizedDescription)"
        }
    }

    private func commitImport(strategy: DataIO.AssetsImportStrategy, categoryMap: [String: String] = [:]) {
        guard let preview = pendingImport else { return }
        do {
            let result = try DataIO.commitImport(preview: preview, strategy: strategy, categoryMap: categoryMap, context: modelContext)
            var lines: [String] = ["✓ 导入完成"]
            lines.append("支出 +\(result.expensesAdded) (\(preview.expensesSkipped) 重复跳过)")
            lines.append("收入 +\(result.incomesAdded) (\(preview.incomesSkipped) 重复跳过)")
            if result.devicesAdded > 0 {
                lines.append("设备 +\(result.devicesAdded)")
            }
            if result.passiveSourcesAdded > 0 {
                lines.append("被动源 +\(result.passiveSourcesAdded)")
            }
            switch strategy {
            case .replace:
                lines.append("净值已替换为 ¥\(FinancialFormatting.wholeNumber(preview.jsonAssetsTotal))")
            case .addToCash:
                lines.append("现金 +¥\(FinancialFormatting.wholeNumber(preview.jsonAssetsTotal))")
            case .skipAssets:
                lines.append("净值未变动")
            }
            importStatus = lines.joined(separator: "\n")
        } catch {
            importStatus = "✗ 写入失败: \(error.localizedDescription)"
        }
        pendingImport = nil
    }

    private func purgeData() {
        do {
            try DataIO.purgeAll(context: modelContext)
            editingBucket = nil
            transferAmount = ""
            importStatus = "✓ 已清空所有数据"
        } catch {
            importStatus = "✗ 清空失败: \(error.localizedDescription)"
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
