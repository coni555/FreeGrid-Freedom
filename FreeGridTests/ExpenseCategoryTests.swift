import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct ExpenseCategoryTests {
    @Test func validatesNamesAndRejectsDuplicates() throws {
        var options = ExpenseCategoryOptions.defaults
        try options.add(" 咖啡 ")
        #expect(options.visibleNames.last == "咖啡")
        for name in ["", "  ", "午餐", "咖啡", "咖\n啡", String(repeating: "字", count: 21)] {
            #expect(throws: ExpenseCategoryOptions.ValidationError.self) { try options.add(name) }
        }
        try options.add("Coffee")
        #expect(throws: ExpenseCategoryOptions.ValidationError.self) { try options.add("coffee") }
    }

    @Test func deletedCategoryLeavesTheOptionsAndComesBackWhenAddedAgain() throws {
        var options = ExpenseCategoryOptions.defaults
        try options.add("Coffee")
        try options.delete("Coffee")
        try options.delete("早餐")
        #expect(!options.visibleNames.contains("Coffee"))
        #expect(!options.visibleNames.contains("早餐"))
        // 旧账还在用这两个名字：不会被当成新分类补回来，导入时仍然认识
        let withLedger = options.including(["Coffee", "早餐"])
        #expect(withLedger.visibleNames == options.visibleNames)
        #expect(withLedger.allNames.contains("Coffee"))
        // 重新添加：回到列表末尾，写法沿用原来的，和旧账对得上
        try options.add("coffee")
        try options.add("早餐")
        #expect(options.visibleNames.suffix(2) == ["Coffee", "早餐"])
        #expect(throws: ExpenseCategoryOptions.ValidationError.self) { try options.add("早餐") }
    }

    @Test func movingSkipsDeletedCategories() throws {
        var options = ExpenseCategoryOptions.defaults   // 早餐 午餐 晚餐 …
        try options.delete("午餐")
        options.move("晚餐", by: -1)
        #expect(Array(options.visibleNames.prefix(2)) == ["晚餐", "早餐"])
        options.move("晚餐", by: -1)                     // 已经在最前
        #expect(options.visibleNames.first == "晚餐")
    }

    @Test func orderDeletionAndRecoveredNamesSurvivePreferenceReload() throws {
        var options = ExpenseCategoryOptions.defaults
        try options.add("房租")
        options.move("房租", by: -1)
        try options.delete("早餐")
        let restored = ExpenseCategoryStorage.decode(try ExpenseCategoryStorage.encode(options))
        #expect(restored == options)
        #expect(restored.allNames.suffix(2) == ["房租", "其他"])
        #expect(restored.visibleNames.first == "午餐")
        let recovered = restored.including(["早餐", "房租", "宠物", "宠物"])
        #expect(!recovered.visibleNames.contains("早餐"))
        #expect(recovered.allNames.filter { $0 == "宠物" }.count == 1)
        #expect(recovered.visibleNames.last == "宠物")
    }

    @Test func cannotDeleteLastOptionOrDecodeAnEmptySelection() throws {
        var options = ExpenseCategoryOptions.defaults
        for name in options.allNames.dropLast() { try options.delete(name) }
        #expect(throws: ExpenseCategoryOptions.ValidationError.self) {
            try options.delete("其他")
        }
        #expect(options.visibleNames == ["其他"])
        // 早期版本存的「隐藏」读进来就是已删除
        let legacy = ExpenseCategoryStorage.decode(#"{"items":[{"name":"早餐","isHidden":true},{"name":"午餐","isHidden":false}]}"#)
        #expect(legacy.visibleNames == ["午餐"])
        #expect(ExpenseCategoryStorage.decode(#"{"items":[]}"#) == .defaults)
        #expect(ExpenseCategoryStorage.decode("broken") == .defaults)
    }

    @Test(arguments: ["咖啡", "数码", "午餐|外卖"])
    func backupRestoresCustomNameWithoutPreferencesOrNoteChanges(category: String) throws {
        for amount in [20.0, -20.0] {
            let source = try TestSupport.makeContext()
            let note = String(repeating: "记", count: FinancialLimits.noteCharacters)
            let expense = Expense(amount: amount, category: category, note: note,
                                  date: TestSupport.day("2026-01-01"))
            source.insert(expense)
            try source.save()
            let data = try DataIO.exportJSON(context: source)
            let target = try TestSupport.makeContext()
            let preview = try DataIO.previewJSON(data: data, context: target)
            #expect(preview.categoryEntries.first?.canonical == category)
            _ = try DataIO.commitImport(preview: preview, strategy: .skipAssets, context: target)
            let restored = try #require(try target.fetch(FetchDescriptor<Expense>()).first)
            #expect(restored.id == expense.id)
            #expect(restored.category == category)
            #expect(restored.note == note)
            #expect(restored.amount == amount)
            #expect(try DataIO.previewJSON(data: data, context: target).expensesNew.isEmpty)
        }
    }

    @Test func legacyMappingToCustomCategoryRemainsIdempotentWithoutPreferences() throws {
        let context = try TestSupport.makeContext()
        let data = Data(#"{"schema_version":1,"expenses":[{"amount":100,"category":"租房","date":"2026-01-01","note":"月租"}]}"#.utf8)
        let preview = try DataIO.previewJSON(data: data, context: context, categoryNames: ["房租"])
        _ = try DataIO.commitImport(preview: preview, strategy: .skipAssets,
                                   categoryMap: ["租房": "房租"], context: context)
        let expense = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        #expect(expense.category == "房租")
        #expect(expense.note == "月租 · 原分类·租房")
        #expect(try DataIO.previewJSON(data: data, context: context).expensesNew.isEmpty)
    }

    @Test func legacyImportCanExplicitlyPreserveOriginalName() throws {
        let context = try TestSupport.makeContext()
        let data = Data(#"{"expenses":[{"amount":10,"category":"宠物","date":"2026-01-01"}]}"#.utf8)
        let preview = try DataIO.previewJSON(data: data, context: context)
        _ = try DataIO.commitImport(preview: preview, strategy: .skipAssets,
                                   categoryMap: ["宠物": "宠物"], context: context)
        #expect(try context.fetch(FetchDescriptor<Expense>()).first?.category == "宠物")
        #expect(try DataIO.previewJSON(data: data, context: context).expensesNew.isEmpty)
    }

    // MARK: - 改名、图标、拖动排序

    @Test func renameKeepsPositionAndRejectsDuplicates() throws {
        var options = ExpenseCategoryOptions.defaults
        try options.add("咖啡")
        #expect(try options.rename("咖啡", to: " 咖啡豆 ") == "咖啡豆")
        #expect(options.visibleNames.last == "咖啡豆")
        try options.rename("午餐", to: "中饭")
        #expect(options.visibleNames[1] == "中饭")
        #expect(throws: ExpenseCategoryOptions.ValidationError.self) { try options.rename("中饭", to: "晚餐") }
        #expect(throws: ExpenseCategoryOptions.ValidationError.self) { try options.rename("中饭", to: " ") }
        // 改成删掉过的名字：沿用那条的写法，删除记号拿掉
        try options.add("Tea")
        try options.delete("Tea")
        #expect(try options.rename("咖啡豆", to: "tea") == "Tea")
        #expect(options.visibleNames.last == "Tea")
        #expect(options.allNames.filter { $0 == "Tea" }.count == 1)
    }

    @Test func iconsDefaultByNameAndStayAfterRename() throws {
        var options = ExpenseCategoryOptions.defaults
        #expect(options.icon(for: "午餐") == "fork.knife")
        try options.add("房租")
        #expect(options.icon(for: "房租") == "house")
        try options.add("奇怪的东西")
        #expect(options.icon(for: "奇怪的东西") == "tag")
        options.setIcon("leaf", for: "奇怪的东西")
        try options.rename("奇怪的东西", to: "绿植")
        #expect(options.icon(for: "绿植") == "leaf")
        let restored = ExpenseCategoryStorage.decode(try ExpenseCategoryStorage.encode(options))
        #expect(restored.icon(for: "绿植") == "leaf")
        // 1.5 存的偏好没有 icon 字段，照常读
        let legacy = ExpenseCategoryStorage.decode(#"{"items":[{"name":"早餐","isHidden":false}]}"#)
        #expect(legacy.icon(for: "早餐") == "cup.and.saucer")
    }

    @Test func dragMoveSkipsDeletedCategories() throws {
        var options = ExpenseCategoryOptions.defaults   // 早餐 午餐 晚餐 购物 …
        try options.delete("午餐")
        // 列出来的是 早餐 晚餐 购物 …；把「购物」拖到最前
        options.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(Array(options.visibleNames.prefix(3)) == ["购物", "早餐", "晚餐"])
        // 删掉的「午餐」还在，只是不列出来
        #expect(options.allNames.contains("午餐"))
        // 往后拖
        options.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(Array(options.visibleNames.prefix(3)) == ["早餐", "晚餐", "购物"])
    }

    @Test func renamingIntoAnotherCategoryMergesThem() throws {
        var options = ExpenseCategoryOptions.defaults
        try options.add("奶茶")
        try options.add("咖啡")
        options.setIcon("leaf", for: "咖啡")
        #expect(options.mergeTarget(for: " 咖啡 ", excluding: "奶茶") == "咖啡")
        #expect(options.mergeTarget(for: "奶茶", excluding: "奶茶") == nil)
        #expect(options.mergeTarget(for: "新名字", excluding: "奶茶") == nil)
        options.merge("奶茶", into: "咖啡")
        #expect(!options.allNames.contains("奶茶"))
        #expect(options.visibleNames.last == "咖啡")
        #expect(options.icon(for: "咖啡") == "leaf")
        // 删掉的分类不能当合并目标
        try options.delete("午餐")
        #expect(options.mergeTarget(for: "午餐", excluding: "晚餐") == nil)

        let context = try TestSupport.makeContext()
        context.insert(Expense(amount: 18, category: "奶茶", date: TestSupport.day("2026-10-01")))
        context.insert(Expense(amount: 25, category: "咖啡", date: TestSupport.day("2026-10-02")))
        try context.save()
        #expect(try LedgerStore.renameCategory(from: "奶茶", to: "咖啡", in: context) == 1)
        #expect(try context.fetch(FetchDescriptor<Expense>()).allSatisfy { $0.category == "咖啡" })
    }

    @Test func renamingRewritesOldRecordsButNotLoanPayments() throws {
        let context = try TestSupport.makeContext()
        context.insert(Expense(amount: 30, category: "咖啡", date: TestSupport.day("2026-10-01")))
        context.insert(Expense(amount: 25, category: "咖啡", date: TestSupport.day("2026-10-02")))
        context.insert(Expense(amount: 40, category: "午餐", date: TestSupport.day("2026-10-02")))
        let payment = Expense(amount: 3000, category: "咖啡", date: TestSupport.day("2026-10-03"))
        payment.loanID = UUID()
        context.insert(payment)
        try context.save()
        #expect(try LedgerStore.renameCategory(from: "咖啡", to: "咖啡豆", in: context) == 2)
        let all = try context.fetch(FetchDescriptor<Expense>())
        #expect(all.filter { $0.category == "咖啡豆" }.count == 2)
        #expect(all.filter { $0.category == "咖啡" }.map(\.loanID) == [payment.loanID])

        struct Failure: Error {}
        #expect(throws: Failure.self) {
            try LedgerStore.renameCategory(from: "咖啡豆", to: "咖啡", in: context, save: { _ in throw Failure() })
        }
        #expect(try context.fetch(FetchDescriptor<Expense>()).filter { $0.category == "咖啡豆" }.count == 2)
    }

    // MARK: - 分类设置进备份

    @Test func categorySettingsRoundTripThroughBackup() throws {
        var options = ExpenseCategoryOptions.defaults
        try options.add("房租")
        options.setIcon("leaf", for: "房租")
        options.move(fromOffsets: IndexSet(integer: options.activeItems.count - 1), toOffset: 0)
        try options.delete("早餐")
        let source = try TestSupport.makeContext()
        source.insert(Expense(amount: 10, category: "午餐", date: TestSupport.day("2026-10-01")))
        try source.save()

        let data = try DataIO.exportJSON(context: source, categoryOptions: options)
        #expect(String(decoding: data, as: UTF8.self).contains("\"expense_categories\""))
        let preview = try DataIO.previewJSON(data: data, context: try TestSupport.makeContext())
        let restored = try #require(preview.categoryOptions)
        #expect(restored == options)
        #expect(restored.visibleNames.first == "房租")
        #expect(restored.icon(for: "房租") == "leaf")
        #expect(!restored.visibleNames.contains("早餐"))

        // 没自定义过分类：备份里没有这一段，导入也不碰本机分类
        let plain = try DataIO.exportJSON(context: source)
        #expect(!String(decoding: plain, as: UTF8.self).contains("expense_categories"))
        #expect(try DataIO.previewJSON(data: plain, context: try TestSupport.makeContext()).categoryOptions == nil)
    }

    @Test func restoringCategorySettingsReplacesOrOnlyAddsMissing() throws {
        var local = ExpenseCategoryOptions.defaults
        try local.add("咖啡")
        var backup = ExpenseCategoryOptions.defaults
        try backup.add("房租")
        backup.move(fromOffsets: IndexSet(integer: backup.activeItems.count - 1), toOffset: 0)

        let replaced = local.merging(backup, replacing: true)
        #expect(replaced.visibleNames.first == "房租")
        #expect(replaced.visibleNames.last == "咖啡")      // 本机有、备份没有的留在后面

        let merged = local.merging(backup, replacing: false)
        #expect(merged.visibleNames.first == "早餐")        // 本机顺序不变
        #expect(Array(merged.visibleNames.suffix(2)) == ["咖啡", "房租"])
    }

    @Test func rejectsBrokenCategorySettingsInBackups() throws {
        for bad in [#"[{"name":""}]"#, #"[{"name":"午餐"},{"name":"午餐"}]"#,
                    #"[{"name":"午餐","icon":"<script>"}]"#, #"[{"name":"午餐","deleted":true}]"#] {
            let data = Data(#"{"schema_version":2,"expense_categories":\#(bad)}"#.utf8)
            #expect(throws: ImportValidationError.invalidExpenseCategories) {
                _ = try ImportValidator.validate(data: data)
            }
        }
    }
}
