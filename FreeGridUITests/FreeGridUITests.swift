//
//  FreeGridUITests.swift
//  FreeGridUITests
//
//  覆盖两种首页布局的引导点击、完整记账流程和恢复页。
//

import XCTest

final class FreeGridUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 走完四步。卡片换位置时有动画，点偏了落在空白处：前三步照样前进，
    /// 最后一步只有按钮能关，所以等卡片停稳再点「知道了」。
    @MainActor
    private func finishGuide(_ next: XCUIElement) {
        for _ in 0..<3 { next.tap() }
        expectation(for: NSPredicate(format: "label == %@", "知道了"), evaluatedWith: next)
        waitForExpectations(timeout: 3)
        Thread.sleep(forTimeInterval: 0.4)
        next.tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testHistoryGuideRunsOnceThenRowOpensEditAndSavedNoteLeadsTheRow() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "NO", "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("12")
        app.buttons["保存"].tap()

        app.tabBars.buttons["History"].tap()
        // 第一次进来先走完指引：月份、点行、左滑、工具栏，共四步
        let next = app.buttons["guide-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        finishGuide(next)
        let row = app.staticTexts["早餐"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let note = app.textFields["edit-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("豆浆")
        let editAmount = app.textFields["edit-amount"]
        editAmount.tap()
        editAmount.typeText("5")   // 12 → 125
        app.buttons["保存"].tap()

        // 有备注后备注做主，分类退成小标签；卡片合计跟着新金额走
        XCTAssertTrue(app.staticTexts["豆浆"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["早餐"].exists)
        XCTAssertTrue(app.staticTexts["−¥125"].firstMatch.exists)
    }

    @MainActor
    func testSettingsReplaysHistoryGuideOnceLedgerHasARecord() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        // 空账本没有可圈的位置，入口只说明原因
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["记一笔后可看"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["replay-history-guide"].exists)

        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("12")
        app.buttons["保存"].tap()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["guide-list"].tap()
        app.buttons["replay-history-guide"].tap()
        // 跳到 History 并从第一步重放，四步走完后消失
        let next = app.buttons["guide-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["History"].exists)
        // 第一步没有上一步；走到第二步后可以退回来
        let back = app.buttons["guide-back"]
        XCTAssertFalse(back.exists)
        next.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 3))
        finishGuide(next)
    }

    @MainActor
    func testGuideListReplaysAssetsAndSettingsTours() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("12")
        app.buttons["保存"].tap()

        let next = app.buttons["guide-next"]
        // Assets 讲四处：净值、调拨、两张卡、被动收入
        app.tabBars.buttons["Settings"].tap()
        app.buttons["guide-list"].tap()
        app.buttons["replay-assets-guide"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Assets"].exists)
        finishGuide(next)

        // Settings 讲三处；讲之前指引列表那一页要先退回去
        app.tabBars.buttons["Settings"].tap()
        app.buttons["guide-list"].tap()
        app.buttons["replay-settings-guide"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        for _ in 0..<2 { next.tap() }
        expectation(for: NSPredicate(format: "label == %@", "知道了"), evaluatedWith: next)
        waitForExpectations(timeout: 3)
        Thread.sleep(forTimeInterval: 0.4)
        next.tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 3))

        // 看过一遍之后，再回到这两页不会自己重放
        app.tabBars.buttons["Assets"].tap()
        XCTAssertFalse(next.waitForExistence(timeout: 2))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(next.waitForExistence(timeout: 2))
        app.tabBars.buttons["Assets"].tap()
        XCTAssertFalse(next.waitForExistence(timeout: 2))
    }

    @MainActor
    func testNormalLaunchAndPrimaryNavigation() throws {
        let app = XCUIApplication()
        // 无值的 -UseInMemoryStore 会吞掉紧随其后的参数,所以它必须排在最后。
        app.launchArguments.append(contentsOf: [
            "-heroLayout", "leading", "-isDarkMode", "NO",
            "-setupGuideCompleted", "YES",
            "-historyGuideCompleted", "YES",   // 这条只测导航，不让指引遮住 Tab 栏
        ])
        app.launchArguments.append("-UseInMemoryStore")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Assets"].tap()
        XCTAssertTrue(app.navigationBars["Assets"].waitForExistence(timeout: 3))
        app.buttons["编辑现金"].tap()

        let savingsField = app.textFields["bucket-amount-field"]
        XCTAssertTrue(savingsField.waitForExistence(timeout: 3))
        savingsField.typeText("10000")
        app.buttons["保存"].tap()

        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["记支出"].tap()

        let amountField = app.textFields["0.00"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText("100")
        app.buttons["保存"].tap()

        XCTAssertTrue(app.staticTexts["99"].waitForExistence(timeout: 3))

        for title in ["Assets", "History", "Settings"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testSimulationWithoutExpenseExplainsMissingBaseline() {
        let app = XCUIApplication()
        app.launchArguments = ["-heroLayout", "leading", "-isDarkMode", "NO", "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Assets"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Assets"].tap()
        app.buttons["编辑现金"].tap()
        let cash = app.textFields["bucket-amount-field"]
        XCTAssertTrue(cash.waitForExistence(timeout: 3))
        cash.typeText("1000")
        app.buttons["保存"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        let simulate = app.buttons["模拟一笔 · 看决策影响"]
        XCTAssertTrue(simulate.waitForExistence(timeout: 5))
        if !simulate.isHittable { app.swipeUp() }
        simulate.tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("100")
        XCTAssertTrue(app.staticTexts["先记一笔支出，建立可比较的基线后再推演自由格。"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["演示这笔熄灭哪几格"].exists)
        app.buttons["关闭"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["还没有记录"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSetupGuideWalksANewUserThroughMoneyAndFirstExpenseThenToursTheDashboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-heroLayout", "leading", "-isDarkMode", "NO",
                               "-setupGuideCompleted", "NO", "-UseInMemoryStore"]
        app.launch()
        // 第 1 步：首页讲清楚大数字，带去 Assets
        let goAssets = app.buttons["setup-guide-go-assets"]
        XCTAssertTrue(goAssets.waitForExistence(timeout: 5))
        goAssets.tap()
        XCTAssertTrue(app.navigationBars["Assets"].waitForExistence(timeout: 3))
        // 第 2 步：圈里的现金卡是真的能点的
        XCTAssertFalse(app.buttons["setup-guide-go-assets"].exists)
        app.buttons["编辑现金"].tap()
        let cash = app.textFields["bucket-amount-field"]
        XCTAssertTrue(cash.waitForExistence(timeout: 3))
        cash.typeText("1000")
        app.buttons["保存"].tap()
        // 钱记好了，带回首页
        let goHome = app.buttons["setup-guide-go-home"]
        XCTAssertTrue(goHome.waitForExistence(timeout: 3))
        goHome.tap()
        // 第 3 步：圈里的记支出也是真的能点的
        XCTAssertTrue(app.staticTexts["setup-guide-text"].waitForExistence(timeout: 3))
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("50")
        app.buttons["保存"].tap()
        // 起步引导结束，接着自动讲一遍首页；新账本没有趋势行，共三步
        let next = app.buttons["guide-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["setup-guide-text"].exists)
        for _ in 0..<2 { next.tap() }
        expectation(for: NSPredicate(format: "label == %@", "知道了"), evaluatedWith: next)
        waitForExpectations(timeout: 3)
        Thread.sleep(forTimeInterval: 0.4)
        next.tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["19"].exists)   // 950 ÷ 50
    }

    @MainActor
    func testSimulationHandsItsAmountToTheExpenseSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-heroLayout", "leading", "-isDarkMode", "NO", "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        let simulate = app.buttons["模拟一笔 · 看决策影响"]
        XCTAssertTrue(simulate.waitForExistence(timeout: 5))
        if !simulate.isHittable { app.swipeUp() }
        simulate.tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.typeText("500")
        let record = app.buttons["simulate-record-expense"]
        XCTAssertTrue(record.waitForExistence(timeout: 3))
        if !record.isHittable { app.swipeUp() }
        record.tap()
        // 模拟收起后接着打开记支出，金额已经填好
        XCTAssertTrue(app.navigationBars["添加支出"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["0.00"].value as? String, "500")
        app.buttons["取消"].tap()
        // 之后从普通入口打开，不带着上次模拟的金额
        let expense = app.buttons["记支出"]
        if !expense.isHittable { app.swipeDown() }
        expense.tap()
        XCTAssertTrue(app.navigationBars["添加支出"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["0.00"].value as? String, "0.00")
    }

    /// 记支出表单打开时不抢键盘；分类从弹出菜单里选。
    /// 搜索刚点开时先等输入，不把全部记录铺出来；只搜备注和金额。
    @MainActor
    func testExpenseSheetOpensWithoutKeyboardAndSearchWaitsForAQuery() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1.5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "分类")).firstMatch.tap()
        let lunch = app.buttons["午餐"]
        XCTAssertTrue(lunch.waitForExistence(timeout: 3))
        lunch.tap()
        XCTAssertTrue(app.buttons["昨天"].exists)
        amount.tap()
        amount.typeText("20")
        app.buttons["保存"].tap()

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["午餐"].waitForExistence(timeout: 5))
        app.buttons["搜索"].tap()
        XCTAssertTrue(app.staticTexts["输入备注或金额"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["午餐"].exists)
        // 分类不归搜索管；金额能搜到，结果按月收着，只有一笔时直接展开
        let field = app.textFields["history-search-field"]
        field.typeText("午餐")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "用右上角的筛选")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["清空搜索"].tap()
        field.typeText("20")
        XCTAssertTrue(app.staticTexts["找到 1 笔"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["午餐"].exists)
    }

    /// 拍 App Store 截图，平时跳过。用法见 `_local/store-screenshots/`：
    /// 环境变量给出演示账本和输出目录时才跑，账本灌进内存，不碰真实数据。
    @MainActor
    func testCaptureStoreScreenshots() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ledger = environment["STORE_SHOTS_LEDGER"], let output = environment["STORE_SHOTS_DIR"] else {
            throw XCTSkip("只在拍商店截图时运行")
        }
        func launch(dark: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
                                   "-heroTrendExpanded", "YES", "-historyGuideCompleted", "YES",
                                   "-setupGuideCompleted", "YES", "-UseInMemoryStore", "-SeedBackupJSON", ledger]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
            return app
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.2)
            let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }

        var app = launch(dark: false)
        try shoot("1-自由天数")

        app.tabBars.buttons["History"].tap()
        try shoot("3-History")
        app.tabBars.buttons["Assets"].tap()
        try shoot("4-Assets")

        app.tabBars.buttons["Dashboard"].tap()
        let simulate = app.buttons["模拟一笔 · 看决策影响"]
        if !simulate.isHittable { app.swipeUp() }
        simulate.tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.typeText("3000")
        // 往下拖进键盘区把键盘收起，露出下面的推演结果
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)))
        Thread.sleep(forTimeInterval: 4)
        try shoot("2-模拟决策")

        app.terminate()
        app = launch(dark: true)
        try shoot("5-深色")
    }

    @MainActor
    func testTransferRejectsBalanceOverflowAndKeepsBuckets() {
        let app = XCUIApplication()
        app.launchArguments = ["-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Assets"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Assets"].tap()
        for label in ["编辑现金", "编辑资产"] {
            app.buttons[label].tap()
            let field = app.textFields["bucket-amount-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.typeText("1000000000000")
            app.buttons["保存"].tap()
        }
        let cashBefore = app.buttons["编辑现金"].value as? String
        let assetsBefore = app.buttons["编辑资产"].value as? String
        // 调拨平时收成一行, 点开才有表单
        let toggle = app.buttons["transfer-toggle"]
        if !toggle.isHittable { app.swipeUp() }
        toggle.tap()
        let amount = app.textFields["0"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("1")
        let transfer = app.buttons["确认调拨"]
        if !transfer.isHittable { app.swipeUp() }
        transfer.tap()
        XCTAssertTrue(app.alerts["保存失败"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["资产桶金额无效或超出允许范围"].exists)
        app.alerts.buttons["好"].tap()
        app.swipeDown()
        XCTAssertEqual(app.buttons["编辑现金"].value as? String, cashBefore)
        XCTAssertEqual(app.buttons["编辑资产"].value as? String, assetsBefore)
    }

    @MainActor
    func testStoreRecoveryViewAppearsWhenBootstrapFails() throws {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "-UseInMemoryStore",
            "-ForceStoreBootstrapFailure",
        ])
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["store-recovery-view"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["store-retry-button"].exists)
        XCTAssertTrue(app.staticTexts["本地数据暂时无法打开"].exists)
    }
}
