// 数据管理页：导出 CSV / JSON、从 JSON 导入、清空全部数据。从 Settings 进入。

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(ExpenseCategoryStorage.key) private var encodedCategoryOptions = ""

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
        .alert("清空所有数据?", isPresented: $showingPurgeAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { purgeData() }
        } message: {
            Text("将删除所有支出、收入、被动收入源、设备记录和资产数据。此操作不可撤销。")
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
                importStatus = "已取消导入"
            }
            Button("继续检查") {
                largeBackupRequest = nil
                readImport(request.url, policy: .confirmedBackup(fileBytes: request.bytes), allowLargeRetry: false)
            }
        } message: { request in
            Text("\(request.reason)\n\n文件大小：\(ByteCountFormatter.string(fromByteCount: Int64(request.bytes), countStyle: .file))。可继续恢复，但需要更多内存和时间。请确认这是你要恢复的备份；检查通过后还会显示导入预览。")
        }
    }

    private var exportCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "Export · 导出")
                HStack(spacing: Spacing.sm) {
                    compactDataButton("导出 CSV", icon: "tablecells") { exportNow(.csv) }
                    compactDataButton("导出 JSON", icon: "curlybraces") { exportNow(.json) }
                }
                Text("CSV 用 Excel / Numbers 打开，JSON 是完整备份，可以再导回来")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }

    private var importCard: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: "Import · 导入")
                compactDataButton("从 JSON 导入", icon: "square.and.arrow.down") {
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
                KickerLabel(text: "Reset · 清空")
                Button {
                    showingPurgeAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 12))
                        Text("清空所有数据").font(.system(.subheadline, design: .rounded))
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
            readImport(url)
        case .failure(let error):
            importStatus = "✗ 文件读取失败: \(error.localizedDescription)"
        }
    }

    private func readImport(_ url: URL, policy: ImportPolicy = .default, allowLargeRetry: Bool = true) {
        guard !isReadingImport else { return }
        isReadingImport = true
        importStatus = "正在检查备份…"
        Task {
            defer { isReadingImport = false }
            guard url.startAccessingSecurityScopedResource() else {
                importStatus = "无法访问该文件"
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
                    importStatus = "备份超过常规导入限额，等待确认恢复。"
                } else {
                    importStatus = "无法确认备份大小，请重新选择文件。"
                }
            } catch {
                importStatus = "✗ 解析失败: \(error.localizedDescription)"
            }
        }
    }

    private func commitImport(strategy: DataIO.AssetsImportStrategy, categoryMap: [String: String] = [:],
                              skippingSuspectedExpenses: Set<Int> = []) throws {
        guard let preview = pendingImport else { return }
        let result = try DataIO.commitImport(preview: preview, strategy: strategy, categoryMap: categoryMap,
                                             skippingSuspectedExpenses: skippingSuspectedExpenses, context: modelContext)
        var lines: [String] = ["✓ 导入完成"]
        lines.append("支出 +\(result.expensesAdded) (\(preview.expensesSkipped) 重复跳过)")
        lines.append("收入 +\(result.incomesAdded) (\(preview.incomesSkipped) 重复跳过)")
        let manuallySkipped = skippingSuspectedExpenses.intersection(preview.suspectedExpenseIndices).count
        if manuallySkipped > 0 { lines.append("疑似重复支出：手动跳过 \(manuallySkipped) 笔") }
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
        pendingImport = nil
    }

    private func purgeData() {
        do {
            try DataIO.purgeAll(context: modelContext)
            importStatus = "✓ 已清空所有数据"
        } catch {
            importStatus = "✗ 清空失败: \(error.localizedDescription)"
        }
    }
}
