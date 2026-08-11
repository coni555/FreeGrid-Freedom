//
//  DataIO.swift
//  FreeGrid
//
//  备份导入、导出与清空数据。外部 JSON 必须先经过 ImportValidator。
//

import Foundation
import SwiftData

enum DataIO {
    enum DataIOError: Error, LocalizedError {
        case invalidCategoryMapping(String)
        case invalidStoredValue(String)

        var errorDescription: String? {
            switch self {
            case .invalidCategoryMapping(let category):
                return "导入分类映射无效：\(category)"
            case .invalidStoredValue(let field):
                return "本地数据中的\(field)无法安全导出"
            }
        }
    }

    struct ImportResult {
        let expensesAdded: Int
        let incomesAdded: Int
        let devicesAdded: Int
        let passiveSourcesAdded: Int
        let assetsTotal: Double
        let firstRecordDate: Date?
    }

    struct CategoryMapEntry: Identifiable {
        var id: String { raw }
        let raw: String
        let count: Int
        let total: Double
        var canonical: String
        let needsReview: Bool
    }

    struct DuplicateCount {
        let existing: Int
        let inFile: Int
        var total: Int { existing + inFile }
    }

    struct AssetSnapshot: Equatable {
        let lockedAssets: Double
        let cash: Double
        let total: Double
        let updatedAt: Date?
    }

    /// 预览只保留已验证的强类型值；BackupEnvelope 的原始字符串不能越过这里。
    struct ImportPreview {
        let schemaVersion: Int
        let expensesNew: [ValidatedImport.ExpenseRecord]
        let expenseDuplicates: DuplicateCount
        let incomesNew: [ValidatedImport.IncomeRecord]
        let incomeDuplicates: DuplicateCount
        let devicesNew: [ValidatedImport.DeviceRecord]
        let deviceDuplicates: DuplicateCount
        let passiveSourcesNew: [ValidatedImport.PassiveSourceRecord]
        let passiveSourceDuplicates: DuplicateCount
        let importedAssets: AssetSnapshot
        let jsonFirstRecordDate: Date?
        let currentCash: Double
        let currentLockedAssets: Double
        let categoryEntries: [CategoryMapEntry]

        var expensesSkipped: Int { expenseDuplicates.total }
        var incomesSkipped: Int { incomeDuplicates.total }
        var devicesSkipped: Int { deviceDuplicates.total }
        var passiveSourcesSkipped: Int { passiveSourceDuplicates.total }
        var jsonAssetsTotal: Double { importedAssets.total }
        var jsonLockedAssets: Double? { importedAssets.lockedAssets }
        var jsonCash: Double? { importedAssets.cash }
        var jsonAssetsUpdatedAt: Date? { importedAssets.updatedAt }
    }

    enum AssetsImportStrategy: Equatable {
        case replace
        case addToCash
        case skipAssets
    }

    struct ImportPlan {
        struct ExpenseRecord {
            let id: UUID?
            let amount: Double
            let category: String
            let note: String
            let date: Date
            let createdAt: Date?
        }

        enum AssetsAction {
            case replace(AssetSnapshot)
            case addToCash(Double)
            case skip
        }

        let expenses: [ExpenseRecord]
        let incomes: [ValidatedImport.IncomeRecord]
        let devices: [ValidatedImport.DeviceRecord]
        let passiveSources: [ValidatedImport.PassiveSourceRecord]
        let assetsAction: AssetsAction
        let importedAssetsTotal: Double
    }

    typealias SaveAction = (ModelContext) throws -> Void

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func exportJSON(context: ModelContext) throws -> Data {
        let day = dayFormatter()
        let iso = ISO8601DateFormatter()
        let expenses = try context.fetch(FetchDescriptor<Expense>(
            sortBy: [SortDescriptor(\.date)]
        ))
        let incomes = try context.fetch(FetchDescriptor<Income>(
            sortBy: [SortDescriptor(\.date)]
        ))
        let devices = try context.fetch(FetchDescriptor<Device>(
            sortBy: [SortDescriptor(\.purchaseDate)]
        ))
        let passives = try context.fetch(FetchDescriptor<PassiveSource>(
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        let assets = try context.fetch(FetchDescriptor<UserAssets>()).first
        let firstExpenseDate = expenses.map(\.date).min()
        let schemaVersion = expenses.contains { $0.amount <= 0 }
            ? ImportValidator.signedExpenseSchemaVersion
            : ImportValidator.strictPositiveExpenseSchemaVersion

        let dump = BackupEnvelope(
            schemaVersion: schemaVersion,
            assets: assets.map {
                BackupEnvelope.AssetsJSON(
                    total: $0.netWorth,
                    lockedAssets: $0.lockedAssets,
                    cash: $0.cash,
                    updatedAt: iso.string(from: $0.updatedAt)
                )
            },
            expenses: expenses.map {
                BackupEnvelope.ExpenseJSON(
                    id: $0.id.uuidString,
                    amount: $0.amount,
                    category: $0.category,
                    date: day.string(from: $0.date),
                    note: $0.note,
                    createdAt: iso.string(from: $0.createdAt)
                )
            },
            incomes: incomes.map {
                BackupEnvelope.IncomeJSON(
                    id: $0.id.uuidString,
                    amount: $0.amount,
                    source: $0.source,
                    date: day.string(from: $0.date),
                    note: $0.note,
                    isPassive: $0.isPassive,
                    createdAt: iso.string(from: $0.createdAt)
                )
            },
            devices: devices.map {
                BackupEnvelope.DeviceJSON(
                    id: $0.id.uuidString,
                    name: $0.name,
                    category: $0.category,
                    price: $0.price,
                    purchaseDate: day.string(from: $0.purchaseDate),
                    status: $0.status,
                    soldPrice: $0.soldPrice,
                    soldDate: $0.soldDate.map { day.string(from: $0) },
                    note: $0.note,
                    createdAt: iso.string(from: $0.createdAt)
                )
            },
            passiveSources: passives.map {
                BackupEnvelope.PassiveSourceJSON(
                    id: $0.id.uuidString,
                    name: $0.name,
                    monthlyAmount: $0.monthlyAmount,
                    createdAt: iso.string(from: $0.createdAt)
                )
            },
            firstRecordDate: firstExpenseDate.map { day.string(from: $0) }
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        let data = try encoder.encode(dump)
        // now 传 .distantFuture 是为了关掉"未来日期"检查:设备时钟曾经快过、
        // 或用户跨时区旅行后,本地合法记录会相对此刻落在未来。那是导入外来文件时
        // 才需要警惕的信号,不该反过来堵死本人的导出。
        _ = try ImportValidator.validate(
            data: data,
            policy: .exportSelfCheck,
            now: .distantFuture
        )
        return data
    }

    static func exportCSV(context: ModelContext) throws -> Data {
        let day = dayFormatter()
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let incomes = try context.fetch(FetchDescriptor<Income>())

        struct Row {
            let date: String
            let kind: String
            let label: String
            let amount: Double
            let note: String
            let allowsSignedAmount: Bool
        }
        var rows: [Row] = []
        rows += expenses.map {
            Row(date: day.string(from: $0.date), kind: "支出", label: $0.category,
                amount: $0.amount, note: $0.note, allowsSignedAmount: true)
        }
        rows += incomes.map {
            Row(date: day.string(from: $0.date), kind: "收入", label: $0.source,
                amount: $0.amount, note: $0.note, allowsSignedAmount: false)
        }
        rows.sort { $0.date < $1.date }

        func neutralizeFormula(_ value: String) -> String {
            let firstNonWhitespace = value.first { !$0.isWhitespace }
            guard let firstNonWhitespace, "=+-@".contains(firstNonWhitespace) else {
                return value
            }
            return "'" + value
        }
        func escape(_ value: String) -> String {
            let value = neutralizeFormula(value)
            guard value.contains(",") || value.contains("\"")
                    || value.contains("\n") || value.contains("\r") else {
                return value
            }
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func amount(_ value: Double, field: String, allowsSigned: Bool) throws -> String {
            let isValid = value.isFinite
                && abs(value) <= FinancialLimits.maximumAmount
                && (allowsSigned || value > 0)
            guard isValid else {
                throw DataIOError.invalidStoredValue(field)
            }
            // 必须锁死 POSIX locale:跟随系统 locale 时,逗号小数区(en_DE / fr 等)
            // 会把 1234.5 写成 "1234,5",而金额列不加引号,整行会多出一列。
            return value.formatted(
                .number
                    .grouping(.never)
                    .precision(.fractionLength(0...2))
                    .locale(Locale(identifier: "en_US_POSIX"))
            )
        }

        var csv = "\u{FEFF}"
        csv += "日期,类型,类别/来源,金额,备注\n"
        for row in rows {
            let formattedAmount = try amount(
                row.amount,
                field: row.kind + "金额",
                allowsSigned: row.allowsSignedAmount
            )
            csv += "\(row.date),\(row.kind),\(escape(row.label)),"
            csv += "\(formattedAmount),\(escape(row.note))\n"
        }
        return Data(csv.utf8)
    }

    static func previewJSON(data: Data, context: ModelContext) throws -> ImportPreview {
        let validated = try ImportValidator.validate(data: data)
        return try preview(validated: validated, context: context)
    }

    static func preview(validated: ValidatedImport, context: ModelContext) throws -> ImportPreview {
        let existingExpenses = try context.fetch(FetchDescriptor<Expense>())
        let existingExpenseKeys = Set(existingExpenses.map {
            expenseKey(amount: $0.amount, date: $0.date, category: $0.category, note: $0.note)
        })
        let existingExpenseIDs = Set(existingExpenses.map(\.id))
        var seenExpenseKeys = existingExpenseKeys
        var seenExpenseIDs = existingExpenseIDs

        let existingIncomes = try context.fetch(FetchDescriptor<Income>())
        let existingIncomeKeys = Set(existingIncomes.map {
            incomeKey(amount: $0.amount, date: $0.date, source: $0.source, note: $0.note)
        })
        let existingIncomeIDs = Set(existingIncomes.map(\.id))
        var seenIncomeKeys = existingIncomeKeys
        var seenIncomeIDs = existingIncomeIDs

        let existingDevices = try context.fetch(FetchDescriptor<Device>())
        let existingDeviceKeys = Set(existingDevices.map {
            deviceKey(name: $0.name, price: $0.price, purchaseDate: $0.purchaseDate)
        })
        let existingDeviceIDs = Set(existingDevices.map(\.id))
        var seenDeviceKeys = existingDeviceKeys
        var seenDeviceIDs = existingDeviceIDs

        let existingPassives = try context.fetch(FetchDescriptor<PassiveSource>())
        let existingPassiveKeys = Set(existingPassives.map {
            passiveKey(name: $0.name, monthlyAmount: $0.monthlyAmount)
        })
        let existingPassiveIDs = Set(existingPassives.map(\.id))
        var seenPassiveKeys = existingPassiveKeys
        var seenPassiveIDs = existingPassiveIDs

        var expensesNew: [ValidatedImport.ExpenseRecord] = []
        var expenseExistingDuplicates = 0
        var expenseFileDuplicates = 0
        for record in validated.expenses {
            let key = expenseKey(
                amount: record.amount,
                date: record.date,
                category: record.category,
                note: record.note
            )
            if let id = record.id {
                if existingExpenseIDs.contains(id) {
                    expenseExistingDuplicates += 1
                    continue
                }
                guard seenExpenseIDs.insert(id).inserted else {
                    expenseFileDuplicates += 1
                    continue
                }
            } else {
                if existingExpenseKeys.contains(key) {
                    expenseExistingDuplicates += 1
                    continue
                }
                guard seenExpenseKeys.insert(key).inserted else {
                    expenseFileDuplicates += 1
                    continue
                }
            }
            seenExpenseKeys.insert(key)
            expensesNew.append(record)
        }

        var incomesNew: [ValidatedImport.IncomeRecord] = []
        var incomeExistingDuplicates = 0
        var incomeFileDuplicates = 0
        for record in validated.incomes {
            let key = incomeKey(
                amount: record.amount,
                date: record.date,
                source: record.source,
                note: record.note
            )
            if let id = record.id {
                if existingIncomeIDs.contains(id) {
                    incomeExistingDuplicates += 1
                    continue
                }
                guard seenIncomeIDs.insert(id).inserted else {
                    incomeFileDuplicates += 1
                    continue
                }
            } else {
                if existingIncomeKeys.contains(key) {
                    incomeExistingDuplicates += 1
                    continue
                }
                guard seenIncomeKeys.insert(key).inserted else {
                    incomeFileDuplicates += 1
                    continue
                }
            }
            seenIncomeKeys.insert(key)
            incomesNew.append(record)
        }

        var devicesNew: [ValidatedImport.DeviceRecord] = []
        var deviceExistingDuplicates = 0
        var deviceFileDuplicates = 0
        for record in validated.devices {
            let key = deviceKey(name: record.name, price: record.price, purchaseDate: record.purchaseDate)
            if let id = record.id {
                if existingDeviceIDs.contains(id) {
                    deviceExistingDuplicates += 1
                    continue
                }
                guard seenDeviceIDs.insert(id).inserted else {
                    deviceFileDuplicates += 1
                    continue
                }
            } else {
                if existingDeviceKeys.contains(key) {
                    deviceExistingDuplicates += 1
                    continue
                }
                guard seenDeviceKeys.insert(key).inserted else {
                    deviceFileDuplicates += 1
                    continue
                }
            }
            seenDeviceKeys.insert(key)
            devicesNew.append(record)
        }

        var passiveSourcesNew: [ValidatedImport.PassiveSourceRecord] = []
        var passiveExistingDuplicates = 0
        var passiveFileDuplicates = 0
        for record in validated.passiveSources {
            let key = passiveKey(name: record.name, monthlyAmount: record.monthlyAmount)
            if let id = record.id {
                if existingPassiveIDs.contains(id) {
                    passiveExistingDuplicates += 1
                    continue
                }
                guard seenPassiveIDs.insert(id).inserted else {
                    passiveFileDuplicates += 1
                    continue
                }
            } else {
                if existingPassiveKeys.contains(key) {
                    passiveExistingDuplicates += 1
                    continue
                }
                guard seenPassiveKeys.insert(key).inserted else {
                    passiveFileDuplicates += 1
                    continue
                }
            }
            seenPassiveKeys.insert(key)
            passiveSourcesNew.append(record)
        }

        let existingAssets = try context.fetch(FetchDescriptor<UserAssets>()).first

        var categoryTotals: [String: (count: Int, total: Double)] = [:]
        for expense in expensesNew {
            let raw = expense.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ExpenseCategory.canonical.contains(raw) else { continue }
            let previous = categoryTotals[raw] ?? (0, 0)
            categoryTotals[raw] = (previous.count + 1, previous.total + expense.amount)
        }
        let categoryEntries = categoryTotals
            .map { raw, aggregate in
                let suggestion = ExpenseCategory.suggest(raw)
                return CategoryMapEntry(
                    raw: raw,
                    count: aggregate.count,
                    total: aggregate.total,
                    canonical: suggestion.canonical,
                    needsReview: !suggestion.known
                )
            }
            .sorted { $0.total > $1.total }

        let importedAssets: AssetSnapshot
        if let assets = validated.assets {
            if let lockedAssets = assets.lockedAssets, let cash = assets.cash {
                importedAssets = AssetSnapshot(
                    lockedAssets: lockedAssets,
                    cash: cash,
                    total: lockedAssets + cash,
                    updatedAt: assets.updatedAt
                )
            } else {
                importedAssets = AssetSnapshot(
                    lockedAssets: 0,
                    cash: assets.total,
                    total: assets.total,
                    updatedAt: assets.updatedAt
                )
            }
        } else {
            importedAssets = AssetSnapshot(lockedAssets: 0, cash: 0, total: 0, updatedAt: nil)
        }

        return ImportPreview(
            schemaVersion: validated.schemaVersion,
            expensesNew: expensesNew,
            expenseDuplicates: DuplicateCount(
                existing: expenseExistingDuplicates,
                inFile: expenseFileDuplicates
            ),
            incomesNew: incomesNew,
            incomeDuplicates: DuplicateCount(
                existing: incomeExistingDuplicates,
                inFile: incomeFileDuplicates
            ),
            devicesNew: devicesNew,
            deviceDuplicates: DuplicateCount(
                existing: deviceExistingDuplicates,
                inFile: deviceFileDuplicates
            ),
            passiveSourcesNew: passiveSourcesNew,
            passiveSourceDuplicates: DuplicateCount(
                existing: passiveExistingDuplicates,
                inFile: passiveFileDuplicates
            ),
            importedAssets: importedAssets,
            jsonFirstRecordDate: validated.firstRecordDate,
            currentCash: existingAssets?.cash ?? 0,
            currentLockedAssets: existingAssets?.lockedAssets ?? 0,
            categoryEntries: categoryEntries
        )
    }

    static func makeImportPlan(
        preview: ImportPreview,
        strategy: AssetsImportStrategy,
        categoryMap: [String: String] = [:]
    ) throws -> ImportPlan {
        for target in categoryMap.values where !ExpenseCategory.canonical.contains(target) {
            throw DataIOError.invalidCategoryMapping(target)
        }

        let expenses = preview.expensesNew.map { record in
            let rawCategory = record.category.trimmingCharacters(in: .whitespacesAndNewlines)
            let mappedCategory = categoryMap[rawCategory] ?? ExpenseCategory.suggest(rawCategory).canonical
            var note = record.note
            if mappedCategory != rawCategory {
                note = note.isEmpty
                    ? "原分类·\(rawCategory)"
                    : "\(note) · 原分类·\(rawCategory)"
                // 拼接后必须重新落回备注上限:否则这条记录写进库就再也导不出去
                // (导出自校验会抛 textTooLong,整份导出被阻断)。
                if note.count > FinancialLimits.noteCharacters {
                    note = String(note.prefix(FinancialLimits.noteCharacters))
                }
            }
            return ImportPlan.ExpenseRecord(
                id: record.id,
                amount: record.amount,
                category: mappedCategory,
                note: note,
                date: record.date,
                createdAt: record.createdAt
            )
        }

        let assetsAction: ImportPlan.AssetsAction
        switch strategy {
        case .replace:
            assetsAction = .replace(preview.importedAssets)
        case .addToCash:
            assetsAction = .addToCash(preview.importedAssets.total)
        case .skipAssets:
            assetsAction = .skip
        }

        return ImportPlan(
            expenses: expenses,
            incomes: preview.incomesNew,
            devices: preview.devicesNew,
            passiveSources: preview.passiveSourcesNew,
            assetsAction: assetsAction,
            importedAssetsTotal: preview.importedAssets.total
        )
    }

    static func commitImport(
        preview: ImportPreview,
        strategy: AssetsImportStrategy,
        categoryMap: [String: String] = [:],
        context: ModelContext
    ) throws -> ImportResult {
        let plan = try makeImportPlan(
            preview: preview,
            strategy: strategy,
            categoryMap: categoryMap
        )
        return try commitImport(plan: plan, context: context)
    }

    static func commitImport(
        plan: ImportPlan,
        context: ModelContext,
        save: SaveAction = { try $0.save() }
    ) throws -> ImportResult {
        var firstRecordDate: Date?
        do {
            try context.transaction {
                for record in plan.expenses {
                    let expense = Expense(
                        amount: record.amount,
                        category: record.category,
                        note: record.note,
                        date: record.date
                    )
                    if let id = record.id { expense.id = id }
                    if let createdAt = record.createdAt { expense.createdAt = createdAt }
                    context.insert(expense)
                }

                for record in plan.incomes {
                    let income = Income(
                        amount: record.amount,
                        source: record.source,
                        isPassive: record.isPassive,
                        note: record.note,
                        date: record.date
                    )
                    if let id = record.id { income.id = id }
                    if let createdAt = record.createdAt { income.createdAt = createdAt }
                    context.insert(income)
                }

                for record in plan.devices {
                    let device = Device(
                        name: record.name,
                        category: record.category,
                        price: record.price,
                        purchaseDate: record.purchaseDate,
                        note: record.note
                    )
                    if let id = record.id { device.id = id }
                    device.status = record.status
                    device.soldPrice = record.soldPrice
                    device.soldDate = record.soldDate
                    if let createdAt = record.createdAt { device.createdAt = createdAt }
                    context.insert(device)
                }

                for record in plan.passiveSources {
                    let source = PassiveSource(name: record.name, monthlyAmount: record.monthlyAmount)
                    if let id = record.id { source.id = id }
                    if let createdAt = record.createdAt { source.createdAt = createdAt }
                    context.insert(source)
                }

                let existingAssets = try context.fetch(FetchDescriptor<UserAssets>()).first
                let userAssets: UserAssets
                if let existingAssets {
                    userAssets = existingAssets
                } else {
                    userAssets = UserAssets(total: 0)
                    context.insert(userAssets)
                }

                switch plan.assetsAction {
                case .replace(let snapshot):
                    userAssets.lockedAssets = snapshot.lockedAssets
                    userAssets.cash = snapshot.cash
                    userAssets.updatedAt = snapshot.updatedAt ?? .now
                case .addToCash(let amount):
                    userAssets.cash += amount
                    userAssets.updatedAt = .now
                case .skip:
                    break
                }

                let allExpenses = try context.fetch(FetchDescriptor<Expense>())
                firstRecordDate = allExpenses.map(\.date).min()
                userAssets.firstRecordDate = firstRecordDate
                try save(context)
            }
        } catch {
            context.rollback()
            throw error
        }

        return ImportResult(
            expensesAdded: plan.expenses.count,
            incomesAdded: plan.incomes.count,
            devicesAdded: plan.devices.count,
            passiveSourcesAdded: plan.passiveSources.count,
            assetsTotal: plan.importedAssetsTotal,
            firstRecordDate: firstRecordDate
        )
    }

    static func purgeAll(context: ModelContext) throws {
        try context.delete(model: Expense.self)
        try context.delete(model: Income.self)
        try context.delete(model: Device.self)
        try context.delete(model: PassiveSource.self)
        try context.delete(model: UserAssets.self)
    }

    private static func expenseKey(amount: Double, date: Date, category: String, note: String) -> String {
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(day)|\(amount)|\(category)|\(note)"
    }

    private static func incomeKey(amount: Double, date: Date, source: String, note: String) -> String {
        let day = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "\(day)|\(amount)|\(source)|\(note)"
    }

    private static func deviceKey(name: String, price: Double, purchaseDate: Date) -> String {
        let day = Int(Calendar.current.startOfDay(for: purchaseDate).timeIntervalSince1970)
        return "\(day)|\(price)|\(name)"
    }

    private static func passiveKey(name: String, monthlyAmount: Double) -> String {
        "\(name)|\(monthlyAmount)"
    }
}
