//
//  BackupRoundTripTests.swift
//  FreeGridTests
//
//  v2 备份必须完整恢复五类业务模型，并让 CSV 文本保持为文本。
//

import Foundation
import SwiftData
import Testing
@testable import FreeGrid

struct BackupRoundTripTests {
    @Test func v2RoundTripPreservesAllBusinessFields() throws {
        let sourceContext = try TestSupport.makeContext()
        let createdAt = TestSupport.day("2026-01-10")

        let expense = Expense(
            amount: 25.5,
            category: "午餐",
            note: "工作餐",
            date: TestSupport.day("2026-01-05")
        )
        expense.id = UUID()
        expense.createdAt = createdAt
        sourceContext.insert(expense)

        let income = Income(
            amount: 800,
            source: "项目",
            isPassive: true,
            note: "尾款",
            date: TestSupport.day("2026-01-06")
        )
        income.id = UUID()
        income.createdAt = createdAt
        sourceContext.insert(income)

        let device = Device(
            name: "旧电脑",
            category: "数码",
            price: 6000,
            purchaseDate: TestSupport.day("2025-01-01"),
            note: "已转卖"
        )
        device.id = UUID()
        device.status = "sold"
        device.soldPrice = 3000
        device.soldDate = TestSupport.day("2026-01-07")
        device.createdAt = createdAt
        sourceContext.insert(device)

        let passive = PassiveSource(name: "版权", monthlyAmount: 120)
        passive.id = UUID()
        passive.createdAt = createdAt
        sourceContext.insert(passive)

        let assets = UserAssets(total: 999, firstRecordDate: TestSupport.day("2020-01-01"))
        assets.lockedAssets = 320
        assets.cash = -20
        assets.updatedAt = createdAt
        sourceContext.insert(assets)
        try sourceContext.save()

        let data = try DataIO.exportJSON(context: sourceContext)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)
        #expect(envelope.schemaVersion == 2)
        #expect(envelope.firstRecordDate == "2026-01-05")
        #expect(envelope.devices?.count == 1)
        #expect(envelope.passiveSources?.first?.id == passive.id.uuidString)

        let targetContext = try TestSupport.makeContext()
        let preview = try DataIO.previewJSON(data: data, context: targetContext)
        #expect(preview.importedAssets.lockedAssets == 320)
        #expect(preview.importedAssets.cash == -20)
        #expect(preview.importedAssets.total == 300)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: targetContext)

        let restoredExpense = try #require(try targetContext.fetch(FetchDescriptor<Expense>()).first)
        #expect(restoredExpense.id == expense.id)
        #expect(restoredExpense.amount == expense.amount)
        #expect(restoredExpense.category == expense.category)
        #expect(restoredExpense.note == expense.note)
        #expect(restoredExpense.date == expense.date)
        #expect(restoredExpense.createdAt == expense.createdAt)

        let restoredIncome = try #require(try targetContext.fetch(FetchDescriptor<Income>()).first)
        #expect(restoredIncome.id == income.id)
        #expect(restoredIncome.source == income.source)
        #expect(restoredIncome.isPassive == income.isPassive)
        #expect(restoredIncome.note == income.note)
        #expect(restoredIncome.createdAt == income.createdAt)

        let restoredDevice = try #require(try targetContext.fetch(FetchDescriptor<Device>()).first)
        #expect(restoredDevice.id == device.id)
        #expect(restoredDevice.name == device.name)
        #expect(restoredDevice.category == device.category)
        #expect(restoredDevice.price == device.price)
        #expect(restoredDevice.purchaseDate == device.purchaseDate)
        #expect(restoredDevice.status == "sold")
        #expect(restoredDevice.soldPrice == 3000)
        #expect(restoredDevice.soldDate == TestSupport.day("2026-01-07"))
        #expect(restoredDevice.note == device.note)
        #expect(restoredDevice.createdAt == device.createdAt)

        let restoredPassive = try #require(try targetContext.fetch(FetchDescriptor<PassiveSource>()).first)
        #expect(restoredPassive.id == passive.id)
        #expect(restoredPassive.name == passive.name)
        #expect(restoredPassive.monthlyAmount == passive.monthlyAmount)
        #expect(restoredPassive.createdAt == passive.createdAt)

        let restoredAssets = try #require(try targetContext.fetch(FetchDescriptor<UserAssets>()).first)
        #expect(restoredAssets.lockedAssets == 320)
        #expect(restoredAssets.cash == -20)
        #expect(restoredAssets.firstRecordDate == expense.date)
    }

    @Test func csvNeutralizesSpreadsheetFormulas() throws {
        let context = try TestSupport.makeContext()
        context.insert(Expense(
            amount: 1,
            category: "=2+2",
            note: "  @SUM(A1)",
            date: TestSupport.day("2026-01-01")
        ))
        context.insert(Income(
            amount: 2,
            source: "+CMD",
            note: "-10",
            date: TestSupport.day("2026-01-02")
        ))

        let csv = String(decoding: try DataIO.exportCSV(context: context), as: UTF8.self)

        #expect(csv.contains("'=2+2"))
        #expect(csv.contains("'  @SUM(A1)"))
        #expect(csv.contains("'+CMD"))
        #expect(csv.contains("'-10"))
    }

    @Test func exportsRejectInvalidStoredAmounts() throws {
        let jsonContext = try TestSupport.makeContext()
        jsonContext.insert(Expense(
            amount: .infinity,
            category: "午餐",
            date: TestSupport.day("2026-01-01")
        ))
        #expect(throws: (any Error).self) {
            _ = try DataIO.exportJSON(context: jsonContext)
        }

        let csvContext = try TestSupport.makeContext()
        csvContext.insert(Income(
            amount: .nan,
            source: "工资",
            date: TestSupport.day("2026-01-01")
        ))
        #expect(throws: DataIO.DataIOError.self) {
            _ = try DataIO.exportCSV(context: csvContext)
        }
    }
}
