import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct ImportFingerprintTests {
    @Test func delimitersDoNotMergeDistinctExpensesOrIncomes() throws {
        let context = try TestSupport.makeContext()
        let day = TestSupport.day("2026-01-01")
        context.insert(Expense(amount: 30, category: "午餐|外卖", note: "备注", date: day))
        context.insert(Income(amount: 80, source: "工资|奖金", note: "五月", date: day))
        try context.save()
        let data = Data(#"{"expenses":[{"amount":30,"category":"午餐","note":"外卖|备注","date":"2026-01-01"}],"incomes":[{"amount":80,"source":"工资","note":"奖金|五月","date":"2026-01-01"}]}"#.utf8)
        let preview = try DataIO.previewJSON(data: data, context: context)
        #expect(preview.expensesNew.count == 1)
        #expect(preview.incomesNew.count == 1)
        #expect(preview.expensesSkipped == 0)
        #expect(preview.incomesSkipped == 0)
        _ = try DataIO.commitImport(preview: preview, strategy: .skipAssets, context: context)
        #expect(try context.fetch(FetchDescriptor<Expense>()).reduce(0) { $0 + $1.amount } == 60)
        #expect(try context.fetch(FetchDescriptor<Income>()).reduce(0) { $0 + $1.amount } == 160)
        let again = try DataIO.previewJSON(data: data, context: context)
        #expect(again.expensesSkipped == 1)
        #expect(again.incomesSkipped == 1)
    }

    @Test func inFileTextBoundariesSurviveMappingAndReimport() throws {
        let context = try TestSupport.makeContext()
        let data = Data(#"{"expenses":[{"amount":30,"category":"午餐|外卖","note":"备注","date":"2026-01-01"},{"amount":30,"category":"午餐","note":"外卖|备注","date":"2026-01-01"}],"incomes":[{"amount":80,"source":"工资|奖金","note":"五月","date":"2026-01-01"},{"amount":80,"source":"工资","note":"奖金|五月","date":"2026-01-01"}]}"#.utf8)
        let preview = try DataIO.previewJSON(data: data, context: context)
        #expect(preview.expensesNew.count == 2)
        #expect(preview.incomesNew.count == 2)
        _ = try DataIO.commitImport(preview: preview, strategy: .skipAssets, context: context)
        let again = try DataIO.previewJSON(data: data, context: context)
        #expect(again.expensesSkipped == 2)
        #expect(again.incomesSkipped == 2)
    }
}
