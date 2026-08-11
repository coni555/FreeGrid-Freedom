//
//  ImportValidationTests.swift
//  FreeGridTests
//
//  JSON 导入边界：结构能解码不代表数据可以进入账本。
//

import Foundation
import Testing
@testable import FreeGrid

struct ImportValidationTests {
    @Test func acceptsLegacyV0AndCurrentV1() throws {
        let v0 = Data("""
        {
          "assets": {"total": 500},
          "expenses": [
            {"amount": 30, "category": "晚餐", "date": "2026-02-01", "note": "聚餐"}
          ]
        }
        """.utf8)
        let v1 = Data("""
        {
          "schema_version": 1,
          "assets": {"total": 500, "locked_assets": 300, "cash": 200},
          "incomes": [
            {"id": "\(UUID().uuidString)", "amount": 100, "source": "工资", "date": "2026-02-01"}
          ]
        }
        """.utf8)

        #expect(try ImportValidator.validate(data: v0).schemaVersion == 0)
        #expect(try ImportValidator.validate(data: v1).schemaVersion == 1)
    }

    @Test func keepsLegacyZeroExpensesButKeepsV2Strict() throws {
        // 0 元占位一律保留:最早的那条常常就是 0 元,丢掉会把追踪基线往后挪,
        // 记录天数变少 → 日均变高 → 自由天数变少,而用户看不出数字为何变了。
        let legacy = Data("""
        {
          "schema_version": 1,
          "expenses": [
            {"amount": 0, "category": "无消费", "date": "2026-02-01"},
            {"amount": 30, "category": "晚餐", "date": "2026-02-02"},
            {"amount": 0, "category": "无消费", "date": "2026-02-03"}
          ]
        }
        """.utf8)
        let validated = try ImportValidator.validate(data: legacy)

        #expect(validated.expenses.map(\.amount) == [0, 30, 0])
        #expect(validated.firstRecordDate == nil)

        let current = Data(#"{"schema_version":2,"expenses":[{"amount":0,"category":"午餐","date":"2026-02-01"}]}"#.utf8)
        expectError(current) {
            if case .amountOutOfRange = $0 { return true }
            return false
        }
    }

    @Test func acceptsLegacyAndV3SignedExpenses() throws {
        let legacy = Data(#"{"schema_version":1,"expenses":[{"amount":-310,"category":"其他","date":"2026-01-01"}]}"#.utf8)
        let legacyValidated = try ImportValidator.validate(data: legacy)
        #expect(legacyValidated.expenses.map(\.amount) == [-310])

        let signed = Data(#"{"schema_version":3,"expenses":[{"amount":-310,"category":"其他","date":"2026-01-01"},{"amount":0,"category":"无消费","date":"2026-01-02"}]}"#.utf8)
        let signedValidated = try ImportValidator.validate(data: signed)
        #expect(signedValidated.expenses.map(\.amount) == [-310, 0])
    }

    @Test func rejectsFutureSchemaAndInvalidUUID() {
        expectError(Data(#"{"schema_version":99}"#.utf8)) {
            if case .unsupportedSchema(99) = $0 { return true }
            return false
        }

        let badUUID = Data("""
        {"schema_version": 1, "expenses": [
          {"id": "not-a-uuid", "amount": 10, "category": "午餐", "date": "2026-01-01"}
        ]}
        """.utf8)
        expectError(badUUID) {
            if case .invalidUUID = $0 { return true }
            return false
        }
    }

    @Test func rejectsInvalidDatesAndAmounts() {
        let invalidDate = Data(#"{"expenses":[{"amount":10,"category":"午餐","date":"2026-02-31"}]}"#.utf8)
        expectError(invalidDate) {
            if case .invalidDate = $0 { return true }
            return false
        }

        let negative = Data(#"{"schema_version":2,"expenses":[{"amount":-1,"category":"午餐","date":"2026-01-01"}]}"#.utf8)
        expectError(negative) {
            if case .amountOutOfRange = $0 { return true }
            return false
        }

        let huge = Data(#"{"assets":{"total":1e308}}"#.utf8)
        expectError(huge) {
            if case .amountOutOfRange = $0 { return true }
            return false
        }
    }

    @Test func rejectsOversizedTextAndAssetMismatch() {
        let note = String(repeating: "字", count: FinancialLimits.noteCharacters + 1)
        let oversized = Data("""
        {"expenses":[{"amount":10,"category":"午餐","date":"2026-01-01","note":"\(note)"}]}
        """.utf8)
        expectError(oversized) {
            if case .textTooLong = $0 { return true }
            return false
        }

        let mismatch = Data(#"{"schema_version":1,"assets":{"total":500,"locked_assets":300,"cash":100}}"#.utf8)
        expectError(mismatch) {
            if case .assetChecksumMismatch = $0 { return true }
            return false
        }
    }

    @Test func rejectsRecordAndFileLimits() {
        let records = (0..<3).map { index in
            "{\"amount\":1,\"category\":\"午餐\",\"date\":\"2026-01-0\(index + 1)\"}"
        }.joined(separator: ",")
        let data = Data("{\"expenses\":[\(records)]}".utf8)
        let recordPolicy = ImportPolicy(maxLedgerRecords: 2)
        expectError(data, policy: recordPolicy) {
            if case .tooManyRecords = $0 { return true }
            return false
        }

        let filePolicy = ImportPolicy(maxFileBytes: 10)
        expectError(Data(#"{"expenses":[]}"#.utf8), policy: filePolicy) {
            if case .fileTooLarge = $0 { return true }
            return false
        }
    }

    @Test func validatesDeviceSoldState() {
        let invalid = Data("""
        {
          "schema_version": 2,
          "devices": [{
            "id": "\(UUID().uuidString)",
            "name": "旧电脑",
            "category": "数码",
            "price": 5000,
            "purchase_date": "2025-01-01",
            "status": "sold"
          }]
        }
        """.utf8)
        expectError(invalid) {
            if case .inconsistentDeviceState = $0 { return true }
            return false
        }
    }

    private func expectError(
        _ data: Data,
        policy: ImportPolicy = .default,
        matches: (ImportValidationError) -> Bool
    ) {
        do {
            _ = try ImportValidator.validate(data: data, policy: policy)
            #expect(Bool(false), "预期导入验证失败，但数据被接受")
        } catch let error as ImportValidationError {
            #expect(matches(error), "收到非预期验证错误：\(error.localizedDescription)")
        } catch {
            #expect(Bool(false), "收到非验证错误：\(error.localizedDescription)")
        }
    }
}
