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
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-hideProPreviewCard", "-proPreview", "YES", "-UseInMemoryStore", "-SeedBackupJSON", file.path]
        app.launch()
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
        app.tabBars.buttons["History"].tap()
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

    @MainActor
    func testFilterCrossMonthSearchSuggestionsAndLatestInput() throws {
        let app = try launch()
        app.buttons["按分类筛选"].tap()
        app.buttons["history-filter-购物"].tap()
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
