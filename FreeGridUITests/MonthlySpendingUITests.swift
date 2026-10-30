// 2.2 按月估算：一笔没记，填「每月大约花多少」，首页日均卡写「按每月估算」。入口在钱包、首页和起步引导第 3 步。
import XCTest

final class MonthlySpendingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testAnEstimateWithoutRecordsGivesADailyBurn() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                                           "-UseInMemoryStore", "-proPreview", "NO"]
        app.launch()
        app.tabBars.buttons["钱包"].tap()
        let row = app.buttons["monthly-spending"]
        for _ in 0..<4 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let field = app.textFields["monthly-spending-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("3044")
        attach(app, "按月估算-填写")
        app.buttons["monthly-spending-save"].tap()
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

    @MainActor
    func testTheHomeEntryFillsItInPlace() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                                           "-UseInMemoryStore", "-proPreview", "NO"]
        app.launch()
        // 先有钱，首页才出现这个入口
        app.tabBars.buttons["钱包"].tap()
        app.buttons["编辑现金"].tap()
        let cash = app.textFields["bucket-amount-field"]
        XCTAssertTrue(cash.waitForExistence(timeout: 3))
        cash.typeText("60000")
        app.buttons["保存"].tap()
        app.tabBars.buttons["首页"].tap()
        let entry = app.buttons["hero-monthly-spending"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        attach(app, "按月估算-首页入口")
        entry.tap()
        let field = app.textFields["monthly-spending-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("3000")
        attach(app, "按月估算-面板")
        app.buttons["monthly-spending-save"].tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["home-stat-daily"].waitForExistence(timeout: 5))
        attach(app, "按月估算-填完")
    }

    @MainActor
    func testTheSetupGuideEndsOnceItIsFilled() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-heroLayout", "leading", "-isDarkMode", "NO", "-UseInMemoryStore"]
        app.launch()
        let goAssets = app.buttons["setup-guide-go-assets"]
        XCTAssertTrue(goAssets.waitForExistence(timeout: 5))
        goAssets.tap()
        XCTAssertTrue(app.navigationBars["钱包"].waitForExistence(timeout: 3))
        app.buttons["编辑现金"].tap()
        let cash = app.textFields["bucket-amount-field"]
        XCTAssertTrue(cash.waitForExistence(timeout: 3))
        cash.typeText("60000")
        app.buttons["保存"].tap()
        let goHome = app.buttons["setup-guide-go-home"]
        XCTAssertTrue(goHome.waitForExistence(timeout: 3))
        goHome.tap()
        let entry = app.buttons["setup-guide-monthly-spending"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        attach(app, "按月估算-引导第3步")
        entry.tap()
        let field = app.textFields["monthly-spending-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("3000")
        app.buttons["monthly-spending-save"].tap()
        // 引导结束，接着讲一遍首页
        XCTAssertTrue(app.buttons["guide-next"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["setup-guide-text"].exists)
        attach(app, "按月估算-引导结束")
    }

    /// 天天记账的人看不到这一行；超过 14 天没记才出现。经典版和钱与时间版都是
    @MainActor
    func testTheWalletRowOnlyShowsWhenItIsNeeded() throws {
        for layout in ["classic", "moneyTime"] {
            let logger = launch(lastExpenseDaysAgo: 0, layout: layout)
            logger.tabBars.buttons["钱包"].tap()
            XCTAssertTrue(logger.navigationBars["钱包"].waitForExistence(timeout: 5))
            XCTAssertFalse(logger.buttons["monthly-spending"].waitForExistence(timeout: 1), layout)
            attach(logger, "按月估算-天天记账-\(layout)")
            logger.terminate()

            let quiet = launch(lastExpenseDaysAgo: 23, layout: layout)
            quiet.tabBars.buttons["钱包"].tap()
            let row = quiet.buttons["monthly-spending"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), layout)
            XCTAssertTrue(row.label.contains("23 天没记了"), row.label)
            attach(quiet, "按月估算-断档-\(layout)")
            quiet.terminate()
        }
    }

    private func launch(lastExpenseDaysAgo days: Int, layout: String) -> XCUIApplication {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        let date = format.string(from: Calendar.current.date(byAdding: .day, value: -days, to: .now)!)
        let json = """
        {"schema_version":2,"assets":{"total":60000,"locked_assets":0,"cash":60000},
         "expenses":[{"amount":100,"category":"午餐","date":"\(date)"}]}
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("monthly-spending-\(UUID().uuidString).json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                                           "-hideProPreviewCard", "-proPreview", "YES", "-assetsLayout", layout,
                                                           "-UseInMemoryStore", "-SeedBackupJSON", url.path]
        app.launch()
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
