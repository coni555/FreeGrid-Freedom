// Pro 现金账户：现金总数永远等于各账户之和；记支出整笔扣第一个够付的账户；撤销、改账、月供、调拨、备份都落在对的账户上。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct CashAccountTests {
    private enum Failure: Error { case save }
    private let failingSave: LedgerStore.SaveAction = { _ in throw Failure.save }

    // MARK: - 夹具

    private func ledger(cash: Double = 0, locked: Double = 0) throws -> ModelContext {
        let context = try TestSupport.makeContext()
        let assets = UserAssets(total: 0)
        assets.cash = cash
        assets.lockedAssets = locked
        context.insert(assets)
        try context.save()
        return context
    }

    private func assets(_ context: ModelContext) throws -> UserAssets {
        try #require(try context.fetch(FetchDescriptor<UserAssets>()).first)
    }

    private func accounts(_ context: ModelContext) throws -> [CashAccount] {
        try CashAccountStore.accounts(in: context)
    }

    private func balances(_ context: ModelContext) throws -> [Double] {
        try accounts(context).map(\.amount)
    }

    /// 微信 32、支付宝 8600、招行卡 5080，按这个顺序扣
    private func threeAccounts() throws -> ModelContext {
        let context = try ledger()
        for (name, amount) in [("微信", 32.0), ("支付宝", 8_600), ("招行卡", 5_080)] {
            try CashAccountStore.save(nil, name: name, amount: amount, in: context)
        }
        return context
    }

    private func account(_ name: String, _ context: ModelContext) throws -> CashAccount {
        try #require(try accounts(context).first { $0.name == name })
    }

    private func spend(_ amount: Double, from account: UUID? = nil, in context: ModelContext) throws -> Expense {
        let expense = Expense(amount: amount, category: "午餐")
        expense.cashAccountID = account
        try LedgerStore.add(.expense(expense), in: context)
        return expense
    }

    // MARK: - 拆分

    @Test func splittingCarvesTheFirstAccountOutOfTheOldTotal() throws {
        let context = try ledger(cash: 14_000)
        try CashAccountStore.save(nil, name: "微信", amount: 320, source: .unsplitTotal, in: context)
        #expect(try accounts(context).map(\.name) == ["现金", "微信"])
        #expect(try balances(context) == [13_680, 320])
        #expect(try assets(context).cash == 14_000)
    }

    @Test func addingNewMoneyGrowsTheTotalAndKeepsTheOldTotalAsAnAccount() throws {
        let context = try ledger(cash: 14_000)
        try CashAccountStore.save(nil, name: "微信", amount: 320, in: context)
        #expect(try balances(context) == [14_000, 320])
        #expect(try assets(context).cash == 14_320)
    }

    @Test func carvingMoreThanTheSourceHasChangesNothing() throws {
        let context = try threeAccounts()
        let wechat = try account("微信", context)
        #expect(throws: CashAccountError.notEnough(name: "微信", available: 32)) {
            try CashAccountStore.save(nil, name: "零钱通", amount: 100, source: .account(wechat.id), in: context)
        }
        #expect(try balances(context) == [32, 8_600, 5_080])
    }

    // MARK: - 记支出扣哪个

    @Test func anExpenseComesFromTheFirstAccountThatCanPayAllOfIt() throws {
        let context = try threeAccounts()
        let small = try spend(12, in: context)
        #expect(small.cashAccountID == (try account("微信", context)).id)
        let bigger = try spend(48, in: context)   // 微信只剩 20，整笔跳到支付宝
        #expect(bigger.cashAccountID == (try account("支付宝", context)).id)
        #expect(try balances(context) == [20, 8_552, 5_080])
        #expect(try assets(context).cash == 13_652)
    }

    @Test func aChosenAccountIsUsedEvenWhenAnEarlierOneCouldPay() throws {
        let context = try threeAccounts()
        let card = try account("招行卡", context)
        let expense = try spend(10, from: card.id, in: context)
        #expect(expense.cashAccountID == card.id)
        #expect(try balances(context) == [32, 8_600, 5_070])
    }

    @Test func whenNoAccountCanPayTheFirstOneGoesNegative() throws {
        let context = try threeAccounts()
        try spend(20_000, in: context)
        #expect(try balances(context) == [-19_968, 8_600, 5_080])
        #expect(try assets(context).cash == 13_712 - 20_000)
    }

    @Test func reorderingChangesWhichAccountPaysFirst() throws {
        let context = try threeAccounts()
        try CashAccountStore.move(try account("招行卡", context), to: 0, in: context)
        #expect(try accounts(context).map(\.name) == ["招行卡", "微信", "支付宝"])
        let expense = try spend(12, in: context)
        #expect(expense.cashAccountID == (try account("招行卡", context)).id)
    }

    @Test func incomeGoesToTheChosenAccountOrTheFirstOne() throws {
        let context = try threeAccounts()
        let card = try account("招行卡", context)
        let salary = Income(amount: 9_000, source: "工资")
        salary.cashAccountID = card.id
        try LedgerStore.add(.income(salary), in: context)
        let gift = Income(amount: 100, source: "红包")
        try LedgerStore.add(.income(gift), in: context)
        #expect(try balances(context) == [132, 8_600, 14_080])
        #expect(gift.cashAccountID == (try account("微信", context)).id)
    }

    // MARK: - 撤销与改账

    @Test func undoRefundsTheSameAccount() throws {
        let context = try threeAccounts()
        let expense = try spend(48, in: context)
        try LedgerStore.undo(id: expense.id, kind: .expense, in: context)
        #expect(try balances(context) == [32, 8_600, 5_080])
    }

    @Test func undoAfterTheAccountWasDeletedRefundsTheFirstAccount() throws {
        let context = try threeAccounts()
        let expense = try spend(100, from: (try account("招行卡", context)).id, in: context)
        try CashAccountStore.delete(try account("招行卡", context), in: context)
        try LedgerStore.undo(id: expense.id, kind: .expense, in: context)
        #expect(try balances(context) == [132, 8_600])
        #expect(try assets(context).cash == 8_732)
    }

    @Test func editingTheAmountAdjustsOnlyThatAccount() throws {
        let context = try threeAccounts()
        let expense = try spend(48, in: context)
        try LedgerStore.edit(id: expense.id, kind: .expense, in: context,
                             to: .init(amount: 60, title: "午餐", note: "", date: expense.date))
        #expect(try balances(context) == [32, 8_540, 5_080])
    }

    @Test func switchingTheAccountMovesTheWholeAmount() throws {
        let context = try threeAccounts()
        let expense = try spend(48, in: context)
        let card = try account("招行卡", context)
        try LedgerStore.edit(id: expense.id, kind: .expense, in: context,
                             to: .init(amount: 50, title: "午餐", note: "", date: expense.date, cashAccountID: card.id))
        #expect(try balances(context) == [32, 8_600, 5_030])
        #expect(expense.cashAccountID == card.id)
    }

    @Test func editingARecordFromBeforeTheSplitUsesTheFirstAccount() throws {
        let context = try threeAccounts()
        // 拆账户以前记的：没记账户，钱早已算在总数里。编辑页上显示的是第一个账户
        let expense = Expense(amount: 48, category: "午餐")
        context.insert(expense)
        try context.save()
        try LedgerStore.edit(id: expense.id, kind: .expense, in: context,
                             to: .init(amount: 148, title: "午餐", note: "", date: expense.date))
        #expect(try balances(context) == [-68, 8_600, 5_080])
        #expect(expense.cashAccountID == (try account("微信", context)).id)
        try LedgerStore.undo(id: expense.id, kind: .expense, in: context)
        #expect(try balances(context) == [80, 8_600, 5_080])
    }

    @Test func aFailedFirstAccountLeavesTheCashUnsplit() throws {
        let context = try ledger(cash: 1_000)
        #expect(throws: Failure.self) {
            try CashAccountStore.save(nil, name: "微信", amount: 200, source: .unsplitTotal, in: context, save: failingSave)
        }
        #expect(try accounts(context).isEmpty)
        #expect(try assets(context).cash == 1_000)
        #expect(!context.hasChanges)

        try CashAccountStore.save(nil, name: "微信", amount: 200, source: .unsplitTotal, in: context)
        #expect(try accounts(context).map(\.name) == ["现金", "微信"])
        #expect(try balances(context) == [800, 200])
    }

    @Test func aFailedSaveLeavesEveryAccountAsItWas() throws {
        let context = try threeAccounts()
        let expense = Expense(amount: 48, category: "午餐")
        #expect(throws: Failure.self) {
            try LedgerStore.add(.expense(expense), in: context, save: failingSave)
        }
        #expect(try balances(context) == [32, 8_600, 5_080])
        #expect(try assets(context).cash == 13_712)
        #expect(throws: Failure.self) {
            try CashAccountStore.move(try account("招行卡", context), to: 0, in: context, save: failingSave)
        }
        #expect(try accounts(context).map(\.name) == ["微信", "支付宝", "招行卡"])
    }

    // MARK: - 删除与合并

    @Test func deletingAnAccountTakesItsBalanceOutOfCash() throws {
        let context = try threeAccounts()
        try CashAccountStore.delete(try account("微信", context), in: context)
        #expect(try assets(context).cash == 13_680)
    }

    @Test func mergingKeepsTheTotalAndDropsTheAccounts() throws {
        let context = try threeAccounts()
        try CashAccountStore.mergeIntoTotal(in: context)
        #expect(try accounts(context).isEmpty)
        #expect(try assets(context).cash == 13_712)
        try spend(12, in: context)
        #expect(try assets(context).cash == 13_700)
    }

    // MARK: - 月供

    @Test func aRepaymentNeedsOneAccountThatCanPayItAll() throws {
        let now = TestSupport.day("2026-10-15").addingTimeInterval(12 * 3600)
        let later = TestSupport.day("2026-11-20").addingTimeInterval(12 * 3600)
        let context = try ledger()
        try CashAccountStore.save(nil, name: "微信", amount: 2_000, in: context)
        try CashAccountStore.save(nil, name: "支付宝", amount: 2_000, in: context)
        try LoanStore.save(nil, name: "房贷", monthlyAmount: 3_000, dueDay: 14, remaining: 24, now: now, in: context)
        // 加起来 4000 够，但没有一个账户单独够付：这期留着等处理
        #expect(try LoanStore.processDue(now: later, in: context) == 0)
        #expect(try balances(context) == [2_000, 2_000])

        let other = try ledger()
        try CashAccountStore.save(nil, name: "微信", amount: 2_000, in: other)
        try CashAccountStore.save(nil, name: "招行卡", amount: 5_000, in: other)
        try LoanStore.save(nil, name: "房贷", monthlyAmount: 3_000, dueDay: 14, remaining: 24, now: now, in: other)
        #expect(try LoanStore.processDue(now: later, in: other) == 1)
        #expect(try balances(other) == [2_000, 2_000])
        let payment = try #require(try other.fetch(FetchDescriptor<Expense>()).first)
        #expect(payment.cashAccountID == (try account("招行卡", other)).id)
    }

    @Test func aLoanBoundToAnAccountOnlyEverPaysFromIt() throws {
        let now = TestSupport.day("2026-10-15").addingTimeInterval(12 * 3600)
        let later = TestSupport.day("2026-11-20").addingTimeInterval(12 * 3600)
        let context = try ledger()
        try CashAccountStore.save(nil, name: "支付宝", amount: 9_000, in: context)
        let card = try CashAccountStore.save(nil, name: "招行卡", amount: 1_000, in: context)
        let loan = try LoanStore.save(nil, name: "房贷", monthlyAmount: 3_000, dueDay: 14, remaining: 24,
                                      cashAccountID: card.id, now: now, in: context)
        // 绑定的卡只有 1000：哪怕支付宝够，这期也不扣，留着等处理
        #expect(try LoanStore.processDue(now: later, in: context) == 0)
        #expect(try balances(context) == [9_000, 1_000])

        // 处理时「从现金扣」也只扣这张卡（扣成负数）
        let due = TestSupport.day("2026-11-14")
        try LoanStore.resolvePending(loan, dueDate: due, fromCash: true, now: later, in: context)
        #expect(try balances(context) == [9_000, -2_000])

        // 卡里有钱了，下一期就从卡里扣
        try TransferStore.transfer(8_000, from: .cashAccount((try account("支付宝", context)).id),
                                   to: .cashAccount(card.id), in: context)
        let december = TestSupport.day("2026-12-20").addingTimeInterval(12 * 3600)
        #expect(try LoanStore.processDue(now: december, in: context) == 1)
        #expect(try balances(context) == [1_000, 3_000])
    }

    @Test func aLoanWhoseAccountWasDeletedFallsBackToTheSpendingOrder() throws {
        let now = TestSupport.day("2026-10-15").addingTimeInterval(12 * 3600)
        let later = TestSupport.day("2026-11-20").addingTimeInterval(12 * 3600)
        let context = try ledger()
        try CashAccountStore.save(nil, name: "支付宝", amount: 9_000, in: context)
        let card = try CashAccountStore.save(nil, name: "招行卡", amount: 1_000, in: context)
        try LoanStore.save(nil, name: "房贷", monthlyAmount: 3_000, dueDay: 14, remaining: 24,
                           cashAccountID: card.id, now: now, in: context)
        try CashAccountStore.delete(card, in: context)
        #expect(try LoanStore.processDue(now: later, in: context) == 1)
        #expect(try balances(context) == [6_000])
    }

    @Test func theBoundAccountSurvivesABackupRoundTrip() throws {
        let source = try ledger()
        let card = try CashAccountStore.save(nil, name: "招行卡", amount: 5_000, in: source)
        try LoanStore.save(nil, name: "房贷", monthlyAmount: 3_000, dueDay: 14, remaining: 24,
                           cashAccountID: card.id, in: source)
        let target = try TestSupport.makeContext()
        let preview = try DataIO.previewJSON(data: try DataIO.exportJSON(context: source), context: target)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)
        let loan = try #require(try LoanStore.loans(in: target).first)
        #expect(loan.cashAccountID == card.id)
    }

    // MARK: - 调拨

    @Test func transferMovesMoneyBetweenAccountsAndItems() throws {
        let context = try threeAccounts()
        let card = try account("招行卡", context)
        let wechat = try account("微信", context)
        #expect(try TransferStore.transfer(500, from: .cashAccount(card.id), to: .cashAccount(wechat.id), in: context) == 500)
        #expect(try balances(context) == [532, 8_600, 4_580])
        #expect(try assets(context).cash == 13_712)

        let fund = try AssetItemStore.save(nil, name: "基金", amount: 1_000, in: context)
        #expect(try TransferStore.transfer(9_999, from: .cashAccount(wechat.id), to: .assetItem(fund.id), in: context) == 532)
        #expect(fund.amount == 1_532)
        #expect(try assets(context).lockedAssets == 1_532)
        #expect(try assets(context).cash == 13_180)

        #expect(throws: CashAccountError.hasAccounts) {
            try TransferStore.transfer(1, from: .cashTotal, to: .assetItem(fund.id), in: context)
        }
    }

    @Test func transferWithoutAnySplitWorksOnTheTotals() throws {
        let context = try ledger(cash: 1_000, locked: 500)
        #expect(try TransferStore.transfer(300, from: .cashTotal, to: .assetsTotal, in: context) == 300)
        #expect(try assets(context).cash == 700)
        #expect(try assets(context).lockedAssets == 800)
    }

    // MARK: - 备份

    @Test func accountsAndWhereEachRecordWentRoundTrip() throws {
        let source = try threeAccounts()
        let expense = try spend(48, in: source)
        let data = try DataIO.exportJSON(context: source)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("cash_accounts"))
        #expect(json.contains("cash_account_id"))

        let target = try TestSupport.makeContext()
        let preview = try DataIO.previewJSON(data: data, context: target)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)
        #expect(try accounts(target).map(\.name) == ["微信", "支付宝", "招行卡"])
        #expect(try balances(target) == [32, 8_552, 5_080])
        #expect(try assets(target).cash == 13_664)
        let restored = try #require(try target.fetch(FetchDescriptor<Expense>()).first)
        #expect(restored.cashAccountID == expense.cashAccountID)
    }

    @Test func exportWithoutAccountsHasNoAccountKeys() throws {
        let context = try ledger(cash: 100)
        try spend(10, in: context)
        let json = try #require(String(data: try DataIO.exportJSON(context: context), encoding: .utf8))
        #expect(!json.contains("cash_account"))
    }

    @Test func accountsThatDoNotAddUpToCashAreRejected() throws {
        let data = Data("""
        {"schema_version":2,"assets":{"total":100,"locked_assets":0,"cash":100},
         "cash_accounts":[{"name":"微信","amount":30},{"name":"支付宝","amount":50}]}
        """.utf8)
        #expect(throws: ImportValidationError.self) {
            try DataIO.previewJSON(data: data, context: try TestSupport.makeContext())
        }
    }

    // MARK: - 计入自由天数

    private func snapshot(_ context: ModelContext, now: Date) throws -> FinancialSnapshot {
        FinancialSnapshot(expenses: try context.fetch(FetchDescriptor<Expense>()), passiveSources: [],
                          assets: try assets(context), cashAccounts: try accounts(context), now: now, countsAssets: true)
    }

    @Test func newAccountsCountAndAnUncountedOneLeavesFreedomButNotNetWorth() throws {
        let context = try threeAccounts()
        #expect(try accounts(context).allSatisfy(\.countsInFreedom))
        let now = TestSupport.day("2026-10-15").addingTimeInterval(12 * 3600)
        // 日均 100：10 天里花了 1000（从支付宝扣）
        try LedgerStore.add(.expense(Expense(amount: 1000, category: "午餐",
                                              date: TestSupport.day("2026-10-06"))), in: context)
        let before = try snapshot(context, now: now)
        #expect(before.freedomBase == before.netWorth && before.excludedCash == 0)
        #expect(before.uncountedAssetsNote == nil)

        try CashAccountStore.setCountsInFreedom(false, for: try account("招行卡", context), in: context)
        let after = try snapshot(context, now: now)
        #expect(after.netWorth == before.netWorth)
        #expect(after.excludedCash == 5_080)
        #expect(after.freedomBase == before.freedomBase - 5_080)
        #expect(after.freedom == .finite(days: (before.freedomBase - 5_080) / 100))
        #expect(after.uncountedAssetsNote == "部分现金未计入")
        #expect(after.hasUncountedMoney)
        #expect(CashRows.countsSummary(accounts: try accounts(context)) == "计入自由天数 ¥\((32.0 + 7_600).formatted(.number))")
    }

    @Test func togglingRollsBackWhenSavingFails() throws {
        let context = try threeAccounts()
        let card = try account("招行卡", context)
        #expect(throws: Failure.self) {
            try CashAccountStore.setCountsInFreedom(false, for: card, in: context, save: failingSave)
        }
        #expect(card.countsInFreedom)
    }

    @Test func aPaymentFromAnUncountedAccountLeavesThePreviewBaseAlone() throws {
        let context = try threeAccounts()
        try CashAccountStore.setCountsInFreedom(false, for: try account("招行卡", context), in: context)
        let now = TestSupport.day("2026-10-15").addingTimeInterval(12 * 3600)
        try LedgerStore.add(.expense(Expense(amount: 100, category: "午餐", date: now)), in: context)
        let s = try snapshot(context, now: now)
        let counted = TransactionImpact(snapshot: s, kind: .expense, amount: 50)
        let uncounted = TransactionImpact(snapshot: s, kind: .expense, amount: 50, account: try account("招行卡", context))
        #expect(counted.newFreedomBase == s.freedomBase - 50)
        #expect(uncounted.newFreedomBase == s.freedomBase)
        #expect(uncounted.newNetWorth == s.netWorth - 50)
        #expect(uncounted.newDailyBurn == counted.newDailyBurn)
    }

    @Test func overdrawingAnUncountedAccountShowsTheOverdraftInThePreview() throws {
        let context = try threeAccounts()
        try CashAccountStore.setCountsInFreedom(false, for: try account("微信", context), in: context)
        let now = TestSupport.day("2026-10-15").addingTimeInterval(12 * 3600)
        try LedgerStore.add(.expense(Expense(amount: 100, category: "午餐", date: now)), in: context)
        let s = try snapshot(context, now: now)
        // 微信只有 32：超出的 18 只能算在自由天数里的钱上
        let impact = TransactionImpact(snapshot: s, kind: .expense, amount: 50, account: try account("微信", context))
        #expect(impact.newFreedomBase == s.freedomBase - 18)
        _ = try spend(50, from: (try account("微信", context)).id, in: context)
        let after = try snapshot(context, now: now)
        #expect(after.freedomBase == impact.newFreedomBase)

        // 再存进去 30：先补上欠的 18，余下的 12 留在不计入的账户里
        let refill = TransactionImpact(snapshot: after, kind: .income, amount: 30, account: try account("微信", context))
        #expect(refill.newFreedomBase == after.freedomBase + 18)
    }

    @Test func transferIntoAnUncountedAccountIsFlagged() throws {
        let context = try threeAccounts()
        let card = try account("招行卡", context)
        let wechat = try account("微信", context)
        try CashAccountStore.setCountsInFreedom(false, for: card, in: context)
        let all = try accounts(context)
        #expect(TransferStore.uncountedDestinationName(from: .cashAccount(wechat.id), to: .cashAccount(card.id),
                                                       assetItems: [], cashAccounts: all) == "招行卡")
        #expect(TransferStore.uncountedDestinationName(from: .cashAccount(card.id), to: .cashAccount(wechat.id),
                                                       assetItems: [], cashAccounts: all) == nil)
    }

    @Test func countingFlagsRoundTripAndOldBackupsDefaultToCounted() throws {
        let source = try threeAccounts()
        try CashAccountStore.setCountsInFreedom(false, for: try account("招行卡", source), in: source)
        let data = try DataIO.exportJSON(context: source)
        let text = String(decoding: data, as: UTF8.self)
        // 只有不计入的那个写了字段
        #expect(text.components(separatedBy: "\"counts_in_freedom\" : false").count == 2)

        let target = try TestSupport.makeContext()
        _ = try DataIO.commitImport(preview: try DataIO.previewJSON(data: data, context: target),
                                    strategy: .replace, context: target)
        let restored = try accounts(target)
        #expect(restored.map(\.countsInFreedom) == [true, true, false])
    }
}
