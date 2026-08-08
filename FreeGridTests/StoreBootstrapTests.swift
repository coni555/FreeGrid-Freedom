//
//  StoreBootstrapTests.swift
//  FreeGridTests
//
//  容器失败必须进入恢复态；重试成功后切回 ready，诊断不得泄露错误正文。
//

import Foundation
import SwiftData
import Testing
@testable import FreeGrid

struct StoreBootstrapTests {
    private enum TestFailure: Error {
        case failed(String)
    }

    @MainActor
    @Test func factoryFailureEntersRecoveryAndRetryCanBecomeReady() throws {
        var shouldFail = true
        let bootstrap = StoreBootstrap {
            if shouldFail {
                throw TestFailure.failed("/Users/private/backup.json · balance 123456")
            }
            return try StoreBootstrap.makeContainer(isStoredInMemoryOnly: true)
        }

        guard case .failed(let failure) = bootstrap.state else {
            Issue.record("首次 factory 失败后应进入 failed 状态")
            return
        }
        #expect(failure.code == "STORE_OPEN_FAILED")
        #expect(!failure.diagnosticText.contains("/Users/private"))
        #expect(!failure.diagnosticText.contains("123456"))
        #expect(!bootstrap.isReady)

        shouldFail = false
        bootstrap.retry()

        guard case .ready(let container) = bootstrap.state else {
            Issue.record("重试成功后应进入 ready 状态")
            return
        }
        #expect(bootstrap.isReady)

        let context = ModelContext(container)
        context.insert(Expense(amount: 1, category: "早餐"))
        context.insert(Income(amount: 2, source: "工资"))
        context.insert(Device(name: "电脑", category: "数码", price: 3, purchaseDate: .now))
        context.insert(PassiveSource(name: "利息", monthlyAmount: 4))
        context.insert(UserAssets(total: 0))
        try context.save()
    }

    @MainActor
    @Test func forcedFailureUsesStableSafeCode() {
        let failure = StoreBootstrap.Failure.make(
            from: StoreBootstrap.BootstrapError.forcedFailure
        )

        #expect(failure.code == "STORE_TEST_FAILURE")
        #expect(failure.diagnosticText.contains("Financial data, notes, file paths"))
    }
}
