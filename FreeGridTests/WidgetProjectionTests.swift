// 小组件那份数：今天和首页一样；往后每天按首页的规则重算（日均分母变大、到期的房租扣掉）；
// 目标只在 Pro 生效时有；文件能读回来，按时间挑对那一份，内容没变时不重写。
import Foundation
import Testing
@testable import FreeGrid

@MainActor
struct WidgetProjectionTests {
    /// 2026-10-24 中午
    private let now = TestSupport.day("2026-10-24").addingTimeInterval(12 * 3600)

    private func at(_ day: String) -> Date { TestSupport.day(day).addingTimeInterval(12 * 3600) }

    /// 10-15 到 10-24 每天 100：今天日均 100
    private var tenDays: [Expense] {
        (15...24).map { Expense(amount: 100, category: "餐饮", date: at("2026-10-\($0)")) }
    }

    private func assets(cash: Double) -> UserAssets {
        let assets = UserAssets(total: 0)
        assets.cash = cash
        return assets
    }

    private func ledger(_ expenses: [Expense], cash: Double = 10_050, loans: [Loan] = []) -> WidgetProjection.Ledger {
        WidgetProjection.Ledger(expenses: expenses, passiveSources: [], assets: assets(cash: cash), loans: loans)
    }

    @Test func todayMatchesTheHomeScreenAndLaterDaysSpreadTheSameSpendingOverMoreDays() {
        let result = WidgetProjection.snapshot(ledger: ledger(tenDays), goals: [], proActive: false, now: now)
        #expect(result.days.count == WidgetSnapshot.projectedDays)
        // 第一份从写的时刻起，之后每天零点
        #expect(result.days[0].date == now)
        #expect(result.days[1].date == TestSupport.day("2026-10-25"))
        #expect(result.days[29].date == TestSupport.day("2026-11-22"))

        let home = FinancialSnapshot(expenses: tenDays, passiveSources: [], assets: assets(cash: 10_050), now: now,
                                     countsAssets: true)
        #expect(result.days[0].freedom.value == FreedomMath.freedomDaysDisplay(home.freedom))
        #expect(result.days[0].freedom.value == "100")          // 10050 ÷ 100
        #expect(result.days[0].freedom.kicker == "Freedom Days")
        #expect(result.days[0].freedom.caption == "此刻拥有的自由")
        #expect(result.days[0].stats["daily"]?.kicker == "Daily Spend")
        #expect(result.days[0].stats["track"]?.kicker == "Track")
        #expect(result.days[0].stats["daily"]?.value == "100.0")
        #expect(result.days[0].stats["today"]?.value == "100")
        // 明天没记账：同样 1000 摊到 11 天，日均 90.9，自由天数 110；今天花的回到 0
        #expect(result.days[1].freedom.value == "110")
        #expect(result.days[1].stats["daily"]?.value == "90.9")
        #expect(result.days[1].stats["today"]?.value == "0")
        // 看板能选的每一项都有
        #expect(Set(result.days[0].stats.keys) == Set(WidgetProjection.stats.map(\.rawValue)))
    }

    @Test func aRentThatFallsDueIsTakenOffLikeTheAppWouldAfterDeductingIt() {
        let rent = Loan(name: "房租", monthlyAmount: 3000, dueDay: 27, periodsAtStart: 0,
                        startDate: at("2026-10-20"), sortOrder: 0, isOngoing: true)
        let result = WidgetProjection.snapshot(ledger: ledger(tenDays, loans: [rent]), goals: [], proActive: false,
                                               now: now)
        // 10-28 还没打开过 App，房租没扣：推演里当天就要付
        let projected = result.days[4]
        #expect(projected.date == TestSupport.day("2026-10-28"))

        // 那天打开 App：自动扣了 3000（不算日常开销），现金少 3000。首页上的自由天数应该一样
        let payment = Expense(amount: 3000, category: "房租", date: at("2026-10-27"))
        payment.loanID = rent.id
        payment.countsInBurn = false
        let opened = FinancialSnapshot(expenses: tenDays + [payment], passiveSources: [], assets: assets(cash: 7_050),
                                       loans: [rent], now: TestSupport.day("2026-10-28"), countsAssets: true)
        #expect(projected.freedom.value == FreedomMath.freedomDaysDisplay(opened.freedom))
        // 下次固定支出跟着倒数：今天 3 天后，10-26 是 1 天后
        #expect(result.days[0].stats["next"]?.value == "3")
        #expect(result.days[2].stats["next"]?.value == "1")
    }

    @Test func goalsCountDownAndOnlyShowWithPro() {
        let goal = FreedomGoal(name: "GAP", targetDays: 365, deadline: TestSupport.day("2026-11-03"))
        let free = WidgetProjection.snapshot(ledger: ledger(tenDays), goals: [goal], proActive: false, now: now)
        #expect(free.days.allSatisfy { $0.goals.isEmpty })
        #expect(!free.proActive)

        let pro = WidgetProjection.snapshot(ledger: ledger(tenDays), goals: [goal], proActive: true, now: now)
        #expect(pro.proActive)
        let today = pro.days[0].goals[0]
        #expect(today.id == goal.id)
        #expect(today.name == "GAP")
        #expect(today.daysUntil == 10)
        #expect(today.freedomDays == "100")
        #expect(today.targetLine == "距离目标还差 265 天")
        #expect(pro.days[1].goals[0].daysUntil == 9)
        #expect(pro.days[10].goals[0].daysUntil == 0)
        #expect(pro.days[11].goals[0].daysUntil == -1)
    }

    @Test func statesWithoutANumberSayWhatToDo() {
        let empty = WidgetProjection.snapshot(ledger: ledger([], cash: 0), goals: [], proActive: false, now: now)
        #expect(empty.days[0].freedom.state == .pending)
        #expect(empty.days[0].freedom.value == "—")
        #expect(empty.days[0].freedom.caption == "先记下你有多少钱")

        let noSpending = WidgetProjection.snapshot(ledger: ledger([]), goals: [], proActive: false, now: now)
        #expect(noSpending.days[0].freedom.caption == "再记一笔支出")

        let passive = PassiveSource(name: "房租收入", monthlyAmount: 6000)
        var covered = ledger(tenDays)
        covered.passiveSources = [passive]
        let result = WidgetProjection.snapshot(ledger: covered, goals: [], proActive: false, now: now)
        #expect(result.days[0].freedom.state == .covered)
        #expect(result.days[0].freedom.value == "∞")
        #expect(result.days[0].freedom.caption == "你已财富自由")
    }

    // MARK: - 按月记账

    private func monthlyLedger(_ months: [String: Double]) -> WidgetProjection.Ledger {
        var tracking = MonthlyTracking()
        tracking.adopt(startingAt: YearMonth(year: 2026, month: 9), now: at("2026-09-01"))
        tracking.months = months
        var result = ledger(tenDays)
        result.tracking = tracking
        return result
    }

    @Test func monthlyTrackingShowsTheWrittenNumberAndDropsTheRecordStats() {
        let result = WidgetProjection.snapshot(ledger: monthlyLedger(["2026-10": 3000]), goals: [], proActive: true, now: now)
        let today = result.days[0]
        #expect(today.stats["month"]?.value == "3,000")
        #expect(today.stats["month"]?.unit == "元 · 10 月")
        #expect(today.stats["today"] == nil)
        #expect(today.stats["track"] == nil)
        // 日均只看写下的数，不看收起来的记录
        #expect(today.stats["daily"]?.unit == "按 10 月 估算")
        #expect(today.freedom.state == .finite)
    }

    @Test func monthlyTrackingKeepsTheLastWrittenMonthUntilTheNextIsWritten() {
        let result = WidgetProjection.snapshot(ledger: monthlyLedger(["2026-10": 3000]), goals: [], proActive: true, now: now)
        // 11-01 这一份：11 月还没写，仍写 10 月那个数
        let november = result.days[8]
        #expect(november.date == TestSupport.day("2026-11-01"))
        #expect(november.stats["month"]?.value == "3,000")
        #expect(november.stats["month"]?.unit == "元 · 10 月")
    }

    @Test func monthlyTrackingWithNothingWrittenSaysSo() {
        let result = WidgetProjection.snapshot(ledger: monthlyLedger([:]), goals: [], proActive: true, now: now)
        #expect(result.days[0].stats["month"]?.value == "—")
        #expect(result.days[0].stats["month"]?.unit == "还没写")
        #expect(result.days[0].freedom.caption == "写下每月花销")
    }

    // MARK: - 文件

    @Test func theFileReadsBackAndPicksTheRightDay() throws {
        let snapshot = WidgetProjection.snapshot(ledger: ledger(tenDays), goals: [], proActive: true, now: now)
        let data = try WidgetSnapshotFile.encode(snapshot)
        let decoded = try #require(WidgetSnapshotFile.decode(data))
        #expect(decoded == snapshot)

        // 今天晚上还是今天那份，过了零点换明天那份
        #expect(decoded.day(at: now.addingTimeInterval(6 * 3600))?.freedom.value == "100")
        #expect(decoded.day(at: TestSupport.day("2026-10-25").addingTimeInterval(60))?.freedom.value == "110")
        #expect(!decoded.isStale(at: TestSupport.day("2026-11-22").addingTimeInterval(23 * 3600)))
        #expect(decoded.isStale(at: TestSupport.day("2026-11-23")))

        // 以后改了不兼容的格式，旧小组件读到当作没有数据
        var future = snapshot
        future.version = WidgetSnapshot.currentVersion + 1
        #expect(WidgetSnapshotFile.decode(try WidgetSnapshotFile.encode(future)) == nil)
    }

    @Test func rewritingTheSameLedgerALittleLaterIsNotAChange() {
        let first = WidgetProjection.snapshot(ledger: ledger(tenDays), goals: [], proActive: false, now: now)
        let later = WidgetProjection.snapshot(ledger: ledger(tenDays), goals: [], proActive: false,
                                              now: now.addingTimeInterval(600))
        #expect(first.sameContent(as: later))
        // 多记了一笔、换了 Pro，都算变了
        let more = WidgetProjection.snapshot(ledger: ledger(tenDays + [Expense(amount: 5, category: "餐饮", date: now)]),
                                             goals: [], proActive: false, now: now)
        #expect(!first.sameContent(as: more))
        let pro = WidgetProjection.snapshot(ledger: ledger(tenDays), goals: [], proActive: true, now: now)
        #expect(!first.sameContent(as: pro))
        // 第二天再写：每天的日期都往后挪了，要重写
        let tomorrow = WidgetProjection.snapshot(ledger: ledger(tenDays), goals: [], proActive: false,
                                                 now: now.addingTimeInterval(24 * 3600))
        #expect(!first.sameContent(as: tomorrow))
    }

    /// 和用户账本差不多大的账：2311 笔、一年多。离开 App 时算一遍 30 天，不能拖太久
    @Test func aRealSizedLedgerProjectsQuickly() {
        let expenses = (0..<2311).map { index in
            Expense(amount: Double(20 + index % 80), category: "餐饮",
                    date: now.addingTimeInterval(-Double(index) * 4 * 3600))
        }
        let rent = Loan(name: "房租", monthlyAmount: 3000, dueDay: 5, periodsAtStart: 0,
                        startDate: at("2025-08-01"), sortOrder: 0, isOngoing: true)
        let start = Date()
        let result = WidgetProjection.snapshot(ledger: ledger(expenses, cash: 80_000, loans: [rent]),
                                               goals: [FreedomGoal(targetDays: 365)], proActive: true, now: now)
        let elapsed = Date().timeIntervalSince(start)
        print("widget projection: \(Int(elapsed * 1000)) ms for \(result.days.count) days")
        #expect(result.days.count == 30)
        #expect(elapsed < 2)
    }
}
