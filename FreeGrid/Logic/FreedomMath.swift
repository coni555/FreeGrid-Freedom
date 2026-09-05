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
    static func trackDays(firstRecordDate: Date?, now: Date = .now) -> Int {
        guard let firstDate = firstRecordDate else { return 0 }
        let calendar = Calendar.current
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
    static func gridState(for state: FreedomState, lockedAssets: Double, netWorth: Double,
                          unit fixedUnit: GridUnit? = nil) -> GridState {
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
        return GridState(unit: unit, count: count, assetCells: split.assets,
                         cashCells: split.cash, isOverflow: overflow)
    }

    // ============================================================================
    // MARK: - 历史趋势 (sparkline + delta + 见底日期)
    // ============================================================================
    // 设计动机: hero card 里展示"过去 12 周自由天数走势"——一条 sparkline +
    // delta badge (▲ +22d) + 见底日期。让用户看到自己是在"赎回自由"
    // 还是"消耗自由",而不只看今天的数字。
    //
    // 数据反推:
    // - 当前没有存 freedomDays 的历史 snapshot。
    // - 反向计算: 取每周末日期,反推那时的 expenses / incomes / assets
    //   (assets 用 current + 后续 net 变动反推, 假设 dataset 完整且 user
    //    没手动调过 assets baseline——足够 sparkline 视觉趋势准确)
    //
    // 边界:
    // - 如果 trackDays < 14 天,数据不够,返回空
    // - 如果 trackDays 在 14~84 天之间,返回 trackDays/7 个点
    // - 如果 ≥ 84 天 (12 周),返回 12 个点

    /// 单个历史 snapshot
    struct HistoryPoint {
        let date: Date
        let freedomDays: Double
    }

    /// 反推过去 N 周末日的 freedomDays
    /// currentNetWorth = lockedAssets + cash
    /// dailyPassive: 当前被动收入日均。历史快照都用当前值近似 — PassiveSource 没存历史
    /// 时间戳, 简化模型 "假设当时也有这些被动"。被动覆盖时 sparkline 都会显示 0 或满,
    /// 反而把"净值是否在涨"暴露得更直观。
    static func freedomDaysHistory(
        expenses: [Expense],
        incomes: [Income],
        currentNetWorth: Double,
        firstRecordDate: Date?,
        dailyPassive: Double = 0,
        weeks: Int = 12
    ) -> [HistoryPoint] {
        guard let firstDate = firstRecordDate,
              currentNetWorth.isFinite,
              dailyPassive.isFinite,
              dailyPassive >= 0,
              // 只挡非有限数。旧账本的退款/冲正是合法负数支出(schema v3 会原样承接),
              // 用 >= 0 挡会让这类用户的走势图整块消失,而不是显示净额趋势。
              expenses.allSatisfy({ $0.amount.isFinite }),
              incomes.allSatisfy({ $0.amount.isFinite }) else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let trackedDays = cal.dateComponents([.day], from: firstDate, to: today).day ?? 0
        guard trackedDays >= 14 else { return [] }

        let availableWeeks = min(weeks, trackedDays / 7)
        var snapshots: [HistoryPoint] = []

        for i in (0...availableWeeks).reversed() {
            guard let weekEnd = cal.date(byAdding: .day, value: -7 * i, to: today) else { continue }
            if weekEnd < firstDate { continue }

            // +1 跟 Hero 的 trackDays(today − first + 1)同口径 —— 含端点当天,
            // 否则分母少 1 天、dailyBurn 微高, sparkline 终点会比 Hero 大数字少 1。
            let trackDays_i = max(1, (cal.dateComponents([.day], from: firstDate, to: weekEnd).day ?? 1) + 1)

            // 关键:交易按"自然日"归属, 不看具体时间戳。
            // weekEnd 是某天的 00:00;若用裸 date 比较, 当天白天发生的交易(时间戳 > 00:00)
            // 会被误判成"weekEnd 之后", 在终点(weekEnd = 今天)那步, 今天到账的收入被当成
            // "今天之后"从 incAfter 减掉 → 终点净值塌陷, sparkline 终点 ≠ Hero 大数字。
            // 用 startOfDay 比较, 把"今天"完整算进 expUntil/此刻净值, 终点就跟 Hero 对齐。
            let dayOf: (Date) -> Date = { cal.startOfDay(for: $0) }
            let expUntil = expenses.filter { dayOf($0.date) <= weekEnd }.reduce(0) { $0 + $1.amount }
            let dailyBurn_i = expUntil / Double(trackDays_i)

            // 反推那时的净值 = 当前净值 + 之后支出 - 之后收入(均按自然日)
            let expAfter = expenses.filter { dayOf($0.date) > weekEnd }.reduce(0) { $0 + $1.amount }
            let incAfter = incomes.filter { dayOf($0.date) > weekEnd }.reduce(0) { $0 + $1.amount }
            let netWorth_i = currentNetWorth + expAfter - incAfter

            let netBurn_i = max(0, dailyBurn_i - dailyPassive)
            let days_i: Double
            if netBurn_i > 0 {
                days_i = max(0, netWorth_i) / netBurn_i
            } else if dailyBurn_i > 0 {
                // 被动覆盖, 显示 cap 数字让 sparkline 不爆掉(用 1825 = 5 年作 upper bound)
                days_i = 1825
            } else {
                days_i = 0
            }

            snapshots.append(HistoryPoint(date: weekEnd, freedomDays: days_i))
        }

        return snapshots
    }

    /// 给定 history,算 12-week-ago vs 当前的 delta
    /// 返回 (起点天数, 终点天数, delta 天数)
    static func deltaSummary(history: [HistoryPoint]) -> (start: Int, end: Int, delta: Int)? {
        guard let first = history.first, let last = history.last,
              history.count >= 2 else { return nil }
        // 向下取整, 跟 Hero freedomDaysDisplay / Grid 一致(避免 sparkline 起终点又四舍五入裂开)
        guard let s = FinancialFormatting.integer(first.freedomDays.rounded(.down)),
              let e = FinancialFormatting.integer(last.freedomDays.rounded(.down)) else {
            return nil
        }
        return (s, e, e - s)
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
}
