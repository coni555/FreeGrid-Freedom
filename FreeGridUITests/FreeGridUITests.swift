//
//  FreeGridUITests.swift
//  FreeGridUITests
//
//  最终 smoke 只启动两次：内存库主导航一次、强制恢复页一次。
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
        app.launchArguments.append(contentsOf: ["-onboardingCompleted", "NO"])
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
