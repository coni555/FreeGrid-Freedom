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
