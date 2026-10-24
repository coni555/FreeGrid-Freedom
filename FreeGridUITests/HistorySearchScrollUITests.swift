import XCTest

final class HistorySearchScrollUITests: XCTestCase {
    @MainActor
    func testRepeatedColdOpening() throws {
        let env = ProcessInfo.processInfo.environment
        guard let folder = env["HISTORY_PERF_DIR"], let phase = env["HISTORY_PERF_PHASE"] else {
            throw XCTSkip("仅在搜索首次打开专项验收时运行")
        }
        continueAfterFailure = false
        for run in 0..<5 {
            let app = XCUIApplication()
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                   "-hideProPreviewCard", "-proPreview", "YES", "-UseInMemoryStore", "-SeedBackupJSON",
                                   folder + "/ledgers/10000.json", "-HistorySearchMetricsFile", folder + "/\(phase)/cold-\(run).json"]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 60))
            app.tabBars.buttons["明细"].tap()
            XCTAssertTrue(app.buttons["搜索"].waitForExistence(timeout: 10))
            app.buttons["搜索"].tap()
            let field = app.textFields["history-search-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
            app.buttons["取消"].tap()
            XCTAssertTrue(field.waitForNonExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testSearchOpeningAndScroll() throws {
        let env = ProcessInfo.processInfo.environment
        guard let folder = env["HISTORY_PERF_DIR"], let phase = env["HISTORY_PERF_PHASE"] else {
            throw XCTSkip("仅在搜索滚动专项验收时运行")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-hideProPreviewCard", "-proPreview", "YES", "-UseInMemoryStore", "-SeedBackupJSON",
                               folder + "/ledgers/10000.json", "-HistorySearchMetricsFile", folder + "/\(phase)/native.json"]
        app.launch()
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 60))
        app.tabBars.buttons["明细"].tap()
        var rounds: [[String: Any]] = []
        for opening in 0..<2 {
            app.buttons["搜索"].tap()
            let field = app.textFields["history-search-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
            // 点建议会收起键盘；模拟用户搜索后持续查看结果。
            app.buttons["咖啡 Coffee"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "找到 ")).firstMatch.waitForExistence(timeout: 10))
            let list = app.collectionViews.firstMatch
            XCTAssertTrue(list.exists)
            let start = Date().timeIntervalSince1970
            for _ in 0..<6 { list.swipeUp(velocity: .fast) }
            for _ in 0..<6 { list.swipeDown(velocity: .fast) }
            // 快速滑动的距离会随键盘和惯性变化，按可见状态回到顶部。
            for _ in 0..<8 {
                if app.buttons["取消"].isHittable { break }
                list.swipeDown(velocity: .fast)
            }
            XCTAssertTrue(app.buttons["取消"].isHittable)
            if !phase.contains("baseline") {
                XCTAssertFalse(app.keyboards.firstMatch.exists, "滚回搜索框不能重新弹出键盘")
            }
            let end = Date().timeIntervalSince1970
            rounds.append(["opening": opening, "scroll_start": start, "scroll_end": end])
            app.buttons["取消"].tap()
            XCTAssertTrue(field.waitForNonExistence(timeout: 5))
            // 第一轮输出留存后再进行暖启动。
            let path = folder + "/\(phase)/native.json.render.json"
            let target = folder + "/\(phase)/render-\(opening).json"
            if FileManager.default.fileExists(atPath: path) {
                if FileManager.default.fileExists(atPath: target) { try FileManager.default.removeItem(atPath: target) }
                try FileManager.default.moveItem(atPath: path, toPath: target)
            }
        }
        let data = try JSONSerialization.data(withJSONObject: rounds, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: folder + "/\(phase)/scroll-times.json"))
    }
}
