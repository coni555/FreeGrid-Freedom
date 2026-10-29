// 2.2 按月估算：一笔没记，在钱包填「每月日常大约花多少」，首页日均卡写「按每月估算」。
import XCTest

final class EverydayEstimateUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testAnEstimateWithoutRecordsGivesADailyBurn() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                                           "-UseInMemoryStore", "-proPreview", "NO"]
        app.launch()
        app.tabBars.buttons["钱包"].tap()
        let row = app.buttons["everyday-estimate"]
        for _ in 0..<4 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let field = app.textFields["everyday-estimate-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("3044")
        attach(app, "按月估算-填写")
        app.buttons["everyday-estimate-save"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "3,044")).firstMatch
            .waitForExistence(timeout: 3))
        attach(app, "按月估算-钱包")

        app.tabBars.buttons["首页"].tap()
        let daily = app.buttons["home-stat-daily"]
        XCTAssertTrue(daily.waitForExistence(timeout: 5))
        XCTAssertTrue(daily.label.contains("按每月估算"), daily.label)
        XCTAssertTrue(daily.label.contains("100"), daily.label)
        attach(app, "按月估算-首页")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
