//
//  BackupSchema.swift
//  FreeGrid
//
//  备份文件只在这一层做 Codable；解码后的原始值必须经过 ImportValidator。
//

import Foundation

nonisolated struct BackupEnvelope: Codable {
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
        /// Pro 每月还款的自动扣款指向哪笔贷款。可选：普通支出不写
        let loanId: String?
        /// 算不算进日均消费。可选：只在「不算」时写 false，没写就是算
        let countsInBurn: Bool?
        /// Pro 现金账户：从哪个账户扣的。可选：没拆账户时不写
        let cashAccountId: String?

        init(id: String? = nil, amount: Double, category: String, date: String,
             note: String? = nil, createdAt: String? = nil,
             loanId: String? = nil, countsInBurn: Bool? = nil, cashAccountId: String? = nil) {
            self.id = id
            self.amount = amount
            self.category = category
            self.date = date
            self.note = note
            self.createdAt = createdAt
            self.loanId = loanId
            self.countsInBurn = countsInBurn
            self.cashAccountId = cashAccountId
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
        /// Pro 现金账户：进了哪个账户。可选：没拆账户时不写
        let cashAccountId: String?

        init(id: String? = nil, amount: Double, source: String, date: String,
             note: String? = nil, isPassive: Bool? = nil, createdAt: String? = nil, cashAccountId: String? = nil) {
            self.id = id
            self.amount = amount
            self.source = source
            self.date = date
            self.note = note
            self.isPassive = isPassive
            self.createdAt = createdAt
            self.cashAccountId = cashAccountId
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
        /// 折合的每月，不管几个月到账一次
        let monthlyAmount: Double
        let createdAt: String?
        /// 几个月到账一次。可选：每月时不写，旧版本读到也只会忽略它，`monthlyAmount` 照样对
        let intervalMonths: Int?

        init(id: String? = nil, name: String, monthlyAmount: Double, createdAt: String? = nil,
             intervalMonths: Int? = nil) {
            self.id = id
            self.name = name
            self.monthlyAmount = monthlyAmount
            self.createdAt = createdAt
            self.intervalMonths = intervalMonths
        }
    }

    /// Pro 资产逐项记录。可选字段：没有资产项时不写，旧版本读到也只会忽略它，资产总数仍在 `assets.locked_assets`。
    struct AssetItemJSON: Codable {
        let id: String?
        let name: String
        let amount: Double
        let sortOrder: Int?
        /// 这一项算不算进自由天数。可选：阶段 2 导出的备份没有它，导入后按计入处理。
        let countsInFreedom: Bool?
        let createdAt: String?
        let updatedAt: String?

        init(id: String? = nil, name: String, amount: Double, sortOrder: Int? = nil,
             countsInFreedom: Bool? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
            self.id = id
            self.name = name
            self.amount = amount
            self.sortOrder = sortOrder
            self.countsInFreedom = countsInFreedom
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    /// Pro 现金账户。可选字段：没拆账户时不写，旧版本读到也只会忽略它，现金总数仍在 `assets.cash`。
    struct CashAccountJSON: Codable {
        let id: String?
        let name: String
        let amount: Double
        let sortOrder: Int?
        let createdAt: String?
        let updatedAt: String?
        /// 不计入自由天数时写 false；计入（默认）时不写
        let countsInFreedom: Bool?

        init(id: String? = nil, name: String, amount: Double, sortOrder: Int? = nil,
             createdAt: String? = nil, updatedAt: String? = nil, countsInFreedom: Bool? = nil) {
            self.id = id
            self.name = name
            self.amount = amount
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.countsInFreedom = countsInFreedom
        }
    }

    /// 固定支出和贷款。可选字段：都没有时不写，旧版本读到也只会忽略它。
    /// 已经扣过的是普通支出（带 `loan_id`），不在这里。
    struct LoanJSON: Codable {
        let id: String?
        let name: String
        let monthlyAmount: Double
        let dueDay: Int
        let periodsAtStart: Int
        let startDate: String
        let processedThrough: String?
        let settledDates: [String]?
        let sortOrder: Int?
        let createdAt: String?
        /// Pro 现金账户：月供固定从哪个账户扣。可选：没指定时不写
        let cashAccountId: String?
        /// 固定支出（一直有）。只在为真时写；没有这个字段的都是贷款
        let isOngoing: Bool?
        /// 隔几个月一次。只在不是 1 时写
        let intervalMonths: Int?

        init(id: String? = nil, name: String, monthlyAmount: Double, dueDay: Int, periodsAtStart: Int,
             startDate: String, processedThrough: String? = nil, settledDates: [String]? = nil,
             sortOrder: Int? = nil, createdAt: String? = nil, cashAccountId: String? = nil,
             isOngoing: Bool? = nil, intervalMonths: Int? = nil) {
            self.id = id
            self.name = name
            self.monthlyAmount = monthlyAmount
            self.dueDay = dueDay
            self.periodsAtStart = periodsAtStart
            self.startDate = startDate
            self.processedThrough = processedThrough
            self.settledDates = settledDates
            self.sortOrder = sortOrder
            self.createdAt = createdAt
            self.cashAccountId = cashAccountId
            self.isOngoing = isOngoing
            self.intervalMonths = intervalMonths
        }
    }

    /// Pro 自定义分类的设置：顺序就是数组顺序。可选字段：没自定义过分类时不写。
    struct ExpenseCategoryJSON: Codable {
        let name: String
        let icon: String?
        /// 删掉的分类留记号，只在为真时写
        let deleted: Bool?

        init(name: String, icon: String? = nil, deleted: Bool? = nil) {
            self.name = name
            self.icon = icon
            self.deleted = deleted
        }
    }

    let schemaVersion: Int?
    let assets: AssetsJSON?
    let expenses: [ExpenseJSON]?
    let incomes: [IncomeJSON]?
    let devices: [DeviceJSON]?
    let passiveSources: [PassiveSourceJSON]?
    let firstRecordDate: String?
    let assetItems: [AssetItemJSON]?
    let loans: [LoanJSON]?
    let expenseCategories: [ExpenseCategoryJSON]?
    let cashAccounts: [CashAccountJSON]?
    /// 2.2：记账方式和每月写下的数。可选：没用过每月一个数时不写
    let monthlyTracking: MonthlyTrackingJSON?

    init(
        schemaVersion: Int? = nil,
        assets: AssetsJSON? = nil,
        expenses: [ExpenseJSON]? = nil,
        incomes: [IncomeJSON]? = nil,
        devices: [DeviceJSON]? = nil,
        passiveSources: [PassiveSourceJSON]? = nil,
        firstRecordDate: String? = nil,
        assetItems: [AssetItemJSON]? = nil,
        loans: [LoanJSON]? = nil,
        expenseCategories: [ExpenseCategoryJSON]? = nil,
        cashAccounts: [CashAccountJSON]? = nil,
        monthlyTracking: MonthlyTrackingJSON? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.assets = assets
        self.expenses = expenses
        self.incomes = incomes
        self.devices = devices
        self.passiveSources = passiveSources
        self.firstRecordDate = firstRecordDate
        self.assetItems = assetItems
        self.loans = loans
        self.expenseCategories = expenseCategories
        self.cashAccounts = cashAccounts
        self.monthlyTracking = monthlyTracking
    }
}

/// 记账方式和每月写下的数（2.2）。日期是 ISO 8601，和备份里别的时间一样
struct MonthlyTrackingJSON: Codable {
    struct Pause: Codable {
        let start: String
        let end: String?
    }

    let method: String
    let months: [String: Double]
    let startMonth: String?
    let pauses: [Pause]?
    let switchedBackAt: String?

    init(_ tracking: MonthlyTracking) {
        let iso = ISO8601DateFormatter()
        method = tracking.method.rawValue
        months = Dictionary(uniqueKeysWithValues: tracking.writtenMonths.map { ($0.month.key, $0.amount) })
        startMonth = tracking.startMonth
        pauses = tracking.pauses.isEmpty ? nil : tracking.pauses.map {
            Pause(start: iso.string(from: $0.start), end: $0.end.map(iso.string(from:)))
        }
        switchedBackAt = tracking.switchedBackAt.map(iso.string(from:))
    }

    /// 只是偏好，不对的部分就当没有，不拦整份备份
    var tracking: MonthlyTracking {
        let iso = ISO8601DateFormatter()
        return MonthlyTracking(
            method: MonthlyTracking.Method(rawValue: method) ?? .entries,
            months: months.filter { YearMonth(key: $0.key) != nil && MonthlyTracking.valid($0.value) != nil },
            startMonth: startMonth.flatMap(YearMonth.init(key:))?.key,
            pauses: (pauses ?? []).compactMap { pause in
                iso.date(from: pause.start).map { MonthlyTracking.Pause(start: $0, end: pause.end.flatMap(iso.date(from:))) }
            },
            switchedBackAt: switchedBackAt.flatMap(iso.date(from:)))
    }
}
