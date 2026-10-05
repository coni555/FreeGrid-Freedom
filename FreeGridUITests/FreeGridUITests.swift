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

    @MainActor
    func testNormalLaunchAndPrimaryNavigation() throws {
        let app = XCUIApplication()
        // 引导闸门存在 UserDefaults 里,跨次运行会残留;必须显式压回 NO,
        // 否则第二次跑这条用例时引导卡不再出现。无值的 -UseInMemoryStore 会吞掉
        // 紧随其后的参数,所以它必须排在最后。
        app.launchArguments.append(contentsOf: [
            "-onboardingCompleted", "NO", "-heroLayout", "leading", "-isDarkMode", "NO",
        ])
        app.launchArguments.append("-UseInMemoryStore")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 5))

        let savingsPrompt = app.buttons["先记下你有多少钱"]
        XCTAssertTrue(savingsPrompt.waitForExistence(timeout: 3))
        savingsPrompt.tap()

        XCTAssertTrue(app.navigationBars["Assets"].waitForExistence(timeout: 3))
        app.buttons["编辑现金"].tap()

        let savingsField = app.textFields["bucket-amount-field"]
        XCTAssertTrue(savingsField.waitForExistence(timeout: 3))
        savingsField.typeText("10000")
        app.buttons["保存"].tap()

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(savingsPrompt.waitForNonExistence(timeout: 3))

        let expensePrompt = app.buttons["再记一笔支出"]
        XCTAssertTrue(expensePrompt.waitForExistence(timeout: 3))
        expensePrompt.tap()

        let amountField = app.textFields["0.00"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText("100")
        app.buttons["保存"].tap()

        XCTAssertTrue(expensePrompt.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["99 天"].waitForExistence(timeout: 3))

        for title in ["Assets", "History", "Settings"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testFreedomHistoryShowsSavedStateAndNetWorth() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingCompleted", "NO", "-heroLayout", "leading", "-UseInMemoryStore"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Assets"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Assets"].tap()
        app.buttons["编辑现金"].tap()
        let field = app.textFields["bucket-amount-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("10000")
        let save = app.buttons["保存"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        save.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.tabBars.buttons["Dashboard"].tap()
        let link = app.descendants(matching: .any).matching(identifier: "freedom-history-link").firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        if !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.staticTexts["逐次变化 · 点选查看当时状态"].waitForExistence(timeout: 5))
        app.buttons["账本净值"].tap()
        XCTAssertTrue(app.staticTexts["这段记录之间的净值变化"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "自由变化记录-净值"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.swipeUp()
        let adjustment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "资产调整")).firstMatch
        XCTAssertTrue(adjustment.waitForExistence(timeout: 3))
        adjustment.tap()
        XCTAssertTrue(app.staticTexts["记录天数增长也会改变日均消费与自由天数，不等于财富增加。"].waitForExistence(timeout: 3))
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "自由变化记录-展开"
        detail.lifetime = .keepAlways
        add(detail)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(link.waitForExistence(timeout: 3))
    }

    @MainActor
    func testOnboardingCardIsTappableInVerticalLayout() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboardingCompleted", "NO", "-heroLayout", "vertical", "-isDarkMode", "YES",
            "-UseInMemoryStore",
        ]
        app.launch()
        let prompt = app.buttons["onboarding-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        // 卡片的空白边缘也应可点，不能只有文字有响应。
        prompt.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.15)).tap()
        XCTAssertTrue(app.navigationBars["Assets"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSimulationWithoutExpenseExplainsMissingBaseline() {
        let app = XCUIApplication()
        app.launchArguments = ["-heroLayout", "leading", "-isDarkMode", "NO", "-UseInMemoryStore"]
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
    func testTransferRejectsBalanceOverflowAndKeepsBuckets() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingCompleted", "YES", "-UseInMemoryStore"]
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
        app.swipeUp()
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
