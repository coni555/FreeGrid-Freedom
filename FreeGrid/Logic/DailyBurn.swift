// 日均消费怎么估：总支出 ÷ 记录天数，只多一条——记账不满 90 天时，单笔大额支出按 90 天摊。
// 首页、记一笔的影响预览、趋势、History 都从这里拿日均，口径只有一个。

import Foundation

extension FreedomMath {
    /// 记账不满这么多天时，大额支出按这么多天摊；记满以后就是「总支出 ÷ 天数」，一分不差
    static let lumpSpreadDays = 90
    /// 单笔达到「平常一天花销」的这么多倍，算大额（大约是平时一个月的花销）
    static let lumpMultiple = 30.0

    /// 一笔算日均的支出，只留日期和金额：记一笔的预览要把还没保存的那笔也算进去
    struct BurnEntry: Equatable {
        let date: Date
        let amount: Double
    }

    struct BurnEstimate: Equatable {
        let total: Double
        let firstDate: Date?
        let trackDays: Int
        let dailyBurn: Double
        /// 这次被摊开算的大额支出加起来是多少；没有摊开时是 0
        let spreadLumps: Double
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
    static func burnEstimate(_ entries: [BurnEntry], now: Date = .now,
                             calendar: Calendar = .current) -> BurnEstimate {
        let total = entries.reduce(0) { $0 + $1.amount }
        let firstDate = entries.map(\.date).min()
        let days = trackDays(firstRecordDate: firstDate, now: now, calendar: calendar)
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
