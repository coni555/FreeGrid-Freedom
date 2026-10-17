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
    /// 一笔算大额，要同时比这两样多 30 倍（大约是平时一个月的花销）：
    /// - 「平常一天」：有花销的那些天，每天合计的中位数。一周或一个月才记一次总账的人，
    ///   每次记的都是「平常」，不会被当成大额；只有两天的账时中位数是两天的平均，谁也不会被当成大额。
    /// - 其余支出的日均：每周一次的买菜钱比每天的咖啡大得多，但放进整本账里不算大。
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
        // 从最大的往下看：摊开一笔，剩下的日均就小一些，下一笔照同样的标准再比
        var lumps = 0.0
        for amount in entries.map(\.amount).sorted(by: >) {
            let othersDaily = (total - lumps - amount) / Double(days)
            guard amount >= usualDay * lumpMultiple, amount >= othersDaily * lumpMultiple else { break }
            lumps += amount
        }
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
