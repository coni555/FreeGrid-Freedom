//
//  MigrationTests.swift
//  FreeGridTests
//
//  最早支出是唯一业务基线；legacy total 只能迁移一次，不能在现金归零后复活。
//

import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct MigrationTests {
    @Test func onlyExpensesStartAndMoveTheTrackingBaseline() {
        let now = TestSupport.day("2026-08-07")
        let earlier = Expense(
            amount: 10,
            category: "早餐",
            date: TestSupport.day("2026-08-05")
        )
        let later = Expense(
            amount: 20,
            category: "午餐",
            date: TestSupport.day("2026-08-06")
        )

        #expect(FreedomMath.earliestExpenseDate([]) == nil)
        #expect(FreedomMath.trackDays(firstRecordDate: nil, now: now) == 0)
        #expect(FreedomMath.earliestExpenseDate([later, earlier]) == earlier.date)
        #expect(FreedomMath.trackDays(firstRecordDate: earlier.date, now: now) == 3)

        // 删除最早一笔后切到下一笔；删完后回到 0 天。
        #expect(FreedomMath.earliestExpenseDate([later]) == later.date)
        #expect(FreedomMath.trackDays(firstRecordDate: later.date, now: now) == 2)
        #expect(FreedomMath.trackDays(firstRecordDate: nil, now: now) == 0)

        let future = TestSupport.day("2026-08-08")
        #expect(FreedomMath.trackDays(firstRecordDate: future, now: now) == 0)
    }

    @Test func legacyTotalMigratesOnceAndCannotReviveCash() throws {
        let context = try TestSupport.makeContext()
        let expenseDate = TestSupport.day("2026-01-02")
        context.insert(Expense(amount: 10, category: "午餐", date: expenseDate))
        let assets = UserAssets(
            total: 500,
            firstRecordDate: TestSupport.day("2020-01-01")
        )
        context.insert(assets)
        try context.save()

        var saves = 0
        try StoreBootstrap.migrateLegacyData(context: context) { ctx in
            saves += 1
            try ctx.save()
        }

        #expect(assets.cash == 500)
        #expect(assets.lockedAssets == 0)
        #expect(assets.total == 0)
        #expect(assets.firstRecordDate == expenseDate)
        #expect(saves == 1)

        assets.cash = 0
        try StoreBootstrap.migrateLegacyData(context: context) { _ in
            saves += 1
        }

        #expect(assets.cash == 0)
        #expect(assets.total == 0)
        #expect(saves == 1)
    }

    @Test func staleLegacyTotalNeverOverwritesExistingBuckets() throws {
        let context = try TestSupport.makeContext()
        let assets = UserAssets(total: 500)
        assets.lockedAssets = 200
        assets.cash = 50
        context.insert(assets)
        try context.save()

        try StoreBootstrap.migrateLegacyData(context: context)

        #expect(assets.lockedAssets == 200)
        #expect(assets.cash == 50)
        #expect(assets.total == 0)
        #expect(assets.firstRecordDate == nil)
    }

    @Test func invalidLegacyTotalIsClearedWithoutEnteringBuckets() throws {
        let context = try TestSupport.makeContext()
        let assets = UserAssets(total: .infinity)
        context.insert(assets)
        try context.save()

        try StoreBootstrap.migrateLegacyData(context: context)

        #expect(assets.lockedAssets == 0)
        #expect(assets.cash == 0)
        #expect(assets.total == 0)
    }
}
