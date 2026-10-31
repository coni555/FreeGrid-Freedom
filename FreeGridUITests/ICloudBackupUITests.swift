// 2.2 iCloud 自动备份：备份与恢复页有 iCloud 一张卡。UI 测试用临时账本，不连真的 iCloud，看到的是「不可用」的说明。
import XCTest

final class ICloudBackupUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testBackupPageShowsTheICloudCard() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                                           "-UseInMemoryStore", "-proPreview", "NO"]
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("settings-data", inCard: "settings-card-ledger")
        XCTAssertTrue(app.switches["icloud-backup-toggle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["icloud-backup-now"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "iCloud-备份与恢复"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
