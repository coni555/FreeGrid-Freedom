// 实际导出 → 文件读取 → 预览 → 保存 → 再导出，覆盖大小和条数两种门槛。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct LargeBackupRestoreTests {
    @Test(arguments: [1800, 50001])
    func exportedBackupRestoresEveryFieldAfterConfirmation(count: Int) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("backup.json")
        let source = try TestSupport.makeContext()
        let note = count == 1800 ? String(repeating: "记", count: 2000) : ""
        let day = TestSupport.day("2026-01-01")
        for _ in 0..<count {
            source.insert(Expense(amount: 30, category: "午餐", note: note, date: day))
        }
        source.insert(Income(amount: 80, source: "工资", date: day))
        source.insert(Device(name: "电脑", category: "数码", price: 100, purchaseDate: day))
        source.insert(PassiveSource(name: "利息", monthlyAmount: 10))
        let assets = UserAssets(total: 0)
        assets.cash = -20
        assets.lockedAssets = 300
        source.insert(assets)
        try source.save()
        let exported = try DataIO.exportJSON(context: source)
        try exported.write(to: file)
        if count == 1800 {
            #expect(exported.count > FinancialLimits.fileBytes)
            #expect(throws: ImportValidationError.self) { _ = try ImportValidator.loadData(from: file) }
        } else {
            #expect(exported.count <= FinancialLimits.fileBytes)
            let normallyLoaded = try ImportValidator.loadData(from: file)
            // 文件读取通过，但随后在解析入口碰到条数限制。
            #expect(throws: ImportValidationError.tooManyRecords(kind: "收支", count: 50002, maximum: 50000)) {
                _ = try ImportValidator.validate(data: normallyLoaded)
            }
        }

        let policy = ImportPolicy.confirmedBackup(fileBytes: exported.count)
        let loaded = try ImportValidator.loadData(from: file, policy: policy)
        let validated = try ImportValidator.validate(data: loaded, policy: policy)
        let storeURL = folder.appendingPathComponent("restored.store")
        try restore(validated, to: storeURL)
        // 释放写入容器后重新打开磁盘库，再核对所有导出字段。
        let reopened = try diskContext(at: storeURL)
        let restored = try DataIO.exportJSON(context: reopened)
        #expect(try canonicalBackup(exported).isEqual(canonicalBackup(restored)))
    }

    @Test func confirmationKeepsFieldValidationAndRejectsFileGrowth() throws {
        let invalidInputs = [
            #"{"expenses":[{"id":"invalid","amount":1,"category":"午餐","date":"2026-01-01"}]}"#,
            #"{"assets":{"total":1e13}}"#,
            #"{"expenses":[{"amount":1,"category":"午餐","date":"2026-02-31"}]}"#,
            #"{"schema_version":99}"#,
            "{\"expenses\":[{\"amount\":1,\"category\":\"午餐\",\"date\":\"2026-01-01\",\"note\":\"\(String(repeating: "记", count: 2001))\"}]}"
        ]
        for input in invalidInputs {
            let data = Data(input.utf8)
            #expect(throws: ImportValidationError.self) {
                _ = try ImportValidator.validate(data: data, policy: .confirmedBackup(fileBytes: data.count))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data(#"{"expenses":[]}"#.utf8)
        try data.write(to: url)
        let policy = ImportPolicy.confirmedBackup(fileBytes: data.count)
        #expect(try ImportValidator.loadData(from: url, policy: policy) == data)
        try (data + Data(" ".utf8)).write(to: url)
        #expect(throws: ImportValidationError.fileTooLarge(actual: data.count + 1, maximum: data.count)) {
            _ = try ImportValidator.loadData(from: url, policy: policy)
        }
    }

    private func diskContext(at url: URL) throws -> ModelContext {
        let schema = StoreBootstrap.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func restore(_ validated: ValidatedImport, to url: URL) throws {
        let target = try diskContext(at: url)
        let preview = try DataIO.preview(validated: validated, context: target)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)
    }

    private func canonicalBackup(_ data: Data) throws -> NSDictionary {
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // 同日记录在数据库中的返回顺序不固定；按稳定 UUID 对齐后比较完整字段。
        for key in ["expenses", "incomes", "devices", "passive_sources"] {
            let records = try #require(json[key] as? [[String: Any]])
            json[key] = records.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
        }
        return NSDictionary(dictionary: json)
    }
}
