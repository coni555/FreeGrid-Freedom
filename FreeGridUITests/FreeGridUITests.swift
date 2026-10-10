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
    func testCustomExpenseCategoryCanBeUsedAndHiddenWithoutChangingHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-ResetExpenseCategories", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.buttons["expense-categories-settings"].tap()
        let name = app.textFields["new-expense-category"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("咖啡")
        app.buttons["add-expense-category"].tap()
        let moveUp = app.buttons["move-up-咖啡"]
        for _ in 0..<6 {
            if moveUp.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(moveUp.isHittable)
        moveUp.tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "自定义分类-浅色"
        attachment.lifetime = .keepAlways
        add(attachment)

        // 重启后仍用已保存的顺序与自定义项；只在首次启动重置偏好。
        app.terminate()
        app.launchArguments = ["-isDarkMode", "NO", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["记支出"].tap()
        let picker = app.buttons["expense-category-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["咖啡"].firstMatch.tap()
        let amount = app.textFields["0.00"]
        amount.tap()
        amount.typeText("12")
        app.buttons["保存"].tap()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["expense-categories-settings"].tap()
        let hide = app.buttons["visibility-咖啡"]
        for _ in 0..<6 {
            if hide.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(hide.isHittable)
        hide.tap()
        XCTAssertEqual(hide.label, "显示咖啡")
        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["记支出"].tap()
        app.buttons["expense-category-picker"].tap()
        XCTAssertFalse(app.buttons["咖啡"].exists)
        app.tap() // 收起分类菜单
        app.buttons["取消"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["咖啡"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCategoryManagementRequiresProAccessOutsidePreview() {
        let app = XCUIApplication()
        app.launchArguments = ["-disableProPreview", "YES", "-ResetExpenseCategories", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.buttons["expense-categories-settings"].tap()
        XCTAssertTrue(app.staticTexts["自定义支出分类是 Pro 功能，正式上线后可购买解锁。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["new-expense-category"].exists)
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
        XCTAssertTrue(app.navigationBars["FreeGrid"].waitForExistence(timeout: 5)
                      || app.buttons["记支出"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Assets"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Assets"].tap()
        XCTAssertTrue(app.navigationBars["Assets"].waitForExistence(timeout: 5))
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
