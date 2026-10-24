import XCTest

final class HistorySearchPerformanceUITests: XCTestCase {
    @MainActor
    func testSearchInteractionAtFourLedgerSizes() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let folder = environment["HISTORY_PERF_DIR"], let phase = environment["HISTORY_PERF_PHASE"] else {
            throw XCTSkip("仅在搜索性能专项验收时运行")
        }
        continueAfterFailure = false
        var measurements: [[String: Any]] = []
        func save() throws {
            let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: folder + "/\(phase)/ui-times.json"))
        }
        for count in [100, 1000, 5000, 10000] {
            let app = XCUIApplication()
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                   "-hideProPreviewCard", "-proPreview", "YES", "-UseInMemoryStore", "-SeedBackupJSON",
                                   folder + "/ledgers/\(count).json", "-HistorySearchMetricsFile",
                                   folder + "/\(phase)/native-\(count).json"]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 60))
            app.tabBars.buttons["明细"].tap()
            XCTAssertTrue(app.buttons["搜索"].waitForExistence(timeout: 10))
            for opening in 0..<(count <= 1000 ? 2 : 1) {
                let started = Date()
                app.buttons["搜索"].tap()
                let field = app.textFields["history-search-field"]
                XCTAssertTrue(field.waitForExistence(timeout: 10))
                let keyboardReady = app.keyboards.firstMatch.waitForExistence(timeout: 10)
                if !keyboardReady {
                    measurements.append(["rows": count, "opening": opening, "keyboard_ready": false])
                    try save()
                    if phase != "baseline" { XCTFail("搜索框没有获得键盘焦点") }
                    break
                }
                let openMS = Date().timeIntervalSince(started) * 1000
                let typing = Date()
                field.typeText("Coffee")
                XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "找到 ")).firstMatch.waitForExistence(timeout: 10))
                let typeMS = Date().timeIntervalSince(typing) * 1000
                measurements.append(["rows": count, "opening": opening, "keyboard_ready": true, "open_ms": openMS, "type_coffee_ms": typeMS])
                try save()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
                XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "找到 ")).firstMatch.exists)
                field.typeText("xyz")
                app.buttons["清空搜索"].tap()
                XCTAssertFalse(app.staticTexts["没有匹配的记录"].exists)
                field.typeText("Coffee 4")
                XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "找到 ")).firstMatch.waitForExistence(timeout: 10))
                let month = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search-month-")).firstMatch
                XCTAssertTrue(month.waitForExistence(timeout: 5))
                month.tap()
                app.buttons["取消"].tap()
                XCTAssertTrue(field.waitForNonExistence(timeout: 5))

            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "\(phase)-\(count)-取消搜索后"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
        let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: folder + "/\(phase)/ui-times.json"))
        print("HISTORY_UI_PERF \(String(decoding: data, as: UTF8.self))")
    }
}
