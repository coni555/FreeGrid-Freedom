// 日均消费怎么估：总支出 ÷ 记录天数，多两条——记账不满 90 天时，单笔大额支出按 90 天摊；
// 最后一笔之后超过 14 天没记，多出来的天不再摊薄日均。
// 用「按月记账」时日均只看写下的数（见 `MonthlyTracking`），那段时间不算进记录；
// 有记录的人改回逐笔记账就回到切换前；从没记过账的人用 30 天从写下的数过渡到记录，不一下子跳（用户 2026-10-30、31 定）。
// 首页、记一笔的影响预览、趋势、History 都从这里拿日均，口径只有一个。

import Foundation

extension FreedomMath {
    /// 记账不满这么多天时，大额支出按这么多天摊；记满以后就是「总支出 ÷ 天数」，一分不差
    static let lumpSpreadDays = 90
    /// 单笔达到「平常一天花销」的这么多倍，算大额（大约是平时一个月的花销）
    static let lumpMultiple = 30.0
    /// 最后一笔之后这么多天内照常摊；再往后算断档，不再让日均往下掉
    static let burnGraceDays = 14
    /// 从没记过账的人改回逐笔记账后，用这么多天从写下的数过渡到记录；记账没跨满这么多天又断档的，不给大数字
    static let estimateBlendDays = 30

    /// 日均是从哪来的
    enum BurnBasis: Equatable {
        /// 全按记下的支出
        case records
        /// 全按每月写下的数
        case estimate
        /// 从没记过账的人刚改回逐笔记账，还在从写下的数过渡到记录
        case recordsAndEstimate
    }

    /// 从没记过账的人改回逐笔记账时的过渡：`everyday` 是写下的数扣掉固定支出后的日常部分，从 `from` 这天起过渡
    struct EstimateBlend: Equatable {
        let everyday: Double
        let from: Date
    }

    /// 一笔算日均的支出，只留日期和金额：记一笔的预览要把还没保存的那笔也算进去
    struct BurnEntry: Equatable {
        let date: Date
        let amount: Double
    }

    struct BurnEstimate: Equatable {
        let total: Double
        let firstDate: Date?
        let trackDays: Int
        var dailyBurn: Double
        /// 这次被摊开算的大额支出加起来是多少；没有摊开时是 0
        var spreadLumps: Double
        var basis: BurnBasis = .records
        /// 断档里没算进记录的天数（最后一笔之后第 15 天起）；没有断档时是 0
        var gapDays = 0
        /// 记账没跨满 30 天就断档了：这点记录算不准，首页不给大数字
        var recordsTooFew = false
    }

    /// 为什么要摊：头几周交一次电脑钱，原来的算法把它当成每天都在花，日均能翻十倍，
    /// 第二天再看又慢慢掉回来。大额支出隔多久来一次，几周的账看不出来，先当它三个月来一次。
    ///
    /// 一笔算大额：比「平常一天」多 30 倍（大约是平时一个月的花销）。「平常一天」是有花销的那些天、
    /// 每天合计的中位数。一周或一个月才记一次总账的人，每次记的都是「平常」，不会被当成大额；
    /// 只有两天的账时中位数是两天的平均，谁也不会被当成大额。
    ///
    /// 没把房租设成固定支出、当普通支出记的：每个月那一笔都算大额，都按 90 天摊，
    /// 日均每交一次涨一小截，第三次交完（约第 60 多天）就和真实的一样，中间不会忽高忽低。
    /// （试过再加一条「也要比其余支出的日均大 30 倍」，第二次交租时第一笔会被「认回来」，日均从 88 跳到 195。）
    /// 不摊平日的小钱：前 90 天的日常开销照实算，新用户的日均不会被压低。
    ///
    /// 断档：最后一笔之后的头 14 天照常摊（一周、一个月记一次总账的人，中间几天本来就空着），
    /// 再往后的天不算进记录的分母，日均停住不再往下掉。
    /// 停在第 14 天而不是退回最后一笔那天：日均是慢慢停下，不会在第 15 天突然跳一截。
    /// 只看最后一笔之后的空档；中间断过又接着记的，那段照常算（记总账的人中间也是空的）。
    ///
    /// `pauses`：用按月记账的那些天既不算记账，也不算花了 0 元，从天数里去掉。
    ///
    /// `blend`：只写过数的人开始记账，一天的账代表不了日均（记一笔 20 元，日均不该从 98 变 20）。
    /// 从改回那天（那之后才记第一笔的，从第一笔那天）起算第 n 天，记录占 n/30，写下的数占其余；满 30 天全按记录。
    static func burnEstimate(_ entries: [BurnEntry], pauses: [MonthlyTracking.Pause] = [], blend: EstimateBlend? = nil,
                             now: Date = .now, calendar: Calendar = .current) -> BurnEstimate {
        // 趋势往回算时，改回之前的日子不过渡
        let blend = blend.flatMap { $0.everyday.isFinite && $0.everyday >= 0
            && calendar.startOfDay(for: now) >= calendar.startOfDay(for: $0.from) ? $0 : nil }
        let estimateDaily = blend.map { $0.everyday / GridUnit.month.daysPerCell }
        guard let lastDate = entries.map(\.date).max() else {
            if let estimateDaily {
                return BurnEstimate(total: 0, firstDate: nil, trackDays: 0, dailyBurn: estimateDaily,
                                    spreadLumps: 0, basis: .estimate)
            }
            return recordedBurn(entries, days: 0, firstDate: nil)
        }
        let firstDate = entries.map(\.date).min() ?? lastDate
        let days = max(1, trackDays(firstRecordDate: firstDate, now: now, calendar: calendar)
            - pausedDays(pauses, from: firstDate, to: now, calendar: calendar))
        let sinceLast = dayCount(from: lastDate, to: now, calendar: calendar)
            - pausedDays(pauses, from: lastDate, to: now, calendar: calendar)
        let gap = min(max(0, sinceLast - burnGraceDays), max(0, days - 1))
        let loggedDays = dayCount(from: firstDate, to: lastDate, calendar: calendar)
            - pausedDays(pauses, from: firstDate, to: lastDate, calendar: calendar) + 1
        // 记录天数照日历算（记账天数卡、自检里程碑用它），只有日均的分母去掉断档
        let recorded = recordedBurn(entries, days: days - gap, firstDate: firstDate, calendar: calendar)
        if let blend, let estimateDaily, recorded.dailyBurn.isFinite {
            let start = max(calendar.startOfDay(for: blend.from), calendar.startOfDay(for: firstDate))
            let elapsed = max(1, dayCount(from: start, to: now, calendar: calendar) + 1)
            if elapsed < estimateBlendDays {
                let share = Double(elapsed) / Double(estimateBlendDays)
                return BurnEstimate(total: recorded.total, firstDate: firstDate, trackDays: days,
                                    dailyBurn: recorded.dailyBurn * share + estimateDaily * (1 - share),
                                    spreadLumps: recorded.spreadLumps, basis: .recordsAndEstimate, gapDays: gap)
            }
        }
        return BurnEstimate(total: recorded.total, firstDate: firstDate, trackDays: days,
                            dailyBurn: recorded.dailyBurn, spreadLumps: recorded.spreadLumps, gapDays: gap,
                            recordsTooFew: gap > 0 && loggedDays < estimateBlendDays)
    }

    /// 按记账方式算日均。按月记账时日均只看写下的数，记录那边的天数和总额留着（记账里程碑暂停在原处）
    static func burnEstimate(_ entries: [BurnEntry], tracking: MonthlyTracking, fixedMonthly: Double, now: Date = .now,
                             calendar: Calendar = .current) -> BurnEstimate {
        let everyday = tracking.everyday(fixedMonthly: fixedMonthly)
        var blend: EstimateBlend?
        if !tracking.isMonthly, let everyday, let from = tracking.switchedBackAt {
            blend = EstimateBlend(everyday: everyday, from: from)
        }
        var burn = burnEstimate(entries, pauses: tracking.pauses, blend: blend, now: now, calendar: calendar)
        if tracking.isMonthly {
            burn.dailyBurn = everyday.map { $0 / GridUnit.month.daysPerCell } ?? .nan
            burn.basis = .estimate
            burn.spreadLumps = 0
            burn.gapDays = 0
            burn.recordsTooFew = false
        }
        return burn
    }

    private static func dayCount(from: Date, to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    /// `from`…`to` 之间有多少天落在这些暂停里。切换的当天还算记账：切过去那天和切回来那天都不去掉
    private static func pausedDays(_ pauses: [MonthlyTracking.Pause], from: Date, to: Date, calendar: Calendar) -> Int {
        pauses.reduce(0) { total, pause in
            let start = max(pause.start, from)
            if let end = pause.end, end <= to {
                return start < end ? total + max(0, dayCount(from: start, to: end, calendar: calendar) - 1) : total
            }
            return start < to ? total + max(0, dayCount(from: start, to: to, calendar: calendar)) : total
        }
    }

    /// 只看记下的支出：总支出 ÷ `days`，不满 90 天时大额按 90 天摊
    private static func recordedBurn(_ entries: [BurnEntry], days: Int, firstDate: Date?,
                                     calendar: Calendar = .current) -> BurnEstimate {
        let total = entries.reduce(0) { $0 + $1.amount }
        let plain = dailyBurn(totalExpenses: total, trackDays: days)
        guard days > 0, days < lumpSpreadDays, plain.isFinite else {
            return BurnEstimate(total: total, firstDate: firstDate, trackDays: days, dailyBurn: plain, spreadLumps: 0)
        }

        var byDay: [Date: Double] = [:]
        for entry in entries { byDay[calendar.startOfDay(for: entry.date), default: 0] += entry.amount }
        let spendingDays = byDay.values.filter { $0 > 0 }.sorted()
        guard !spendingDays.isEmpty else {
            return BurnEstimate(total: total, firstDate: firstDate, trackDays: days, dailyBurn: plain, spreadLumps: 0)
        }
        let middle = spendingDays.count / 2
        let usualDay = spendingDays.count.isMultiple(of: 2)
            ? (spendingDays[middle - 1] + spendingDays[middle]) / 2 : spendingDays[middle]
        let threshold = usualDay * lumpMultiple
        let lumps = entries.reduce(0) { $1.amount >= threshold ? $0 + $1.amount : $0 }
        guard lumps > 0 else {
            return BurnEstimate(total: total, firstDate: firstDate, trackDays: days, dailyBurn: plain, spreadLumps: 0)
        }
        let burn = (total - lumps) / Double(days) + lumps / Double(lumpSpreadDays)
        return BurnEstimate(total: total, firstDate: firstDate, trackDays: days, dailyBurn: burn, spreadLumps: lumps)
    }

    static func burnEntries(_ expenses: [Expense]) -> [BurnEntry] {
        expenses.compactMap { $0.countsInBurn ? BurnEntry(date: $0.date, amount: $0.amount) : nil }
    }
}
