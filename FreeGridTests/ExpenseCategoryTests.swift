import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct ExpenseCategoryTests {
    @Test func validatesNamesAndKeepsHiddenNamesReserved() throws {
        var options = ExpenseCategoryOptions.defaults
        try options.add(" 咖啡 ")
        try options.setHidden(true, name: "咖啡")
        #expect(options.allNames.contains("咖啡"))
        #expect(!options.visibleNames.contains("咖啡"))
        for name in ["", "  ", "午餐", "咖啡", "咖\n啡", String(repeating: "字", count: 21)] {
            #expect(throws: ExpenseCategoryOptions.ValidationError.self) { try options.add(name) }
        }
        try options.add("Coffee")
        #expect(throws: ExpenseCategoryOptions.ValidationError.self) { try options.add("coffee") }
    }

    @Test func orderVisibilityAndRecoveredNamesSurvivePreferenceReload() throws {
        var options = ExpenseCategoryOptions.defaults
        try options.add("房租")
        options.move("房租", by: -1)
        try options.setHidden(true, name: "早餐")
        let restored = ExpenseCategoryStorage.decode(try ExpenseCategoryStorage.encode(options))
        #expect(restored == options)
        #expect(restored.allNames.suffix(2) == ["房租", "其他"])
        #expect(restored.visibleNames.first == "午餐")
        let recovered = restored.including(["早餐", "房租", "宠物", "宠物"])
        #expect(!recovered.visibleNames.contains("早餐"))
        #expect(recovered.allNames.filter { $0 == "宠物" }.count == 1)
        #expect(recovered.visibleNames.last == "宠物")
    }

    @Test func cannotHideLastOptionOrDecodeAnEmptySelection() throws {
        var options = ExpenseCategoryOptions.defaults
        for name in options.allNames.dropLast() { try options.setHidden(true, name: name) }
        #expect(throws: ExpenseCategoryOptions.ValidationError.self) {
            try options.setHidden(true, name: "其他")
        }
        #expect(options.visibleNames == ["其他"])
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
}
