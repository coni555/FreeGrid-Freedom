import XCTest

final class HistorySearchRegressionUITests: XCTestCase {
    @MainActor
    private func launch(scrolling: Bool = false) throws -> XCUIApplication {
        continueAfterFailure = false
        let date = DateFormatter()
        date.dateFormat = "yyyy-MM-dd"
        let today = date.string(from: .now)
        let previous = date.string(from: Calendar.current.date(byAdding: .month, value: -1, to: .now)!)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("search-regression.json")
        let additional: [[String: Any]] = scrolling ? (0..<160).map { index in
            ["id": UUID().uuidString, "amount": index + 1, "category": "购物", "note": "Coffee", "date": today]
        } : []
        let data: [String: Any] = [
            "schema_version": 3,
            "assets": ["total": 10000, "locked_assets": 0, "cash": 10000],
            "expenses": [
                ["id": UUID().uuidString, "amount": 20, "category": "购物", "note": "Coffee", "date": today],
                ["id": UUID().uuidString, "amount": 30, "category": "午餐", "note": "Coffee", "date": previous],
                ["id": UUID().uuidString, "amount": -1234.5, "category": "交通", "note": "退款", "date": today],
            ] + additional,
            "incomes": [["id": UUID().uuidString, "amount": 2000, "source": "Salary", "note": "工资", "date": previous]],
            "devices": [], "passive_sources": [],
        ]
        try JSONSerialization.data(withJSONObject: data).write(to: file)
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-hideProPreviewCard", "-proPreview", "YES", "-UseInMemoryStore", "-SeedBackupJSON", file.path]
        app.launch()
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
        app.tabBars.buttons["明细"].tap()
        return app
    }

    @MainActor
    private func expectCount(_ count: Int, in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "找到 \(count) 笔")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testScrollingBackToSearchFieldDoesNotRefocusKeyboard() throws {
        let app = try launch(scrolling: true)
        app.buttons["搜索"].tap()
        let field = app.textFields["history-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Coffee"].tap()
        expectCount(162, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let list = app.collectionViews.firstMatch
        list.swipeUp(velocity: .fast)
        list.swipeUp(velocity: .fast)
        XCTAssertFalse(field.isHittable)
        for _ in 0..<8 {
            if field.isHittable { break }
            list.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(field.isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.buttons["搜索"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSearchRefreshesAfterEditingAndUndoingAResult() throws {
        let app = try launch()
        app.buttons["搜索"].tap()
        let field = app.textFields["history-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("Coffee")
        expectCount(2, in: app)
        app.staticTexts["Coffee"].firstMatch.tap()
        let note = app.textFields["edit-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        note.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "Tea")
        app.buttons["保存"].tap()
        expectCount(1, in: app)
        app.buttons["清空搜索"].tap()
        field.tap()
        field.typeText("Tea")
        expectCount(1, in: app)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "history-transaction-", "Tea")).firstMatch.swipeLeft()
        app.buttons["撤销"].tap()
        app.alerts.buttons["撤销"].tap()
        XCTAssertTrue(app.staticTexts["没有匹配的记录"].waitForExistence(timeout: 5))
        app.buttons["清空搜索"].tap()
        XCTAssertFalse(app.staticTexts["没有匹配的记录"].exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    }

    /// 月份卡片里的支出构成：默认收起，展开后点一类流水只留它，再点或「看全部」回来；收入单列一行；
    /// 首页「本月花销」回到本月的明细
    @MainActor
    func testBreakdownRowsFilterTheFlowAndHomeMonthCardOpensThisMonth() throws {
        let app = try launch()
        let toggle = app.buttons["history-breakdown-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let shopping = app.buttons["history-breakdown-购物"]
        XCTAssertFalse(shopping.exists)
        toggle.tap()
        XCTAssertTrue(shopping.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["history-breakdown-交通"].exists)
        XCTAssertFalse(app.buttons["history-breakdown-income"].exists)
        shopping.tap()
        XCTAssertTrue(app.staticTexts["只看「购物」 · 1 笔"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "history-transaction-", "退款")).firstMatch.exists)
        shopping.tap()
        XCTAssertTrue(app.staticTexts["只看「购物」 · 1 笔"].waitForNonExistence(timeout: 3))

        app.buttons["上个月"].tap()
        let income = app.buttons["history-breakdown-income"]
        XCTAssertTrue(income.waitForExistence(timeout: 3))
        income.tap()
        XCTAssertTrue(app.staticTexts["只看「收入」 · 1 笔"].waitForExistence(timeout: 3))

        app.tabBars.buttons["首页"].tap()
        let month = app.buttons["home-stat-month"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        month.tap()
        let title = app.buttons["history-scope-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let label = Calendar.current.dateComponents([.year, .month], from: .now)
        XCTAssertTrue(title.label.hasPrefix("\(label.year!)年\(label.month!)月"), title.label)
        XCTAssertFalse(app.staticTexts["只看「收入」 · 1 笔"].exists)
        XCTAssertTrue(app.buttons["history-breakdown-购物"].exists)
    }

    /// 月度汇总：最近的月默认展开，支出构成在柱状图和扇形图之间切换，切换后别的月份也跟着换
    @MainActor
    func testMonthlySummaryShowsTheBreakdownAsBarsOrPie() throws {
        let app = try launch()
        app.buttons["history-scope-title"].tap()
        let pie = app.buttons["month-chart-pie"]
        XCTAssertTrue(pie.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["month-chart-bars"].isSelected)
        pie.tap()
        XCTAssertTrue(pie.isSelected)
        let first = app.buttons["month-chart-pie"].firstMatch
        XCTAssertTrue(first.exists)
        // 点开上个月：同样是扇形图
        let previous = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "month-card-")).element(boundBy: 1)
        previous.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "month-chart-pie").count, 2)
        XCTAssertTrue(app.buttons.matching(identifier: "month-chart-pie").element(boundBy: 1).isSelected)
    }

    @MainActor
    func testFilterCrossMonthSearchSuggestionsAndLatestInput() throws {
        let app = try launch()
        // 展开月份卡片、点中「购物」，再搜索就在这一类里搜
        app.buttons["history-breakdown-toggle"].tap()
        app.buttons["history-breakdown-购物"].tap()
        app.buttons["搜索"].tap()
        let field = app.textFields["history-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["history-search-filter"].exists)
        field.typeText("Coffee")
        expectCount(1, in: app)
        app.buttons["history-search-filter"].tap()
        expectCount(2, in: app)
        app.buttons["清空搜索"].tap()
        // 空搜索的常用备注与旧版一致，点击建议直接查，不等输入防抖。
        let suggestion = app.buttons["Coffee"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        expectCount(2, in: app)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search-month-")).count, 2)
        let month = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search-month-")).firstMatch
        month.tap()
        let expanded = month.value as? String
        month.tap()
        XCTAssertNotEqual(month.value as? String, expanded)
        app.buttons["清空搜索"].tap()
        field.tap()
        field.typeText("Coffee" + String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "Salary")
        expectCount(1, in: app)
        XCTAssertTrue(app.staticTexts["Salary"].exists)
        XCTAssertFalse(app.staticTexts["Coffee"].exists)
        app.buttons["清空搜索"].tap()
        field.typeText("1,234.5")
        expectCount(1, in: app)
        XCTAssertTrue(app.staticTexts["退款"].exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.buttons["搜索"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }
}
