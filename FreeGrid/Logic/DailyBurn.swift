// 日均消费怎么估：总支出 ÷ 记录天数，多两条——记账不满 90 天时，单笔大额支出按 90 天摊；
// 最后一笔之后超过 14 天没记，多出来的天不再摊薄日均（填了每月估算就按估算补）。
// 没记过日常支出、但填了每月估算时，日均就是估算折成的每天（2.2，用户 2026-10-29 定）。
// 首页、记一笔的影响预览、趋势、History 都从这里拿日均，口径只有一个。

import Foundation

/// 自己填的「每月日常大约花多少」。不记账的人靠它算自由天数，断档时用它补空档。
/// 存在本机偏好里，JSON 备份会带上（见 `BackupEnvelope.monthlyEverydayEstimate`）。
enum EverydayEstimate {
    static let key = "monthlyEverydayEstimate"

    /// 没填、填 0 或不是有效数字时为 nil
    static func monthly(in defaults: UserDefaults) -> Double? {
        valid(defaults.double(forKey: key))
    }

    static var monthly: Double? { monthly(in: AppPreferences.store) }

    static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= FinancialLimits.maximumAmount else { return nil }
        return value
    }
}

extension FreedomMath {
    /// 记账不满这么多天时，大额支出按这么多天摊；记满以后就是「总支出 ÷ 天数」，一分不差
    static let lumpSpreadDays = 90
    /// 单笔达到「平常一天花销」的这么多倍，算大额（大约是平时一个月的花销）
    static let lumpMultiple = 30.0
    /// 最后一笔之后这么多天内照常摊；再往后算断档，不再让日均往下掉
    static let burnGraceDays = 14

    /// 日均是从哪来的；界面上「按估算」的标记看它
    enum BurnBasis: Equatable {
        /// 全按记下的支出
        case records
        /// 没记过日常支出，全按每月估算
        case estimate
        /// 记下的支出加上断档那几天按估算补
        case recordsAndEstimate
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
        let dailyBurn: Double
        /// 这次被摊开算的大额支出加起来是多少；没有摊开时是 0
        let spreadLumps: Double
        var basis: BurnBasis = .records
        /// 断档里没算进记录的天数（最后一笔之后第 15 天起）；没有断档时是 0
        var gapDays = 0
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
    /// 再往后的天不算进记录的分母，日均停住不再往下掉；填了 `monthlyEstimate` 就把这些天按估算补进去。
    /// 停在第 14 天而不是退回最后一笔那天：日均是慢慢停下，不会在第 15 天突然跳一截。
    /// 只看最后一笔之后的空档；中间断过又接着记的，那段照常算（记总账的人中间也是空的）。
    static func burnEstimate(_ entries: [BurnEntry], monthlyEstimate: Double? = nil, now: Date = .now,
                             calendar: Calendar = .current) -> BurnEstimate {
        let estimateDaily = EverydayEstimate.valid(monthlyEstimate).map { $0 / GridUnit.month.daysPerCell }
        guard let lastDate = entries.map(\.date).max() else {
            if let estimateDaily {
                return BurnEstimate(total: 0, firstDate: nil, trackDays: 0, dailyBurn: estimateDaily,
                                    spreadLumps: 0, basis: .estimate)
            }
            return recordedBurn(entries, days: 0, firstDate: nil)
        }
        let firstDate = entries.map(\.date).min()
        let days = trackDays(firstRecordDate: firstDate, now: now, calendar: calendar)
        let sinceLast = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastDate),
                                                to: calendar.startOfDay(for: now)).day ?? 0
        let gap = min(max(0, sinceLast - burnGraceDays), max(0, days - 1))
        // 记录天数照日历算（记账天数卡、自检里程碑用它），只有日均的分母去掉断档
        let recorded = recordedBurn(entries, days: days - gap, firstDate: firstDate, calendar: calendar)
        guard gap > 0, let estimateDaily, recorded.dailyBurn.isFinite else {
            return BurnEstimate(total: recorded.total, firstDate: firstDate, trackDays: days,
                                dailyBurn: recorded.dailyBurn, spreadLumps: recorded.spreadLumps, gapDays: gap)
        }
        let mixed = (recorded.dailyBurn * Double(days - gap) + estimateDaily * Double(gap)) / Double(days)
        return BurnEstimate(total: recorded.total, firstDate: firstDate, trackDays: days, dailyBurn: mixed,
                            spreadLumps: recorded.spreadLumps, basis: .recordsAndEstimate, gapDays: gap)
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
