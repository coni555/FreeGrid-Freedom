//
//  StoreBootstrap.swift
//  FreeGrid
//
//  SwiftData schema、容器创建与一次性兼容迁移的单一入口。
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class StoreBootstrap {
    enum BootstrapError: Error, Equatable {
        case forcedFailure
    }

    struct Failure: Equatable {
        let code: String
        let diagnosticText: String

        static func make(from error: Error) -> Failure {
            let code = (error as? BootstrapError) == .forcedFailure
                ? "STORE_TEST_FAILURE"
                : "STORE_OPEN_FAILED"
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            let errorType = String(reflecting: type(of: error))
            let diagnostic = """
            FreeGrid Store Diagnostic
            Code: \(code)
            App: \(version) (\(build))
            OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
            Error type: \(errorType)
            Financial data, notes, file paths, and backup contents are not included.
            """
            return Failure(code: code, diagnosticText: diagnostic)
        }
    }

    enum State {
        case loading
        case ready(ModelContainer)
        case failed(Failure)
    }

    typealias ContainerFactory = @MainActor () throws -> ModelContainer
    typealias SaveAction = (ModelContext) throws -> Void

    private let factory: ContainerFactory
    private(set) var state: State = .loading

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    init(factory: @escaping ContainerFactory = StoreBootstrap.makeProductionContainer) {
        self.factory = factory
        retry()
    }

    func retry() {
        state = .loading
        do {
            let container = try factory()
            try Self.migrateLegacyData(context: ModelContext(container))
            state = .ready(container)
        } catch {
            state = .failed(Failure.make(from: error))
        }
    }

    nonisolated static var schema: Schema {
        Schema([
            Expense.self,
            Income.self,
            Device.self,
            PassiveSource.self,
            UserAssets.self,
        ])
    }

    nonisolated static func makeContainer(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = schema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeProductionContainer() throws -> ModelContainer {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ForceStoreBootstrapFailure") {
            throw BootstrapError.forcedFailure
        }
        return try makeContainer(
            isStoredInMemoryOnly: arguments.contains("-UseInMemoryStore")
        )
        #else
        return try makeContainer()
        #endif
    }

    /// legacy `total` 只允许迁移一次：复制到空现金桶后立即清零，作为完成标记。
    /// 同时把兼容字段 firstRecordDate 校准为最早支出；业务计算不再依赖该字段。
    static func migrateLegacyData(
        context: ModelContext,
        save: SaveAction = { try $0.save() }
    ) throws {
        do {
            try context.transaction {
                guard let assets = try context.fetch(FetchDescriptor<UserAssets>()).first else {
                    return
                }

                var changed = false
                if assets.total != 0 {
                    if FinancialFormatting.validAmount(assets.total),
                       assets.lockedAssets == 0,
                       assets.cash == 0 {
                        assets.cash = assets.total
                        assets.updatedAt = .now
                    }
                    assets.total = 0
                    changed = true
                }

                let expenses = try context.fetch(FetchDescriptor<Expense>())
                let firstExpenseDate = FreedomMath.earliestExpenseDate(expenses)
                if assets.firstRecordDate != firstExpenseDate {
                    assets.firstRecordDate = firstExpenseDate
                    changed = true
                }

                if changed {
                    try save(context)
                }
            }
        } catch {
            context.rollback()
            throw error
        }
    }
}
