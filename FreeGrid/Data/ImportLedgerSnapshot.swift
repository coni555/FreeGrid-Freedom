// 预览时保留字段值，而非可变模型引用；提交前核对，避免另一窗口改变账本后仍应用旧计划。
import Foundation
import SwiftData

struct ImportLedgerSnapshot: Equatable {
    // 金额只用于比较版本，以位模式保存，让原有异常值也能稳定比较。
    private struct ExpenseValue: Equatable {
        let id: UUID
        let amount: UInt64
        let category: String
        let note: String
        let date: Date
        let createdAt: Date

        init(_ record: Expense) {
            id = record.id
            amount = record.amount.bitPattern
            category = record.category
            note = record.note
            date = record.date
            createdAt = record.createdAt
        }
    }

    private struct IncomeValue: Equatable {
        let id: UUID
        let amount: UInt64
        let source: String
        let isPassive: Bool
        let note: String
        let date: Date
        let createdAt: Date

        init(_ record: Income) {
            id = record.id
            amount = record.amount.bitPattern
            source = record.source
            isPassive = record.isPassive
            note = record.note
            date = record.date
            createdAt = record.createdAt
        }
    }

    private struct DeviceValue: Equatable {
        let id: UUID
        let name: String
        let category: String
        let price: UInt64
        let purchaseDate: Date
        let status: String
        let soldPrice: UInt64?
        let soldDate: Date?
        let note: String
        let createdAt: Date

        init(_ record: Device) {
            id = record.id
            name = record.name
            category = record.category
            price = record.price.bitPattern
            purchaseDate = record.purchaseDate
            status = record.status
            soldPrice = record.soldPrice?.bitPattern
            soldDate = record.soldDate
            note = record.note
            createdAt = record.createdAt
        }
    }

    private struct PassiveSourceValue: Equatable {
        let id: UUID
        let name: String
        let monthlyAmount: UInt64
        let createdAt: Date

        init(_ record: PassiveSource) {
            id = record.id
            name = record.name
            monthlyAmount = record.monthlyAmount.bitPattern
            createdAt = record.createdAt
        }
    }

    private struct UserAssetsValue: Equatable {
        let total: UInt64
        let lockedAssets: UInt64
        let cash: UInt64
        let updatedAt: Date
        let firstRecordDate: Date?

        init(_ record: UserAssets) {
            total = record.total.bitPattern
            lockedAssets = record.lockedAssets.bitPattern
            cash = record.cash.bitPattern
            updatedAt = record.updatedAt
            firstRecordDate = record.firstRecordDate
        }
    }

    private let observations: [PersistentIdentifier: ObservationValue]
    private let expenses: [PersistentIdentifier: ExpenseValue]
    private let incomes: [PersistentIdentifier: IncomeValue]
    private let devices: [PersistentIdentifier: DeviceValue]
    private let passiveSources: [PersistentIdentifier: PassiveSourceValue]
    private let assets: [PersistentIdentifier: UserAssetsValue]

    init(expenses: [Expense], incomes: [Income], devices: [Device], passiveSources: [PassiveSource], assets: [UserAssets], observations: [FreedomObservation] = []) {
        self.observations = Dictionary(uniqueKeysWithValues: observations.map { ($0.persistentModelID, $0.value) })
        self.expenses = Dictionary(uniqueKeysWithValues: expenses.map { ($0.persistentModelID, ExpenseValue($0)) })
        self.incomes = Dictionary(uniqueKeysWithValues: incomes.map { ($0.persistentModelID, IncomeValue($0)) })
        self.devices = Dictionary(uniqueKeysWithValues: devices.map { ($0.persistentModelID, DeviceValue($0)) })
        self.passiveSources = Dictionary(uniqueKeysWithValues: passiveSources.map { ($0.persistentModelID, PassiveSourceValue($0)) })
        self.assets = Dictionary(uniqueKeysWithValues: assets.map { ($0.persistentModelID, UserAssetsValue($0)) })
    }

    static func capture(in context: ModelContext) throws -> Self {
        try Self(
            expenses: context.fetch(FetchDescriptor<Expense>()),
            incomes: context.fetch(FetchDescriptor<Income>()),
            devices: context.fetch(FetchDescriptor<Device>()),
            passiveSources: context.fetch(FetchDescriptor<PassiveSource>()),
            assets: context.fetch(FetchDescriptor<UserAssets>()),
            observations: context.fetch(FetchDescriptor<FreedomObservation>())
        )
    }
}
