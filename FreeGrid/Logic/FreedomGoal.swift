// 自己的目标（Pro）：想要多少天自由，加一个可选的截止日，个数不限。
// 直接和首页的自由天数比：现在多少、还差多少，一眼看出差距；定了日子再倒数还有几天。不按收入往后推算。
// 目标存在本机偏好里（JSON），不进备份。

import Foundation

struct FreedomGoal: Codable, Equatable, Identifiable {
    var id = UUID()
    /// 自己起的名字，可以空着
    var name: String = ""
    /// 想要多少天自由
    var targetDays: Int
    /// 在哪天之前；nil 表示不设日子
    var deadline: Date?

    var isValid: Bool { targetDays > 0 }

    /// 没起名字时叫「攒够一年」
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        // 「攒够一年」；自己填的天数是「攒够 100 天」，数字前后要空格
        return Self.targetChoices.contains(targetDays) ? String(localized: "攒够\(Self.targetName(targetDays))")
                                                       : String(localized: "攒够 \(targetDays) 天")
    }

    /// 「想要多少天自由」的三档：半年、一年、两年；也可以自己填
    static let targetChoices = [183, 365, 730]
    /// 名字的几个备选
    static var nameSuggestions: [String] {
        [String(localized: "应急金"), "GAP", String(localized: "辞职"), String(localized: "毕业旅行")]
    }

    /// 「一年」「半年」这样的说法；不是三档之一时写天数
    static func targetName(_ days: Int) -> String {
        switch days {
        case 183: return String(localized: "半年")
        case 365: return String(localized: "一年")
        case 730: return String(localized: "两年")
        default: return String(localized: "\(days) 天")
        }
    }
}

/// 目标存成一串 JSON，放在本机偏好里
enum FreedomGoalStore {
    static let key = "freedomGoals"

    /// 读不出来的、天数不对的跳过
    static func decode(_ stored: String) -> [FreedomGoal] {
        guard let data = stored.data(using: .utf8),
              let goals = try? JSONDecoder().decode([FreedomGoal].self, from: data) else { return [] }
        return goals.filter(\.isValid)
    }

    static func encode(_ goals: [FreedomGoal]) -> String {
        guard !goals.isEmpty, let data = try? JSONEncoder().encode(goals) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// 改了就替换，新的加在最后
    static func saving(_ goal: FreedomGoal, into goals: [FreedomGoal]) -> [FreedomGoal] {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return goals + [goal] }
        var result = goals
        result[index] = goal
        return result
    }
}

/// 一个目标和首页自由天数比的结果
struct FreedomGoalProgress: Equatable {
    let goal: FreedomGoal
    /// 首页的自由天数
    let freedom: FreedomState
    /// 离那天还有几天；0 是今天，负数是已经过了；没定日子时为 nil
    let daysUntil: Int?

    init(goal: FreedomGoal, snapshot: FinancialSnapshot, calendar: Calendar = .current) {
        self.goal = goal
        freedom = snapshot.freedom
        daysUntil = goal.deadline.map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: snapshot.now),
                                    to: calendar.startOfDay(for: $0)).day ?? 0
        }
    }

    /// 现在的自由天数占目标多少，0...1；算不出来时为 nil
    var progress: Double? {
        switch freedom {
        case .covered: return 1
        case .finite(let days): return min(1, max(0, days / Double(goal.targetDays)))
        case .insufficientData, .invalidData: return nil
        }
    }

    /// 够了；算不出来时为 nil
    var enough: Bool? { progress.map { $0 >= 1 } }

    /// 自由天数取整，不写小数；被动收入盖住开销时是 nil
    var freedomDaysText: String? {
        guard case .finite(let days) = freedom else { return nil }
        return FinancialFormatting.wholeNumber(max(0, days).rounded(.down))
    }

    /// 还差多少天自由；够了或算不出来时为 nil
    var shortText: String? {
        guard enough == false, case .finite(let days) = freedom else { return nil }
        return FinancialFormatting.wholeNumber((Double(goal.targetDays) - days).rounded(.up))
    }

    /// 「现在 341 / 365 天」
    var freedomLine: String {
        switch freedom {
        case .covered: return String(localized: "被动收入已经盖住开销")
        case .insufficientData, .invalidData: return String(localized: "记下支出、算出日均后才能算")
        case .finite: return String(localized: "现在 \(freedomDaysText ?? "0") / \(goal.targetDays) 天")
        }
    }

    /// 进度条旁边：「已达成」或「还差 24 天自由」
    var targetLine: String? {
        if enough == true { return String(localized: "已达成") }
        return shortText.map { String(localized: "还差 \($0) 天自由") }
    }

    /// 一句话的倒数：「GAP · 189 天后」，留给锁屏小组件这种只放得下一行的地方
    var countdownLine: String? {
        guard let daysUntil else { return nil }
        let name = goal.displayName
        if daysUntil > 0 { return String(localized: "\(name) · \(daysUntil) 天后") }
        if daysUntil == 0 { return String(localized: "\(name) · 就是今天") }
        return String(localized: "\(name) · 这一天已经过了")
    }
}
