//
//  BackupSchema.swift
//  FreeGrid
//
//  备份文件只在这一层做 Codable；解码后的原始值必须经过 ImportValidator。
//

import Foundation

struct BackupEnvelope: Codable {
    struct AssetsJSON: Codable {
        let total: Double
        let lockedAssets: Double?
        let cash: Double?
        let updatedAt: String?

        init(total: Double, lockedAssets: Double? = nil, cash: Double? = nil, updatedAt: String? = nil) {
            self.total = total
            self.lockedAssets = lockedAssets
            self.cash = cash
            self.updatedAt = updatedAt
        }
    }

    struct ExpenseJSON: Codable {
        let id: String?
        let amount: Double
        let category: String
        let date: String
        let note: String?
        let createdAt: String?

        init(id: String? = nil, amount: Double, category: String, date: String,
             note: String? = nil, createdAt: String? = nil) {
            self.id = id
            self.amount = amount
            self.category = category
            self.date = date
            self.note = note
            self.createdAt = createdAt
        }
    }

    struct IncomeJSON: Codable {
        let id: String?
        let amount: Double
        let source: String
        let date: String
        let note: String?
        let isPassive: Bool?
        let createdAt: String?

        init(id: String? = nil, amount: Double, source: String, date: String,
             note: String? = nil, isPassive: Bool? = nil, createdAt: String? = nil) {
            self.id = id
            self.amount = amount
            self.source = source
            self.date = date
            self.note = note
            self.isPassive = isPassive
            self.createdAt = createdAt
        }
    }

    struct DeviceJSON: Codable {
        let id: String?
        let name: String
        let category: String
        let price: Double
        let purchaseDate: String
        let status: String?
        let soldPrice: Double?
        let soldDate: String?
        let note: String?
        let createdAt: String?

        init(id: String? = nil, name: String, category: String, price: Double,
             purchaseDate: String, status: String? = nil, soldPrice: Double? = nil,
             soldDate: String? = nil, note: String? = nil, createdAt: String? = nil) {
            self.id = id
            self.name = name
            self.category = category
            self.price = price
            self.purchaseDate = purchaseDate
            self.status = status
            self.soldPrice = soldPrice
            self.soldDate = soldDate
            self.note = note
            self.createdAt = createdAt
        }
    }

    struct PassiveSourceJSON: Codable {
        let id: String?
        let name: String
        let monthlyAmount: Double
        let createdAt: String?

        init(id: String? = nil, name: String, monthlyAmount: Double, createdAt: String? = nil) {
            self.id = id
            self.name = name
            self.monthlyAmount = monthlyAmount
            self.createdAt = createdAt
        }
    }

    let schemaVersion: Int?
    let assets: AssetsJSON?
    let expenses: [ExpenseJSON]?
    let incomes: [IncomeJSON]?
    let devices: [DeviceJSON]?
    let passiveSources: [PassiveSourceJSON]?
    let firstRecordDate: String?

    init(
        schemaVersion: Int? = nil,
        assets: AssetsJSON? = nil,
        expenses: [ExpenseJSON]? = nil,
        incomes: [IncomeJSON]? = nil,
        devices: [DeviceJSON]? = nil,
        passiveSources: [PassiveSourceJSON]? = nil,
        firstRecordDate: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.assets = assets
        self.expenses = expenses
        self.incomes = incomes
        self.devices = devices
        self.passiveSources = passiveSources
        self.firstRecordDate = firstRecordDate
    }
}

// 保留现有调用点名称；后续统一改名不应与安全修复绑在同一批。
typealias BackupJSON = BackupEnvelope
