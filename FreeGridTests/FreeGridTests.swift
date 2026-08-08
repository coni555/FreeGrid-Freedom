//
//  FreeGridTests.swift
//  FreeGridTests
//
//  导入去重 + 备份保真度单测:
//  - 带 id 的记录按 UUID 去重(schema v1 导出), 无 id 退回内容指纹(旧文件/Web 版)
//  - .replace 策略: 双桶字段原样还原, 旧文件退回单桶行为
//

import Testing
import Foundation
import SwiftData
@testable import FreeGrid

struct FreeGridTests {

    @Test func dedupByIDWhenPresent() throws {
        let context = try TestSupport.makeContext()
        let existingID = UUID()
        let exp = Expense(amount: 25.5, category: "午餐", note: "", date: TestSupport.day("2026-01-15"))
        exp.id = existingID
        context.insert(exp)

        let json = """
        {
          "schema_version": 1,
          "expenses": [
            {"id": "\(existingID.uuidString)", "amount": 25.5, "category": "午餐", "date": "2026-01-15", "note": "备注被改过"},
            {"id": "\(UUID().uuidString)", "amount": 25.5, "category": "午餐", "date": "2026-01-15", "note": ""}
          ]
        }
        """
        let preview = try DataIO.previewJSON(data: Data(json.utf8), context: context)

        // 第 1 条 id 命中 → 跳过(哪怕 note 被改过, id 比指纹权威)
        // 第 2 条 id 不同 → 保留(内容指纹与现有记录一致也不误杀 — 同日同额同类的两笔是合法的)
        #expect(preview.expensesSkipped == 1)
        #expect(preview.expensesNew.count == 1)
    }

    @Test func dedupFallsBackToFingerprintWithoutID() throws {
        let context = try TestSupport.makeContext()
        context.insert(Expense(amount: 30, category: "晚餐", note: "聚餐", date: TestSupport.day("2026-02-01")))

        // 旧文件: 无 schema_version 无 id, 解码必须容忍(视为 v0)
        let json = """
        {
          "expenses": [
            {"amount": 30, "category": "晚餐", "date": "2026-02-01", "note": "聚餐"},
            {"amount": 30, "category": "晚餐", "date": "2026-02-01", "note": "另一笔"}
          ]
        }
        """
        let preview = try DataIO.previewJSON(data: Data(json.utf8), context: context)

        // 指纹 (date|amount|category|note) 完全一致 → 跳过; note 不同 → 保留
        #expect(preview.expensesSkipped == 1)
        #expect(preview.expensesNew.count == 1)
    }

    @Test func replaceRestoresDualBucketsAndFallsBackForLegacyFiles() throws {
        // schema v1 文件: locked_assets / cash 原样还原
        let v1Context = try TestSupport.makeContext()
        let v1JSON = """
        {"schema_version": 1, "assets": {"total": 500, "locked_assets": 300, "cash": 200}}
        """
        let v1Preview = try DataIO.previewJSON(data: Data(v1JSON.utf8), context: v1Context)
        _ = try DataIO.commitImport(preview: v1Preview, strategy: .replace, context: v1Context)
        let v1Assets = try #require(try v1Context.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(v1Assets.lockedAssets == 300)
        #expect(v1Assets.cash == 200)

        // 旧文件只有 total: 退回现有行为 lockedAssets=0, cash=total
        let oldContext = try TestSupport.makeContext()
        let oldJSON = """
        {"assets": {"total": 500}}
        """
        let oldPreview = try DataIO.previewJSON(data: Data(oldJSON.utf8), context: oldContext)
        _ = try DataIO.commitImport(preview: oldPreview, strategy: .replace, context: oldContext)
        let oldAssets = try #require(try oldContext.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(oldAssets.lockedAssets == 0)
        #expect(oldAssets.cash == 500)
    }
}
