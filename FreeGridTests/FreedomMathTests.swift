//
//  FreedomMathTests.swift
//  FreeGridTests
//
//  无数据、覆盖、异常持久化值和 Double → Int 边界不得混为同一种业务状态。
//

import Foundation
import Testing
@testable import FreeGrid

struct FreedomMathTests {
    @Test func distinguishesInsufficientCoveredFiniteAndInvalidStates() {
        #expect(FreedomMath.freedomState(
            netWorth: 10_000,
            dailyBurn: 0,
            hasExpenses: false
        ) == .insufficientData)

        #expect(FreedomMath.freedomState(
            netWorth: 0,
            dailyBurn: 0,
            dailyPassive: 100,
            hasExpenses: false
        ) == .insufficientData)

        #expect(FreedomMath.freedomState(
            netWorth: 1_000,
            dailyBurn: 100,
            dailyPassive: 10,
            hasExpenses: true
        ) == .finite(days: 1_000 / 90))

        #expect(FreedomMath.freedomState(
            netWorth: 1_000,
            dailyBurn: 100,
            dailyPassive: 100,
            hasExpenses: true
        ) == .covered)

        #expect(FreedomMath.freedomState(
            netWorth: .infinity,
            dailyBurn: 100,
            hasExpenses: true
        ) == .invalidData)

        #expect(FreedomMath.freedomState(
            netWorth: 1_000,
            dailyBurn: .nan,
            hasExpenses: true
        ) == .invalidData)
    }

    @Test func amountAndIntegerBoundariesRejectUnrepresentableValues() {
        #expect(FinancialFormatting.validAmount(FinancialLimits.maximumAmount))
        #expect(!FinancialFormatting.validAmount(FinancialLimits.maximumAmount.nextUp))
        #expect(!FinancialFormatting.validAmount(.infinity))
        #expect(!FinancialFormatting.validAmount(.nan))
        #expect(!FinancialFormatting.validAmount(0))
        #expect(FinancialFormatting.validAmount(0, allowsZero: true))

        #expect(FinancialFormatting.integer(Double(Int.max)) == nil)
        #expect(FinancialFormatting.integer(.greatestFiniteMagnitude) == nil)
        #expect(FinancialFormatting.integer(Double(Int.min)) == Int.min)
        #expect(FinancialFormatting.clampedInteger(
            .greatestFiniteMagnitude,
            range: 0...99
        ) == 99)
        #expect(FinancialFormatting.percentage(.greatestFiniteMagnitude) == "9999%")
    }

    @Test func gridCountsAndAssetRatiosAreClampedBeforeIntegerConversion() {
        let allBlue = FreedomMath.gridState(
            lockedAssets: 200,
            cash: -100,
            dailyBurn: 1
        )
        #expect(allBlue.count == 100)
        #expect(allBlue.blueDays == 100)
        #expect(allBlue.yellowDays == 0)

        let allCash = FreedomMath.gridState(
            lockedAssets: -100,
            cash: 200,
            dailyBurn: 1
        )
        #expect(allCash.count == 100)
        #expect(allCash.blueDays == 0)
        #expect(allCash.yellowDays == 100)

        let covered = FreedomMath.gridState(
            lockedAssets: 100,
            cash: 0,
            dailyBurn: 10,
            dailyPassive: 10
        )
        #expect(covered.unit == .year)
        #expect(covered.count == 99)
        #expect(covered.blueDays == 99)

        let invalid = FreedomMath.gridState(
            lockedAssets: .infinity,
            cash: 0,
            dailyBurn: 10
        )
        #expect(invalid.count == 0)
    }

    @Test func historyAndDeltaDropNonFiniteFinancialValues() {
        let firstDate = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        let invalidExpense = Expense(
            amount: .infinity,
            category: "午餐",
            date: firstDate
        )

        let history = FreedomMath.freedomDaysHistory(
            expenses: [invalidExpense],
            incomes: [],
            currentNetWorth: 1_000,
            firstRecordDate: firstDate
        )
        #expect(history.isEmpty)

        let invalidDelta = FreedomMath.deltaSummary(history: [
            .init(date: firstDate, freedomDays: 10),
            .init(date: .now, freedomDays: .infinity),
        ])
        #expect(invalidDelta == nil)
        #expect(FreedomMath.depleteDate(freedomDays: .infinity) == nil)
    }

    @Test func maximumSupportedAmountsRemainFinite() {
        let burn = FreedomMath.dailyBurn(
            totalExpenses: FinancialLimits.maximumAmount,
            trackDays: 1
        )
        #expect(burn == FinancialLimits.maximumAmount)
        #expect(FreedomMath.freedomState(
            netWorth: FinancialLimits.maximumAmount,
            dailyBurn: burn,
            hasExpenses: true
        ) == .finite(days: 1))
    }
}
