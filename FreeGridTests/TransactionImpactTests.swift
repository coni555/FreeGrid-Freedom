// 预览必须等于实际保存后的计算，不因单位切换、补录或退款误导用户。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct TransactionImpactTests {
    private let today = TestSupport.day("2026-06-10")

    @Test func incomePreviewKeepsUnitsAcrossDayMonthAndYearBoundaries() {
        for (cash, amount, oldUnit, newUnit) in [(36_000.0, 1_000.0, "天", "月"), (364_900.0, 200.0, "月", "年")] {
            let assets = UserAssets(total: 0)
            assets.cash = cash
            let snapshot = FinancialSnapshot(expenses: [Expense(amount: 100, category: "午餐", date: today)],
                                             passiveSources: [], assets: assets, now: today)
            let impact = TransactionImpact(snapshot: snapshot, kind: .income, amount: amount)
            #expect(FreedomMath.freedomDescription(snapshot.freedom).hasSuffix(oldUnit))
            #expect(FreedomMath.freedomDescription(impact.newFreedom).hasSuffix(newUnit))
            #expect(impact.freedomChange == amount / 100)
        }
    }

    @Test func backdatedExpenseCanIncreaseFreedomAndMatchesSavedLedger() throws {
        let context = try TestSupport.makeContext()
        let assets = UserAssets(total: 0)
        assets.cash = 10_000
        context.insert(assets)
        context.insert(Expense(amount: 100, category: "午餐", date: today))
        try context.save()
        let oldExpenses = try context.fetch(FetchDescriptor<Expense>())
        let snapshot = FinancialSnapshot(expenses: oldExpenses, passiveSources: [], assets: assets, now: today)
        let date = Calendar.current.date(byAdding: .day, value: -9, to: today)!
        let impact = TransactionImpact(snapshot: snapshot, kind: .expense, amount: 1, date: date)
        #expect(impact.changesTrackingStart)
        #expect(impact.newDailyBurn == 10.1)
        #expect(try #require(impact.freedomChange) > 0)
        #expect(FinancialFormatting.daysChange(impact.freedomChange).hasPrefix("+"))
        try LedgerStore.add(.expense(Expense(amount: 1, category: "午餐", date: date)), in: context)
        let saved = FinancialSnapshot(expenses: try context.fetch(FetchDescriptor<Expense>()),
                                      passiveSources: [], assets: assets, now: today)
        #expect(saved.freedom == impact.newFreedom)
        #expect(saved.netWorth == impact.newNetWorth)
        #expect(assets.firstRecordDate == date)
    }

    @Test func firstExpenseAndPassiveCoverageRemainDifferentStates() {
        let assets = UserAssets(total: 0)
        assets.cash = 1_000
        let noExpenses = FinancialSnapshot(expenses: [], passiveSources: [], assets: assets, now: today)
        let first = TransactionImpact(snapshot: noExpenses, kind: .expense, amount: 100)
        #expect(first.before.freedom == .insufficientData)
        #expect(first.newFreedom == .finite(days: 9))
        #expect(first.freedomChange == nil)
        #expect(TransactionImpact(snapshot: noExpenses, kind: .income, amount: 100).newFreedom == .insufficientData)

        let covered = FinancialSnapshot(expenses: [Expense(amount: 100, category: "午餐", date: today)],
                                        passiveSources: [PassiveSource(name: "利息", monthlyAmount: 3_000)],
                                        assets: assets, now: today)
        let expense = TransactionImpact(snapshot: covered, kind: .expense, amount: 100)
        #expect(covered.freedom == .covered)
        #expect(expense.newFreedom == .finite(days: 9))
        #expect(expense.freedomChange == nil)
    }

    @Test func smallLossCanLeaveCellCountUnchanged() throws {
        let assets = UserAssets(total: 0)
        assets.cash = 10_090
        let snapshot = FinancialSnapshot(expenses: [Expense(amount: 100, category: "午餐", date: today)],
                                         passiveSources: [], assets: assets, now: today)
        let impact = TransactionImpact(snapshot: snapshot, kind: .expense, amount: 0.01)
        let old = FreedomMath.gridState(for: snapshot.freedom, lockedAssets: 0, netWorth: snapshot.netWorth)
        let new = FreedomMath.gridState(for: impact.newFreedom, lockedAssets: 0, netWorth: impact.newNetWorth, unit: old.unit)
        #expect(old.count == new.count)
        #expect(try #require(impact.freedomChange) < 0)
        #expect(FinancialFormatting.daysChange(impact.freedomChange) == "−不足 1 天")
    }

    @Test func refundAndInvalidAmountsHaveUnambiguousSigns() {
        let refund = LedgerTransaction.expense(Expense(amount: -30, category: "购物"))
        #expect(FinancialFormatting.signedYuan(refund.cashChange) == "+¥30")
        #expect(refund.undoMessage.contains("撤销后现金变化：−¥30"))
        #expect(FinancialFormatting.signedYuan(0) == "¥0")
        #expect(FinancialFormatting.signedYuan(.nan) == "—")
        #expect(FinancialFormatting.daysChange(0) == "0 天")
        #expect(FinancialFormatting.daysChange(nil) == "—")
    }

    @Test func checklistShowsDaysWhenHeroUsesMonths() {
        let assets = UserAssets(total: 0)
        assets.cash = 36_500
        let summary = FreedomChecklist.evaluate(expenses: [Expense(amount: 100, category: "午餐")],
                                                passiveSources: [], assets: assets)
        #expect(summary.items[4].detail == "当前 365 / 365 天")
    }
}
