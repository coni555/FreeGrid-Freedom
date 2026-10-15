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
    func testCustomExpenseCategoryCanBeUsedAndDeletedWithoutChangingHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-ResetExpenseCategories", "-UseInMemoryStore", "-proPreview", "YES"]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.buttons["expense-categories-settings"].tap()
        let addCategory = app.buttons["add-expense-category"]
        XCTAssertTrue(addCategory.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            if addCategory.isHittable { break }
            app.swipeUp()
        }
        addCategory.tap()
        let name = app.textFields["category-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("咖啡")
        app.buttons["save-category"].tap()
        // 按住「咖啡」拖到「其他」上面
        let coffee = app.buttons["category-row-咖啡"]
        let other = app.buttons["category-row-其他"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 3))
        coffee.press(forDuration: 0.8, thenDragTo: other)
        XCTAssertLessThan(coffee.frame.minY, other.frame.minY)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "自定义分类-浅色"
        attachment.lifetime = .keepAlways
        add(attachment)

        // 重启后仍用已保存的顺序与自定义项；只在首次启动重置偏好。
        app.terminate()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-UseInMemoryStore", "-KeepScratchPreferences", "-proPreview", "YES"]
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
        let row = app.buttons["category-row-咖啡"]
        for _ in 0..<6 {
            if row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(app.staticTexts["1 笔"].exists)
        row.tap()
        app.buttons["delete-category"].tap()
        // 先确认再删；删掉后这一行从列表里消失
        let confirm = app.buttons["删除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        let delete = row
        XCTAssertTrue(delete.waitForNonExistence(timeout: 3))
        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["记支出"].tap()
        app.buttons["expense-category-picker"].tap()
        XCTAssertFalse(app.buttons["咖啡"].exists)
        app.tap() // 收起分类菜单
        app.buttons["取消"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["咖啡"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Pro：把一个分类改成另一个已有分类的名字，确认后两个合并，旧账都归到留下的那个。
    @MainActor
    func testRenamingIntoAnExistingCategoryMergesThem() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-ResetExpenseCategories", "-UseInMemoryStore", "-proPreview", "YES"]
        app.launch()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("30")
        app.buttons["保存"].tap()   // 默认分类「早餐」

        app.tabBars.buttons["Settings"].tap()
        app.buttons["expense-categories-settings"].tap()
        let row = app.buttons["category-row-早餐"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let name = app.textFields["category-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "午餐")
        XCTAssertTrue(app.staticTexts["category-merge-hint"].waitForExistence(timeout: 3))
        app.buttons["save-category"].tap()
        let merge = app.buttons["合并"]
        XCTAssertTrue(merge.waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "合并分类-确认"
        shot.lifetime = .keepAlways
        add(shot)
        merge.tap()
        XCTAssertTrue(app.buttons["category-row-早餐"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1 笔"].exists)

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["午餐"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["早餐"].exists)
    }

    /// 记支出表单里没有常驻的 Pro 入口：它在分类菜单的最后一项。没有 Pro 打开购买页，有 Pro 进管理页。
    @MainActor
    func testCategoryMenuEndsWithManageOrProEntry() {
        for pro in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                   "-ResetExpenseCategories", "-UseInMemoryStore", "-proPreview", pro ? "YES" : "NO"]
            app.launch()
            app.buttons["记支出"].tap()
            let picker = app.buttons["expense-category-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["管理支出分类 · Pro"].exists)
            picker.tap()
            if pro {
                let manage = app.buttons["管理分类…"]
                XCTAssertTrue(manage.waitForExistence(timeout: 3))
                manage.tap()
                XCTAssertTrue(app.buttons["add-expense-category"].waitForExistence(timeout: 5))
            } else {
                let upsell = app.buttons["添加自己的分类 · Pro"]
                XCTAssertTrue(upsell.waitForExistence(timeout: 3))
                upsell.tap()
                XCTAssertTrue(app.buttons["pro-restore"].waitForExistence(timeout: 5))
            }
            app.terminate()
        }
    }

    /// Pro：分类改名，用这个分类的旧账在 History 里跟着改；换的图标出现在 History 行首。
    @MainActor
    func testRenamingACategoryRenamesItsRecords() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-ResetExpenseCategories", "-UseInMemoryStore", "-proPreview", "YES"]
        app.launch()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("30")
        app.buttons["保存"].tap()   // 默认分类「早餐」

        app.tabBars.buttons["Settings"].tap()
        app.buttons["expense-categories-settings"].tap()
        let row = app.buttons["category-row-早餐"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let name = app.textFields["category-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        // 点到输入框最右边，光标落在末尾，删掉两个字再输入
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "早饭")
        XCTAssertTrue(app.staticTexts["改名后，这个分类下的 1 笔记录一起改成「早饭」。"].exists)
        app.buttons["leaf"].tap()
        app.buttons["save-category"].tap()
        XCTAssertTrue(app.buttons["category-row-早饭"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["category-row-早餐"].exists)

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["早饭"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["早餐"].exists)
    }

    @MainActor
    func testHistoryGuideRunsOnceThenRowOpensEditAndSavedNoteLeadsTheRow() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "NO", "-setupGuideCompleted", "YES",
                               "-ResetExpenseCategories", "-UseInMemoryStore"]
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
    func testLockedCategoriesOpenThePaywallAndPreviewUnlocksThem() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-setupGuideCompleted", "YES", "-proPreview", "NO",
                               "-ResetExpenseCategories", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        app.buttons["expense-categories-settings"].tap()
        // 没有 Pro：看不到管理界面，只有去购买页的入口
        let openPro = app.buttons["open-pro-from-categories"]
        XCTAssertTrue(openPro.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["add-expense-category"].exists)
        openPro.tap()
        XCTAssertTrue(app.buttons["pro-restore"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["自定义支出分类"].exists)
        let paywall = XCTAttachment(screenshot: app.screenshot())
        paywall.name = "Pro购买页-未解锁"
        paywall.lifetime = .keepAlways
        add(paywall)

        // 解锁后购买页换成已解锁，关掉就能管理分类
        let preview = app.switches["pro-preview-toggle"]
        for _ in 0..<4 {
            if preview.isHittable { break }
            app.swipeUp()
        }
        preview.switches.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["pro-unlocked"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pro-restore"].exists)
        let unlocked = XCTAttachment(screenshot: app.screenshot())
        unlocked.name = "Pro购买页-已解锁"
        unlocked.lifetime = .keepAlways
        add(unlocked)
        app.buttons["pro-close"].tap()
        XCTAssertTrue(app.buttons["add-expense-category"].waitForExistence(timeout: 5))
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

    /// 在 Assets 页关掉「资产计入自由天数」：首页大数字只按现金算，图例写明资产未计入；再打开就回来。
    @MainActor
    func testAssetSwitchChangesTheDashboardNumber() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-heroLayout", "leading", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["Assets"].tap()
        for (label, amount) in [("编辑现金", "10000"), ("编辑资产", "10000")] {
            app.buttons[label].tap()
            let field = app.textFields["bucket-amount-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.typeText(amount)
            app.buttons["保存"].tap()
        }
        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["记支出"].tap()
        let expense = app.textFields["0.00"]
        XCTAssertTrue(expense.waitForExistence(timeout: 3))
        expense.tap()
        expense.typeText("100")
        app.buttons["保存"].tap()
        // 现金 9900 + 资产 10000，日均 100
        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["资产未计入"].exists)

        app.tabBars.buttons["Assets"].tap()
        let toggle = app.switches["counts-assets-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["自由天数只按现金算，资产仍在净值里。"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["99"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["199"].exists)
        XCTAssertTrue(app.staticTexts["资产未计入"].exists)

        app.tabBars.buttons["Assets"].tap()
        toggle.switches.firstMatch.tap()
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["资产未计入"].exists)
    }

    /// 有 Pro：资产拆成多项。原来的总数自动变成一项「资产」，再加两项，改一项，删一项。
    @MainActor
    func testProCanSplitAssetsIntoItemsEditAndDeleteThem() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-proPreview", "YES", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["Assets"].tap()
        app.buttons["编辑资产"].tap()
        let bucket = app.textFields["bucket-amount-field"]
        XCTAssertTrue(bucket.waitForExistence(timeout: 3))
        bucket.typeText("100000")
        app.buttons["保存"].tap()

        // 进逐项管理：总数自动变成一项「资产」
        app.buttons["编辑资产"].tap()
        let split = app.buttons["split-assets-into-items"]
        XCTAssertTrue(split.waitForExistence(timeout: 3))
        split.tap()
        let total = app.staticTexts["asset-items-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["asset-item-资产"].waitForExistence(timeout: 3))
        XCTAssertEqual(total.label, "¥100,000")

        func add(_ name: String, _ amount: String) {
            app.buttons["add-asset-item"].tap()
            let nameField = app.textFields["asset-item-name-field"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 3))
            nameField.typeText(name)
            let amountField = app.textFields["asset-item-amount-field"]
            amountField.tap()
            amountField.typeText(amount)
            app.buttons["保存"].tap()
        }
        add("车", "30000")
        add("基金", "5000")
        XCTAssertTrue(app.buttons["asset-item-基金"].waitForExistence(timeout: 3))
        XCTAssertEqual(total.label, "¥135,000")

        // 改一项：总数跟着变
        app.buttons["asset-item-资产"].tap()
        let amountField = app.textFields["asset-item-amount-field"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText(String(repeating: "\u{8}", count: 12) + "120000")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["asset-item-资产"].waitForExistence(timeout: 3))
        XCTAssertEqual(total.label, "¥155,000")

        // 删一项：先确认，总数减少对应金额，其他项不动
        app.buttons["delete-asset-item-基金"].tap()
        let confirm = app.buttons["删除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["asset-item-基金"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(total.label, "¥150,000")
        XCTAssertTrue(app.buttons["asset-item-车"].exists)

        // 回到 Assets：资产桶和净值跟着明细走
        app.navigationBars.buttons.firstMatch.tap()
        let bucketCard = app.buttons["资产明细"]
        XCTAssertTrue(bucketCard.waitForExistence(timeout: 3))
        XCTAssertEqual(bucketCard.value as? String, "¥150,000")
        XCTAssertTrue(app.staticTexts["¥150,000"].firstMatch.exists)   // 净值
    }

    /// 有 Pro：关掉一项资产的自由天数开关，回首页看到大数字变小且图例旁出现「部分资产未计入」。
    @MainActor
    func testPerItemAssetSwitchChangesTheDashboardNumber() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-heroLayout", "leading", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-proPreview", "YES", "-UseInMemoryStore"]
        app.launch()

        // 1. 设置现金 10000，资产 10000
        app.tabBars.buttons["Assets"].tap()
        for (label, amount) in [("编辑现金", "10000"), ("编辑资产", "10000")] {
            app.buttons[label].tap()
            let field = app.textFields["bucket-amount-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.typeText(amount)
            app.buttons["保存"].tap()
        }

        // 2. 将资产拆成多项：先有「资产」10000，改成 5000，再加「房」5000
        app.buttons["编辑资产"].tap()
        let split = app.buttons["split-assets-into-items"]
        XCTAssertTrue(split.waitForExistence(timeout: 3))
        split.tap()
        XCTAssertTrue(app.staticTexts["asset-items-total"].waitForExistence(timeout: 5))

        app.buttons["asset-item-资产"].tap()
        let amountField = app.textFields["asset-item-amount-field"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText(String(repeating: "\u{8}", count: 12) + "5000")
        app.buttons["保存"].tap()

        app.buttons["add-asset-item"].tap()
        let nameField = app.textFields["asset-item-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.typeText("房")
        let houseAmount = app.textFields["asset-item-amount-field"]
        houseAmount.tap()
        houseAmount.typeText("5000")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["asset-item-房"].waitForExistence(timeout: 3))

        // 3. 记一笔 100 支出：现金 9900，资产 10000（全部计入），日均 100 -> 199 天
        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["记支出"].tap()
        let expense = app.textFields["0.00"]
        XCTAssertTrue(expense.waitForExistence(timeout: 3))
        expense.tap()
        expense.typeText("100")
        app.buttons["保存"].tap()

        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["uncounted-assets-note"].exists)

        // 4. 进 Assets -> 编辑「房」 -> 关掉「计入自由天数」
        app.tabBars.buttons["Assets"].tap()
        let houseRow = app.buttons["asset-item-房"]
        if !houseRow.exists {
            let detailButton = app.buttons["资产明细"]
            XCTAssertTrue(detailButton.waitForExistence(timeout: 3))
            detailButton.tap()
        }

        XCTAssertTrue(houseRow.waitForExistence(timeout: 3))
        houseRow.tap()

        let toggle = app.switches["asset-item-counts-in-freedom-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.switches.firstMatch.tap()
        app.buttons["保存"].tap()

        // 列表上显示「未计入自由天数」
        XCTAssertTrue(app.staticTexts["未计入自由天数"].waitForExistence(timeout: 3))

        // 5. 回首页：自由天数按 9900 + 5000 = 14900 算，大数字变成 149，并显示「部分资产未计入」
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["149"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["199"].exists)
        let note = app.staticTexts["uncounted-assets-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertEqual(note.label, "部分资产未计入")

        // 6. 再把房改回计入：回到 199 天
        app.tabBars.buttons["Assets"].tap()
        if !houseRow.exists {
            let detailButton = app.buttons["资产明细"]
            XCTAssertTrue(detailButton.waitForExistence(timeout: 3))
            detailButton.tap()
        }
        XCTAssertTrue(houseRow.waitForExistence(timeout: 3))
        houseRow.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.switches.firstMatch.tap()
        app.buttons["保存"].tap()
        XCTAssertFalse(app.staticTexts["未计入自由天数"].exists)

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["uncounted-assets-note"].exists)
    }

    /// 没有 Pro：资产桶的「拆成多项」进的是锁定页，能走到购买页，不显示管理界面。
    @MainActor
    func testAssetItemsAreLockedWithoutProAndOpenThePaywall() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-proPreview", "NO", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["Assets"].tap()
        app.buttons["编辑资产"].tap()
        let bucket = app.textFields["bucket-amount-field"]
        XCTAssertTrue(bucket.waitForExistence(timeout: 3))
        bucket.typeText("1000")
        app.buttons["保存"].tap()
        app.buttons["编辑资产"].tap()
        let split = app.buttons["split-assets-into-items"]
        XCTAssertTrue(split.waitForExistence(timeout: 3))
        split.tap()
        let open = app.buttons["open-pro-from-assets"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["add-asset-item"].exists)
        // 锁定页不会悄悄把总数拆成一项
        XCTAssertFalse(app.buttons["asset-item-资产"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "资产逐项-锁定页"
        shot.lifetime = .keepAlways
        add(shot)
        open.tap()
        XCTAssertTrue(app.buttons["pro-restore"].waitForExistence(timeout: 5))
    }

    /// Pro 每月还款：Assets 里加一笔房贷，首页数字变小、格子上出现还款日的孔和图例。
    @MainActor
    func testProAddsALoanAndTheDashboardRunsThroughRepaymentDays() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-heroLayout", "leading", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-proPreview", "YES", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["Assets"].tap()
        app.buttons["编辑现金"].tap()
        let cash = app.textFields["bucket-amount-field"]
        XCTAssertTrue(cash.waitForExistence(timeout: 3))
        cash.typeText("20000")
        app.buttons["保存"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["记支出"].tap()
        let expense = app.textFields["0.00"]
        XCTAssertTrue(expense.waitForExistence(timeout: 3))
        expense.tap()
        expense.typeText("100")
        app.buttons["保存"].tap()
        // 现金 19900，日均 100，没有贷款
        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["repayment-day-legend"].exists)

        app.tabBars.buttons["Assets"].tap()
        let add = app.buttons["add-loan-button"]
        if !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        let name = app.textFields["loan-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("房贷")
        let monthly = app.textFields["loan-monthly-field"]
        monthly.tap()
        monthly.typeText("3000")
        let periods = app.textFields["loan-periods-field"]
        periods.tap()
        periods.typeText("24")
        XCTAssertTrue(app.staticTexts["loan-last-due"].label.hasPrefix("最后一期："))
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["loan-row"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["repayment-day-legend"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["199"].exists)
    }

    /// 没有 Pro、也没加过贷款：Assets 里看不到每月还款。
    @MainActor
    func testLoansAreHiddenWithoutProWhenNoneWereAdded() {
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-proPreview", "NO", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["Assets"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["PASSIVE · 被动收入"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["REPAY · 每月还款"].exists)
        XCTAssertFalse(app.buttons["add-loan-button"].exists)
    }

    /// 自定义分类的截图：管理列表、编辑表单、History 行首图标，深浅各一。只在给了环境变量时运行。
    @MainActor
    func testCaptureCategoryScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ledger = environment["CATEGORY_SHOTS_LEDGER"], let output = environment["CATEGORY_SHOTS_DIR"] else {
            throw XCTSkip("只在拍分类截图时运行")
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.2)
            let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        for dark in [false, true] {
            let mode = dark ? "深色" : "浅色"
            let app = XCUIApplication()
            app.launchArguments = ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
                                   "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                   "-proPreview", "YES", "-ResetExpenseCategories",
                                   "-UseInMemoryStore", "-SeedBackupJSON", ledger]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
            app.tabBars.buttons["Settings"].tap()
            app.buttons["expense-categories-settings"].tap()
            let addCategory = app.buttons["add-expense-category"]
            XCTAssertTrue(addCategory.waitForExistence(timeout: 5))
            for _ in 0..<6 {
                if addCategory.isHittable { break }
                app.swipeUp()
            }
            addCategory.tap()
            let name = app.textFields["category-name-field"]
            XCTAssertTrue(name.waitForExistence(timeout: 3))
            name.typeText("房租")
            app.buttons["save-category"].tap()
            app.swipeDown()
            try shoot("\(mode)-1-分类列表")
            app.buttons["category-row-午餐"].firstMatch.tap()
            XCTAssertTrue(app.textFields["category-name-field"].waitForExistence(timeout: 3))
            try shoot("\(mode)-2-编辑分类")
            app.buttons["取消"].tap()
            app.tabBars.buttons["History"].tap()
            try shoot("\(mode)-3-History图标")
            app.buttons["按分类筛选"].firstMatch.tap()
            try shoot("\(mode)-4-分类筛选条")
            app.tabBars.buttons["Dashboard"].tap()
            app.buttons["记支出"].tap()
            let picker = app.buttons["expense-category-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            try shoot("\(mode)-5-记支出表单")
            picker.tap()
            XCTAssertTrue(app.buttons["管理分类…"].waitForExistence(timeout: 3))
            try shoot("\(mode)-6-分类菜单")
            app.terminate()
        }
    }

    /// 每月还款的截图：演示账本带两笔贷款，开 App 时补扣到期的月供。
    /// 拍 Assets 的还款卡、添加表单、首页格子上的孔、History 里的扣款，深浅各一。只在给了环境变量时运行。
    @MainActor
    func testCaptureLoanScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ledger = environment["LOAN_SHOTS_LEDGER"], let output = environment["LOAN_SHOTS_DIR"] else {
            throw XCTSkip("只在拍每月还款截图时运行")
        }
        func launch(dark: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
                                   "-heroTrendExpanded", "NO", "-historyGuideCompleted", "YES",
                                   "-setupGuideCompleted", "YES", "-proPreview", "YES",
                                   "-UseInMemoryStore", "-SeedBackupJSON", ledger]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
            return app
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.2)
            let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        for dark in [false, true] {
            let mode = dark ? "深色" : "浅色"
            let app = launch(dark: dark)
            let legend = app.descendants(matching: .any)["repayment-day-legend"]
            XCTAssertTrue(legend.waitForExistence(timeout: 5))
            app.swipeUp()
            try shoot("\(mode)-1-首页格子")

            app.tabBars.buttons["Assets"].tap()
            app.swipeUp()
            app.swipeUp()
            XCTAssertTrue(app.buttons["loan-row"].firstMatch.waitForExistence(timeout: 3))
            try shoot("\(mode)-2-每月还款")

            app.buttons["add-loan-button"].tap()
            let name = app.textFields["loan-name-field"]
            XCTAssertTrue(name.waitForExistence(timeout: 3))
            name.typeText("装修贷")
            let monthly = app.textFields["loan-monthly-field"]
            monthly.tap()
            monthly.typeText("1500")
            let periods = app.textFields["loan-periods-field"]
            periods.tap()
            periods.typeText("36")
            try shoot("\(mode)-3-添加表单")
            app.buttons["取消"].tap()

            app.tabBars.buttons["History"].tap()
            let payment = app.staticTexts["自动扣款"].firstMatch
            XCTAssertTrue(payment.waitForExistence(timeout: 3))
            app.swipeUp()
            try shoot("\(mode)-4-History扣款")
            app.terminate()
        }
    }

    /// 资产总开关的截图：开和关时的首页与 Assets 开关卡。只在给了环境变量时运行。
    /// 演示账本做法见 `_local/store-screenshots/`，账本灌进内存，不碰真实数据。
    @MainActor
    func testCaptureAssetSwitchScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ledger = environment["STORE_SHOTS_LEDGER"], let output = environment["ASSET_SWITCH_SHOTS_DIR"] else {
            throw XCTSkip("只在拍方案图时运行")
        }
        func launch(dark: Bool, counts: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
                                   "-heroTrendExpanded", "YES", "-historyGuideCompleted", "YES",
                                   "-setupGuideCompleted", "YES", "-proPreview", "NO",
                                   "-countAssetsInFreedom", counts ? "YES" : "NO",
                                   "-UseInMemoryStore", "-SeedBackupJSON", ledger]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
            return app
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.2)
            let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        for dark in [false, true] {
            let mode = dark ? "深色" : "浅色"
            var app = launch(dark: dark, counts: true)
            try shoot("\(mode)-1-开-首页")
            app.tabBars.buttons["Assets"].tap()
            try shoot("\(mode)-4-开-Assets开关卡")
            app.terminate()
            app = launch(dark: dark, counts: false)
            try shoot("\(mode)-2-关-首页")
            app.tabBars.buttons["Assets"].tap()
            try shoot("\(mode)-5-关-Assets开关卡")
            app.terminate()
        }
    }

    /// 退款之后（没有 Pro 但已经拆好了项）：每一项和金额还在，不能增删改；合并成总数后回到只改总数。
    @MainActor
    func testItemsStayVisibleWithoutProAndCanBeMergedBackIntoATotal() throws {
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("asset-items-ui-test.json")
        try Data("""
        {"schema_version":2,"assets":{"total":135000,"locked_assets":135000,"cash":0},
         "asset_items":[{"name":"房","amount":100000},{"name":"定期","amount":30000},{"name":"基金","amount":5000}]}
        """.utf8).write(to: backup)
        defer { try? FileManager.default.removeItem(at: backup) }
        let app = XCUIApplication()
        app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-proPreview", "NO", "-UseInMemoryStore", "-SeedBackupJSON", backup.path]
        app.launch()
        app.tabBars.buttons["Assets"].tap()
        let card = app.buttons["资产明细"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertEqual(card.value as? String, "¥135,000")
        card.tap()
        XCTAssertTrue(app.buttons["asset-item-房"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["asset-item-基金"].exists)
        XCTAssertEqual(app.staticTexts["asset-items-total"].label, "¥135,000")
        XCTAssertFalse(app.buttons["add-asset-item"].exists)
        XCTAssertFalse(app.buttons["delete-asset-item-房"].exists)
        let merge = app.buttons["merge-asset-items"]
        XCTAssertTrue(merge.exists)
        merge.tap()
        let confirm = app.buttons["合并"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["asset-item-房"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["asset-items-total"].label, "¥135,000")
        app.navigationBars.buttons.firstMatch.tap()
        let editable = app.buttons["编辑资产"]
        XCTAssertTrue(editable.waitForExistence(timeout: 3))
        XCTAssertEqual(editable.value as? String, "¥135,000")
    }

    /// 资产逐项记录的截图（演示账本）：列表、新增表单、锁定页。只在给了环境变量时运行。
    @MainActor
    func testCaptureAssetItemScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ledger = environment["STORE_SHOTS_LEDGER"], let output = environment["ASSET_ITEM_SHOTS_DIR"] else {
            throw XCTSkip("只在拍方案图时运行")
        }
        func launch(dark: Bool, pro: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
                                   "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                   "-proPreview", pro ? "YES" : "NO", "-UseInMemoryStore", "-SeedBackupJSON", ledger]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
            return app
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.2)
            let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        func openItems(_ app: XCUIApplication) {
            app.tabBars.buttons["Assets"].tap()
            app.buttons["编辑资产"].tap()
            let split = app.buttons["split-assets-into-items"]
            XCTAssertTrue(split.waitForExistence(timeout: 3))
            split.tap()
            XCTAssertTrue(app.staticTexts["asset-items-total"].waitForExistence(timeout: 5))
        }
        for dark in [false, true] {
            let mode = dark ? "深色" : "浅色"
            var app = launch(dark: dark, pro: true)
            openItems(app)
            for (name, amount) in [("车", "30000"), ("基金", "5000")] {
                app.buttons["add-asset-item"].tap()
                let nameField = app.textFields["asset-item-name-field"]
                XCTAssertTrue(nameField.waitForExistence(timeout: 3))
                nameField.typeText(name)
                let amountField = app.textFields["asset-item-amount-field"]
                amountField.tap()
                amountField.typeText(amount)
                app.buttons["保存"].tap()
                XCTAssertTrue(app.buttons["asset-item-\(name)"].waitForExistence(timeout: 3))
            }
            try shoot("\(mode)-1-资产列表")
            app.buttons["add-asset-item"].tap()
            XCTAssertTrue(app.textFields["asset-item-name-field"].waitForExistence(timeout: 3))
            try shoot("\(mode)-2-新增表单")
            app.terminate()
            app = launch(dark: dark, pro: false)
            openItems(app)
            try shoot("\(mode)-3-锁定页")
            app.terminate()
        }
    }

    /// 阶段 3 截图：演示账本拍资产列表上的逐项开关、首页「部分资产未计入」，深浅各一。
    @MainActor
    func testCaptureStage3Screens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ledger = environment["STORE_SHOTS_LEDGER"], let output = environment["STAGE3_SHOTS_DIR"] else {
            throw XCTSkip("只在拍阶段 3 截图时运行")
        }
        func launch(dark: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
                                   "-heroTrendExpanded", "YES", "-historyGuideCompleted", "YES",
                                   "-setupGuideCompleted", "YES", "-proPreview", "YES",
                                   "-countAssetsInFreedom", "YES",
                                   "-UseInMemoryStore", "-SeedBackupJSON", ledger]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
            return app
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.2)
            let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        for dark in [false, true] {
            let mode = dark ? "深色" : "浅色"
            let app = launch(dark: dark)

            // 先进 Assets 把资产拆成多项，并把其中一项关掉
            app.tabBars.buttons["Assets"].tap()
            app.buttons["编辑资产"].tap()
            let split = app.buttons["split-assets-into-items"]
            XCTAssertTrue(split.waitForExistence(timeout: 3))
            split.tap()
            XCTAssertTrue(app.staticTexts["asset-items-total"].waitForExistence(timeout: 5))

            // 添加一项不计入的资产「房」
            app.buttons["add-asset-item"].tap()
            let nameField = app.textFields["asset-item-name-field"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 3))
            nameField.typeText("房")
            let amountField = app.textFields["asset-item-amount-field"]
            amountField.tap()
            amountField.typeText("100000")
            // 关掉计入自由天数
            let toggle = app.switches["asset-item-counts-in-freedom-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 3))
            toggle.switches.firstMatch.tap()
            try shoot("\(mode)-2-编辑表单-开关关")
            app.buttons["保存"].tap()

            // 拍资产列表（列表上能一眼看出「房」未计入）
            XCTAssertTrue(app.buttons["asset-item-房"].waitForExistence(timeout: 3))
            try shoot("\(mode)-1-资产列表-逐项开关")

            // 回首页：部分资产未计入
            app.tabBars.buttons["Dashboard"].tap()
            XCTAssertTrue(app.staticTexts["uncounted-assets-note"].waitForExistence(timeout: 3))
            try shoot("\(mode)-3-首页-部分资产未计入")
            app.terminate()
        }
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
