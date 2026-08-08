//
//  ImportCommitTests.swift
//  FreeGridTests
//
//  导入预览、计划与事务提交必须保持同一份 canonical 数据。
//

import Foundation
import SwiftData
import Testing
@testable import FreeGrid

struct ImportCommitTests {
    @Test func deduplicatesRecordsInsideOneFile() throws {
        let context = try TestSupport.makeContext()
        let expenseID = UUID()
        let deviceID = UUID()
        let json = """
        {
          "schema_version": 2,
          "expenses": [
            {"id": "\(expenseID.uuidString)", "amount": 20, "category": "午餐", "date": "2026-01-01"},
            {"id": "\(expenseID.uuidString)", "amount": 99, "category": "晚餐", "date": "2026-01-02"},
            {"amount": 30, "category": "交通", "date": "2026-01-03", "note": "地铁"},
            {"amount": 30, "category": "交通", "date": "2026-01-03", "note": "地铁"}
          ],
          "devices": [
            {"id": "\(deviceID.uuidString)", "name": "电脑", "category": "数码", "price": 5000, "purchase_date": "2025-01-01"},
            {"id": "\(deviceID.uuidString)", "name": "另一台电脑", "category": "数码", "price": 6000, "purchase_date": "2025-02-01"}
          ],
          "passive_sources": [
            {"name": "版权", "monthly_amount": 100},
            {"name": "版权", "monthly_amount": 100}
          ]
        }
        """

        let preview = try DataIO.previewJSON(data: Data(json.utf8), context: context)

        #expect(preview.expensesNew.count == 2)
        #expect(preview.expenseDuplicates.existing == 0)
        #expect(preview.expenseDuplicates.inFile == 2)
        #expect(preview.devicesNew.count == 1)
        #expect(preview.deviceDuplicates.inFile == 1)
        #expect(preview.passiveSourcesNew.count == 1)
        #expect(preview.passiveSourceDuplicates.inFile == 1)
    }

    @Test func previewAndCommitUseSameCanonicalAssets() throws {
        let context = try TestSupport.makeContext()
        let json = """
        {
          "schema_version": 2,
          "assets": {"total": 500, "locked_assets": 320, "cash": 180},
          "expenses": [
            {"amount": 20, "category": "外卖", "date": "2026-01-02", "note": "晚餐"}
          ]
        }
        """

        let preview = try DataIO.previewJSON(data: Data(json.utf8), context: context)
        #expect(preview.importedAssets == DataIO.AssetSnapshot(
            lockedAssets: 320,
            cash: 180,
            total: 500,
            updatedAt: nil
        ))

        let plan = try DataIO.makeImportPlan(
            preview: preview,
            strategy: .replace,
            categoryMap: ["外卖": "晚餐"]
        )
        #expect(plan.expenses.first?.category == "晚餐")
        #expect(plan.expenses.first?.note == "晚餐 · 原分类·外卖")

        _ = try DataIO.commitImport(plan: plan, context: context)
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        let expense = try #require(try context.fetch(FetchDescriptor<Expense>()).first)
        #expect(assets.lockedAssets == preview.importedAssets.lockedAssets)
        #expect(assets.cash == preview.importedAssets.cash)
        #expect(expense.category == "晚餐")
        #expect(expense.note == "晚餐 · 原分类·外卖")
        #expect(assets.firstRecordDate == TestSupport.day("2026-01-02"))
    }

    @Test func rejectsNonCanonicalCategoryMappingBeforeWriting() throws {
        let context = try TestSupport.makeContext()
        let json = Data(#"{"expenses":[{"amount":20,"category":"外卖","date":"2026-01-02"}]}"#.utf8)
        let preview = try DataIO.previewJSON(data: json, context: context)
        let defaultPlan = try DataIO.makeImportPlan(preview: preview, strategy: .skipAssets)
        #expect(defaultPlan.expenses.first?.category == ExpenseCategory.fallback)
        #expect(ExpenseCategory.canonical.contains(defaultPlan.expenses.first?.category ?? ""))

        do {
            _ = try DataIO.makeImportPlan(
                preview: preview,
                strategy: .skipAssets,
                categoryMap: ["外卖": "不是标准分类"]
            )
            #expect(Bool(false), "非 canonical 分类映射不应生成导入计划")
        } catch let error as DataIO.DataIOError {
            guard case .invalidCategoryMapping("不是标准分类") = error else {
                #expect(Bool(false), "收到非预期映射错误：\(error.localizedDescription)")
                return
            }
        }

        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UserAssets>()) == 0)
    }

    @Test func previewCancellationDoesNotWriteContext() throws {
        let context = try TestSupport.makeContext()
        let json = Data(#"{"assets":{"total":500},"expenses":[{"amount":20,"category":"午餐","date":"2026-01-02"}]}"#.utf8)

        _ = try DataIO.previewJSON(data: json, context: context)

        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UserAssets>()) == 0)
    }

    @Test func saveFailureRollsBackRecordsAndAssets() throws {
        enum InjectedFailure: Error { case save }

        let context = try TestSupport.makeContext()
        let existingAssets = UserAssets(total: 0)
        existingAssets.lockedAssets = 80
        existingAssets.cash = 20
        context.insert(existingAssets)
        try context.save()

        let json = Data("""
        {
          "schema_version": 2,
          "assets": {"total": 500, "locked_assets": 300, "cash": 200},
          "expenses": [{"amount": 20, "category": "午餐", "date": "2026-01-02"}],
          "incomes": [{"amount": 100, "source": "工资", "date": "2026-01-03"}]
        }
        """.utf8)
        let preview = try DataIO.previewJSON(data: json, context: context)
        let plan = try DataIO.makeImportPlan(preview: preview, strategy: .replace)

        do {
            _ = try DataIO.commitImport(plan: plan, context: context) { _ in
                throw InjectedFailure.save
            }
            #expect(Bool(false), "注入 save 失败后不应返回成功")
        } catch InjectedFailure.save {
            // 预期失败。
        }

        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Income>()) == 0)
        let assets = try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(assets.lockedAssets == 80)
        #expect(assets.cash == 20)
        #expect(assets.firstRecordDate == nil)
    }
}
