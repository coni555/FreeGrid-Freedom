import XCTest

final class ReviewInvitationUITests: XCTestCase {
    @MainActor
    private func launch(days: Int, recentlyRequested: Bool = false, intro: Bool = false) throws -> (XCUIApplication, URL) {
        continueAfterFailure = false
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let expenses: [[String: Any]] = (1...max(days, 1)).prefix(days).map { offset in
            ["id": UUID().uuidString, "amount": 10, "category": "午餐", "note": "测试记账",
             "date": formatter.string(from: calendar.date(byAdding: .day, value: -offset, to: .now)!)]
        }
        let ledger: [String: Any] = ["schema_version": 3,
            "assets": ["total": 10000, "cash": 10000, "locked_assets": 0],
            "expenses": expenses, "incomes": [], "devices": [], "passive_sources": []]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let backup = folder.appendingPathComponent("ledger.json")
        let probe = folder.appendingPathComponent("request.json")
        try JSONSerialization.data(withJSONObject: ledger).write(to: backup)
        let app = XCUIApplication()
        app.launchArguments = ["-UseInMemoryStore", "-SeedBackupJSON", backup.path,
                               "-setupGuideCompleted", "YES", "-historyGuideCompleted", "YES",
                               "-hideProPreviewCard", "-proPreview", "NO", "-isDarkMode", "NO",
                               "-reviewInvitation", "-ReviewRequestProbe", "-ReviewRequestProbeFile", probe.path]
        if recentlyRequested { app.launchArguments += ["-reviewLastRequestedAt", String(Date.now.timeIntervalSince1970)] }
        if intro { app.launchArguments += ["-proIntro", "-proSamplePrices"] }
        app.launch()
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
        return (app, probe)
    }

    private func requests(_ probe: URL) -> Int {
        guard let data = try? Data(contentsOf: probe),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int] else { return 0 }
        return json["requests", default: 0]
    }

    @MainActor
    private func addExpense(_ app: XCUIApplication) {
        app.buttons["记支出"].tap()
        let field = app.textFields["0.00"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("12")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["撤销"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func waitForQuiet(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["撤销"].waitForNonExistence(timeout: 8))
    }

    @MainActor
    func testTenthDayOnlyRequestsAfterSavingAndUndoWindow() throws {
        let (app, probe) = try launch(days: 9)
        XCTAssertEqual(requests(probe), 0)
        app.buttons["记支出"].tap()
        app.buttons["取消"].tap()
        XCTAssertEqual(requests(probe), 0)
        addExpense(app)
        XCTAssertEqual(requests(probe), 0, "撤销窗口内不能邀请")
        waitForQuiet(app)
        let offered = NSPredicate { _, _ in self.requests(probe) == 1 }
        expectation(for: offered, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        addExpense(app)
        waitForQuiet(app)
        // 系统是否展示不可控，冷却按请求记录；再记一笔也不重复申请。
        XCTAssertEqual(requests(probe), 1)
    }

    @MainActor
    func testUndoAndChangingTabsDiscardTheOpportunity() throws {
        let (app, probe) = try launch(days: 10)
        addExpense(app)
        app.buttons["撤销"].tap()
        waitForQuiet(app)
        app.tabBars.buttons["History"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertEqual(requests(probe), 0)
        addExpense(app)
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.buttons["搜索"].waitForExistence(timeout: 5))
        // 留在别页超过撤销窗口，再回首页也不能把旧邀请补弹。
        let timer = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.requests(probe) > 0 }, object: nil)
        timer.isInverted = true
        wait(for: [timer], timeout: 7)
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertEqual(requests(probe), 0)
    }

    @MainActor
    func testSavingIncomeAlsoUsesTheQuietDashboardOpportunity() throws {
        let (app, probe) = try launch(days: 10)
        app.buttons["记收入"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("100")
        let source = app.textFields["工资 / 投资 / 副业 / ..."]
        source.tap()
        source.typeText("Salary")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["撤销"].waitForExistence(timeout: 5))
        XCTAssertEqual(requests(probe), 0)
        waitForQuiet(app)
        expectation(for: NSPredicate { _, _ in self.requests(probe) == 1 }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testOpeningSimulationDiscardsInsteadOfChainingAReviewAfterDismissal() throws {
        let (app, probe) = try launch(days: 10)
        addExpense(app)
        app.buttons["模拟一笔 · 看决策影响"].tap()
        let close = app.buttons["关闭"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let offered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.requests(probe) > 0 }, object: nil)
        offered.isInverted = true
        wait(for: [offered], timeout: 7)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertEqual(requests(probe), 0)
    }

    @MainActor
    func testBeginningAnotherEntryDoesNotBringBackThePreviousInvitationOnCancel() throws {
        let (app, probe) = try launch(days: 10)
        addExpense(app)
        app.buttons["记支出"].tap()
        XCTAssertTrue(app.textFields["0.00"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        waitForQuiet(app)
        let offered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.requests(probe) > 0 }, object: nil)
        offered.isInverted = true
        wait(for: [offered], timeout: 2)
        XCTAssertEqual(requests(probe), 0)
    }

    @MainActor
    func testRecentRequestAndInsufficientDaysDoNotRequest() throws {
        for (days, recent) in [(8, false), (10, true)] {
            let (app, probe) = try launch(days: days, recentlyRequested: recent)
            addExpense(app)
            waitForQuiet(app)
            let offered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.requests(probe) > 0 }, object: nil)
            offered.isInverted = true
            wait(for: [offered], timeout: 2)
            XCTAssertEqual(requests(probe), 0)
            app.terminate()
        }
    }
}
