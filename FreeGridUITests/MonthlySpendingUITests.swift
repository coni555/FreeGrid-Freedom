// 2.2 按月记账：引导第 3 步选定、月底再记、写了数以后的首页和明细、老用户看警告切过去再切回来、记得太少不给大数字。
import XCTest

final class MonthlySpendingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private var thisMonthKey: String {
        let parts = Calendar.current.dateComponents([.year, .month], from: .now)
        return String(format: "%04d-%02d", parts.year!, parts.month!)
    }

    private var thisMonthName: String { "\(Calendar.current.component(.month, from: .now)) 月" }

    private func monthlyJSON(_ months: String = "") -> String {
        "{\"method\":\"monthly\",\"months\":{\(months)},\"startMonth\":\"\(thisMonthKey)\",\"pauses\":[]}"
    }

    private func goThroughSetup(_ app: XCUIApplication) {
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
    }

    /// 新用户在引导第 3 步选定按月记账，可以先不写：回到首页，大数字先空着
    @MainActor
    func testChoosingInTheSetupGuideAndWritingLater() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-heroLayout", "leading", "-isDarkMode", "NO", "-UseInMemoryStore"]
        app.launch()
        goThroughSetup(app)
        let entry = app.buttons["setup-guide-monthly-spending"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["hero-switch-monthly"].exists)   // 气泡里已经有了
        attach(app, "按月记账-引导第3步")
        entry.tap()
        XCTAssertTrue(app.textFields["monthly-spending-field"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["填这个数不扣现金。"].exists)
        XCTAssertFalse(app.buttons["monthly-spending-save"].isEnabled)
        attach(app, "按月记账-面板")
        app.buttons["monthly-spending-later"].tap()

        let pill = app.buttons["monthly-spending-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["setup-guide-text"].exists)
        XCTAssertFalse(app.buttons["guide-next"].waitForExistence(timeout: 2))   // 还没有数字可讲
        XCTAssertFalse(app.buttons["记支出"].exists)
        XCTAssertFalse(app.buttons["hero-switch-monthly"].exists)
        XCTAssertTrue(pill.label.contains("\(thisMonthName)你花了多少"), pill.label)
        attach(app, "按月记账-还没写")

        pill.tap()
        let field = app.textFields["monthly-spending-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("3044")
        app.buttons["monthly-spending-save"].tap()
        let daily = app.buttons["home-stat-daily"]
        XCTAssertTrue(daily.waitForExistence(timeout: 5))
        XCTAssertTrue(daily.label.contains("100"), daily.label)
        XCTAssertTrue(daily.label.contains("按 \(thisMonthName) 估算"), daily.label)
        XCTAssertTrue(pill.label.contains("3,044"), pill.label)
        XCTAssertTrue(app.buttons["home-stat-base"].exists)
        XCTAssertFalse(app.buttons["home-stat-track"].exists)
        attach(app, "按月记账-写好了")

        // 明细列出写过的月份，点了能改
        app.tabBars.buttons["明细"].tap()
        let row = app.buttons["monthly-spending-\(thisMonthKey)"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        attach(app, "按月记账-明细")
        row.tap()
        let again = app.textFields["monthly-spending-field"]
        XCTAssertTrue(again.waitForExistence(timeout: 3))
        XCTAssertEqual(again.value as? String, "3044")
    }

    /// 在引导里就写了数：引导结束，接着讲一遍首页
    @MainActor
    func testWritingInTheSetupGuideEndsItWithTheHomeTour() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-heroLayout", "leading", "-isDarkMode", "NO", "-UseInMemoryStore"]
        app.launch()
        goThroughSetup(app)
        let entry = app.buttons["setup-guide-monthly-spending"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        entry.tap()
        let field = app.textFields["monthly-spending-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("3000")
        app.buttons["monthly-spending-save"].tap()
        XCTAssertTrue(app.buttons["guide-next"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["setup-guide-text"].exists)
    }

    /// 只写了每月花销、不记账的人也能重看讲解；明细要有记录才讲，所以不列
    @MainActor
    func testGuideListOpensWithOnlyAMonthlyNumber() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                                           "-monthlyTracking", monthlyJSON("\"\(thisMonthKey)\":3000"), "-UseInMemoryStore", "-proPreview", "NO"]
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("guide-list", inCard: "settings-card-about")
        XCTAssertTrue(app.buttons["replay-dashboard-guide"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["replay-history-guide"].exists)
        app.buttons["replay-dashboard-guide"].tap()
        XCTAssertTrue(app.buttons["guide-next"].waitForExistence(timeout: 5))
    }

    /// 记过账的人切过去：先看警告，暂不切换什么都不变；确认后和新用户一样，首页换成胶囊、大数字空着、明细里记录收起来。
    /// 再切回来：日均回到切换前，记账按钮和记录都回来
    @MainActor
    func testSwitchingFromEntriesAndBack() {
        let app = launch(expenseDaysAgo: Array(stride(from: 80, through: 0, by: -1)))
        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("settings-tracking-method", inCard: "settings-card-ledger")
        let confirm = app.buttons["tracking-switch-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["确定切换为「按月记账」？"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "原有的 81 笔记录将暂时隐藏")).firstMatch.exists)
        XCTAssertFalse(app.textFields["monthly-spending-field"].exists)
        attach(app, "按月记账-切过去")
        app.buttons["tracking-switch-cancel"].tap()

        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 5))
        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("settings-tracking-method", inCard: "settings-card-ledger")
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        app.tabBars.buttons["首页"].tap()
        let pill = app.buttons["monthly-spending-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertTrue(pill.label.contains("\(thisMonthName)你花了多少"), pill.label)
        XCTAssertFalse(app.buttons["记支出"].exists)
        XCTAssertFalse(app.buttons["home-stat-daily"].exists)   // 和新用户一样，写了数才有日均
        attach(app, "按月记账-老用户首页")

        app.tabBars.buttons["明细"].tap()
        XCTAssertTrue(app.staticTexts["按月记账不用记明细"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["搜索"].exists)
        attach(app, "按月记账-老用户明细")

        // 写一个数：日均只看它，每天 100 的记录不混进来
        app.tabBars.buttons["首页"].tap()
        pill.tap()
        let field = app.textFields["monthly-spending-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("6088")
        app.buttons["monthly-spending-save"].tap()
        let daily = app.buttons["home-stat-daily"]
        XCTAssertTrue(daily.waitForExistence(timeout: 5))
        XCTAssertTrue(daily.label.contains("200"), daily.label)
        app.tabBars.buttons["明细"].tap()
        let row = app.buttons["monthly-spending-\(thisMonthKey)"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        // 去别的页再回来，在明细当场改这个数：列表要跟着变
        app.tabBars.buttons["设置"].tap()
        app.tabBars.buttons["明细"].tap()
        row.tap()
        let again = app.textFields["monthly-spending-field"]
        XCTAssertTrue(again.waitForExistence(timeout: 3))
        again.typeText("0")
        app.buttons["monthly-spending-save"].tap()
        XCTAssertTrue(app.staticTexts["¥60,880"].waitForExistence(timeout: 3))

        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("settings-tracking-method", inCard: "settings-card-ledger")
        XCTAssertTrue(app.staticTexts["回到之前的逐笔记账方式和记账数据。"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["¥100.0"].exists)
        attach(app, "按月记账-切回来")
        app.buttons["tracking-switch-confirm"].tap()

        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 5))
        XCTAssertFalse(pill.exists)
        XCTAssertTrue(daily.label.contains("100"), daily.label)
        XCTAssertFalse(daily.label.contains("200"), daily.label)
        app.tabBars.buttons["明细"].tap()
        XCTAssertTrue(app.buttons["搜索"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["按月记账不用记明细"].exists)
    }

    /// 选了按月记账还没写就改回去：内容只有一行字，面板也要铺满，日均那两行不出现
    @MainActor
    func testSwitchingBackWithoutANumber() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                                           "-monthlyTracking", monthlyJSON(), "-UseInMemoryStore", "-proPreview", "NO"]
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("settings-tracking-method", inCard: "settings-card-ledger")
        XCTAssertTrue(app.staticTexts["之后记的每笔支出都会从现金扣。"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["现在的日均"].exists)
        attach(app, "按月记账-没写就切回来")
        app.buttons["tracking-switch-confirm"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 5))
    }

    /// 写过数又切回去，再切过来点「月底再记」：写过的数还在
    @MainActor
    func testWritingLaterKeepsTheNumberWritten() {
        let app = XCUIApplication()
        let tracking = "{\"method\":\"entries\",\"months\":{\"\(thisMonthKey)\":5000},\"startMonth\":\"\(thisMonthKey)\",\"pauses\":[]}"
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                                           "-monthlyTracking", tracking, "-UseInMemoryStore", "-proPreview", "NO"]
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("settings-tracking-method", inCard: "settings-card-ledger")
        let later = app.buttons["monthly-spending-later"]
        XCTAssertTrue(later.waitForExistence(timeout: 3))
        later.tap()
        app.tabBars.buttons["首页"].tap()
        let pill = app.buttons["monthly-spending-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertTrue(pill.label.contains("5,000"), pill.label)
    }

    /// 记了一笔就不记：一个月后不给大数字，给一个入口
    @MainActor
    func testTooFewRecordsGiveNoNumber() {
        let app = launch(expenseDaysAgo: [30])
        XCTAssertTrue(app.staticTexts["已有 1 笔支出，上次记录在 30 天前"].waitForExistence(timeout: 5))
        let entry = app.buttons["hero-switch-monthly"]
        XCTAssertTrue(entry.exists)
        XCTAssertTrue(entry.label.contains("不想每天记账"), entry.label)
        attach(app, "断档-记得太少")
        entry.tap()
        XCTAssertTrue(app.buttons["tracking-switch-confirm"].waitForExistence(timeout: 3))
    }

    /// 记得多的老用户断档：大数字照常，多一行入口
    @MainActor
    func testAVeteranKeepsTheNumberAndGetsAnEntry() {
        let app = launch(expenseDaysAgo: Array(stride(from: 90, through: 30, by: -1)))
        let entry = app.buttons["hero-switch-monthly"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.label.contains("上次记账是 30 天前"), entry.label)
        XCTAssertTrue(app.buttons["home-stat-daily"].exists)
        attach(app, "断档-老用户")
    }

    private func launch(expenseDaysAgo days: [Int]) -> XCUIApplication {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        let expenses = days.map { ago -> String in
            let date = format.string(from: Calendar.current.date(byAdding: .day, value: -ago, to: .now)!)
            return "{\"amount\":100,\"category\":\"午餐\",\"date\":\"\(date)\"}"
        }.joined(separator: ",")
        let json = """
        {"schema_version":2,"assets":{"total":60000,"locked_assets":0,"cash":60000},"expenses":[\(expenses)]}
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("monthly-spending-\(UUID().uuidString).json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                                           "-hideProPreviewCard", "-proPreview", "NO",
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
