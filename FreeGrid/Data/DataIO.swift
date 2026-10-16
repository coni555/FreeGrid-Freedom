//
//  DataIO.swift
//  FreeGrid
//
//  备份导入、导出与清空数据。外部 JSON 必须先经过 ImportValidator。
//

import Foundation
import SwiftData

enum DataIO {
    enum DataIOError: Error, LocalizedError, Equatable {
        case invalidCategoryMapping(String)
        case invalidStoredValue(String)
        case stalePreview

        var errorDescription: String? {
            switch self {
            case .stalePreview:
                return "账本已在预览后发生变化。请取消并重新选择备份，核对新的预览后再导入。"
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
        var loansAdded = 0
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
        let ledgerSnapshot: ImportLedgerSnapshot
        let schemaVersion: Int
        let expensesNew: [ValidatedImport.ExpenseRecord]
        /// expensesNew 中待用户判断的下标；默认保留，不计入确定重复。
        let suspectedExpenseIndices: [Int]
        let expenseDuplicates: DuplicateCount
        let incomesNew: [ValidatedImport.IncomeRecord]
        let incomeDuplicates: DuplicateCount
        let devicesNew: [ValidatedImport.DeviceRecord]
        let deviceDuplicates: DuplicateCount
        let passiveSourcesNew: [ValidatedImport.PassiveSourceRecord]
        let passiveSourceDuplicates: DuplicateCount
        /// 备份里的资产项。只在「替换」资产时一起恢复，其他策略不碰现有的项。
        let importedAssetItems: [ValidatedImport.AssetItemRecord]
        let currentAssetItemCount: Int
        /// 备份里的现金账户。和资产项一样，只在「替换」时一起恢复
        var importedCashAccounts: [ValidatedImport.CashAccountRecord] = []
        /// 备份里账本还没有的每月还款（按 ID 认），所有策略都一样合并进来
        var loansNew: [ValidatedImport.LoanRecord] = []
        /// 备份里的 Pro 分类设置；nil 表示没有。导入成功后由页面并进本机偏好（见 `ExpenseCategoryOptions.merging`）
        var categoryOptions: ExpenseCategoryOptions? = nil
        let importedAssets: AssetSnapshot
        let jsonFirstRecordDate: Date?
        let currentCash: Double
        let currentLockedAssets: Double
        let categoryEntries: [CategoryMapEntry]
        let categoryNames: [String]

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
            var loanID: UUID? = nil
            var countsInBurn = true
            var cashAccountID: UUID? = nil
        }

        enum AssetsAction {
            case replace(AssetSnapshot)
            case addToCash(Double)
            case skip
        }

        let ledgerSnapshot: ImportLedgerSnapshot
        let expenses: [ExpenseRecord]
        let incomes: [ValidatedImport.IncomeRecord]
        let devices: [ValidatedImport.DeviceRecord]
        let passiveSources: [ValidatedImport.PassiveSourceRecord]
        let assetsAction: AssetsAction
        /// 仅 `.replace` 时写入：现有资产项整体换成这些（可以是空，也就是回到只有总数）
        let assetItems: [ValidatedImport.AssetItemRecord]
        let importedAssetsTotal: Double
        var loans: [ValidatedImport.LoanRecord] = []
        /// 仅 `.replace` 时写入：现有现金账户整体换成这些（可以是空，也就是回到只有总数）
        var cashAccounts: [ValidatedImport.CashAccountRecord] = []
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

    /// `categoryOptions` 是本机的分类设置；用户没自定义过时传 nil，备份里就不写这一段。
    static func exportJSON(context: ModelContext, categoryOptions: ExpenseCategoryOptions? = nil) throws -> Data {
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
        let assetItems = try AssetItemStore.items(in: context)
        let cashAccounts = try CashAccountStore.accounts(in: context)
        let loans = try LoanStore.loans(in: context)
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
                    createdAt: iso.string(from: $0.createdAt),
                    // 普通支出两个字段都不写，没有贷款的账本导出和以前一字不差
                    loanId: $0.loanID?.uuidString,
                    countsInBurn: $0.countsInBurn ? nil : false,
                    cashAccountId: $0.cashAccountID?.uuidString
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
                    createdAt: iso.string(from: $0.createdAt),
                    cashAccountId: $0.cashAccountID?.uuidString
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
            firstRecordDate: firstExpenseDate.map { day.string(from: $0) },
            assetItems: assetItems.isEmpty ? nil : assetItems.map {
                BackupEnvelope.AssetItemJSON(
                    id: $0.id.uuidString,
                    name: $0.name,
                    amount: $0.amount,
                    sortOrder: $0.sortOrder,
                    countsInFreedom: $0.countsInFreedom,
                    createdAt: iso.string(from: $0.createdAt),
                    updatedAt: iso.string(from: $0.updatedAt)
                )
            },
            loans: loans.isEmpty ? nil : loans.map {
                BackupEnvelope.LoanJSON(
                    id: $0.id.uuidString,
                    name: $0.name,
                    monthlyAmount: $0.monthlyAmount,
                    dueDay: $0.dueDay,
                    periodsAtStart: $0.periodsAtStart,
                    startDate: day.string(from: $0.startDate),
                    processedThrough: $0.processedThrough.map { day.string(from: $0) },
                    settledDates: $0.settledDates.isEmpty ? nil : $0.settledDates.sorted().map { day.string(from: $0) },
                    sortOrder: $0.sortOrder,
                    createdAt: iso.string(from: $0.createdAt),
                    cashAccountId: $0.cashAccountID?.uuidString
                )
            },
            expenseCategories: categoryOptions.map { options in
                options.items.map {
                    BackupEnvelope.ExpenseCategoryJSON(name: $0.name, icon: $0.icon, deleted: $0.isDeleted ? true : nil)
                }
            },
            cashAccounts: cashAccounts.isEmpty ? nil : cashAccounts.map {
                BackupEnvelope.CashAccountJSON(
                    id: $0.id.uuidString,
                    name: $0.name,
                    amount: $0.amount,
                    sortOrder: $0.sortOrder,
                    createdAt: iso.string(from: $0.createdAt),
                    updatedAt: iso.string(from: $0.updatedAt)
                )
            }
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

    static func previewJSON(data: Data, context: ModelContext,
                            categoryNames: [String] = ExpenseCategory.canonical) throws -> ImportPreview {
        let validated = try ImportValidator.validate(data: data)
        return try preview(validated: validated, context: context, categoryNames: categoryNames)
    }

    static func preview(validated: ValidatedImport, context: ModelContext,
                        categoryNames: [String] = ExpenseCategory.canonical) throws -> ImportPreview {
        let existingExpenses = try context.fetch(FetchDescriptor<Expense>())
        let knownCategories = Array(Set(ExpenseCategory.canonical + categoryNames
            + existingExpenses.filter { $0.loanID == nil }.map(\.category))).filter {
                !$0.isEmpty && $0.count <= FinancialLimits.nameCharacters
                    && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.sorted()
        let existingExpenseKeys = Set(existingExpenses.map {
            expenseKey(amount: $0.amount, date: $0.date, category: $0.category, note: $0.note)
        })
        let existingExpenseIDs = Set(existingExpenses.map(\.id))
        // 分类不限数量后，不逐条遍历全部分类。按日期、金额和映射后的备注索引旧记录。
        var existingProvenance: [TransactionKey: Set<String>] = [:]
        for expense in existingExpenses {
            let key = expenseKey(amount: expense.amount, date: expense.date, category: "", note: expense.note)
            existingProvenance[key, default: []].insert(expense.category)
        }
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
        var suspectedExpenseIndices: [Int] = []
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
                let raw = record.category.trimmingCharacters(in: .whitespacesAndNewlines)
                let annotation = annotatedExpenseNote(rawCategory: raw, note: record.note)
                let provenanceKey = expenseKey(amount: record.amount, date: record.date, category: "",
                    note: String(annotation.prefix(FinancialLimits.noteCharacters)))
                let normalizedMatch = existingExpenseKeys.contains(expenseKey(
                    amount: record.amount, date: record.date, category: raw, note: record.note))
                let mappedMatch = normalizedMatch || (!ExpenseCategory.canonical.contains(raw)
                    && (existingProvenance[provenanceKey]?.contains { $0 != raw } ?? false))
                let annotationIsComplete = annotation.count <= FinancialLimits.noteCharacters
                if existingExpenseKeys.contains(key) || (mappedMatch && annotationIsComplete) {
                    expenseExistingDuplicates += 1
                    continue
                }
                guard seenExpenseKeys.insert(key).inserted else {
                    expenseFileDuplicates += 1
                    continue
                }
                if mappedMatch { suspectedExpenseIndices.append(expensesNew.count) }
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

        let allAssets = try context.fetch(FetchDescriptor<UserAssets>())
        let existingAssets = allAssets.first
        let existingAssetItems = try context.fetch(FetchDescriptor<AssetItem>())
        let existingLoans = try context.fetch(FetchDescriptor<Loan>())
        let existingCashAccounts = try context.fetch(FetchDescriptor<CashAccount>())
        let existingLoanIDs = Set(existingLoans.map(\.id))
        let loansNew = validated.loans.filter { record in
            record.id.map { !existingLoanIDs.contains($0) } ?? !existingLoans.contains {
                $0.name == record.name && $0.monthlyAmount == record.monthlyAmount && $0.dueDay == record.dueDay
            }
        }
        // 文件里没写顺序时按文件中的先后；写了就按写的顺序
        let importedAssetItems = validated.assetItems.enumerated()
            .sorted { ($0.element.sortOrder ?? $0.offset, $0.offset) < ($1.element.sortOrder ?? $1.offset, $1.offset) }
            .map(\.element)

        var categoryTotals: [String: (count: Int, total: Double)] = [:]
        // 月供扣款的分类就是贷款名，原样保留，不进分类对齐
        for expense in expensesNew where expense.loanID == nil {
            let raw = expense.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ExpenseCategory.canonical.contains(raw) else { continue }
            let previous = categoryTotals[raw] ?? (0, 0)
            categoryTotals[raw] = (previous.count + 1, previous.total + expense.amount)
        }
        // 带 UUID 的 v2/v3 账本备份原样恢复名称；旧无 ID 数据仍保留分类对齐。
        let restorableCategories = Set(expensesNew.filter { validated.schemaVersion >= 2 && $0.id != nil }
            .map { $0.category.trimmingCharacters(in: .whitespacesAndNewlines) })
        let categoryEntries = categoryTotals
            .map { raw, aggregate in
                let suggestion = ExpenseCategory.suggest(raw)
                let preserve = knownCategories.contains(raw) || restorableCategories.contains(raw)
                return CategoryMapEntry(
                    raw: raw,
                    count: aggregate.count,
                    total: aggregate.total,
                    canonical: preserve ? raw : suggestion.canonical,
                    needsReview: !preserve && !suggestion.known
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
            ledgerSnapshot: ImportLedgerSnapshot(expenses: existingExpenses, incomes: existingIncomes,
                devices: existingDevices, passiveSources: existingPassives, assets: allAssets,
                assetItems: existingAssetItems, loans: existingLoans, cashAccounts: existingCashAccounts),
            schemaVersion: validated.schemaVersion,
            expensesNew: expensesNew,
            suspectedExpenseIndices: suspectedExpenseIndices,
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
            importedAssetItems: importedAssetItems,
            currentAssetItemCount: existingAssetItems.count,
            importedCashAccounts: validated.cashAccounts.enumerated()
                .sorted { ($0.element.sortOrder ?? $0.offset, $0.offset) < ($1.element.sortOrder ?? $1.offset, $1.offset) }
                .map(\.element),
            loansNew: loansNew,
            categoryOptions: validated.expenseCategories.map { records in
                ExpenseCategoryOptions(items: records.map {
                    ExpenseCategoryOptions.Item(name: $0.name, isDeleted: $0.isDeleted, icon: $0.icon)
                })
            },
            importedAssets: importedAssets,
            jsonFirstRecordDate: validated.firstRecordDate,
            currentCash: existingAssets?.cash ?? 0,
            currentLockedAssets: existingAssets?.lockedAssets ?? 0,
            categoryEntries: categoryEntries,
            categoryNames: knownCategories
        )
    }

    static func makeImportPlan(
        preview: ImportPreview,
        strategy: AssetsImportStrategy,
        categoryMap: [String: String] = [:],
        skippingSuspectedExpenses: Set<Int> = []
    ) throws -> ImportPlan {
        let rawCategories = Set(preview.categoryEntries.map(\.raw))
        for (raw, target) in categoryMap {
            guard preview.categoryNames.contains(target) || (raw == target && rawCategories.contains(raw)) else {
                throw DataIOError.invalidCategoryMapping(target)
            }
        }

        let suggestedCategories = Dictionary(uniqueKeysWithValues: preview.categoryEntries.map { ($0.raw, $0.canonical) })
        let skipped = skippingSuspectedExpenses.intersection(preview.suspectedExpenseIndices)
        let expenses = preview.expensesNew.enumerated().compactMap { index, record -> ImportPlan.ExpenseRecord? in
            guard !skipped.contains(index) else { return nil }
            if record.loanID != nil {
                return ImportPlan.ExpenseRecord(id: record.id, amount: record.amount, category: record.category,
                                                note: record.note, date: record.date, createdAt: record.createdAt,
                                                loanID: record.loanID, countsInBurn: record.countsInBurn,
                                                cashAccountID: record.cashAccountID)
            }
            let rawCategory = record.category.trimmingCharacters(in: .whitespacesAndNewlines)
            let mappedCategory = categoryMap[rawCategory] ?? suggestedCategories[rawCategory]
                ?? ExpenseCategory.suggest(rawCategory).canonical
            let note = mappedExpenseNote(rawCategory: rawCategory, mappedCategory: mappedCategory, note: record.note)
            return ImportPlan.ExpenseRecord(
                id: record.id,
                amount: record.amount,
                category: mappedCategory,
                note: note,
                date: record.date,
                createdAt: record.createdAt,
                countsInBurn: record.countsInBurn,
                cashAccountID: record.cashAccountID
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
            ledgerSnapshot: preview.ledgerSnapshot,
            expenses: expenses,
            incomes: preview.incomesNew,
            devices: preview.devicesNew,
            passiveSources: preview.passiveSourcesNew,
            assetsAction: assetsAction,
            assetItems: preview.importedAssetItems,
            importedAssetsTotal: preview.importedAssets.total,
            loans: preview.loansNew,
            cashAccounts: preview.importedCashAccounts
        )
    }

    static func commitImport(
        preview: ImportPreview,
        strategy: AssetsImportStrategy,
        categoryMap: [String: String] = [:],
        skippingSuspectedExpenses: Set<Int> = [],
        context: ModelContext
    ) throws -> ImportResult {
        let plan = try makeImportPlan(
            preview: preview,
            strategy: strategy,
            categoryMap: categoryMap,
            skippingSuspectedExpenses: skippingSuspectedExpenses
        )
        return try commitImport(plan: plan, context: context)
    }

    static func commitImport(
        plan: ImportPlan,
        context: ModelContext,
        save: SaveAction = { try $0.save() }
    ) throws -> ImportResult {
        // 核对和写入在同一个 MainActor 调用中完成，中途不让出执行权。
        guard !context.hasChanges else { throw LedgerStore.StoreError.pendingChanges }
        guard try ImportLedgerSnapshot.capture(in: context) == plan.ledgerSnapshot else {
            throw DataIOError.stalePreview
        }
        var firstRecordDate: Date?
        try LedgerStore.updateAssets(in: context, save: save) { userAssets in
            for record in plan.expenses {
                let expense = Expense(
                    amount: record.amount,
                    category: record.category,
                    note: record.note,
                    date: record.date
                )
                if let id = record.id { expense.id = id }
                if let createdAt = record.createdAt { expense.createdAt = createdAt }
                expense.loanID = record.loanID
                expense.countsInBurn = record.countsInBurn
                expense.cashAccountID = record.cashAccountID
                context.insert(expense)
            }

            let existingLoans = try context.fetch(FetchDescriptor<Loan>())
            var nextLoanOrder = (existingLoans.map(\.sortOrder).max() ?? -1) + 1
            for record in plan.loans.enumerated().sorted(by: {
                ($0.element.sortOrder ?? $0.offset, $0.offset) < ($1.element.sortOrder ?? $1.offset, $1.offset)
            }).map(\.element) {
                let loan = Loan(name: record.name, monthlyAmount: record.monthlyAmount, dueDay: record.dueDay,
                                periodsAtStart: record.periodsAtStart, startDate: record.startDate,
                                sortOrder: nextLoanOrder)
                nextLoanOrder += 1
                if let id = record.id { loan.id = id }
                loan.processedThrough = record.processedThrough
                loan.settledDates = record.settledDates
                loan.cashAccountID = record.cashAccountID
                if let createdAt = record.createdAt { loan.createdAt = createdAt }
                context.insert(loan)
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
                income.cashAccountID = record.cashAccountID
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

            switch plan.assetsAction {
            case .replace(let snapshot):
                userAssets.lockedAssets = snapshot.lockedAssets
                userAssets.cash = snapshot.cash
                userAssets.updatedAt = snapshot.updatedAt ?? .now
                // 资产桶换成备份里的数，资产项也跟着整体换：同一份备份导两次不会多出重复项。
                // 没有项的旧备份导入后就只按总数走。
                for existing in try context.fetch(FetchDescriptor<AssetItem>()) { context.delete(existing) }
                for (index, record) in plan.assetItems.enumerated() {
                    let item = AssetItem(name: record.name, amount: record.amount, sortOrder: index,
                                         countsInFreedom: record.countsInFreedom ?? true)
                    if let id = record.id { item.id = id }
                    if let createdAt = record.createdAt { item.createdAt = createdAt }
                    item.updatedAt = record.updatedAt ?? record.createdAt ?? .now
                    context.insert(item)
                }
                // 现金账户同理：整体换成备份里的
                for existing in try context.fetch(FetchDescriptor<CashAccount>()) { context.delete(existing) }
                for (index, record) in plan.cashAccounts.enumerated() {
                    let account = CashAccount(name: record.name, amount: record.amount, sortOrder: index)
                    if let id = record.id { account.id = id }
                    if let createdAt = record.createdAt { account.createdAt = createdAt }
                    account.updatedAt = record.updatedAt ?? record.createdAt ?? .now
                    context.insert(account)
                }
            case .addToCash(let amount):
                // 本机拆了现金账户时，加进扣款顺序第一个账户，总数仍是各账户之和
                try CashAccountStore.applyCashChange(amount, accountID: nil, assets: userAssets, in: context)
                userAssets.updatedAt = .now
            case .skip:
                break
            }

            let allExpenses = try context.fetch(FetchDescriptor<Expense>())
            firstRecordDate = allExpenses.map(\.date).min()
            userAssets.firstRecordDate = firstRecordDate
        }

        return ImportResult(
            expensesAdded: plan.expenses.count,
            incomesAdded: plan.incomes.count,
            devicesAdded: plan.devices.count,
            passiveSourcesAdded: plan.passiveSources.count,
            loansAdded: plan.loans.count,
            assetsTotal: plan.importedAssetsTotal,
            firstRecordDate: firstRecordDate
        )
    }

    static func purgeAll(context: ModelContext, save: SaveAction = { try $0.save() }) throws {
        try LedgerStore.perform(in: context, save: save) {
            for record in try context.fetch(FetchDescriptor<Expense>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<Income>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<Device>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<PassiveSource>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<UserAssets>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<AssetItem>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<Loan>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<CashAccount>()) { context.delete(record) }
        }
    }

    private static func mappedExpenseNote(rawCategory: String, mappedCategory: String, note: String) -> String {
        guard rawCategory != mappedCategory else { return note }
        return String(annotatedExpenseNote(rawCategory: rawCategory, note: note).prefix(FinancialLimits.noteCharacters))
    }

    private static func annotatedExpenseNote(rawCategory: String, note: String) -> String {
        note.isEmpty ? "原分类·\(rawCategory)" : "\(note) · 原分类·\(rawCategory)"
    }

    // 文本可以包含任意分隔符，字段边界必须由类型保留。
    private struct TransactionKey: Hashable {
        let day: Date
        let amount: Double
        let label: String
        let note: String
    }

    private struct DeviceKey: Hashable {
        let day: Date
        let price: Double
        let name: String
    }

    private struct PassiveKey: Hashable {
        let name: String
        let monthlyAmount: Double
    }

    private static func expenseKey(amount: Double, date: Date, category: String, note: String) -> TransactionKey {
        TransactionKey(day: Calendar.current.startOfDay(for: date), amount: amount, label: category, note: note)
    }

    private static func incomeKey(amount: Double, date: Date, source: String, note: String) -> TransactionKey {
        TransactionKey(day: Calendar.current.startOfDay(for: date), amount: amount, label: source, note: note)
    }

    private static func deviceKey(name: String, price: Double, purchaseDate: Date) -> DeviceKey {
        DeviceKey(day: Calendar.current.startOfDay(for: purchaseDate), price: price, name: name)
    }

    private static func passiveKey(name: String, monthlyAmount: Double) -> PassiveKey {
        PassiveKey(name: name, monthlyAmount: monthlyAmount)
    }
}
