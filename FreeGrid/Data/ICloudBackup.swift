// iCloud 自动备份（2.2，免费，默认开）：离开 App 时，距上次超过 20 小时、有东西可备份，就往 App 自己的 iCloud 云盘文件夹
// 写一份 JSON，留最近 7 份。内容和手动「导出 JSON」一样，恢复也走同一套校验和预览。
// 账本本身不进 iCloud，不做多设备同步（SwiftData + CloudKit 风险大，2026-10-26 定的范围）。
// 文件在「文件」App 的 iCloud 云盘 → FreeGrid 里看得到（Info.plist 的 NSUbiquitousContainers）。

import Foundation
import SwiftData
#if os(iOS)
import UIKit
#endif

enum ICloudBackup {
    static let containerID = "iCloud.cn.conilab.FreeGrid"
    /// 开关，没设过时是开
    static let enabledKey = "iCloudBackupEnabled"
    /// 上次自动或手动备份成功的时刻（时间戳）
    static let lastBackupKey = "iCloudBackupLastAt"
    static let keepCount = 7
    /// 一天最多自动写一次；用 20 小时，每天差不多同一时间打开的人也能天天有一份
    static let interval: TimeInterval = 20 * 3600
    nonisolated static let filePrefix = "FreeGrid-auto-"

    enum BackupError: Error, LocalizedError {
        case unavailable
        var errorDescription: String? {
            String(localized: "iCloud 云盘不可用：在 iOS 设置里登录 iCloud，并给 FreeGrid 打开 iCloud 云盘。")
        }
    }

    /// iCloud 云盘里的一份备份。没下载到这台设备上的也列出来，恢复时再下
    struct Item: Identifiable, Equatable, Sendable {
        let url: URL
        let date: Date
        let bytes: Int?
        var id: URL { url }
    }

    static func isEnabled(in defaults: UserDefaults = AppPreferences.store) -> Bool {
        defaults.object(forKey: enabledKey) == nil || defaults.bool(forKey: enabledKey)
    }

    static func lastBackup(in defaults: UserDefaults = AppPreferences.store) -> Date? {
        let stamp = defaults.double(forKey: lastBackupKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// 从来没备份过、隔够 20 小时、或者时钟被往回拨过时该备份了
    static func isDue(lastBackup: Date?, now: Date = .now) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= interval || lastBackup > now
    }

    // MARK: - 文件名

    nonisolated static func fileName(for date: Date) -> String {
        filePrefix + stampFormatter().string(from: date) + ".json"
    }

    /// 从文件名读出备份时刻；不是自动备份的文件返回 nil。没下载的文件在目录里叫「.名字.icloud」
    nonisolated static func date(fromFileName name: String) -> Date? {
        var name = name
        if name.hasPrefix("."), name.hasSuffix(".icloud") { name = String(name.dropFirst().dropLast(".icloud".count)) }
        guard name.hasPrefix(filePrefix), name.hasSuffix(".json") else { return nil }
        let stamp = name.dropFirst(filePrefix.count).dropLast(".json".count)
        return stampFormatter().date(from: String(stamp))
    }

    /// 按时刻从新到旧，只留最新 `keep` 份，返回要删的
    nonisolated static func expired(_ names: [String], keep: Int = keepCount) -> [String] {
        let dated = names.compactMap { name in date(fromFileName: name).map { (name, $0) } }
            .sorted { $0.1 > $1.1 }
        return dated.dropFirst(keep).map(\.0)
    }

    nonisolated private static func stampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }

    // MARK: - 读写 iCloud 云盘

    /// iCloud 里 App 自己的 Documents 文件夹；没登录 iCloud 或关了 iCloud 云盘时为 nil。
    /// 第一次调用会等系统准备好容器，不要在主线程上调
    nonisolated static func folder() -> URL? {
        #if DEBUG
        // UI 测试、拍图用的临时账本不往真的 iCloud 里写
        if ProcessInfo.processInfo.arguments.contains("-UseInMemoryStore") { return nil }
        #endif
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else { return nil }
        let folder = root.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// 现在的账本做成一份备份。和数据管理页的「导出 JSON」是同一份内容
    @MainActor
    static func currentBackup(context: ModelContext, tracking: MonthlyTracking = .current) throws -> Data {
        let encodedOptions = AppPreferences.store.string(forKey: ExpenseCategoryStorage.key) ?? ""
        // 自定义过分类才把分类设置写进备份；没动过的账本导出和以前一样。按月记账写下的数同理
        return try DataIO.exportJSON(
            context: context,
            categoryOptions: encodedOptions.isEmpty ? nil : ExpenseCategoryStorage.decode(encodedOptions),
            monthlyTracking: tracking.isUntouched ? nil : tracking)
    }

    /// 有东西可备份：记过账、写过每月花销，或者钱包里填过钱。按月记账的人账本里可以一笔记录都没有。
    /// 什么都没有时不写：刚重装的 App 不该用空账本挤掉之前的备份
    @MainActor
    static func hasContent(in context: ModelContext, tracking: MonthlyTracking = .current) -> Bool {
        if tracking.hasNumber { return true }
        if ((try? context.fetchCount(FetchDescriptor<Expense>())) ?? 0) > 0
            || ((try? context.fetchCount(FetchDescriptor<Income>())) ?? 0) > 0 { return true }
        guard let assets = (try? context.fetch(FetchDescriptor<UserAssets>()))?.first else { return false }
        return assets.cash != 0 || assets.lockedAssets != 0
    }

    /// 离开 App 时调：开着、到时间了、有东西可备份才写
    @MainActor
    static func backUpIfDue(in context: ModelContext, now: Date = .now) {
        guard isEnabled(), isDue(lastBackup: lastBackup(), now: now) else { return }
        guard hasContent(in: context), let data = try? currentBackup(context: context) else { return }
        #if os(iOS)
        // 退到后台后系统只给几秒，申请一段后台时间把文件写完
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "iCloudBackup") {
            UIApplication.shared.endBackgroundTask(task)
        }
        Task {
            _ = try? await write(data, now: now)
            UIApplication.shared.endBackgroundTask(task)
        }
        #else
        Task { _ = try? await write(data, now: now) }
        #endif
    }

    /// 写一份、删掉多出来的旧备份，记下时刻。数据管理页的「现在备份」也走这里
    @MainActor
    static func write(_ data: Data, now: Date = .now) async throws -> URL {
        let url = try await Task.detached(priority: .utility) { () throws -> URL in
            guard let folder = folder() else { throw BackupError.unavailable }
            let url = folder.appendingPathComponent(fileName(for: now))
            try coordinatedWrite(data, to: url)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in expired(names) {
                coordinatedDelete(folder.appendingPathComponent(name))
            }
            return url
        }.value
        AppPreferences.store.set(now.timeIntervalSince1970, forKey: lastBackupKey)
        return url
    }

    /// 列出 iCloud 云盘里的自动备份，新的在前；iCloud 不可用时为 nil
    nonisolated static func list() async -> [Item]? {
        await Task.detached(priority: .userInitiated) { () -> [Item]? in
            guard let folder = folder() else { return nil }
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            var items: [Item] = []
            for name in names {
                guard let date = date(fromFileName: name) else { continue }
                let real = name.hasPrefix(".") ? fileName(for: date) : name
                let url = folder.appendingPathComponent(real)
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey, .ubiquitousItemDownloadingStatusKey]))?.fileSize
                items.append(Item(url: url, date: date, bytes: bytes))
            }
            // 同一份可能既有占位文件又有真文件
            var seen = Set<URL>()
            return items.filter { seen.insert($0.url).inserted }.sorted { $0.date > $1.date }
        }.value
    }

    /// 恢复前确保文件在本机：别的设备写的、或者被系统清掉本地副本的，先从 iCloud 下回来（最多等 30 秒）
    nonisolated static func download(_ item: Item) async throws -> URL {
        try await Task.detached(priority: .userInitiated) { () throws -> URL in
            let manager = FileManager.default
            func isLocal() -> Bool {
                let status = try? item.url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                    .ubiquitousItemDownloadingStatus
                return status == .current || (status == nil && manager.fileExists(atPath: item.url.path))
            }
            if !isLocal() { try manager.startDownloadingUbiquitousItem(at: item.url) }
            for _ in 0..<60 where !isLocal() {
                try await Task.sleep(for: .milliseconds(500))
            }
            guard isLocal() else { throw BackupError.unavailable }
            return item.url
        }.value
    }

    nonisolated private static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    nonisolated private static func coordinatedDelete(_ url: URL) {
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { target in
            try? FileManager.default.removeItem(at: target)
        }
    }
}
