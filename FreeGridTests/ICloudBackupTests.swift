// 2.2 iCloud 自动备份：文件名和时刻互相换算、只留最新 7 份、隔够 20 小时才写、按月记账的数也进备份。读写 iCloud 本身要真机验。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct ICloudBackupTests {
    private let noon = Date(timeIntervalSince1970: 1_793_000_000)

    @Test func fileNamesRoundTrip() {
        let name = ICloudBackup.fileName(for: noon)
        #expect(name.hasPrefix("FreeGrid-auto-") && name.hasSuffix(".json"))
        #expect(ICloudBackup.date(fromFileName: name) == noon)
        // 没下载到本机的占位文件
        #expect(ICloudBackup.date(fromFileName: "." + name + ".icloud") == noon)
        #expect(ICloudBackup.date(fromFileName: "FreeGrid-备份-20261029.json") == nil)
    }

    @Test func onlyTheNewestSevenStay() {
        let names = (0..<10).map { ICloudBackup.fileName(for: noon.addingTimeInterval(Double($0) * 86_400)) }
            + ["别的文件.json"]
        let expired = ICloudBackup.expired(names.shuffled())
        #expect(Set(expired) == Set(names.prefix(3)))
    }

    @Test func uploadStateReadsThroughTheSystemsWrappedQuotaError() {
        // 真机上空间满时读到的就是这样三层（2026-10-31）
        let kit = NSError(domain: "CKErrorDomain", code: 25)
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: 4354, userInfo: [NSUnderlyingErrorKey: kit])
        let quota = NSError(domain: "NSFileProviderErrorDomain", code: -1003, userInfo: [NSUnderlyingErrorKey: cocoa])
        #expect(ICloudBackup.uploadState(isUploaded: false, error: quota) == .quotaFull)
        #expect(ICloudBackup.uploadState(isUploaded: false, error: cocoa) == .quotaFull)
        #expect(ICloudBackup.uploadState(isUploaded: false, error: NSError(domain: NSCocoaErrorDomain, code: 4355)) == .failed)
        #expect(ICloudBackup.uploadState(isUploaded: false, error: nil) == .pending)
        #expect(ICloudBackup.uploadState(isUploaded: nil, error: nil) == .pending)
        // 传上去之后残留的错误不算
        #expect(ICloudBackup.uploadState(isUploaded: true, error: quota) == .uploaded)
    }

    @Test func backsUpOnceADayOrSo() {
        #expect(ICloudBackup.isDue(lastBackup: nil, now: noon))
        #expect(!ICloudBackup.isDue(lastBackup: noon, now: noon.addingTimeInterval(19 * 3600)))
        #expect(ICloudBackup.isDue(lastBackup: noon, now: noon.addingTimeInterval(20 * 3600)))
        // 时钟往回拨过
        #expect(ICloudBackup.isDue(lastBackup: noon, now: noon.addingTimeInterval(-60)))
    }

    private var monthly: MonthlyTracking {
        var tracking = MonthlyTracking()
        tracking.adopt(startingAt: YearMonth(year: 2026, month: 10), now: noon)
        tracking.set(3000, for: YearMonth(year: 2026, month: 10))
        return tracking
    }

    @Test func aMonthlyTrackerWithNoRecordsStillGetsBackedUp() throws {
        let context = try TestSupport.makeContext()
        #expect(!ICloudBackup.hasContent(in: context, tracking: MonthlyTracking()))
        #expect(ICloudBackup.hasContent(in: context, tracking: monthly))

        let data = try ICloudBackup.currentBackup(context: context, tracking: monthly)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["monthly_tracking"] != nil)
    }

    @Test func aLedgerThatNeverUsedMonthlyTrackingLeavesItOut() throws {
        let context = try TestSupport.makeContext()
        context.insert(Expense(amount: 20, category: "午餐", date: noon))
        try context.save()
        #expect(ICloudBackup.hasContent(in: context, tracking: MonthlyTracking()))
        let data = try ICloudBackup.currentBackup(context: context, tracking: MonthlyTracking())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["monthly_tracking"] == nil)
    }

    @Test func moneyInTheWalletCountsAsSomethingToBackUp() throws {
        let context = try TestSupport.makeContext()
        let assets = UserAssets()
        context.insert(assets)
        #expect(!ICloudBackup.hasContent(in: context, tracking: MonthlyTracking()))
        assets.cash = 1000
        #expect(ICloudBackup.hasContent(in: context, tracking: MonthlyTracking()))
    }
}
