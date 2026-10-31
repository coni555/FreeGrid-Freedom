// 更新公告：有账本的老用户在首页看到一次，点「开始使用」收起；空账本不弹。
import XCTest

final class UpdateNoticeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func seedFile() throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("update-notice.json")
        let date = DateFormatter()
        date.dateFormat = "yyyy-MM-dd"
        let data: [String: Any] = [
            "schema_version": 3,
            "assets": ["total": 10000, "locked_assets": 0, "cash": 10000],
            "expenses": [["id": UUID().uuidString, "amount": 20, "category": "购物", "note": "", "date": date.string(from: .now)]],
            "incomes": [], "devices": [], "passive_sources": [],
        ]
        try JSONSerialization.data(withJSONObject: data).write(to: file)
        return file.path
    }

    @MainActor
    func testReturningUserSeesTheNoticeOnceAndNothingElseStacksOnIt() throws {
        let app = XCUIApplication()
        // 同时开着 2.0 老用户卡片：一次只弹一张，公告优先
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                                           "-UseInMemoryStore", "-SeedBackupJSON", try seedFile(), "-updateNotice",
                                                           "-proIntro", "-proSamplePrices", "-proIntroAudience", "returning", "-proPreview", "NO"]
        app.launch()
        let card = app.descendants(matching: .any)["update-notice"]
        XCTAssertTrue(card.waitForExistence(timeout: 6))
        XCTAssertFalse(app.descendants(matching: .any)["pro-intro-returning"].exists)
        XCTAssertTrue(app.staticTexts["让每一笔记录，都更从容。"].exists)
        XCTAssertTrue(app.staticTexts["PRO"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "更新公告"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["update-notice-close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3))

        // 回到前台不再弹公告
        XCUIDevice.shared.press(.home)
        app.activate()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(card.exists)
    }

    @MainActor
    func testVeryLargeTextScrollsAndKeepsTheButton() throws {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                                           "-UseInMemoryStore", "-SeedBackupJSON", try seedFile(), "-updateNotice", "-proPreview", "NO",
                                                           "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        let close = app.buttons["update-notice-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 6))
        XCTAssertTrue(close.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "更新公告-大字"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testEmptyLedgerNeverSeesTheNotice() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-setupGuideCompleted", "YES", "-historyGuideCompleted", "YES",
                                                           "-dashboardGuideCompleted", "YES", "-UseInMemoryStore", "-updateNotice", "-proPreview", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(app.descendants(matching: .any)["update-notice"].exists)
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("12")
        app.buttons["保存"].tap()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(app.descendants(matching: .any)["update-notice"].exists)
    }
}
