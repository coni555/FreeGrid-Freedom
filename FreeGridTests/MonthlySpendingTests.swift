// 2.2 两种记账方式：逐笔记账，或者按月记账。
// 按月记账含固定支出，算日均时扣掉；日均取写过的月份的平均，旧记录不计入；问哪个月有规则；
// 记过账的人切回逐笔记账回到切换前，只写过数的人日均 30 天过渡；记账没跨满 30 天又断档的不给大数字；备份带上这些。
// 3044 / 月按 30.44 天折成每天 100，下面的数都按这个算。
import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct MonthlySpendingTests {
    /// 第 n 天的中午（第 1 天是 2026-10-01）
    private func dayNumber(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n - 1, to: TestSupport.day("2026-10-01"))!
            .addingTimeInterval(12 * 3600)
    }

    private func entries(_ pairs: [(Int, Double)]) -> [FreedomMath.BurnEntry] {
        pairs.map { FreedomMath.BurnEntry(date: dayNumber($0.0), amount: $0.1) }
    }

    /// 第 1 天到第 n 天每天 60
    private func daily(_ n: Int) -> [(Int, Double)] { (1...n).map { ($0, 60) } }

    private func expenses(_ pairs: [(Int, Double)]) -> [Expense] {
        pairs.map { Expense(amount: $0.1, category: "午餐", date: dayNumber($0.0)) }
    }

    private func cash(_ amount: Double) -> UserAssets {
        let assets = UserAssets(total: 0)
        assets.cash = amount
        return assets
    }

    private func rent(_ amount: Double) -> Loan {
        Loan(name: "房租", monthlyAmount: amount, dueDay: 5, periodsAtStart: 0,
             startDate: dayNumber(1), sortOrder: 0, isOngoing: true)
    }

    private func monthly(_ months: [String: Double] = ["2026-10": 3044], start: String = "2026-10") -> MonthlyTracking {
        MonthlyTracking(method: .monthly, months: months, startMonth: start,
                        pauses: [MonthlyTracking.Pause(start: dayNumber(1), end: nil)])
    }

    private func snapshot(_ expenses: [Expense] = [], tracking: MonthlyTracking, loans: [Loan] = [], day: Int = 1) -> FinancialSnapshot {
        FinancialSnapshot(expenses: expenses, passiveSources: [], assets: cash(10_000), loans: loans,
                          now: dayNumber(day), countsAssets: true, tracking: tracking)
    }

    // MARK: - 按月记账：日均

    @Test func freedomDaysFromOneNumber() {
        let snapshot = snapshot(tracking: monthly())
        #expect(snapshot.hasExpenses && !snapshot.hasRecords)
        #expect(snapshot.burnBasis == .estimate)
        guard case .finite(let days) = snapshot.freedom else { Issue.record("应该算得出自由天数"); return }
        #expect(abs(days - 100) < 1e-6)
        // 记账里程碑不因为写了数而开始
        #expect(FreedomChecklist.evaluate(snapshot: snapshot).items.first { $0.group == .record }?.progress == 0)
    }

    @Test func noNumberYetMeansNoFreedomDays() {
        let snapshot = snapshot(tracking: monthly([:]))
        #expect(!snapshot.hasExpenses)
        #expect(snapshot.freedom == .insufficientData)
    }

    @Test func severalMonthsAreAveraged() {
        let snapshot = snapshot(tracking: monthly(["2026-10": 2044, "2026-11": 4044]))
        #expect(abs(snapshot.dailyBurn - 100) < 1e-9)
        #expect(HomeStat.dailyNote(snapshot) == String(localized: "按 2 个月平均"))
    }

    @Test func theDailyCardNamesTheOnlyMonth() {
        let snapshot = snapshot(tracking: monthly())
        #expect(HomeStat.dailyNote(snapshot) == String(localized: "按 \(YearMonth(year: 2026, month: 10).name(now: dayNumber(1))) 估算"))
    }

    @Test func oldRecordsDoNotCount() {
        // 每天 60 记了 30 天，切过去写 3044：日均是 100，不是混算
        let snapshot = snapshot(expenses(daily(30)), tracking: monthly(), day: 40)
        #expect(abs(snapshot.dailyBurn - 100) < 1e-9)
        #expect(snapshot.burnBasis == .estimate)
        #expect(snapshot.hasRecords)
        #expect(snapshot.burnGapDays == 0)
    }

    @Test func recordMilestonesPauseWhileMonthly() {
        // 第 30 天切过去，第 100 天看：记账天数停在 30，不会自己涨到 90 天
        let pause = MonthlyTracking.Pause(start: dayNumber(30), end: nil)
        let tracking = MonthlyTracking(method: .monthly, months: ["2026-10": 3044], pauses: [pause])
        let snapshot = snapshot(expenses(daily(30)), tracking: tracking, day: 100)
        #expect(snapshot.trackDays == 30)
    }

    @Test func simulatingKeepsTheDailyBurn() {
        let snapshot = snapshot(expenses(daily(30)), tracking: monthly(), day: 40)
        let impact = TransactionImpact(snapshot: snapshot, kind: .expense, amount: 5000, date: dayNumber(40))
        #expect(abs(impact.newDailyBurn - 100) < 1e-9)
        #expect(!impact.changesTrackingStart)
        guard case .finite(let days) = impact.newFreedom else { Issue.record("预览应该算得出"); return }
        #expect(abs(days - 50) < 1e-6)
    }

    @Test func simulatingWithoutANumberStaysPending() {
        let impact = TransactionImpact(snapshot: snapshot(tracking: monthly([:])), kind: .expense, amount: 100, date: dayNumber(1))
        #expect(impact.newFreedom == .insufficientData)
    }

    @Test func recordCardsAreHiddenInMonthlyMode() {
        #expect(HomeStat.slots(stored: "", hasPassive: false, monthly: true) == [.daily, .base])
        #expect(HomeStat.slots(stored: "", hasPassive: true, monthly: true) == [.daily, .passive])
        for stat in [HomeStat.month, .today, .track, .todayBar] { #expect(stat.needsRecords) }
        for stat in [HomeStat.daily, .base, .passive, .next] { #expect(!stat.needsRecords) }
    }

    // MARK: - 按月记账：固定支出在里面

    @Test func fixedExpensesAreInsideTheMonthlyNumber() {
        // 写 3044、房租 1000：日常 2044；首页写的日均还是 3044 折成的 100，没有多算一遍
        let snapshot = snapshot(tracking: monthly(), loans: [rent(1000)])
        #expect(abs(snapshot.dailyBurn - 2044 / 30.44) < 1e-9)
        #expect(abs(snapshot.dailyCost - 100) < 1e-9)
    }

    @Test func addingAFixedExpenseBarelyMovesFreedomDays() {
        // 同样每月花 3044：不管有没有把房租单列出来，都是一百来天
        let plain = snapshot(tracking: monthly())
        let withRent = snapshot(tracking: monthly(), loans: [rent(1000)])
        guard case .finite(let a) = plain.freedom, case .finite(let b) = withRent.freedom else {
            Issue.record("都应该算得出自由天数"); return
        }
        #expect(abs(a - 100) < 1e-6)
        #expect(abs(a - b) < 31)
    }

    @Test func fixedExpensesOverTheMonthlyNumberAreNotABadData() {
        // 房租比写的数还多：日常 0，只按日历扣房租，不提示「有一笔金额不对」
        let snapshot = snapshot(tracking: monthly(["2026-10": 1000]), loans: [rent(2000)])
        #expect(snapshot.dailyBurn == 0)
        guard case .finite(let days) = snapshot.freedom else { Issue.record("应该算得出自由天数"); return }
        // 10000 付得起 5 个月房租，第 6 次到期的前一天停住
        #expect(days > 120 && days < 170)
        // 记收入的预览也不报错
        let impact = TransactionImpact(snapshot: snapshot, kind: .income, amount: 100, date: dayNumber(1))
        guard case .finite = impact.newFreedom else { Issue.record("预览应该算得出"); return }
    }

    @Test func recordingAZeroAmountIsStillBadData() {
        // 真的记过账、日均却是 0：这才是数据有问题，放宽只给每月花销
        let run = FreedomMath.freedomRun(netWorth: 1000, dailyBurn: 0, hasExpenses: true,
                                         loans: LoanSchedule.plan(loans: [rent(100)], payments: [], now: dayNumber(1)))
        #expect(run.state == .invalidData)
    }

    // MARK: - 问哪个月

    private func date(_ text: String) -> Date { TestSupport.day(text).addingTimeInterval(12 * 3600) }

    private func tracking(start: String, written: [String] = []) -> MonthlyTracking {
        var months: [String: Double] = [:]
        for key in written { months[key] = 3000 }
        return MonthlyTracking(method: .monthly, months: months, startMonth: start)
    }

    @Test func aNewUserIsAskedAboutTheMonthTheyAreIn() {
        let prompt = tracking(start: "2026-11").prompt(now: date("2026-11-05"))
        #expect(prompt.month == YearMonth(year: 2026, month: 11))
        #expect(prompt.amount == nil && prompt.isEarly)
    }

    @Test func aWrittenMonthShowsItsNumber() {
        let prompt = tracking(start: "2026-11", written: ["2026-11"]).prompt(now: date("2026-11-05"))
        #expect(prompt.month == YearMonth(year: 2026, month: 11))
        #expect(prompt.amount == 3000)
    }

    @Test func theNextMonthIsAskedOnceTheLastOneIsWritten() {
        let prompt = tracking(start: "2026-11", written: ["2026-11"]).prompt(now: date("2026-12-03"))
        #expect(prompt.month == YearMonth(year: 2026, month: 12))
        #expect(prompt.amount == nil && prompt.isEarly)
    }

    @Test func aFinishedMonthIsAskedFirst() {
        let prompt = tracking(start: "2026-11").prompt(now: date("2026-12-03"))
        #expect(prompt.month == YearMonth(year: 2026, month: 11))
        #expect(!prompt.isEarly)
    }

    @Test func onlyTheLatestFinishedMonthIsAsked() {
        let prompt = tracking(start: "2026-11", written: ["2026-11"]).prompt(now: date("2027-03-15"))
        #expect(prompt.month == YearMonth(year: 2027, month: 2))
    }

    @Test func monthsBeforeTheStartAreNotAsked() {
        // 11 月才开始用，12 月不问 10 月；跨年也一样
        let prompt = tracking(start: "2026-12").prompt(now: date("2026-12-03"))
        #expect(prompt.month == YearMonth(year: 2026, month: 12))
        let january = tracking(start: "2027-01").prompt(now: date("2027-01-03"))
        #expect(january.month == YearMonth(year: 2027, month: 1))
    }

    @Test func noReminderAtTheEndOfTheMonth() {
        #expect(tracking(start: "2026-11").prompt(now: date("2026-11-27")).isEarly)
        #expect(!tracking(start: "2026-11").prompt(now: date("2026-11-28")).isEarly)
        #expect(!tracking(start: "2026-11").prompt(now: date("2026-11-30")).isEarly)
    }

    @Test func switchingIsAFreshStartAtTheCurrentMonth() {
        // 记过账的人切过来和新用户一样：问这个月，不问已经记过的上个月，大数字等写了第一个数
        var tracking = MonthlyTracking()
        tracking.adopt(startingAt: YearMonth(year: 2026, month: 11), now: date("2026-11-15"))
        let prompt = tracking.prompt(now: date("2026-11-15"))
        #expect(prompt.month == YearMonth(year: 2026, month: 11))
        #expect(prompt.amount == nil)
        #expect(snapshot(expenses(daily(30)), tracking: tracking, day: 46).freedom == .insufficientData)
    }

    @Test func switchingAgainDoesNotAskAboutTheMonthsInBetween() {
        // 11 月写过，12 月切回逐笔记账，2 月再切过来：问 2 月，不追问记账的那些月；写过的 11 月还算
        var tracking = monthly(["2026-11": 3000], start: "2026-11")
        tracking.switchBack(hasRecords: true, now: date("2026-12-01"))
        tracking.adopt(startingAt: YearMonth(year: 2027, month: 2), now: date("2027-02-10"))
        #expect(tracking.prompt(now: date("2027-02-10")).month == YearMonth(year: 2027, month: 2))
        #expect(tracking.monthlyAverage == 3000)
    }

    @Test func monthsHaveFriendlyNames() {
        guard AppLanguage.isChinese else { return }
        #expect(YearMonth(year: 2026, month: 11).name(now: date("2026-12-03")) == "11 月")
        #expect(YearMonth(year: 2026, month: 12).name(now: date("2027-01-03")) == "2026 年 12 月")
    }

    @Test func clearingAMonthRemovesIt() {
        var tracking = tracking(start: "2026-11", written: ["2026-11", "2026-12"])
        tracking.set(nil, for: YearMonth(year: 2026, month: 12))
        #expect(tracking.writtenMonths.map(\.month) == [YearMonth(year: 2026, month: 11)])
        #expect(tracking.monthlyAverage == 3000)
    }

    // MARK: - 切回逐笔记账

    private func switchedBack(at day: Int, from: Int = 1, months: [String: Double] = ["2026-10": 3044]) -> MonthlyTracking {
        MonthlyTracking(method: .entries, months: months,
                        pauses: [MonthlyTracking.Pause(start: dayNumber(from), end: dayNumber(day))],
                        switchedBackAt: dayNumber(day))
    }

    @Test func withoutRecordsTheNumberKeepsWorking() {
        let burn = FreedomMath.burnEstimate([], tracking: switchedBack(at: 1), fixedMonthly: 0, now: dayNumber(1))
        #expect(abs(burn.dailyBurn - 100) < 1e-9)
        #expect(burn.basis == .estimate)
        #expect(burn.trackDays == 0)
        #expect(snapshot(tracking: switchedBack(at: 1)).hasExpenses)
    }

    @Test func switchingBackReturnsToTheDailyBurnFromBeforeTheSwitch() {
        // 每天 60 记了 30 天：切过去写 3044 日均是 100，当场切回来还是 60，一分不差、不过渡
        let before = FreedomMath.burnEstimate(entries(daily(30)), tracking: plain, fixedMonthly: 0, now: dayNumber(30))
        var tracking = MonthlyTracking()
        tracking.adopt(startingAt: YearMonth(year: 2026, month: 10), now: dayNumber(30))
        tracking.set(3044, for: YearMonth(year: 2026, month: 10))
        let monthly = FreedomMath.burnEstimate(entries(daily(30)), tracking: tracking, fixedMonthly: 0, now: dayNumber(30))
        #expect(abs(monthly.dailyBurn - 100) < 1e-9)
        tracking.switchBack(hasRecords: true, now: dayNumber(30))
        #expect(tracking.switchedBackAt == nil)
        let after = FreedomMath.burnEstimate(entries(daily(30)), tracking: tracking, fixedMonthly: 0, now: dayNumber(30))
        #expect(after == before)
        #expect(after.basis == .records)
    }

    @Test func theMonthsInBetweenAreLeftOutAfterSwitchingBack() {
        // 记了 30 天每天 60，第 30 天切过去，写 3044，第 90 天切回来：写的数不混进来，中间那段不算花了 0 元
        var tracking = MonthlyTracking()
        tracking.adopt(startingAt: YearMonth(year: 2026, month: 10), now: dayNumber(30))
        tracking.set(3044, for: YearMonth(year: 2026, month: 10))
        tracking.switchBack(hasRecords: true, now: dayNumber(90))
        let burn = FreedomMath.burnEstimate(entries(daily(30)), tracking: tracking, fixedMonthly: 0, now: dayNumber(90))
        #expect(abs(burn.dailyBurn - 1800.0 / 31) < 1e-9)
        #expect(burn.basis == .records)
        #expect(burn.trackDays == 31)
    }

    @Test func theFirstEntryDoesNotJump() {
        // 记 20：(20 × 1 + 100 × 29) / 30
        let burn = FreedomMath.burnEstimate(entries([(5, 20)]), tracking: switchedBack(at: 5), fixedMonthly: 0, now: dayNumber(5))
        #expect(abs(burn.dailyBurn - 2920.0 / 30) < 1e-9)
        #expect(burn.basis == .recordsAndEstimate)
    }

    @Test func theBurnMovesTowardsTheRecordsDayByDay() {
        // 第 5 天切回，每天记 60：第 n 天记录占 n/30
        let tracking = switchedBack(at: 5)
        let tenDays = FreedomMath.burnEstimate(entries((5...14).map { ($0, 60) }), tracking: tracking, fixedMonthly: 0, now: dayNumber(14))
        #expect(abs(tenDays.dailyBurn - (60.0 * 10 + 100 * 20) / 30) < 1e-9)
        let done = FreedomMath.burnEstimate(entries((5...34).map { ($0, 60) }), tracking: tracking, fixedMonthly: 0, now: dayNumber(34))
        #expect(done.dailyBurn == 60)
        #expect(done.basis == .records)
    }

    @Test func thePausedStretchIsNotCountedAsSpendingNothing() {
        // 记了 30 天每天 60，第 30 天切过去，第 120 天切回来，第 150 天又记一笔 60：
        // 中间 90 天既不算记账、也不算花了 0 元
        let tracking = MonthlyTracking(method: .entries, months: ["2026-10": 3044],
                                       pauses: [MonthlyTracking.Pause(start: dayNumber(30), end: dayNumber(120))])
        let burn = FreedomMath.burnEstimate(entries(daily(30) + (120...150).map { ($0, 60) }), tracking: tracking,
                                            fixedMonthly: 0, now: dayNumber(150))
        #expect(burn.dailyBurn == 60)
        #expect(burn.trackDays == 61)
    }

    @Test func switchingBackKeepsTheWrittenMonths() {
        var tracking = monthly()
        tracking.switchBack(hasRecords: false, now: dayNumber(10))
        #expect(!tracking.isMonthly)
        #expect(tracking.months == ["2026-10": 3044])
        #expect(tracking.pauses.last?.end == dayNumber(10))
        #expect(tracking.switchedBackAt == dayNumber(10))
        tracking.adopt(startingAt: YearMonth(year: 2026, month: 10), now: dayNumber(20))
        #expect(tracking.isMonthly && tracking.pauses.count == 2 && tracking.switchedBackAt == nil)
    }

    // MARK: - 逐笔记账：断档

    private let plain = MonthlyTracking()

    @Test func withoutMonthlyRecordsWorkAsBefore() {
        let burn = FreedomMath.burnEstimate(entries(daily(10)), tracking: plain, fixedMonthly: 0, now: dayNumber(10))
        #expect(burn.dailyBurn == 60)
        #expect(burn.basis == .records)
    }

    @Test func fourteenQuietDaysStillCount() {
        // 记了 60 天，最后一笔之后 14 天：照常摊
        let burn = FreedomMath.burnEstimate(entries(daily(60)), now: dayNumber(74))
        #expect(burn.gapDays == 0)
        #expect(abs(burn.dailyBurn - 3600.0 / 74) < 1e-9)
    }

    @Test func aLongerGapStopsTheBurnFromFalling() {
        let at14 = FreedomMath.burnEstimate(entries(daily(60)), now: dayNumber(74))
        let at40 = FreedomMath.burnEstimate(entries(daily(60)), now: dayNumber(100))
        #expect(at40.gapDays == 26)
        #expect(at40.trackDays == 100)
        #expect(abs(at40.dailyBurn - at14.dailyBurn) < 1e-9)
    }

    @Test func monthlyLoggersAreNotCutShort() {
        // 一个月记一次总账：中间 29 天是空的，但最后一笔就在今天，全算
        let burn = FreedomMath.burnEstimate(entries([(1, 3000), (31, 3000), (61, 3000)]), now: dayNumber(61))
        #expect(burn.gapDays == 0)
        #expect(abs(burn.dailyBurn - 9000.0 / 61) < 1e-9)
    }

    @Test func oneEntryThenAMonthOfSilenceGivesNoNumber() {
        // 下载那天记一笔 20，之后 30 天没打开：不给 123 年那样的大数字
        let snapshot = snapshot(expenses([(1, 20)]), tracking: plain, day: 31)
        #expect(snapshot.recordsTooFew)
        #expect(snapshot.burnGapDays == 16)
        #expect(snapshot.freedom == .insufficientData)
        #expect(snapshot.hasRecords)
    }

    @Test func aFewQuietDaysStillGiveTheNumber() {
        let snapshot = snapshot(expenses([(1, 20)]), tracking: plain, day: 15)
        #expect(!snapshot.recordsTooFew)
        guard case .finite = snapshot.freedom else { Issue.record("14 天内应该照常算"); return }
    }

    @Test func aVeteranKeepsTheNumberThroughAGap() {
        let snapshot = snapshot(expenses(daily(40)), tracking: plain, day: 90)
        #expect(!snapshot.recordsTooFew)
        #expect(snapshot.burnGapDays == 36)
        guard case .finite = snapshot.freedom else { Issue.record("记得多的人大数字照常"); return }
        #expect(HomeStat.dailyNote(snapshot) == String(localized: "50 天没记 · 日均先停住"))
    }

    @Test func lumpsAreSpreadOverTheRecordedSpan() {
        // 第 1 天 5000 的大额，其余每天 60：大额按 90 天摊，平日除以记录段
        let burn = FreedomMath.burnEstimate(entries([(1, 5000)] + (2...40).map { ($0, 60) }), now: dayNumber(40))
        #expect(burn.spreadLumps == 5000)
        #expect(abs(burn.dailyBurn - (2340.0 / 40 + 5000.0 / 90)) < 1e-9)
    }

    // MARK: - 存取和备份

    @Test func storedValueRoundTrips() {
        var tracking = monthly(["2026-10": 3044, "2026-11": 2000])
        tracking.switchBack(hasRecords: false, now: dayNumber(10))
        #expect(MonthlyTracking.decode(tracking.encoded) == tracking)
        #expect(MonthlyTracking.decode("") == MonthlyTracking())
        #expect(MonthlyTracking.decode("不是 JSON").isUntouched)
    }

    @Test func theBackupCarriesIt() throws {
        let context = try TestSupport.makeContext()
        var tracking = monthly(["2026-10": 3000])
        tracking.pauses = [MonthlyTracking.Pause(start: Date(timeIntervalSince1970: 1_790_000_000), end: nil)]
        let data = try DataIO.exportJSON(context: context, monthlyTracking: tracking)
        let restored = try ImportValidator.validate(data: data).monthlyTracking
        #expect(restored == tracking)
        let without = try DataIO.exportJSON(context: context)
        let absent = try ImportValidator.validate(data: without).monthlyTracking
        #expect(absent == nil)
        #expect(String(decoding: without, as: UTF8.self).contains("monthly_tracking") == false)
    }

    @Test func badBackupValuesAreDropped() throws {
        let json = """
        {"method":"unknown","months":{"2026-10":3000,"oops":10,"2026-11":-5},"start_month":"bad","pauses":[{"start":"nope"}]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tracking = try decoder.decode(MonthlyTrackingJSON.self, from: Data(json.utf8)).tracking
        #expect(tracking == MonthlyTracking(method: .entries, months: ["2026-10": 3000]))
    }
}
