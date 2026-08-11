//
//  ImportValidation.swift
//  FreeGrid
//
//  所有外部备份先解码、校验、转成强类型值，再进入预览和 SwiftData。
//

import Foundation

enum FinancialLimits {
    static let fileBytes = 10 * 1024 * 1024
    static let ledgerRecords = 50_000
    static let deviceRecords = 10_000
    static let passiveSourceRecords = 1_000
    static let nameCharacters = 120
    static let noteCharacters = 2_000
    static let maximumAmount = 1_000_000_000_000.0
    static let assetChecksumTolerance = 0.01
}

struct ImportPolicy: Sendable {
    static let `default` = ImportPolicy()

    /// 导出自校验专用。本地数据是可信的,这里只该验证"编码是否正确"——能解码、
    /// UUID/日期格式合法、金额有界——而不该套用防御外部文件的输入限额。
    /// 套用输入限额的后果就是 1.2.1 那次事故:本地数据一旦越过任何一条为
    /// 外来文件设的红线,用户就再也导不出自己的账本,而导出是唯一的逃生舱。
    static let exportSelfCheck = ImportPolicy(
        maxFileBytes: .max,
        maxLedgerRecords: .max,
        maxDeviceRecords: .max,
        maxPassiveSourceRecords: .max
    )

    let maxFileBytes: Int
    let maxLedgerRecords: Int
    let maxDeviceRecords: Int
    let maxPassiveSourceRecords: Int
    let maxNameCharacters: Int
    let maxNoteCharacters: Int
    let maximumAmount: Double

    init(
        maxFileBytes: Int = FinancialLimits.fileBytes,
        maxLedgerRecords: Int = FinancialLimits.ledgerRecords,
        maxDeviceRecords: Int = FinancialLimits.deviceRecords,
        maxPassiveSourceRecords: Int = FinancialLimits.passiveSourceRecords,
        maxNameCharacters: Int = FinancialLimits.nameCharacters,
        maxNoteCharacters: Int = FinancialLimits.noteCharacters,
        maximumAmount: Double = FinancialLimits.maximumAmount
    ) {
        self.maxFileBytes = maxFileBytes
        self.maxLedgerRecords = maxLedgerRecords
        self.maxDeviceRecords = maxDeviceRecords
        self.maxPassiveSourceRecords = maxPassiveSourceRecords
        self.maxNameCharacters = maxNameCharacters
        self.maxNoteCharacters = maxNoteCharacters
        self.maximumAmount = maximumAmount
    }
}

enum ImportValidationError: Error, Equatable, LocalizedError {
    case fileTooLarge(actual: Int, maximum: Int)
    case malformedJSON
    case unsupportedSchema(Int)
    case tooManyRecords(kind: String, count: Int, maximum: Int)
    case invalidUUID(field: String)
    case invalidDate(field: String)
    case futureDate(field: String)
    case emptyText(field: String)
    case textTooLong(field: String, maximum: Int)
    case amountOutOfRange(field: String)
    case incompleteAssetBuckets
    case assetChecksumMismatch
    case invalidDeviceStatus
    case inconsistentDeviceState

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let actual, let maximum):
            return "备份文件过大（\(actual) 字节，上限 \(maximum) 字节）"
        case .malformedJSON:
            return "备份文件不是可识别的 FreeGrid JSON"
        case .unsupportedSchema(let version):
            return "不支持备份格式版本 \(version)，请更新 FreeGrid 后重试"
        case .tooManyRecords(let kind, let count, let maximum):
            return "\(kind)记录过多（\(count) 条，上限 \(maximum) 条）"
        case .invalidUUID(let field):
            return "\(field) 的记录 ID 无效"
        case .invalidDate(let field):
            return "\(field) 的日期格式无效"
        case .futureDate(let field):
            return "\(field) 不能晚于今天"
        case .emptyText(let field):
            return "\(field)不能为空"
        case .textTooLong(let field, let maximum):
            return "\(field)过长（上限 \(maximum) 个字符）"
        case .amountOutOfRange(let field):
            return "\(field)金额无效或超出允许范围"
        case .incompleteAssetBuckets:
            return "资产备份必须同时包含资产桶和现金桶"
        case .assetChecksumMismatch:
            return "备份净值与资产桶、现金桶之和不一致"
        case .invalidDeviceStatus:
            return "设备状态只能是 active、retired 或 sold"
        case .inconsistentDeviceState:
            return "设备卖出状态与卖出金额、日期不一致"
        }
    }
}

struct ValidatedImport: Sendable {
    struct Assets: Sendable {
        let total: Double
        let lockedAssets: Double?
        let cash: Double?
        let updatedAt: Date?
    }

    struct ExpenseRecord: Sendable {
        let id: UUID?
        let amount: Double
        let category: String
        let date: Date
        let note: String
        let createdAt: Date?
    }

    struct IncomeRecord: Sendable {
        let id: UUID?
        let amount: Double
        let source: String
        let date: Date
        let note: String
        let isPassive: Bool
        let createdAt: Date?
    }

    struct DeviceRecord: Sendable {
        let id: UUID?
        let name: String
        let category: String
        let price: Double
        let purchaseDate: Date
        let status: String
        let soldPrice: Double?
        let soldDate: Date?
        let note: String
        let createdAt: Date?
    }

    struct PassiveSourceRecord: Sendable {
        let id: UUID?
        let name: String
        let monthlyAmount: Double
        let createdAt: Date?
    }

    let schemaVersion: Int
    let assets: Assets?
    let expenses: [ExpenseRecord]
    let incomes: [IncomeRecord]
    let devices: [DeviceRecord]
    let passiveSources: [PassiveSourceRecord]
    let firstRecordDate: Date?
}

enum ImportValidator {
    /// v2 保持新账严格正金额；v3 只在需要无损承接旧版退款/冲正记录时使用。
    static let strictPositiveExpenseSchemaVersion = 2
    static let signedExpenseSchemaVersion = 3
    static let latestSchemaVersion = signedExpenseSchemaVersion

    static func loadData(from url: URL, policy: ImportPolicy = .default) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > policy.maxFileBytes {
            throw ImportValidationError.fileTooLarge(actual: size, maximum: policy.maxFileBytes)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try validateSize(data.count, policy: policy)
        return data
    }

    static func validate(
        data: Data,
        policy: ImportPolicy = .default,
        now: Date = .now
    ) throws -> ValidatedImport {
        try validateSize(data.count, policy: policy)

        let envelope: BackupEnvelope
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            envelope = try decoder.decode(BackupEnvelope.self, from: data)
        } catch {
            throw ImportValidationError.malformedJSON
        }

        let schemaVersion = envelope.schemaVersion ?? 0
        guard (0...latestSchemaVersion).contains(schemaVersion) else {
            throw ImportValidationError.unsupportedSchema(schemaVersion)
        }

        let expenseCount = envelope.expenses?.count ?? 0
        let incomeCount = envelope.incomes?.count ?? 0
        let ledgerCount = expenseCount + incomeCount
        guard ledgerCount <= policy.maxLedgerRecords else {
            throw ImportValidationError.tooManyRecords(
                kind: "收支",
                count: ledgerCount,
                maximum: policy.maxLedgerRecords
            )
        }

        let deviceCount = envelope.devices?.count ?? 0
        guard deviceCount <= policy.maxDeviceRecords else {
            throw ImportValidationError.tooManyRecords(
                kind: "设备",
                count: deviceCount,
                maximum: policy.maxDeviceRecords
            )
        }

        let passiveCount = envelope.passiveSources?.count ?? 0
        guard passiveCount <= policy.maxPassiveSourceRecords else {
            throw ImportValidationError.tooManyRecords(
                kind: "被动收入源",
                count: passiveCount,
                maximum: policy.maxPassiveSourceRecords
            )
        }

        let assets = try envelope.assets.map { raw in
            let hasLocked = raw.lockedAssets != nil
            let hasCash = raw.cash != nil
            guard hasLocked == hasCash else {
                throw ImportValidationError.incompleteAssetBuckets
            }

            // 历史版本会在记支出时把现金扣成负数；余额可以为负，交易金额仍必须为正。
            let total = try signedAmount(
                raw.total,
                field: "净值",
                maximum: hasLocked ? policy.maximumAmount * 2 : policy.maximumAmount
            )
            let locked = try raw.lockedAssets.map {
                try amount($0, field: "资产桶", allowsZero: true, policy: policy)
            }
            let cash = try raw.cash.map {
                try signedAmount($0, field: "现金桶", maximum: policy.maximumAmount)
            }
            if let locked, let cash,
               abs(total - (locked + cash)) > FinancialLimits.assetChecksumTolerance {
                throw ImportValidationError.assetChecksumMismatch
            }

            let updatedAt = try raw.updatedAt.map {
                try timestamp($0, field: "资产更新时间", now: now)
            }
            return ValidatedImport.Assets(
                total: total,
                lockedAssets: locked,
                cash: cash,
                updatedAt: updatedAt
            )
        }

        var expenses: [ValidatedImport.ExpenseRecord] = []
        for raw in envelope.expenses ?? [] {
            // 旧版导入器会把“当天无消费”保存成 0 元支出。这类记录一律保留：
            // 它没有财务影响，但可能是账本里最早的一条，丢掉会把追踪基线往后挪，
            // 于是记录天数变少、日均消费变高、自由天数变少——用户看不出数字为何变了。
            // v2 例外，那是 1.2.1 之后才产生的备份，本来就不可能含 0 元支出。
            let validatedAmount: Double
            if schemaVersion == strictPositiveExpenseSchemaVersion {
                validatedAmount = try amount(
                    raw.amount,
                    field: "支出",
                    allowsZero: false,
                    policy: policy
                )
            } else {
                validatedAmount = try signedAmount(
                    raw.amount,
                    field: "支出",
                    maximum: policy.maximumAmount
                )
            }
            expenses.append(
                ValidatedImport.ExpenseRecord(
                    id: try identifier(raw.id, field: "支出"),
                    amount: validatedAmount,
                    category: try text(raw.category, field: "支出分类", maximum: policy.maxNameCharacters),
                    date: try day(raw.date, field: "支出日期", now: now),
                    note: try optionalText(raw.note, field: "支出备注", maximum: policy.maxNoteCharacters),
                    createdAt: try raw.createdAt.map { try timestamp($0, field: "支出创建时间", now: now) }
                )
            )
        }

        let incomes = try (envelope.incomes ?? []).map { raw in
            ValidatedImport.IncomeRecord(
                id: try identifier(raw.id, field: "收入"),
                amount: try amount(raw.amount, field: "收入", allowsZero: false, policy: policy),
                source: try text(raw.source, field: "收入来源", maximum: policy.maxNameCharacters),
                date: try day(raw.date, field: "收入日期", now: now),
                note: try optionalText(raw.note, field: "收入备注", maximum: policy.maxNoteCharacters),
                isPassive: raw.isPassive ?? false,
                createdAt: try raw.createdAt.map { try timestamp($0, field: "收入创建时间", now: now) }
            )
        }

        let devices = try (envelope.devices ?? []).map { raw in
            let status = raw.status ?? "active"
            guard ["active", "retired", "sold"].contains(status) else {
                throw ImportValidationError.invalidDeviceStatus
            }
            let purchaseDate = try day(raw.purchaseDate, field: "设备购买日期", now: now)
            let soldPrice = try raw.soldPrice.map {
                try amount($0, field: "设备卖出价", allowsZero: true, policy: policy)
            }
            let soldDate = try raw.soldDate.map {
                try day($0, field: "设备卖出日期", now: now)
            }
            if status == "sold" {
                guard soldPrice != nil, let soldDate, soldDate >= purchaseDate else {
                    throw ImportValidationError.inconsistentDeviceState
                }
            } else if soldPrice != nil || soldDate != nil {
                throw ImportValidationError.inconsistentDeviceState
            }

            return ValidatedImport.DeviceRecord(
                id: try identifier(raw.id, field: "设备"),
                name: try text(raw.name, field: "设备名称", maximum: policy.maxNameCharacters),
                category: try text(raw.category, field: "设备分类", maximum: policy.maxNameCharacters),
                price: try amount(raw.price, field: "设备价格", allowsZero: true, policy: policy),
                purchaseDate: purchaseDate,
                status: status,
                soldPrice: soldPrice,
                soldDate: soldDate,
                note: try optionalText(raw.note, field: "设备备注", maximum: policy.maxNoteCharacters),
                createdAt: try raw.createdAt.map { try timestamp($0, field: "设备创建时间", now: now) }
            )
        }

        let passiveSources = try (envelope.passiveSources ?? []).map { raw in
            ValidatedImport.PassiveSourceRecord(
                id: try identifier(raw.id, field: "被动收入源"),
                name: try text(raw.name, field: "被动收入源名称", maximum: policy.maxNameCharacters),
                monthlyAmount: try amount(
                    raw.monthlyAmount,
                    field: "被动收入",
                    allowsZero: false,
                    policy: policy
                ),
                createdAt: try raw.createdAt.map { try timestamp($0, field: "被动收入源创建时间", now: now) }
            )
        }

        let firstRecordDate = try envelope.firstRecordDate.map {
            try day($0, field: "首次记录日期", now: now)
        }

        return ValidatedImport(
            schemaVersion: schemaVersion,
            assets: assets,
            expenses: expenses,
            incomes: incomes,
            devices: devices,
            passiveSources: passiveSources,
            firstRecordDate: firstRecordDate
        )
    }

    private static func validateSize(_ count: Int, policy: ImportPolicy) throws {
        guard count <= policy.maxFileBytes else {
            throw ImportValidationError.fileTooLarge(actual: count, maximum: policy.maxFileBytes)
        }
    }

    private static func identifier(_ value: String?, field: String) throws -> UUID? {
        guard let value else { return nil }
        guard let id = UUID(uuidString: value) else {
            throw ImportValidationError.invalidUUID(field: field)
        }
        return id
    }

    private static func amount(
        _ value: Double,
        field: String,
        allowsZero: Bool,
        policy: ImportPolicy
    ) throws -> Double {
        let lowerBound = allowsZero ? 0.0 : Double.leastNonzeroMagnitude
        guard value.isFinite, value >= lowerBound, value <= policy.maximumAmount else {
            throw ImportValidationError.amountOutOfRange(field: field)
        }
        return value
    }

    private static func signedAmount(_ value: Double, field: String, maximum: Double) throws -> Double {
        guard value.isFinite, abs(value) <= maximum else {
            throw ImportValidationError.amountOutOfRange(field: field)
        }
        return value
    }

    private static func text(_ value: String, field: String, maximum: Int) throws -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportValidationError.emptyText(field: field)
        }
        guard value.count <= maximum else {
            throw ImportValidationError.textTooLong(field: field, maximum: maximum)
        }
        return value
    }

    private static func optionalText(_ value: String?, field: String, maximum: Int) throws -> String {
        let value = value ?? ""
        guard value.count <= maximum else {
            throw ImportValidationError.textTooLong(field: field, maximum: maximum)
        }
        return value
    }

    private static func day(_ value: String, field: String, now: Date) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard value.count == 10,
              let date = formatter.date(from: value),
              formatter.string(from: date) == value else {
            throw ImportValidationError.invalidDate(field: field)
        }
        let calendar = Calendar.current
        guard calendar.startOfDay(for: date) <= calendar.startOfDay(for: now) else {
            throw ImportValidationError.futureDate(field: field)
        }
        return date
    }

    private static func timestamp(_ value: String, field: String, now: Date) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: value) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }()
        guard let parsed else {
            throw ImportValidationError.invalidDate(field: field)
        }
        guard parsed <= now else {
            throw ImportValidationError.futureDate(field: field)
        }
        return parsed
    }
}
