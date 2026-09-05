//
//  FinancialFormatting.swift
//  FreeGrid
//
//  持久化与导入数值进入 Int、百分比和 Grid 前的统一安全边界。
//

import Foundation

enum FinancialFormatting {
    /// 金额的共用显示入口；非法数值不显示成 ¥NaN / ¥∞。
    static func yuan(_ value: Double, precision: Int? = nil) -> String {
        guard value.isFinite else { return "—" }
        let digits = precision.map { $0...$0 } ?? 0...2
        return "¥" + value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func signedYuan(_ value: Double, precision: Int? = nil) -> String {
        guard value.isFinite else { return "—" }
        let sign = value > 0 ? "+" : value < 0 ? "−" : ""
        return sign + yuan(abs(value), precision: precision)
    }

    /// 增减量一直用天，不随首页的日/月/年档切换，也不显示 −0 天。
    static func daysChange(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if value == 0 { return "0 天" }
        let sign = value > 0 ? "+" : "−"
        let rounded = abs(value).rounded()
        if rounded == 0 { return "\(sign)不足 1 天" }
        return "\(sign)\(wholeNumber(rounded)) 天"
    }

    static func validAmount(_ value: Double, allowsZero: Bool = false) -> Bool {
        guard value.isFinite, value <= FinancialLimits.maximumAmount else { return false }
        return allowsZero ? value >= 0 : value > 0
    }

    static func integer(
        _ value: Double,
        rounded rule: FloatingPointRoundingRule = .towardZero
    ) -> Int? {
        guard value.isFinite else { return nil }
        let rounded = value.rounded(rule)
        guard rounded >= Double(Int.min), rounded < Double(Int.max) else { return nil }
        if rounded == Double(Int.min) { return Int.min }
        return Int(rounded)
    }

    static func clampedInteger(
        _ value: Double,
        range: ClosedRange<Int>,
        rounded rule: FloatingPointRoundingRule = .towardZero
    ) -> Int {
        guard value.isFinite else { return range.lowerBound }
        let rounded = value.rounded(rule)
        if rounded <= Double(range.lowerBound) { return range.lowerBound }
        if rounded >= Double(range.upperBound) { return range.upperBound }
        return Int(rounded)
    }

    static func wholeNumber(_ value: Double, fallback: String = "—") -> String {
        guard value.isFinite else { return fallback }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    static func percentage(_ ratio: Double, maximum: Int = 9_999) -> String {
        guard ratio.isFinite, ratio >= 0, maximum >= 0 else { return "—" }
        if ratio >= Double(maximum) / 100 { return "\(maximum)%" }
        let value = clampedInteger(
            ratio * 100,
            range: 0...maximum,
            rounded: .toNearestOrAwayFromZero
        )
        return "\(value)%"
    }

    static func gridCount(days: Double, divisor: Double, maximum: Int) -> Int {
        guard divisor > 0 else { return 0 }
        return clampedInteger(days / divisor, range: 0...maximum)
    }

    static func assetCellSplit(count: Int, lockedAssets: Double, netWorth: Double) -> (assets: Int, cash: Int) {
        guard count > 0, lockedAssets.isFinite, netWorth.isFinite, netWorth > 0 else {
            return (0, max(0, count))
        }
        let ratio = min(max(max(0, lockedAssets) / netWorth, 0), 1)
        let assets = clampedInteger(
            Double(count) * ratio,
            range: 0...count,
            rounded: .toNearestOrAwayFromZero
        )
        return (assets, count - assets)
    }
}
