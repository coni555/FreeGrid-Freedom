// 2.2 iCloud 自动备份：文件名和时刻互相换算、只留最新 7 份、隔够 20 小时才写。读写 iCloud 本身要真机验。
import Foundation
import Testing
@testable import FreeGrid

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

    @Test func backsUpOnceADayOrSo() {
        #expect(ICloudBackup.isDue(lastBackup: nil, now: noon))
        #expect(!ICloudBackup.isDue(lastBackup: noon, now: noon.addingTimeInterval(19 * 3600)))
        #expect(ICloudBackup.isDue(lastBackup: noon, now: noon.addingTimeInterval(20 * 3600)))
        // 时钟往回拨过
        #expect(ICloudBackup.isDue(lastBackup: noon, now: noon.addingTimeInterval(-60)))
    }
}
