// 数据管理页：导出 CSV / JSON、从 JSON 导入、清空全部数据。从 Settings 进入。

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(ExpenseCategoryStorage.key, store: AppPreferences.store) private var encodedCategoryOptions = ""
    @AppStorage(FreedomSettings.countsAssetsKey, store: AppPreferences.store) private var countsAssets = true
    @AppStorage(ProIntro.audienceKey, store: AppPreferences.store) private var introAudience = ""
    @AppStorage(FirstWeekRecap.shownKey, store: AppPreferences.store) private var recapShown = false
    @AppStorage(MonthlySpending.key, store: AppPreferences.store) private var monthlySpending = 0.0

    @State private var showingFileImporter = false
    @State private var showingPurgeAlert = false
    @State private var importStatus: String? = nil
    @State private var pendingImport: DataIO.ImportPreview? = nil
    @State private var showingImportReview = false
    @State private var isReadingImport = false
    @State private var largeBackupRequest: LargeBackupRequest?

    private struct LargeBackupRequest {
        let url: URL
        let bytes: Int
        let reason: String
    }

    // --- 数据导出 (按需: 点按钮才序列化 + 弹分享, 平时切页面不碰) ---
    @State private var shareItem: ExportShareItem? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                exportCard
                importCard
                purgeCard
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("数据管理")
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("清空记账数据？", isPresented: $showingPurgeAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { purgeData() }
        } message: {
            Text("会删除所有支出、收入、被动收入、固定支出、贷款、资产和现金，不能撤销。")
        }
        .sheet(isPresented: $showingImportReview) {
            if let p = pendingImport {
                ImportReviewSheet(preview: p) { strategy, categoryMap, skipped in
                    try commitImport(strategy: strategy, categoryMap: categoryMap, skippingSuspectedExpenses: skipped)
                } onCancel: {
                    pendingImport = nil
                }
            }
        }
        .alert("恢复大备份？", isPresented: Binding(
            get: { largeBackupRequest != nil },
            set: { if !$0 { largeBackupRequest = nil } }
        ), presenting: largeBackupRequest) { request in
            Button("取消", role: .cancel) {
                largeBackupRequest = nil
                importStatus = String(localized: "已取消导入")
            }
            Button("继续检查") {
                largeBackupRequest = nil
                readImport(request.url, policy: .confirmedBackup(fileBytes: request.bytes), allowLargeRetry: false)
            }
        } message: { request in
            Text("\(request.reason)\n\n这份备份有 \(ByteCountFormatter.string(fromByteCount: Int64(request.bytes), countStyle: .file))，恢复会慢一些。确认是这份，就点「继续检查」，之后还会先给你看预览。")
        }
    }

    private var exportCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: String(localized: "Export · 导出"))
                HStack(spacing: Spacing.sm) {
                    compactDataButton(String(localized: "导出 CSV"), icon: "tablecells") { exportNow(.csv) }
                    compactDataButton(String(localized: "导出 JSON"), icon: "curlybraces") { exportNow(.json) }
                }
                Text("CSV 用 Excel / Numbers 打开看；JSON 用来备份和恢复记账数据，外观这类本机设置要重新选")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }

    private var importCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: String(localized: "Import · 导入"))
                compactDataButton(String(localized: "从 JSON 导入"), icon: "square.and.arrow.down") {
                    showingFileImporter = true
                }
                .disabled(isReadingImport)

                if let status = importStatus {
                    Text(status)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("写入前会先给你看一遍预览，重复的记录会跳过")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
            }
        }
    }

    /// 清空单独一张卡放在最下面, 和日常的导出导入隔开
    private var purgeCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: String(localized: "Reset · 清空"))
                Button {
                    showingPurgeAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 12))
                        Text("清空记账数据").font(.system(.subheadline, design: .rounded))
                    }
                    .foregroundStyle(Color.flame)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(Capsule().stroke(Color.flame.opacity(0.45), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Text("删除全部支出、收入、被动收入和资产，不能撤销。先导出一份 JSON 再清空。")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
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
                name = String(localized: "FreeGrid-记账-\(timestamp)-\(nonce).csv")
            case .json:
                // 自定义过分类才把分类设置写进备份；没动过的账本导出和以前一样
                data = try DataIO.exportJSON(
                    context: modelContext,
                    categoryOptions: encodedCategoryOptions.isEmpty ? nil : ExpenseCategoryStorage.decode(encodedCategoryOptions),
                    monthlySpending: MonthlySpending.valid(monthlySpending))
                name = String(localized: "FreeGrid-备份-\(timestamp)-\(nonce).json")
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            importStatus = nil
            shareItem = ExportShareItem(url: url)
        } catch {
            importStatus = String(localized: "导出失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 数据导入 (两步: preview → confirm → commit)
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importStatus = String(localized: "未选择文件")
                return
            }
            readImport(url)
        case .failure(let error):
            importStatus = String(localized: "这个文件读不出来：\(error.localizedDescription)")
        }
    }

    private func readImport(_ url: URL, policy: ImportPolicy = .default, allowLargeRetry: Bool = true) {
        guard !isReadingImport else { return }
        isReadingImport = true
        importStatus = String(localized: "正在检查备份…")
        Task {
            defer { isReadingImport = false }
            guard url.startAccessingSecurityScopedResource() else {
                importStatus = String(localized: "无法访问该文件")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let validated = try await Task.detached(priority: .userInitiated) {
                    let data = try ImportValidator.loadData(from: url, policy: policy)
                    return try ImportValidator.validate(data: data, policy: policy)
                }.value
                let preview = try DataIO.preview(validated: validated, context: modelContext,
                    categoryNames: ExpenseCategoryStorage.decode(encodedCategoryOptions).allNames)
                pendingImport = preview
                importStatus = nil
                showingImportReview = true
            } catch let error as ImportValidationError where error.isResourceLimit && allowLargeRetry {
                if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    largeBackupRequest = LargeBackupRequest(url: url, bytes: bytes, reason: error.localizedDescription)
                    importStatus = String(localized: "备份超过常规导入限额，等待确认恢复。")
                } else {
                    importStatus = String(localized: "无法确认备份大小，请重新选择文件。")
                }
            } catch {
                importStatus = String(localized: "导入不了：\(error.localizedDescription)")
            }
        }
    }

    private func commitImport(strategy: DataIO.AssetsImportStrategy, categoryMap: [String: String] = [:],
                              skippingSuspectedExpenses: Set<Int> = []) throws {
        guard let preview = pendingImport else { return }
        let result = try DataIO.commitImport(preview: preview, strategy: strategy, categoryMap: categoryMap,
                                             skippingSuspectedExpenses: skippingSuspectedExpenses, context: modelContext)
        // 备份里带着分类设置：整份恢复（替换）时以备份为准，其他方式只补本机没有的分类
        if let backup = preview.categoryOptions,
           let merged = try? ExpenseCategoryStorage.encode(
            ExpenseCategoryStorage.decode(encodedCategoryOptions).merging(backup, replacing: strategy == .replace)) {
            encodedCategoryOptions = merged
        }
        // 每月花销：整份恢复时以备份为准，其他方式只在本机还没填时补上
        if let backup = preview.monthlySpending, strategy == .replace || MonthlySpending.valid(monthlySpending) == nil {
            monthlySpending = backup
        }
        // 导入后资产拆成了多项：算不算由各项自带的设置决定，总开关回到默认
        if (try? AssetItemStore.items(in: modelContext))?.isEmpty == false { countsAssets = true }
        // 换机后先打开、再恢复备份的老用户：改回老用户，看 2.0 更新说明，不弹新手小结
        if let audience = ProIntro.audienceAfterRestoring(ProIntro.Audience(rawValue: introAudience), recapShown: recapShown,
                                                          restoredExpenses: result.expensesAdded) {
            introAudience = audience.rawValue
        }
        var lines: [String] = [String(localized: "导入完成")]
        lines.append(String(localized: "支出 +\(result.expensesAdded)（跳过 \(preview.expensesSkipped) 笔重复）"))
        lines.append(String(localized: "收入 +\(result.incomesAdded)（跳过 \(preview.incomesSkipped) 笔重复）"))
        let manuallySkipped = skippingSuspectedExpenses.intersection(preview.suspectedExpenseIndices).count
        if manuallySkipped > 0 { lines.append(String(localized: "可能重复的支出：你跳过了 \(manuallySkipped) 笔")) }
        if result.devicesAdded > 0 {
            lines.append(String(localized: "设备 +\(result.devicesAdded)"))
        }
        if result.passiveSourcesAdded > 0 {
            lines.append(String(localized: "被动收入 +\(result.passiveSourcesAdded)"))
        }
        switch strategy {
        case .replace:
            lines.append(String(localized: "净值已替换为 ¥\(FinancialFormatting.wholeNumber(preview.jsonAssetsTotal))"))
        case .addToCash:
            lines.append(String(localized: "现金 +¥\(FinancialFormatting.wholeNumber(preview.jsonAssetsTotal))"))
        case .skipAssets:
            lines.append(String(localized: "净值未变动"))
        }
        importStatus = lines.joined(separator: "\n")
        pendingImport = nil
    }

    private func purgeData() {
        do {
            try DataIO.purgeAll(context: modelContext)
            importStatus = String(localized: "已清空记账数据")
        } catch {
            importStatus = String(localized: "清空失败：\(error.localizedDescription)")
        }
    }
}
