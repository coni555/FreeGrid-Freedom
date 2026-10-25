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

    /// 走完 `steps` 步（默认四步）。卡片换位置时有动画，点偏了落在空白处：前面几步照样前进，
    /// 最后一步只有按钮能关，所以等卡片停稳再点「知道了」。
    @MainActor
    private func finishGuide(_ next: XCUIElement, steps: Int = 4) {
        for _ in 0..<(steps - 1) { next.tap() }
        expectation(for: NSPredicate(format: "label == %@", "知道了"), evaluatedWith: next)
        waitForExpectations(timeout: 3)
        Thread.sleep(forTimeInterval: 0.4)
        next.tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testCustomExpenseCategoryCanBeUsedAndDeletedWithoutChangingHistory() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-ResetExpenseCategories", "-UseInMemoryStore", "-proPreview", "YES"]
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("expense-categories-settings", inCard: "settings-card-ledger")
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
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-UseInMemoryStore", "-KeepScratchPreferences", "-proPreview", "YES"]
        app.launch()
        app.tabBars.buttons["首页"].tap()
        app.buttons["记支出"].tap()
        let picker = app.buttons["expense-category-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["咖啡"].firstMatch.tap()
        let amount = app.textFields["0.00"]
        amount.tap()
        amount.typeText("12")
        app.buttons["保存"].tap()

        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("expense-categories-settings", inCard: "settings-card-ledger")
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
        app.tabBars.buttons["首页"].tap()
        app.buttons["记支出"].tap()
        app.buttons["expense-category-picker"].tap()
        XCTAssertFalse(app.buttons["咖啡"].exists)
        app.tap() // 收起分类菜单
        app.buttons["取消"].tap()
        app.tabBars.buttons["明细"].tap()
        XCTAssertTrue(app.staticTexts["咖啡"].firstMatch.waitForExistence(timeout: 5))
    }

    /// 首页卡片：首页上按住拖动换位置（小卡和今日长条都行）；编辑面板里移除、加回来、全部添加，重开 App 后还在；最后恢复默认
    @MainActor
    func testHomeCardsAreDraggedOnHomeAndEditedInThePanel() {
        let app = XCUIApplication()
        func launch(keepingPreferences: Bool) {
            app.launchArguments = ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                   "-UseInMemoryStore", "-proPreview", "NO"]
                + (keepingPreferences ? ["-KeepScratchPreferences"] : [])
            app.launch()
            app.buttons["记支出"].tap()
            let amount = app.textFields["0.00"]
            XCTAssertTrue(amount.waitForExistence(timeout: 3))
            amount.tap()
            amount.typeText("30")
            app.buttons["保存"].tap()
        }
        func card(_ stat: String) -> XCUIElement { app.buttons["home-stat-\(stat)"] }
        let done = app.buttons["home-stat-editor-done"]

        launch(keepingPreferences: false)
        // 没有被动收入：默认是 日均 / 本月 / 记账，下面是今日对比长条
        XCTAssertTrue(card("daily").waitForExistence(timeout: 5))
        for _ in 0..<4 where !app.buttons["edit-home-stats"].isHittable { app.swipeUp() }
        XCTAssertTrue(card("month").exists)
        XCTAssertTrue(card("track").exists)
        XCTAssertTrue(card("todayBar").exists)
        XCTAssertGreaterThan(card("todayBar").frame.minY, card("daily").frame.maxY)

        // 首页上直接拖：本月拖到日均的位置；今日长条拖到最前面，还是占一整行
        card("month").press(forDuration: 1.2, thenDragTo: card("daily"))
        XCTAssertLessThan(card("month").frame.minX, card("daily").frame.minX)
        card("todayBar").press(forDuration: 1.2, thenDragTo: card("month"))
        XCTAssertLessThan(card("todayBar").frame.maxY, card("month").frame.minY)
        XCTAssertGreaterThan(card("todayBar").frame.width, card("month").frame.width * 2)

        // 点一张卡打开编辑面板；移除记账天数和今日长条，它们回到「还可以添加」；再全部添加
        card("daily").tap()
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        app.buttons["remove-stat-track"].tap()
        app.buttons["remove-stat-todayBar"].tap()
        XCTAssertTrue(app.buttons["add-stat-track"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["add-stat-todayBar"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "编辑卡片"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["add-all-stats"].tap()
        XCTAssertTrue(app.buttons["remove-stat-next"].waitForExistence(timeout: 3))
        // 再拿掉今日长条
        app.buttons["remove-stat-todayBar"].tap()
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 3))
        XCTAssertTrue(card("next").waitForExistence(timeout: 3))
        XCTAssertFalse(card("todayBar").exists)

        // 七张小卡排成三行：收起只留第一行（3 张），再展开
        let toggle = app.buttons["home-cards-toggle"]
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        toggle.tap()
        XCTAssertTrue(card("next").waitForNonExistence(timeout: 3))
        XCTAssertTrue(card("month").exists)
        XCTAssertEqual(toggle.value as? String, "已收起")
        toggle.tap()
        XCTAssertTrue(card("next").waitForExistence(timeout: 3))

        // 重开 App 后还是改过的样子
        app.terminate()
        launch(keepingPreferences: true)
        XCTAssertTrue(card("next").waitForExistence(timeout: 5))
        XCTAssertTrue(card("base").exists)
        XCTAssertFalse(card("todayBar").exists)

        // 恢复默认
        for _ in 0..<4 where !app.buttons["edit-home-stats"].isHittable { app.swipeUp() }
        app.buttons["edit-home-stats"].tap()
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        app.buttons["reset-home-stats"].tap()
        done.tap()
        XCTAssertTrue(card("todayBar").waitForExistence(timeout: 3))
        XCTAssertTrue(card("track").exists)
        XCTAssertFalse(card("base").exists)
    }

    /// Pro：把一个分类改成另一个已有分类的名字，确认后两个合并，旧账都归到留下的那个。
    @MainActor
    func testRenamingIntoAnExistingCategoryMergesThem() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-ResetExpenseCategories", "-UseInMemoryStore", "-proPreview", "YES"]
        app.launch()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("30")
        app.buttons["保存"].tap()   // 默认分类「早餐」

        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("expense-categories-settings", inCard: "settings-card-ledger")
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

        app.tabBars.buttons["明细"].tap()
        XCTAssertTrue(app.staticTexts["午餐"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["早餐"].exists)
    }

    /// 记支出表单里没有常驻的 Pro 入口：它在分类菜单的最后一项。没有 Pro 打开购买页，有 Pro 进管理页。
    @MainActor
    func testCategoryMenuEndsWithManageOrProEntry() {
        for pro in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
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
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-ResetExpenseCategories", "-UseInMemoryStore", "-proPreview", "YES"]
        app.launch()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("30")
        app.buttons["保存"].tap()   // 默认分类「早餐」

        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("expense-categories-settings", inCard: "settings-card-ledger")
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

        app.tabBars.buttons["明细"].tap()
        XCTAssertTrue(app.staticTexts["早饭"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["早餐"].exists)
    }

    @MainActor
    func testHistoryGuideRunsOnceThenRowOpensEditAndSavedNoteLeadsTheRow() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "NO", "-setupGuideCompleted", "YES",
                               "-ResetExpenseCategories", "-UseInMemoryStore"]
        app.launch()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("12")
        app.buttons["保存"].tap()

        app.tabBars.buttons["明细"].tap()
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
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-setupGuideCompleted", "YES", "-proPreview", "NO",
                               "-ResetExpenseCategories", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("expense-categories-settings", inCard: "settings-card-ledger")
        // 没有 Pro：直接打开购买页，不经过中间页
        XCTAssertTrue(app.buttons["pro-restore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["add-expense-category"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["pro-comparison"].exists)
        let paywall = XCTAttachment(screenshot: app.screenshot())
        paywall.name = "Pro购买页-未解锁"
        paywall.lifetime = .keepAlways
        add(paywall)

        // 「贷款与分期」旁边的 ⓘ：点开说明，「知道了」关掉
        let info = app.buttons["pro-info-贷款与分期"]
        XCTAssertTrue(info.exists)
        info.tap()
        XCTAssertTrue(app.staticTexts["有负债，也能看见自由"].waitForExistence(timeout: 3))
        let infoShot = XCTAttachment(screenshot: app.screenshot())
        infoShot.name = "Pro购买页-说明"
        infoShot.lifetime = .keepAlways
        add(infoShot)
        app.buttons["pro-info-close"].tap()
        XCTAssertTrue(app.staticTexts["有负债，也能看见自由"].waitForNonExistence(timeout: 3))

        // 解锁后购买页换成已解锁，关掉就能管理分类
        // 底部固定的购买栏会盖住调试开关的一部分，先滑到底让它露出来
        let preview = app.switches["pro-preview-toggle"]
        app.swipeUp()
        for _ in 0..<3 {
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

    /// 试用的四个阶段：没试用、试用中、试用结束但专属价还在、专属价也过了。
    /// 模拟器读不到商品，用 -proSamplePrices 显示示例价格，-proTrialDaysAgo 指定试用开始了几天
    @MainActor
    func testPaywallWalksThroughTrialAndSpecialPrice() {
        let stages: [(daysAgo: String?, name: String)] = [
            (nil, "未试用"), ("2", "试用中"), ("10", "试用结束-专属价"), ("20", "原价"),
        ]
        for stage in stages {
            let app = XCUIApplication()
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-setupGuideCompleted", "YES", "-proPreview", "NO",
                                   "-UseInMemoryStore", "-proSamplePrices"]
            if let days = stage.daysAgo { app.launchArguments += ["-proTrialDaysAgo", days] }
            app.launch()
            app.tabBars.buttons["设置"].tap()
            let card = app.buttons["settings-card-pro"]
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.tap()
            XCTAssertTrue(app.descendants(matching: .any)["pro-header"].waitForExistence(timeout: 5))
            let note = app.staticTexts["pro-price-note"]
            XCTAssertTrue(note.waitForExistence(timeout: 5))
            switch stage.daysAgo {
            case nil:
                XCTAssertTrue(app.buttons["pro-start-trial"].exists)
                XCTAssertTrue(app.buttons["pro-purchase"].label.contains("¥19.90"))
                XCTAssertTrue(note.label.contains("买断优惠价 ¥19.90，开启体验后保留 14 天，之后恢复 ¥29.90"))
                XCTAssertFalse(app.staticTexts["pro-trial-status"].exists)
            case "2":
                XCTAssertFalse(app.buttons["pro-start-trial"].exists)
                XCTAssertEqual(app.staticTexts["pro-trial-status"].label, "体验中 · 还剩 5 天")
                XCTAssertTrue(app.buttons["pro-purchase"].label.contains("¥19.90"))
                XCTAssertTrue(note.label.contains("买断优惠价还剩 12 天"))
            case "10":
                XCTAssertEqual(app.staticTexts["pro-trial-status"].label, "体验已结束")
                XCTAssertTrue(app.buttons["pro-purchase"].label.contains("¥19.90"))
                XCTAssertTrue(note.label.contains("买断优惠价还剩 4 天"))
            default:
                XCTAssertEqual(app.staticTexts["pro-trial-status"].label, "体验已结束")
                XCTAssertTrue(app.buttons["pro-purchase"].label.contains("¥29.90"))
                XCTAssertEqual(note.label, "一次购买 · 永久使用 · 不会自动续费")
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Pro购买页-\(stage.name)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }

    @MainActor
    func testSettingsReplaysHistoryGuideOnceLedgerHasARecord() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        // 空账本没有可圈的位置，入口只说明原因
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings-card-about"].tap()
        XCTAssertTrue(app.staticTexts["记一笔后可看"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["replay-history-guide"].exists)

        app.tabBars.buttons["首页"].tap()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("12")
        app.buttons["保存"].tap()

        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("guide-list", inCard: "settings-card-about")
        app.buttons["replay-history-guide"].tap()
        // 跳到 History 并从第一步重放，四步走完后消失
        let next = app.buttons["guide-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["明细"].exists)
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
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("12")
        app.buttons["保存"].tap()

        let next = app.buttons["guide-next"]
        // Assets 讲五处：净值、调拨、两张卡、固定支出、被动收入
        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("guide-list", inCard: "settings-card-about")
        app.buttons["replay-assets-guide"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["钱包"].exists)
        finishGuide(next, steps: 5)

        // Settings 讲六处（没有 Pro 时多讲 Pro 卡）；讲之前指引列表那一页要先退回去
        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("guide-list", inCard: "settings-card-about")
        app.buttons["replay-settings-guide"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["设置"].exists)
        finishGuide(next, steps: 6)

        // 看过一遍之后，再回到这两页不会自己重放
        app.tabBars.buttons["钱包"].tap()
        XCTAssertFalse(next.waitForExistence(timeout: 2))
        app.tabBars.buttons["设置"].tap()
        XCTAssertFalse(next.waitForExistence(timeout: 2))
        app.tabBars.buttons["钱包"].tap()
        XCTAssertFalse(next.waitForExistence(timeout: 2))
    }

    /// 有 Pro 时：Assets 是「钱与时间」，讲它自己的六处；Settings 不讲 Pro 卡，五处
    @MainActor
    func testProGuidesFollowTheMoneyTimeAssetsAndSkipTheProCard() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-proPreview", "YES", "-UseInMemoryStore"]
        app.launch()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("12")
        app.buttons["保存"].tap()

        let next = app.buttons["guide-next"]
        let text = app.staticTexts["guide-text"]
        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("guide-list", inCard: "settings-card-about")
        app.buttons["replay-assets-guide"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["unit-days"].exists)
        // 第二步讲 ¥ / 天，最后一步讲「出」
        next.tap()
        XCTAssertTrue(text.label.hasPrefix("切到钟"))
        for _ in 0..<4 { next.tap() }
        expectation(for: NSPredicate(format: "label == %@", "知道了"), evaluatedWith: next)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(text.label.hasPrefix("「出」"))
        Thread.sleep(forTimeInterval: 0.4)
        next.tap()
        XCTAssertTrue(next.waitForNonExistence(timeout: 3))

        app.tabBars.buttons["设置"].tap()
        app.tapSettingsRow("guide-list", inCard: "settings-card-about")
        app.buttons["replay-settings-guide"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        finishGuide(next, steps: 5)
    }

    /// 使用说明空账本也能看：设置 → FreeGrid → 使用说明 → 一章。给了 GUIDE_SHOTS_DIR 时顺便拍图
    @MainActor
    /// 外观卡里换语言：当场整页换成英文，停在设置页、外观卡还开着；再换回中文
    func testLanguageSwitchesInAppAndStaysOnSettings() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["设置"].tap()
        let picker = app.segmentedControls["language-picker"]
        if !picker.waitForExistence(timeout: 2) { app.buttons["settings-card-look"].tap() }
        XCTAssertTrue(picker.waitForExistence(timeout: 3))

        let output = ProcessInfo.processInfo.environment["L10N_SHOTS_DIR"]
        func shoot(_ name: String) {
            guard let output else { return }
            Thread.sleep(forTimeInterval: 0.8)
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
        }
        shoot("switch-0-zh")

        picker.buttons["English"].tap()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        XCTAssertTrue(app.segmentedControls["language-picker"].buttons["English"].isSelected)
        shoot("switch-1-en-settings")
        app.tabBars.buttons["Dashboard"].tap()
        shoot("switch-2-en-home")
        app.tabBars.buttons["Settings"].tap()

        app.segmentedControls["language-picker"].buttons["中文"].tap()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["设置"].isSelected)
    }

    func testUserManualOpensFromSettingsEvenWithAnEmptyLedger() throws {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        let output = ProcessInfo.processInfo.environment["GUIDE_SHOTS_DIR"]
        func shoot(_ name: String) throws {
            guard let output else { return }
            Thread.sleep(forTimeInterval: 0.8)
            try XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
        }
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings-card-about"].tap()
        XCTAssertTrue(app.buttons["user-manual"].waitForExistence(timeout: 3))
        try shoot("说明-0-FreeGrid卡")
        app.tapSettingsRow("user-manual", inCard: "settings-card-about")
        XCTAssertTrue(app.navigationBars["使用说明"].waitForExistence(timeout: 5))
        try shoot("说明-1-目录")
        for (index, name) in [(0, "怎么算"), (2, "Assets")] {
            app.buttons["manual-chapter-\(index)"].tap()
            XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 3))
            try shoot("说明-2-\(name)")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["使用说明"].waitForExistence(timeout: 3))
        }
    }

    /// 各页讲解逐步截图：免费（经典 Assets）和 Pro（钱与时间）各一套，浅色。只在给了环境变量时运行。
    @MainActor
    func testCaptureGuideScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ledger = environment["STORE_SHOTS_LEDGER"], let split = environment["ACCOUNTS_SPLIT_LEDGER"],
              let output = environment["GUIDE_SHOTS_DIR"] else {
            throw XCTSkip("只在拍讲解截图时运行")
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 0.9)
            let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        for pro in [false, true] {
            let edition = pro ? "Pro" : "免费"
            let app = XCUIApplication()
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-heroLayout", "leading", "-historyGuideCompleted", "YES",
                                   "-setupGuideCompleted", "YES", "-proPreview", pro ? "YES" : "NO",
                                   "-UseInMemoryStore", "-SeedBackupJSON", pro ? split : ledger]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
            let next = app.buttons["guide-next"]
            for (tour, page) in [("replay-dashboard-guide", "首页"), ("replay-assets-guide", "钱包"),
                                 ("replay-history-guide", "明细"), ("replay-settings-guide", "设置")] {
                app.tabBars.buttons["设置"].tap()
                app.tapSettingsRow("guide-list", inCard: "settings-card-about")
                app.buttons[tour].tap()
                XCTAssertTrue(next.waitForExistence(timeout: 5))
                var step = 1
                while next.exists {
                    try shoot("\(edition)-\(page)-\(step)")
                    next.tap()
                    Thread.sleep(forTimeInterval: 0.5)
                    step += 1
                    if step > 8 { break }
                }
            }
            app.terminate()
        }
    }

    @MainActor
    func testNormalLaunchAndPrimaryNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI
        // 无值的 -UseInMemoryStore 会吞掉紧随其后的参数,所以它必须排在最后。
        app.launchArguments.append(contentsOf: [
            "-heroLayout", "leading", "-isDarkMode", "NO",
            "-setupGuideCompleted", "YES",
            "-historyGuideCompleted", "YES",   // 这条只测导航，不让指引遮住 Tab 栏
        ])
        app.launchArguments.append("-UseInMemoryStore")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))

        app.tabBars.buttons["钱包"].tap()
        XCTAssertTrue(app.navigationBars["钱包"].waitForExistence(timeout: 3))
        app.buttons["编辑现金"].tap()

        let savingsField = app.textFields["bucket-amount-field"]
        XCTAssertTrue(savingsField.waitForExistence(timeout: 3))
        savingsField.typeText("10000")
        app.buttons["保存"].tap()

        app.tabBars.buttons["首页"].tap()
        app.buttons["记支出"].tap()

        let amountField = app.textFields["0.00"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText("100")
        app.buttons["保存"].tap()

        XCTAssertTrue(app.staticTexts["99"].waitForExistence(timeout: 3))

        for title in ["钱包", "明细", "设置"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testSimulationWithoutExpenseExplainsMissingBaseline() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-heroLayout", "leading", "-isDarkMode", "NO", "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
        app.launch()
        XCTAssertTrue(app.navigationBars["FreeGrid"].waitForExistence(timeout: 5)
                      || app.buttons["记支出"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["钱包"].waitForExistence(timeout: 5))
        app.tabBars.buttons["钱包"].tap()
        XCTAssertTrue(app.navigationBars["钱包"].waitForExistence(timeout: 5))
        app.buttons["编辑现金"].tap()
        let cash = app.textFields["bucket-amount-field"]
        XCTAssertTrue(cash.waitForExistence(timeout: 3))
        cash.typeText("1000")
        app.buttons["保存"].tap()
        app.tabBars.buttons["首页"].tap()
        let simulate = app.buttons["模拟一笔 · 看决策影响"]
        XCTAssertTrue(simulate.waitForExistence(timeout: 5))
        if !simulate.isHittable { app.swipeUp() }
        simulate.tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("100")
        XCTAssertTrue(app.staticTexts["先记一笔支出，才能演示格子怎么变。"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["演示这笔熄灭哪几格"].exists)
        app.buttons["关闭"].tap()
        app.tabBars.buttons["明细"].tap()
        XCTAssertTrue(app.staticTexts["还没有记录"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSetupGuideWalksANewUserThroughMoneyAndFirstExpenseThenToursTheDashboard() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-heroLayout", "leading", "-isDarkMode", "NO",
                               "-setupGuideCompleted", "NO", "-UseInMemoryStore"]
        app.launch()
        // 第 1 步：首页讲清楚大数字，带去 Assets
        let goAssets = app.buttons["setup-guide-go-assets"]
        XCTAssertTrue(goAssets.waitForExistence(timeout: 5))
        goAssets.tap()
        XCTAssertTrue(app.navigationBars["钱包"].waitForExistence(timeout: 3))
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

    /// 起步引导任何一步都能跳过；这里测最后一步（记支出），圈里能点、圈外点不动的那一步
    /// 不带 -setupGuideCompleted：带了的话启动参数压过 App 写的值，点了跳过也读回「没跳过」
    @MainActor
    func testSetupGuideCanBeSkippedAtTheExpenseStep() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-heroLayout", "leading", "-isDarkMode", "NO", "-UseInMemoryStore"]
        app.launch()
        let goAssets = app.buttons["setup-guide-go-assets"]
        XCTAssertTrue(goAssets.waitForExistence(timeout: 5))
        goAssets.tap()
        XCTAssertTrue(app.navigationBars["钱包"].waitForExistence(timeout: 3))
        app.buttons["编辑现金"].tap()
        let cash = app.textFields["bucket-amount-field"]
        XCTAssertTrue(cash.waitForExistence(timeout: 3))
        cash.typeText("1000")
        app.buttons["保存"].tap()
        let goHome = app.buttons["setup-guide-go-home"]
        XCTAssertTrue(goHome.waitForExistence(timeout: 3))
        goHome.tap()
        let text = app.staticTexts["setup-guide-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        app.buttons["setup-guide-skip"].tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 3))
    }

    /// 新用户：走完起步引导后，首页和 Settings 都不弹 Pro 介绍或购买页
    @MainActor
    func testNewUserIsNeverShownTheProIntro() throws {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-heroLayout", "leading", "-isDarkMode", "NO",
                               "-proPreview", "NO", "-UseInMemoryStore", "-proIntro", "-proSamplePrices"]
        app.launch()
        let goAssets = app.buttons["setup-guide-go-assets"]
        XCTAssertTrue(goAssets.waitForExistence(timeout: 5))
        goAssets.tap()
        XCTAssertTrue(app.navigationBars["钱包"].waitForExistence(timeout: 3))
        app.buttons["编辑现金"].tap()
        let cash = app.textFields["bucket-amount-field"]
        XCTAssertTrue(cash.waitForExistence(timeout: 3))
        cash.typeText("1000")
        app.buttons["保存"].tap()
        let goHome = app.buttons["setup-guide-go-home"]
        XCTAssertTrue(goHome.waitForExistence(timeout: 3))
        goHome.tap()
        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("50")
        app.buttons["保存"].tap()
        let next = app.buttons["guide-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 6))
        finishGuide(next, steps: 3)

        let paywall = app.descendants(matching: .any)["pro-header"]
        let intro = app.descendants(matching: .any)["pro-intro-returning"]
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(paywall.exists)
        XCTAssertFalse(intro.exists)
        app.tabBars.buttons["设置"].tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(paywall.exists)
        XCTAssertFalse(intro.exists)
    }

    /// 老用户：账本里已经有支出，打开 2.0 就在首页弹一张卡片，先讲免费更新再提 Pro；
    /// 「看看 Pro」进购买页，「知道了」直接收起
    @MainActor
    func testReturningUserSeesTheProIntroOnFirstLaunch() throws {
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("pro-intro-ui-test.json")
        let expenses = (1...9).map { #"{"amount":100,"category":"午餐","note":"","date":"2026-10-0\#($0)"}"# }.joined(separator: ",")
        try Data("""
        {"schema_version":2,"assets":{"total":10000,"locked_assets":0,"cash":10000},"expenses":[\(expenses)]}
        """.utf8).write(to: backup)
        defer { try? FileManager.default.removeItem(at: backup) }
        for dark in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = XCUIApplication.chineseUI + ["-heroLayout", "leading", "-isDarkMode", dark ? "YES" : "NO",
                                   "-historyGuideCompleted", "YES", "-proPreview", "NO", "-UseInMemoryStore",
                                   "-SeedBackupJSON", backup.path, "-proIntro", "-proSamplePrices"]
            app.launch()
            let card = app.descendants(matching: .any)["pro-intro-returning"]
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["以上所有人都有，一直免费。"].exists)
            Thread.sleep(forTimeInterval: 0.8)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Pro介绍-老用户卡片-\(dark ? "深色" : "浅色")"
            shot.lifetime = .keepAlways
            add(shot)
            if dark {
                app.buttons["intro-card-close"].tap()
                XCTAssertTrue(card.waitForNonExistence(timeout: 3))
            } else {
                app.buttons["intro-card-learn-more"].tap()
                XCTAssertTrue(card.waitForNonExistence(timeout: 3))
                let paywall = app.descendants(matching: .any)["pro-header"]
                XCTAssertTrue(paywall.waitForExistence(timeout: 5))
                app.buttons["pro-close"].tap()
                XCTAssertTrue(paywall.waitForNonExistence(timeout: 3))
            }
            XCTAssertTrue(app.buttons["记支出"].exists)
            app.terminate()
        }
    }

    /// 新用户：记满 7 天那一笔一记下，首页就弹「记账 7 天的小结」；「看看 Pro」进购买页，之后重开不再弹。
    /// 前 6 天放在备份里，第 7 天在 App 里记
    @MainActor
    func testNewUserSeesTheFirstWeekRecapWhenTheSeventhDayIsLogged() throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        /// 截到昨天的几天，每天一笔
        func backup(days amounts: [Int], name: String) throws -> URL {
            let expenses = amounts.enumerated().map { index, amount in
                let day = Calendar.current.date(byAdding: .day, value: index - amounts.count, to: .now)!
                return #"{"amount":\#(amount),"category":"午餐","note":"","date":"\#(formatter.string(from: day))"}"#
            }.joined(separator: ",")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try Data("""
            {"schema_version":2,"assets":{"total":10000,"locked_assets":0,"cash":10000},"expenses":[\(expenses)]}
            """.utf8).write(to: url)
            return url
        }
        let sixDays = try backup(days: [48, 96, 62, 71, 55, 104], name: "first-week-6.json")
        let sevenDays = try backup(days: [48, 96, 62, 71, 55, 104, 146], name: "first-week-7.json")
        defer { [sixDays, sevenDays].forEach { try? FileManager.default.removeItem(at: $0) } }
        func arguments(seed: URL) -> [String] {
            ["-heroLayout", "leading", "-isDarkMode", "NO", "-setupGuideCompleted", "YES",
             "-historyGuideCompleted", "YES", "-proPreview", "NO", "-UseInMemoryStore",
             "-SeedBackupJSON", seed.path, "-proIntroAudience", "newcomer", "-proIntro", "-proSamplePrices"]
        }
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + arguments(seed: sixDays)
        app.launch()
        let recap = app.descendants(matching: .any)["first-week-recap"]
        // 只记了 6 天：不弹
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertFalse(recap.exists)

        app.buttons["记支出"].tap()
        let amount = app.textFields["0.00"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("146")
        app.buttons["保存"].tap()
        XCTAssertTrue(recap.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["记账 7 天的小结"].exists)
        XCTAssertTrue(app.buttons["intro-card-learn-more"].exists)
        Thread.sleep(forTimeInterval: 0.8)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "新用户-第一周小结"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["intro-card-learn-more"].tap()
        XCTAssertTrue(recap.waitForNonExistence(timeout: 3))
        let paywall = app.descendants(matching: .any)["pro-header"]
        XCTAssertTrue(paywall.waitForExistence(timeout: 5))
        app.buttons["pro-close"].tap()
        XCTAssertTrue(paywall.waitForNonExistence(timeout: 3))

        // 重开 App 不再弹（账本是临时的，重开时换成记满 7 天的那份）
        app.terminate()
        app.launchArguments = XCUIApplication.chineseUI + arguments(seed: sevenDays) + ["-KeepScratchPreferences"]
        app.launch()
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertFalse(recap.exists)
    }

    @MainActor
    func testSimulationHandsItsAmountToTheExpenseSheet() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-heroLayout", "leading", "-isDarkMode", "NO", "-setupGuideCompleted", "YES", "-UseInMemoryStore"]
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
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES",
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

        app.tabBars.buttons["明细"].tap()
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
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-heroLayout", "leading", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-assetsLayout", "classic", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["钱包"].tap()
        for (label, amount) in [("编辑现金", "10000"), ("编辑资产", "10000")] {
            app.buttons[label].tap()
            let field = app.textFields["bucket-amount-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.typeText(amount)
            app.buttons["保存"].tap()
        }
        app.tabBars.buttons["首页"].tap()
        app.buttons["记支出"].tap()
        let expense = app.textFields["0.00"]
        XCTAssertTrue(expense.waitForExistence(timeout: 3))
        expense.tap()
        expense.typeText("100")
        app.buttons["保存"].tap()
        // 现金 9900 + 资产 10000，日均 100
        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["资产未计入"].exists)

        app.tabBars.buttons["钱包"].tap()
        // 资产抽屉里那一行前面的方格就是总开关
        let toggle = app.switches["counts-assets-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "计入")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "不计入")

        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["99"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["199"].exists)
        XCTAssertTrue(app.staticTexts["资产未计入"].exists)

        app.tabBars.buttons["钱包"].tap()
        toggle.tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["资产未计入"].exists)
    }

    /// 有 Pro：资产拆成多项。第一项默认从原来的总数里拆出来（总数不变），再加一项新的钱，改一项，删一项。
    @MainActor
    func testProCanSplitAssetsIntoItemsEditAndDeleteThem() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-proPreview", "YES", "-assetsLayout", "classic", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["钱包"].tap()
        app.buttons["编辑资产"].tap()
        let bucket = app.textFields["bucket-amount-field"]
        XCTAssertTrue(bucket.waitForExistence(timeout: 3))
        bucket.typeText("100000")
        app.buttons["保存"].tap()

        func fill(_ name: String, _ amount: String) {
            let nameField = app.textFields["asset-item-name-field"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 3))
            nameField.typeText(name)
            let amountField = app.textFields["asset-item-amount-field"]
            amountField.tap()
            amountField.typeText(amount)
        }
        let card = app.buttons["assets-drawer"]
        func total() -> String { String((card.value as? String ?? "").prefix { $0 != "，" }) }

        // 从编辑资产的弹窗进拆分：「车」默认从原来的 10 万里拆出来，总数不变
        app.buttons["编辑资产"].tap()
        let split = app.buttons["split-assets-into-items"]
        XCTAssertTrue(split.waitForExistence(timeout: 3))
        split.tap()
        fill("车", "30000")
        if let output = ProcessInfo.processInfo.environment["FIXED_SHOTS_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: output).appendingPathComponent("5-拆成多项.png"))
        }
        XCTAssertEqual(app.staticTexts["asset-item-source-result"].label, "「资产」¥100,000 → ¥70,000，资产总数不变")
        app.buttons["save-asset-item"].tap()
        XCTAssertTrue(app.buttons["asset-item-车"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["asset-item-资产"].exists)
        XCTAssertEqual(total(), "¥100,000")

        // 「添加资产项」加的是新的钱：总数变大
        app.buttons["add-asset-item"].tap()
        fill("基金", "5000")
        XCTAssertEqual(app.staticTexts["asset-item-source-result"].label, "资产总数 ¥100,000 → ¥105,000")
        app.buttons["save-asset-item"].tap()
        XCTAssertTrue(app.buttons["asset-item-基金"].waitForExistence(timeout: 3))
        XCTAssertEqual(total(), "¥105,000")

        // 改一项：总数跟着变（资产 70000 → 120000）
        app.buttons["asset-item-资产"].tap()
        let amountField = app.textFields["asset-item-amount-field"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText(String(repeating: "\u{8}", count: 12) + "120000")
        app.buttons["save-asset-item"].tap()
        XCTAssertTrue(app.buttons["asset-item-资产"].waitForExistence(timeout: 3))
        XCTAssertEqual(total(), "¥155,000")

        // 删一项：在编辑弹窗里删，先确认，总数减少对应金额，其他项不动
        app.buttons["asset-item-基金"].tap()
        let delete = app.buttons["delete-asset-item"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        let confirm = app.buttons["删除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["asset-item-基金"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(total(), "¥150,000")
        XCTAssertTrue(app.buttons["asset-item-车"].exists)
        XCTAssertTrue(app.staticTexts["¥150,000"].firstMatch.exists)   // 净值
        // 拆开以后总开关退场，由各项自己决定
        XCTAssertFalse(app.switches["counts-assets-toggle"].exists)
    }

    /// 有 Pro：在资产明细里点一项前面的方格，首页大数字变小且图例旁出现「部分资产未计入」；再点回来。
    @MainActor
    func testPerItemAssetSwitchChangesTheDashboardNumber() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-heroLayout", "leading", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-proPreview", "YES", "-assetsLayout", "classic", "-UseInMemoryStore"]
        app.launch()

        // 1. 现金 10000，资产 10000
        app.tabBars.buttons["钱包"].tap()
        for (label, amount) in [("编辑现金", "10000"), ("编辑资产", "10000")] {
            app.buttons[label].tap()
            let field = app.textFields["bucket-amount-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.typeText(amount)
            app.buttons["保存"].tap()
        }

        // 2. 在资产抽屉里拆分：「房」5000 从资产里拆出来，剩下「资产」5000
        let split = app.buttons["add-asset-item"]
        XCTAssertTrue(split.waitForExistence(timeout: 3))
        split.tap()
        let nameField = app.textFields["asset-item-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.typeText("房")
        let houseAmount = app.textFields["asset-item-amount-field"]
        houseAmount.tap()
        houseAmount.typeText("5000")
        app.buttons["save-asset-item"].tap()
        XCTAssertTrue(app.buttons["asset-item-房"].waitForExistence(timeout: 3))

        // 3. 记一笔 100 支出：现金 9900，资产 10000（全部计入），日均 100 -> 199 天
        app.tabBars.buttons["首页"].tap()
        app.buttons["记支出"].tap()
        let expense = app.textFields["0.00"]
        XCTAssertTrue(expense.waitForExistence(timeout: 3))
        expense.tap()
        expense.typeText("100")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["uncounted-assets-note"].exists)

        // 4. 回 Assets，点「房」前面的方格：不计入
        app.tabBars.buttons["钱包"].tap()
        let houseCell = app.switches["asset-item-counts-房"]
        XCTAssertTrue(houseCell.waitForExistence(timeout: 3))
        XCTAssertEqual(houseCell.value as? String, "计入")
        houseCell.tap()
        XCTAssertEqual(houseCell.value as? String, "不计入")

        // 5. 回首页：按 9900 + 5000 = 14900 算，大数字变成 149，并显示「部分资产未计入」
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["149"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["199"].exists)
        let note = app.staticTexts["uncounted-assets-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertEqual(note.label, "部分资产未计入")

        // 6. 再点一次方格：回到 199 天
        app.tabBars.buttons["钱包"].tap()
        XCTAssertTrue(houseCell.waitForExistence(timeout: 3))
        houseCell.tap()
        XCTAssertEqual(houseCell.value as? String, "计入")
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["uncounted-assets-note"].exists)
    }

    /// 没有 Pro：两处「拆成多项」都直接打开购买页，不会悄悄把总数拆成一项。
    @MainActor
    func testAssetItemsAreLockedWithoutProAndOpenThePaywall() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-proPreview", "NO", "-assetsLayout", "classic", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["钱包"].tap()
        app.buttons["编辑资产"].tap()
        let bucket = app.textFields["bucket-amount-field"]
        XCTAssertTrue(bucket.waitForExistence(timeout: 3))
        bucket.typeText("1000")
        app.buttons["保存"].tap()

        app.buttons["编辑资产"].tap()
        let split = app.buttons["split-assets-into-items"]
        XCTAssertTrue(split.waitForExistence(timeout: 3))
        split.tap()
        let restore = app.buttons["pro-restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        if let output = ProcessInfo.processInfo.environment["FIXED_SHOTS_DIR"] {
            Thread.sleep(forTimeInterval: 1.2)
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: output).appendingPathComponent("7-购买页-从资产进.png"))
        }
        app.buttons["pro-close"].tap()
        XCTAssertTrue(restore.waitForNonExistence(timeout: 5))

        let fromSwitch = app.buttons["add-asset-item"]
        XCTAssertTrue(fromSwitch.waitForExistence(timeout: 3))
        fromSwitch.tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        app.buttons["pro-close"].tap()
        XCTAssertTrue(restore.waitForNonExistence(timeout: 5))

        XCTAssertFalse(app.buttons["asset-item-资产"].exists)
        XCTAssertTrue(app.switches["counts-assets-toggle"].exists)
    }

    /// 主题选「系统」：外观卡收起后写「跟随系统」，首页的深浅开关跟着系统（模拟器是浅色）；
    /// 在首页点开关，就固定成深色、不再跟随。
    @MainActor
    func testThemeCanFollowTheSystem() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "YES", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-UseInMemoryStore"]
        app.launch()
        XCTAssertTrue(app.buttons["切换浅色模式"].waitForExistence(timeout: 5))
        app.tabBars.buttons["设置"].tap()
        let picker = app.segmentedControls["theme-picker"]
        if !picker.waitForExistence(timeout: 2) { app.buttons["settings-card-look"].tap() }
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.buttons["系统"].tap()
        app.buttons["settings-card-look"].tap()
        let summary = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "跟随系统")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 3))

        app.tabBars.buttons["首页"].tap()
        let toDark = app.buttons["切换深色模式"]
        XCTAssertTrue(toDark.waitForExistence(timeout: 3))
        toDark.tap()
        XCTAssertTrue(app.buttons["切换浅色模式"].waitForExistence(timeout: 3))
        app.tabBars.buttons["设置"].tap()
        let fixed = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "深色")).firstMatch
        XCTAssertTrue(fixed.waitForExistence(timeout: 3))
    }

    /// Pro 每月还款：Assets 里加一笔房贷，首页数字变小、格子上出现还款日的孔和图例。
    @MainActor
    func testProAddsALoanAndTheDashboardRunsThroughRepaymentDays() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-heroLayout", "leading", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-proPreview", "YES", "-assetsLayout", "classic", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["钱包"].tap()
        app.buttons["编辑现金"].tap()
        let cash = app.textFields["bucket-amount-field"]
        XCTAssertTrue(cash.waitForExistence(timeout: 3))
        cash.typeText("20000")
        app.buttons["保存"].tap()
        app.tabBars.buttons["首页"].tap()
        app.buttons["记支出"].tap()
        let expense = app.textFields["0.00"]
        XCTAssertTrue(expense.waitForExistence(timeout: 3))
        expense.tap()
        expense.typeText("100")
        app.buttons["保存"].tap()
        // 现金 19900，日均 100，没有贷款
        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["repayment-day-legend"].exists)

        app.tabBars.buttons["钱包"].tap()
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

        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["repayment-day-legend"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["199"].exists)
    }

    /// 没有 Pro 也能加固定支出：Assets 里加一笔房租，首页数字变小，但格子上不打孔；加房贷、车贷会打开购买页。
    /// 给了 FIXED_SHOTS_DIR 时顺手拍表单、抽屉、首页。
    @MainActor
    func testFreeUsersAddRentAsAFixedExpenseButLoansNeedPro() throws {
        let output = ProcessInfo.processInfo.environment["FIXED_SHOTS_DIR"]
        func shoot(_ name: String) throws {
            guard let output else { return }
            Thread.sleep(forTimeInterval: 1.2)
            try XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
        }
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-heroLayout", "leading", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-proPreview", "NO", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["钱包"].tap()
        app.buttons["编辑现金"].tap()
        let cash = app.textFields["bucket-amount-field"]
        XCTAssertTrue(cash.waitForExistence(timeout: 3))
        cash.typeText("20000")
        app.buttons["保存"].tap()
        app.tabBars.buttons["首页"].tap()
        app.buttons["记支出"].tap()
        let expense = app.textFields["0.00"]
        XCTAssertTrue(expense.waitForExistence(timeout: 3))
        expense.tap()
        expense.typeText("100")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 3))

        app.tabBars.buttons["钱包"].tap()
        let add = app.buttons["add-fixed-button"]
        if !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        let name = app.textFields["loan-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("房租")
        let amount = app.textFields["loan-monthly-field"]
        amount.tap()
        amount.typeText("2500")
        XCTAssertFalse(app.textFields["loan-periods-field"].exists)
        XCTAssertTrue(app.staticTexts["fixed-schedule"].label.contains("自动记一笔支出"))
        try shoot("1-添加固定支出")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["loan-row"].waitForExistence(timeout: 3))
        try shoot("2-固定支出抽屉")

        let addLoan = app.buttons["add-loan-button"]
        if !addLoan.isHittable { app.swipeUp() }
        addLoan.tap()
        XCTAssertTrue(app.descendants(matching: .any)["pro-comparison"].waitForExistence(timeout: 3))
        app.buttons["pro-close"].tap()

        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.staticTexts["199"].waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["repayment-day-legend"].exists)
        try shoot("3-首页")

        // Daily 卡的日均含房租折成的每天（100 + 2500 ÷ 30.44），小字拆开写；Today 只和日常比
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["182.1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["日常 100 · 固定 82"].exists)
        try shoot("4-首页日均")
    }

    /// 被动收入选「每年」：填一次到账的总数，下面折成每月和每天；列表行写「每年 ¥6,000」。
    /// 给了 FIXED_SHOTS_DIR 时拍一张表单。
    @MainActor
    func testPassiveIncomeCanBePaidOutYearly() throws {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-assetsLayout", "classic", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["钱包"].tap()
        let add = app.buttons["添加被动收入"]
        if !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(app.navigationBars["添加被动收入"].waitForExistence(timeout: 3))
        app.typeText("分红")
        app.buttons["passive-interval-picker"].tap()
        let yearly = app.buttons["每年"]
        XCTAssertTrue(yearly.waitForExistence(timeout: 3))
        yearly.tap()
        let amount = app.textFields["passive-monthly-field"]
        amount.tap()
        amount.typeText("6000")
        XCTAssertEqual(app.staticTexts["passive-summary"].label, "折合每月 ¥500 · 每天 ¥16.7")
        if let output = ProcessInfo.processInfo.environment["FIXED_SHOTS_DIR"] {
            Thread.sleep(forTimeInterval: 1.2)
            try XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: output).appendingPathComponent("6-被动收入每年.png"))
        }
        app.buttons["保存"].tap()
        let row = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "每年 ¥6,000")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.label.contains("¥500/月"))

        // 每天 16.7 盖住了记的 10 块：首页说已覆盖，但写明只按 1 天的账算
        app.tabBars.buttons["首页"].tap()
        app.buttons["记支出"].tap()
        let expense = app.textFields["0.00"]
        XCTAssertTrue(expense.waitForExistence(timeout: 3))
        expense.tap()
        expense.typeText("10")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["按 1 天记账估算，被动收入已覆盖开销"].waitForExistence(timeout: 3))
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
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
                                   "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                                   "-proPreview", "YES", "-ResetExpenseCategories",
                                   "-UseInMemoryStore", "-SeedBackupJSON", ledger]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
            app.tabBars.buttons["设置"].tap()
            app.tapSettingsRow("expense-categories-settings", inCard: "settings-card-ledger")
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
            app.tabBars.buttons["明细"].tap()
            try shoot("\(mode)-3-History图标")
            app.buttons["按分类筛选"].firstMatch.tap()
            try shoot("\(mode)-4-分类筛选条")
            app.tabBars.buttons["首页"].tap()
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
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
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

            app.tabBars.buttons["钱包"].tap()
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

            app.tabBars.buttons["明细"].tap()
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
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
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
            app.tabBars.buttons["钱包"].tap()
            try shoot("\(mode)-4-开-Assets开关卡")
            app.terminate()
            app = launch(dark: dark, counts: false)
            try shoot("\(mode)-2-关-首页")
            app.tabBars.buttons["钱包"].tap()
            try shoot("\(mode)-5-关-Assets开关卡")
            app.terminate()
        }
    }

    /// 自由卡（Pro 第五项）：首页升级提示只出现一次；长按大数字、设置页那一行都能打开；没有 Pro 能看卡，分享要 Pro。
    @MainActor
    func testFreedomCardOpensFromHomeAndSettingsAndPromptShowsOnce() throws {
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("freedom-card-ui-test.json")
        let expenses = (1...9).map { #"{"amount":100,"category":"午餐","note":"","date":"2026-10-0\#($0)"}"# }.joined(separator: ",")
        try Data("""
        {"schema_version":2,"assets":{"total":10000,"locked_assets":0,"cash":10000},"expenses":[\(expenses)]}
        """.utf8).write(to: backup)
        defer { try? FileManager.default.removeItem(at: backup) }
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-heroLayout", "leading", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-proPreview", "NO", "-UseInMemoryStore", "-SeedBackupJSON", backup.path]
        app.launch()

        // 第一次有了银卡以上：大数字下面一行提示，点开是卡，分享要 Pro
        let prompt = app.buttons["freedom-card-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        prompt.tap()
        let holder = app.textFields["freedom-card-holder"]
        XCTAssertTrue(holder.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["share-freedom-card-pro"].exists)
        XCTAssertFalse(app.buttons["share-freedom-card"].exists)
        app.buttons["完成"].tap()
        // 看过了，提示不再出现
        XCTAssertTrue(prompt.waitForNonExistence(timeout: 3))

        // 彩蛋：长按大数字
        let number = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9,]+$'")).firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 3))
        number.press(forDuration: 0.8)
        XCTAssertTrue(holder.waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        // 设置页：紧挨着自检
        app.tabBars.buttons["设置"].tap()
        let row = app.buttons["settings-freedom-card"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(holder.waitForExistence(timeout: 5))
    }

    /// 设置页截图：上半屏、滑到底，浅色深色各一套（免费用户）。只在给了环境变量时运行。
    @MainActor
    func testCaptureSettingsScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ledger = environment["SETTINGS_LEDGER"], let output = environment["SETTINGS_SHOTS_DIR"] else {
            throw XCTSkip("只在拍设置页截图时运行")
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.2)
            let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        for dark in [false, true] {
            let mode = dark ? "深色" : "浅色"
            let app = XCUIApplication()
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
                                   "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES", "-proPreview", "NO",
                                   "-UseInMemoryStore", "-SeedBackupJSON", ledger]
            app.launch()
            app.tabBars.buttons["设置"].tap()
            XCTAssertTrue(app.buttons["settings-freedom-card"].waitForExistence(timeout: 5))
            if !app.segmentedControls["assets-layout-picker"].waitForExistence(timeout: 2) {
                app.buttons["settings-card-look"].tap()
            }
            try shoot("\(mode)-1-外观")
            app.buttons["settings-card-ledger"].tap()
            try shoot("\(mode)-2-账本")
            app.buttons["settings-card-pro"].tap()
            XCTAssertTrue(app.buttons["pro-close"].waitForExistence(timeout: 5))
            try shoot("\(mode)-3-Pro")
            app.buttons["pro-close"].tap()
            app.buttons["settings-card-about"].tap()
            app.swipeUp()
            try shoot("\(mode)-4-FreeGrid")
            app.buttons["settings-card-about"].tap()
            app.swipeDown()
            try shoot("\(mode)-5-都收起")
            app.terminate()
        }
    }

    /// 自由卡截图：首页提示、卡（Pro 能分享）、海报分享面板、设置页那一行，浅色深色各一套。只在给了环境变量时运行。
    @MainActor
    func testCaptureFreedomCardScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ledger = environment["FREEDOM_CARD_LEDGER"], let output = environment["FREEDOM_CARD_SHOTS_DIR"] else {
            throw XCTSkip("只在拍自由卡截图时运行")
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.2)
            let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        for dark in [false, true] {
            let mode = dark ? "深色" : "浅色"
            let app = XCUIApplication()
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
                                   "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES", "-proPreview", "YES",
                                   "-UseInMemoryStore", "-SeedBackupJSON", ledger]
            app.launch()
            let prompt = app.buttons["freedom-card-prompt"]
            XCTAssertTrue(prompt.waitForExistence(timeout: 10))
            try shoot("\(mode)-1-首页提示")
            prompt.tap()
            XCTAssertTrue(app.buttons["share-freedom-poster"].waitForExistence(timeout: 5))
            try shoot("\(mode)-2-卡")
            app.textFields["freedom-card-holder"].tap()
            app.textFields["freedom-card-holder"].typeText("coni\n")
            XCTAssertFalse(app.switches["freedom-card-shows-money"].exists)
            try shoot("\(mode)-3-昵称")
            app.buttons["share-freedom-poster"].tap()
            Thread.sleep(forTimeInterval: 1.5)
            try shoot("\(mode)-4-分享海报")
            app.terminate()
            app.launch()
            app.tabBars.buttons["设置"].tap()
            XCTAssertTrue(app.buttons["settings-freedom-card"].waitForExistence(timeout: 5))
            try shoot("\(mode)-5-设置页")
            app.terminate()
        }
    }

    /// 体验刚结束、体验期间拆了资产和现金、加了贷款：首页弹「回到免费版」，合并资产和现金、删掉停用的贷款后写「已调整完成」；
    /// 之后从购买页对照表下面还能打开。给了 BACK_TO_FREE_SHOTS_DIR 时拍图。
    @MainActor
    func testBackToFreeGuideAppearsOnceTheTrialEndsAndMergesEverything() throws {
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("back-to-free-ui-test.json")
        try Data("""
        {"schema_version":3,"assets":{"total":137000,"locked_assets":135000,"cash":2000},
         "expenses":[{"amount":1000,"category":"咖啡","date":"2026-10-01"}],
         "asset_items":[{"name":"房","amount":100000,"counts_in_freedom":false},{"name":"基金","amount":35000}],
         "cash_accounts":[{"name":"微信","amount":500},{"name":"招行卡","amount":1500}],
         "loans":[{"id":"6f1d2c9a-0b4e-4c55-9a51-1c2f6e4d7a02","name":"车贷","monthly_amount":1200,"due_day":25,
                   "periods_at_start":18,"start_date":"2026-09-01","processed_through":"2026-09-01","sort_order":0}]}
        """.utf8).write(to: backup)
        defer { try? FileManager.default.removeItem(at: backup) }
        let output = ProcessInfo.processInfo.environment["BACK_TO_FREE_SHOTS_DIR"]
        func shoot(_ name: String) throws {
            guard let output else { return }
            Thread.sleep(forTimeInterval: 0.8)
            try XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
        }
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-proPreview", "NO", "-proWasUnlocked", "YES", "-proTrialDaysAgo", "10",
                               "-hideProPreviewCard", "-proSamplePrices", "-assetsLayout", "classic",
                               "-UseInMemoryStore", "-SeedBackupJSON", backup.path]
        app.launch()

        XCTAssertTrue(app.staticTexts["Pro 体验已结束"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["「房」目前未计入自由天数。合并后资产统一计入，之后可整体选择是否计入。"].exists)
        try shoot("1-引导")
        if output != nil {
            app.swipeUp()
            try shoot("1b-引导底部")
            app.swipeDown()
        }

        app.buttons["back-to-free-merge-assets"].tap()
        let confirm = app.buttons["合并"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["back-to-free-merge-assets"].waitForNonExistence(timeout: 3))
        app.buttons["back-to-free-merge-cash"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["back-to-free-merge-cash"].waitForNonExistence(timeout: 3))

        // 贷款已停用，引导删除
        XCTAssertTrue(app.staticTexts["已停用"].exists)
        app.buttons["back-to-free-delete-loans"].tap()
        let delete = app.buttons["删除"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertTrue(app.descendants(matching: .any)["back-to-free-finished"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["back-to-free-pro"].exists)
        try shoot("2-整理好了")
        app.buttons["back-to-free-done"].tap()

        // 合并后在 Assets 能直接改总数，资产总开关是开的（基金一直算着）
        app.tabBars.buttons["钱包"].tap()
        let editable = app.buttons["编辑资产"]
        XCTAssertTrue(editable.waitForExistence(timeout: 5))
        XCTAssertEqual(editable.value as? String, "¥135,000")
        let toggle = app.switches["counts-assets-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "计入")
        try shoot("3-Assets")

        // 整理完就不用再给入口了
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings-card-pro"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pro-header"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pro-back-to-free"].exists)
    }

    /// 已经关掉引导、还没整理的人：设置里 Pro 卡提示待调整、点了打开引导；从引导进购买页，那里不再套一层入口
    @MainActor
    func testPaywallReopensTheBackToFreeGuide() throws {
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("back-to-free-paywall-ui-test.json")
        try Data("""
        {"schema_version":3,"assets":{"total":2000,"locked_assets":0,"cash":2000},
         "expenses":[{"amount":1000,"category":"午餐","date":"2026-10-01"}],
         "cash_accounts":[{"name":"微信","amount":500},{"name":"招行卡","amount":1500}]}
        """.utf8).write(to: backup)
        defer { try? FileManager.default.removeItem(at: backup) }
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-proPreview", "NO", "-proTrialDaysAgo", "10", "-hideProPreviewCard", "-proSamplePrices",
                               "-UseInMemoryStore", "-SeedBackupJSON", backup.path]
        app.launch()
        XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Pro 体验已结束"].exists)   // 没有「上次还能用」的记录，不弹

        // 设置里 Pro 卡写「1 项待调整」，点了直接打开引导
        app.tabBars.buttons["设置"].tap()
        let proCard = app.buttons["settings-card-pro"]
        XCTAssertTrue(proCard.waitForExistence(timeout: 5))
        XCTAssertTrue(proCard.label.contains("1 项待调整"))
        proCard.tap()
        XCTAssertTrue(app.staticTexts["Pro 体验已结束"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["back-to-free-pro"].label.contains("保留子账户"))
        // 从引导进购买页：那里不再套一层「继续使用免费版」
        app.buttons["back-to-free-pro"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pro-header"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pro-back-to-free"].exists)
        app.buttons["pro-close"].tap()
        app.buttons["back-to-free-done"].tap()
        XCTAssertTrue(app.staticTexts["Pro 体验已结束"].waitForNonExistence(timeout: 5))

        // 从别的地方进购买页（这里是「支出分类」），对照表下面能打开引导
        app.tapSettingsRow("expense-categories-settings", inCard: "settings-card-ledger")
        let link = app.buttons["pro-back-to-free"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        // 对照表下面的链接可能藏在底部购买栏后面（系统仍算它点得到）：滑到它整个露在购买栏上面为止
        let barTop = ["pro-notice", "pro-start-trial", "pro-purchase"]
            .map { app.descendants(matching: .any)[$0].firstMatch }
            .filter(\.exists)
            .map(\.frame.minY)
            .min() ?? app.frame.maxY
        for _ in 0..<4 where link.frame.maxY > barTop {
            app.swipeUp()
        }
        link.tap()
        XCTAssertTrue(app.staticTexts["Pro 体验已结束"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["back-to-free-merge-cash"].exists)
        XCTAssertFalse(app.buttons["back-to-free-merge-assets"].exists)
    }

    /// 退款之后（没有 Pro 但已经拆好了项）：每一项和金额还在 Assets 页上，不能增删改、不能点方格；合并成总数后回到总开关。
    @MainActor
    func testItemsStayVisibleWithoutProAndCanBeMergedBackIntoATotal() throws {
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("asset-items-ui-test.json")
        try Data("""
        {"schema_version":2,"assets":{"total":135000,"locked_assets":135000,"cash":0},
         "asset_items":[{"name":"房","amount":100000,"counts_in_freedom":false},{"name":"定期","amount":30000},{"name":"基金","amount":5000}]}
        """.utf8).write(to: backup)
        defer { try? FileManager.default.removeItem(at: backup) }
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-proPreview", "NO", "-assetsLayout", "classic", "-UseInMemoryStore", "-SeedBackupJSON", backup.path]
        app.launch()
        app.tabBars.buttons["钱包"].tap()
        let card = app.buttons["assets-drawer"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue((card.value as? String ?? "").hasPrefix("¥135,000"))
        XCTAssertTrue(app.buttons["asset-item-房"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["asset-item-基金"].exists)
        XCTAssertFalse(app.buttons["add-asset-item"].exists)
        XCTAssertFalse(app.buttons["delete-asset-item-房"].exists)
        XCTAssertFalse(app.switches["counts-assets-toggle"].exists)
        let houseCell = app.switches["asset-item-counts-房"]
        XCTAssertEqual(houseCell.value as? String, "不计入")
        houseCell.tap()
        XCTAssertEqual(houseCell.value as? String, "不计入")   // 没有 Pro 点了也不变

        let merge = app.buttons["merge-asset-items"]
        XCTAssertTrue(merge.exists)
        merge.tap()
        let confirm = app.buttons["合并"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["asset-item-房"].waitForNonExistence(timeout: 3))
        let editable = app.buttons["编辑资产"]
        XCTAssertTrue(editable.waitForExistence(timeout: 3))
        XCTAssertEqual(editable.value as? String, "¥135,000")
        // 有两项算着：合并后总开关是开的
        let toggle = app.switches["counts-assets-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "计入")
    }

    /// 有 Pro：把现金拆出一个「微信」，记一笔支出时手动换到微信扣，余额落在微信上；总数不变。
    @MainActor
    func testProSplitsCashIntoAccountsAndAnExpenseLandsOnTheChosenOne() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-proPreview", "YES", "-assetsLayout", "classic", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["钱包"].tap()
        app.buttons["编辑现金"].tap()
        let bucket = app.textFields["bucket-amount-field"]
        XCTAssertTrue(bucket.waitForExistence(timeout: 3))
        bucket.typeText("10000")
        app.buttons["保存"].tap()

        // 拆成多个账户：「微信」300 默认从原来的现金里分出来
        let split = app.buttons["add-cash-account"]
        XCTAssertTrue(split.waitForExistence(timeout: 3))
        split.tap()
        let name = app.textFields["cash-account-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("微信")
        let amount = app.textFields["cash-account-amount-field"]
        amount.tap()
        amount.typeText("300")
        XCTAssertEqual(app.staticTexts["cash-account-source-result"].label, "「现金」¥10,000 → ¥9,700，现金总数不变")
        app.buttons["save-cash-account"].tap()
        let wechat = app.buttons["cash-account-微信"]
        XCTAssertTrue(wechat.waitForExistence(timeout: 3))
        XCTAssertEqual(wechat.value as? String, "¥300")
        XCTAssertEqual(app.buttons["cash-account-现金"].value as? String, "¥9,700")
        XCTAssertTrue((app.buttons["cash-drawer"].value as? String ?? "").hasPrefix("¥10,000"))

        // 记 20：默认从排第一的「现金」扣，手动换到「微信」
        app.tabBars.buttons["首页"].tap()
        app.buttons["记支出"].tap()
        let expense = app.textFields["0.00"]
        XCTAssertTrue(expense.waitForExistence(timeout: 3))
        expense.tap()
        expense.typeText("20")
        let picker = app.buttons["transaction-account-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertTrue(picker.label.contains("现金"))
        picker.tap()
        let option = app.buttons["微信 · ¥300"]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
        XCTAssertTrue(picker.label.contains("微信"))
        app.buttons["保存"].tap()

        app.tabBars.buttons["钱包"].tap()
        XCTAssertTrue(wechat.waitForExistence(timeout: 3))
        XCTAssertEqual(wechat.value as? String, "¥280")
        XCTAssertEqual(app.buttons["cash-account-现金"].value as? String, "¥9,700")

        // 点「微信」的序号：不计入自由天数，现金总数不变，首页图例旁写「部分现金未计入」
        let counts = app.switches["cash-account-counts-微信"]
        XCTAssertEqual(counts.value as? String, "计入")
        counts.tap()
        XCTAssertEqual(counts.value as? String, "不计入")
        XCTAssertTrue((app.buttons["cash-drawer"].value as? String ?? "").hasPrefix("¥9,980"))
        app.tabBars.buttons["首页"].tap()
        let note = app.staticTexts["uncounted-assets-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertEqual(note.label, "部分现金未计入")
    }

    /// Assets 新版「钱与时间」：录入现金和资产、记一笔，换成「天」后大数字是自由天数、两张标签按日均换算；
    /// 中间的圆钮调拨；设置里换成经典版就回到抽屉页面。
    @MainActor
    func testMoneyTimeAssetsShowsDaysTransfersAndSwitchesToClassic() {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", "NO", "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES",
                               "-proPreview", "YES", "-UseInMemoryStore"]
        app.launch()
        app.tabBars.buttons["钱包"].tap()
        // 还没录钱时先打开的是现金标签
        app.buttons["编辑现金"].tap()
        var field = app.textFields["bucket-amount-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("10000")
        app.buttons["保存"].tap()
        app.buttons["assets-tab"].tap()
        app.buttons["编辑资产"].tap()
        field = app.textFields["bucket-amount-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("10000")
        app.buttons["保存"].tap()
        XCTAssertEqual(app.buttons["cash-tab"].value as? String, "¥10,000")

        app.tabBars.buttons["首页"].tap()
        app.buttons["记支出"].tap()
        let expense = app.textFields["0.00"]
        XCTAssertTrue(expense.waitForExistence(timeout: 3))
        expense.tap()
        expense.typeText("100")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["199"].waitForExistence(timeout: 5))

        // 换成「天」：大数字就是首页那个 199，现金 9900 ÷ 日均 100 = 99 天
        app.tabBars.buttons["钱包"].tap()
        app.buttons["unit-days"].tap()
        let days = app.descendants(matching: .any)["assets-hero-days"]
        XCTAssertTrue(days.waitForExistence(timeout: 3))
        XCTAssertTrue(days.label.contains("199"))
        XCTAssertEqual(app.buttons["cash-tab"].value as? String, "99 天")
        XCTAssertEqual(app.buttons["assets-tab"].value as? String, "100 天")
        app.buttons["unit-money"].tap()

        // 中间的圆钮：从现金调 500 到资产
        app.buttons["transfer-toggle"].tap()
        let amount = app.textFields["transfer-amount-field"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.typeText("500")
        app.buttons["confirm-transfer"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.buttons["cash-tab"].value as? String, "¥9,400")
        XCTAssertEqual(app.buttons["assets-tab"].value as? String, "¥10,500")

        // 设置里换成经典版
        app.tabBars.buttons["设置"].tap()
        let picker = app.segmentedControls["assets-layout-picker"]
        if !picker.waitForExistence(timeout: 3) { app.swipeUp() }
        picker.buttons["经典"].tap()
        app.tabBars.buttons["钱包"].tap()
        XCTAssertTrue(app.buttons["assets-drawer"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["assets-tab"].exists)
    }

    /// 新版「钱与时间」截图（演示账本）：钱、天、现金标签、调拨弹窗，浅深各一套。只在给了环境变量时运行。
    @MainActor
    func testCaptureMoneyTimeScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let split = environment["ACCOUNTS_SPLIT_LEDGER"], let output = environment["MONEY_TIME_SHOTS_DIR"] else {
            throw XCTSkip("只在拍新版 Assets 截图时运行")
        }
        func launch(dark: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
                                   "-historyGuideCompleted", "YES", "-setupGuideCompleted", "YES", "-proPreview", "YES",
                                   "-UseInMemoryStore", "-SeedBackupJSON", split]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
            return app
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.2)
            let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        func nudge(_ app: XCUIApplication, by amount: CGFloat) {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8 - amount)))
        }
        for dark in [false, true] {
            let mode = dark ? "深色" : "浅色"
            let app = launch(dark: dark)
            app.tabBars.buttons["钱包"].tap()
            app.buttons["assets-tab"].tap()
            try shoot("\(mode)-1-钱")
            app.buttons["unit-days"].tap()
            try shoot("\(mode)-2-天")
            app.buttons["unit-money"].tap()
            app.buttons["cash-tab"].tap()
            nudge(app, by: 0.3)
            try shoot("\(mode)-3-现金标签")
            nudge(app, by: 0.4)
            try shoot("\(mode)-4-每月")
            app.swipeDown()
            app.swipeDown()
            app.buttons["transfer-toggle"].tap()
            XCTAssertTrue(app.textFields["transfer-amount-field"].waitForExistence(timeout: 3))
            app.textFields["transfer-amount-field"].typeText("2000")
            try shoot("\(mode)-5-调拨")
            app.terminate()
        }
    }

    /// 资产和现金分账户（Pro）截图：演示账本没拆分 / 拆好了、记支出时的账户行、调拨、两个抽屉收起。只在给了环境变量时运行。
    @MainActor
    func testCaptureAccountsScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let ledger = environment["STORE_SHOTS_LEDGER"], let split = environment["ACCOUNTS_SPLIT_LEDGER"],
              let output = environment["ACCOUNTS_SHOTS_DIR"] else {
            throw XCTSkip("只在拍分账户截图时运行")
        }
        func launch(_ seed: String, dark: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
                                   "-heroTrendExpanded", "YES", "-historyGuideCompleted", "YES",
                                   "-setupGuideCompleted", "YES", "-proPreview", "YES",
                                   "-assetsLayout", "classic", "-UseInMemoryStore", "-SeedBackupJSON", seed]
            app.launch()
            XCTAssertTrue(app.buttons["记支出"].waitForExistence(timeout: 10))
            return app
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 1.2)
            let url = URL(fileURLWithPath: output).appendingPathComponent(name + ".png")
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        func nudge(_ app: XCUIApplication, by amount: CGFloat = 0.3) {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8 - amount)))
        }
        for dark in [false, true] {
            let mode = dark ? "深色" : "浅色"
            var app = launch(ledger, dark: dark)
            app.tabBars.buttons["钱包"].tap()
            nudge(app)
            try shoot("\(mode)-1-没拆分")
            app.terminate()

            app = launch(split, dark: dark)
            app.tabBars.buttons["钱包"].tap()
            try shoot("\(mode)-2-拆好了-上半")
            nudge(app, by: 0.35)
            try shoot("\(mode)-3-拆好了-抽屉")
            nudge(app, by: 0.4)
            try shoot("\(mode)-3b-每月还款")
            app.swipeDown()
            // 两个抽屉都收起
            app.buttons["assets-drawer"].tap()
            app.buttons["cash-drawer"].tap()
            try shoot("\(mode)-4-抽屉收起")
            app.buttons["assets-drawer"].tap()
            app.buttons["cash-drawer"].tap()

            // 调拨：从招行卡到基金
            app.swipeDown()
            app.buttons["transfer-toggle"].tap()
            try shoot("\(mode)-5-调拨")

            // 记一笔 480：微信只有 320，自动跳到支付宝
            app.tabBars.buttons["首页"].tap()
            app.buttons["记支出"].tap()
            let expense = app.textFields["0.00"]
            XCTAssertTrue(expense.waitForExistence(timeout: 3))
            expense.tap()
            expense.typeText("480")
            try shoot("\(mode)-6-记支出选账户")
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
            app.launchArguments = XCUIApplication.chineseUI + ["-isDarkMode", dark ? "YES" : "NO", "-heroLayout", "leading",
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

        app.tabBars.buttons["明细"].tap()
        try shoot("3-History")
        app.tabBars.buttons["钱包"].tap()
        try shoot("4-Assets")

        app.tabBars.buttons["首页"].tap()
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
        app.launchArguments = XCUIApplication.chineseUI + ["-setupGuideCompleted", "YES", "-assetsLayout", "classic", "-UseInMemoryStore"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["钱包"].waitForExistence(timeout: 5))
        app.tabBars.buttons["钱包"].tap()
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
        XCTAssertTrue(app.staticTexts["资产金额不对，或者超出了能记的范围。"].exists)
        app.alerts.buttons["好"].tap()
        app.swipeDown()
        XCTAssertEqual(app.buttons["编辑现金"].value as? String, cashBefore)
        XCTAssertEqual(app.buttons["编辑资产"].value as? String, assetsBefore)
    }

    @MainActor
    func testStoreRecoveryViewAppearsWhenBootstrapFails() throws {
        let app = XCUIApplication()
        app.launchArguments = XCUIApplication.chineseUI
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

/// 英文界面逐屏截图，给人看排版和措辞。只在给了 L10N_SHOTS_DIR 和 L10N_LEDGER 时运行
final class EnglishScreensUITests: XCTestCase {
    @MainActor
    func testCaptureEnglishScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let output = environment["L10N_SHOTS_DIR"], let ledger = environment["L10N_LEDGER"] else {
            throw XCTSkip("只在拍英文截图时运行")
        }
        func shoot(_ name: String) throws {
            Thread.sleep(forTimeInterval: 0.9)
            try XCUIScreen.main.screenshot().pngRepresentation
                .write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
        }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-isDarkMode", "NO", "-heroLayout", "leading", "-historyGuideCompleted", "YES",
                               "-setupGuideCompleted", "YES", "-proPreview", "YES", "-hideProPreviewCard",
                               "-UseInMemoryStore", "-SeedBackupJSON", ledger]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 10))
        try shoot("01-dashboard")
        app.swipeUp()
        try shoot("02-dashboard-bottom")
        // 首页卡片的编辑面板，再把卡全加上看英文小字
        if app.buttons["edit-home-stats"].exists {
            app.buttons["edit-home-stats"].tap()
            try shoot("02b-edit-cards")
            if app.buttons["Add All"].exists { app.buttons["Add All"].tap() }
            app.buttons["Done"].tap()
            try shoot("02c-dashboard-all-cards")
        }
        app.swipeDown()

        app.buttons["Add Expense"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 3))
        try shoot("03-add-expense")
        app.navigationBars.buttons["Cancel"].tap()

        app.buttons["Simulate · See the impact first"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 0.6)
        app.typeText("3000")
        try shoot("04-simulate")
        app.swipeDown(velocity: .fast)

        app.tabBars.buttons["Assets"].tap()
        try shoot("05-assets")
        if app.buttons["unit-days"].exists {
            app.buttons["unit-days"].tap()
            try shoot("06-assets-days")
            app.buttons["unit-money"].tap()
        }
        app.swipeUp()
        try shoot("07-assets-bottom")

        app.tabBars.buttons["History"].tap()
        try shoot("08-history")
        app.buttons["history-scope-title"].tap()
        try shoot("09-monthly-summary")
        app.swipeDown(velocity: .fast)

        app.tabBars.buttons["Settings"].tap()
        try shoot("10-settings")
        app.buttons["settings-card-look"].tap()
        try shoot("11-settings-appearance")
        app.buttons["settings-card-ledger"].tap()
        try shoot("12-settings-ledger")
        app.buttons["settings-card-about"].tap()
        try shoot("13-settings-about")
        app.tapSettingsRow("user-manual", inCard: "settings-card-about")
        try shoot("14-manual")
        app.buttons["manual-chapter-0"].tap()
        try shoot("15-manual-chapter")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["settings-card-pro"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        try shoot("16-pro")
        app.buttons["Close"].firstMatch.tap()

        app.buttons["settings-freedom-card"].tap()
        try shoot("18-freedom-card")
        if app.buttons["Done"].exists { app.buttons["Done"].firstMatch.tap() } else { app.swipeDown(velocity: .fast) }
        app.staticTexts["Freedom Check"].firstMatch.tap()
        try shoot("19-check")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tapSettingsRow("guide-list", inCard: "settings-card-about")
        app.buttons["replay-dashboard-guide"].tap()
        if app.buttons["guide-next"].waitForExistence(timeout: 5) {
            try shoot("20-guide-1")
            app.buttons["guide-next"].tap()
            try shoot("21-guide-2")
            app.buttons["guide-skip"].tap()
        }

        app.tabBars.buttons["Assets"].tap()
        app.swipeUp()
        if app.buttons["add-fixed-button"].waitForExistence(timeout: 3) {
            app.buttons["add-fixed-button"].tap()
            try shoot("22-fixed-expense")
            app.swipeDown(velocity: .fast)
        }

        app.tabBars.buttons["Settings"].tap()
        app.swipeDown()
        let language = app.segmentedControls["language-picker"]
        if !language.waitForExistence(timeout: 2), app.buttons["settings-card-look"].exists {
            app.buttons["settings-card-look"].tap()
        }
        if language.waitForExistence(timeout: 3) {
            try shoot("17-language")
        }
    }
}

extension XCUIApplication {
    /// 断言都按中文界面写；模拟器系统语言是英文时也要固定成中文启动
    static let chineseUI = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]

    /// 设置页是一叠卡：要点的那一行在收着的卡里时，先点卡头把卡抽出来；在屏幕下面就往上滑
    func tapSettingsRow(_ identifier: String, inCard card: String) {
        let row = buttons[identifier]
        if !row.waitForExistence(timeout: 2) {
            buttons[card].tap()
            XCTAssertTrue(row.waitForExistence(timeout: 3))
        }
        for _ in 0..<3 where !row.isHittable { swipeUp() }
        row.tap()
    }
}
