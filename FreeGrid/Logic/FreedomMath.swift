// 自由天数、追踪区间、网格数量和趋势估算的计算规则。

import Foundation

enum FreedomState: Equatable {
    case insufficientData
    case covered
    case finite(days: Double)
    case invalidData
}

// ============================================================================
// MARK: - FreedomMath (业务计算工具集)
// ============================================================================
// 无状态计算，首页和交易预览共用。

enum FreedomMath {

    // ===== 基础计量 =====

    /// 最早支出日期是追踪基线；收入和资产录入不启动自由天数计算。
    static func earliestExpenseDate(_ expenses: [Expense]) -> Date? {
        expenses.map(\.date).min()
    }

    /// 记录天数 = 今天 − 最早支出日期 + 1。没有支出或基线在未来时返回 0。
    static func trackDays(firstRecordDate: Date?, now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let firstDate = firstRecordDate else { return 0 }
        let start = calendar.startOfDay(for: firstDate)
        let end = calendar.startOfDay(for: now)
        guard let days = calendar.dateComponents([.day], from: start, to: end).day,
              days >= 0 else {
            return 0
        }
        return days + 1
    }

    /// 日均消费 = 总支出 ÷ 记录天数
    static func dailyBurn(totalExpenses: Double, trackDays: Int) -> Double {
        guard totalExpenses.isFinite, totalExpenses >= 0, trackDays > 0 else { return .nan }
        return totalExpenses / Double(trackDays)
    }

    /// 日均被动收入 = Σ(月被动收入 ÷ 30)
    static func dailyPassive(sources: [PassiveSource]) -> Double {
        sources.reduce(0) { $0 + $1.monthlyAmount / 30 }
    }

    /// 被动覆盖率 = 日均被动 ÷ 日均消费(≥ 1.0 即财务自由)
    static func passiveRatio(dailyPassive: Double, dailyBurn: Double) -> Double {
        guard dailyPassive.isFinite, dailyPassive >= 0,
              dailyBurn.isFinite, dailyBurn > 0 else { return 0 }
        let ratio = dailyPassive / dailyBurn
        return ratio.isFinite ? ratio : 0
    }

    // ===== 核心: 自由天数 =====

    /// 自由天数 = 净值 / 净每日消耗
    /// 净每日消耗 = max(0, 日均消费 − 日均被动收入)
    ///
    /// 设计动机: 被动收入是"不工作也有的钱", 它的本质就是让你不必动用净值。
    /// 当被动覆盖率 ≥ 100%, 净值不被消耗 → 自由天数 = ∞ (永远自由)。
    /// 把被动收入排除在自由天数之外, 等于让"被动覆盖率"沦为装饰指标, 跟核心数字脱钩。
    static func freedomState(
        netWorth: Double,
        dailyBurn: Double,
        dailyPassive: Double = 0,
        hasExpenses: Bool
    ) -> FreedomState {
        guard hasExpenses else { return .insufficientData }
        guard netWorth.isFinite, dailyBurn.isFinite, dailyPassive.isFinite,
              dailyBurn >= 0, dailyPassive >= 0 else {
            return .invalidData
        }
        guard dailyBurn > 0 else { return .invalidData }
        guard dailyPassive < dailyBurn else { return .covered }

        let days = max(0, netWorth) / (dailyBurn - dailyPassive)
        guard days.isFinite else { return .invalidData }
        return .finite(days: days)
    }

    /// 自由天数格式化:三档无后缀(单位由 hero KickerLabel 承载)
    static func freedomDaysDisplay(_ state: FreedomState) -> String {
        switch state {
        case .insufficientData, .invalidData:
            return "—"
        case .covered:
            return "∞"
        case .finite(let days):
            return freedomDaysDisplay(days)
        }
    }

    static func freedomDaysDisplay(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return value.isInfinite ? "∞" : "—" }
        let unit = gridUnit(for: .finite(days: value))
        let count = value / unit.daysPerCell
        return unit == .year ? String(format: "%.1f", count)
            : FinancialFormatting.wholeNumber(count.rounded(.down))
    }

    /// 预览必须带上单位；首页大数字仍由 freedomDaysDisplay 提供裸数字。
    static func freedomDescription(_ state: FreedomState) -> String {
        guard case .finite = state else { return freedomDaysDisplay(state) }
        return "\(freedomDaysDisplay(state)) \(gridUnit(for: state).label)"
    }

    // ============================================================================
    // MARK: - 生命网格(自适应单位:日/月/年)
    // ============================================================================
    // 设计动机: 把"自由天数"这个抽象数字,可视化为格子。
    // 颗粒度随自由度自适应升级——
    //   < 1 年 (< 365 天):   日格 (每格 1 天, 最多 365)
    //   1-10 年 (365-3649): 月格 (每格 1 月, 最多 120 = 10 年)
    //   ≥ 10 年 (≥ 3650):   年格 (每格 1 年, 最多 99)
    // 跟 hero 数字单位切换同步,UI 在数字 + grid 两层一起做维度提升。

    /// Grid 颗粒度档位
    enum GridUnit: Equatable {
        case day, month, year

        var daysPerCell: Double {
            switch self {
            case .day: return 1
            case .month: return 30.44
            case .year: return 365.25
            }
        }

        /// 单档上限(超过即升档,或在年档 cap 99)
        var maxCells: Int {
            switch self {
            case .day: return 365
            case .month: return 120     // 10 年
            case .year: return 99
            }
        }

        /// 中文单位标签
        var label: String {
            switch self {
            case .day: return "天"
            case .month: return "月"
            case .year: return "年"
            }
        }
    }

    struct GridState {
        let unit: GridUnit
        let count: Int
        /// 资产格子数（金色）
        let assetCells: Int
        /// 现金格子数（蓝色）
        let cashCells: Int
        let isOverflow: Bool
        /// 还款日落在的格子（从 0 数）。只在按天显示时有，最后一格（正在呼吸的那格）不算
        var paymentCells: Set<Int> = []
        /// 钱撑不到下一次还款：最后一格后面补一个淡色带孔的格子。只在按天显示时有
        var showsMissedPayment = false
    }

    static func gridUnit(for state: FreedomState) -> GridUnit {
        switch state {
        case .covered: return .year
        case .finite(let days) where days >= 3650: return .year
        case .finite(let days) where days >= 365: return .month
        case .finite, .insufficientData, .invalidData: return .day
        }
    }

    static func gridState(lockedAssets: Double, cash: Double, dailyBurn: Double, dailyPassive: Double = 0) -> GridState {
        let state = freedomState(netWorth: lockedAssets + cash, dailyBurn: dailyBurn,
                                 dailyPassive: dailyPassive, hasExpenses: true)
        return gridState(for: state, lockedAssets: lockedAssets, netWorth: lockedAssets + cash)
    }

    /// 模拟动画可传入固定档位，让操作前后的格子始终表示相同的单位。
    /// `paymentDays` 是推演里扣月供的那几天（明天是 1），第 n 天对应第 n 格。
    static func gridState(for state: FreedomState, lockedAssets: Double, netWorth: Double,
                          unit fixedUnit: GridUnit? = nil, paymentDays: [Int] = [],
                          missedPaymentDay: Int? = nil) -> GridState {
        let unit = fixedUnit ?? gridUnit(for: state)
        let count: Int
        let overflow: Bool
        switch state {
        case .covered:
            count = unit.maxCells
            overflow = true
        case .finite(let days):
            count = FinancialFormatting.gridCount(days: days, divisor: unit.daysPerCell, maximum: unit.maxCells)
            overflow = days / unit.daysPerCell > Double(unit.maxCells)
        case .insufficientData, .invalidData:
            count = 0
            overflow = false
        }
        let split = FinancialFormatting.assetCellSplit(count: count, lockedAssets: lockedAssets, netWorth: netWorth)
        let paymentCells = unit == .day
            ? Set(paymentDays.filter { $0 >= 1 && $0 < count }.map { $0 - 1 })
            : []
        return GridState(unit: unit, count: count, assetCells: split.assets,
                         cashCells: split.cash, isOverflow: overflow, paymentCells: paymentCells,
                         showsMissedPayment: unit == .day && count > 0 && !overflow && missedPaymentDay != nil)
    }

    /// 当前自由耗尽的预计日期 (今天 + freedomDays 天)
    /// 返回 nil 表示 ∞ 或没数据
    static func depleteDate(freedomDays: Double) -> Date? {
        guard freedomDays.isFinite, freedomDays > 0, freedomDays < 1825 * 5,
              let days = FinancialFormatting.integer(
                freedomDays,
                rounded: .toNearestOrAwayFromZero
              ) else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: .now)
    }

    /// 首页「大约撑到 …」的日期：今年之内只写月日，跨年写上年份，免得把明年 9 月读成今年 9 月
    static func depleteDateText(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "M 月 d 日" : "yyyy 年 M 月 d 日"
        return f.string(from: date)
    }
}
