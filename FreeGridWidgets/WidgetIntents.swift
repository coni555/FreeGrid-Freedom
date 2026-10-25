// 长按小组件「编辑」里能选的：看板放哪两项，目标小组件看哪个目标。

import AppIntents
import WidgetKit

/// 看板能放的数，和首页小卡同一套（今日对比长条、目标卡不在里面）
enum WidgetMetric: String, AppEnum {
    case daily, month, today, track, base, passive, next

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "数字")
    static let caseDisplayRepresentations: [WidgetMetric: DisplayRepresentation] = [
        .daily: "日均消费",
        .month: "本月花销",
        .today: "今日花销",
        .track: "记账天数",
        .base: "可动用资产",
        .passive: "被动收入覆盖率",
        .next: "下次固定支出",
    ]
}

struct DashboardIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "自由看板"
    static let description = IntentDescription("自由天数旁边放哪两项。")

    @Parameter(title: "上面一项", default: .daily)
    var first: WidgetMetric

    @Parameter(title: "下面一项", default: .month)
    var second: WidgetMetric

    init() {}

    init(first: WidgetMetric, second: WidgetMetric) {
        self.first = first
        self.second = second
    }
}

/// 自检里「我的目标」的一个。只认 id 和名字，数从 App 写的那份里取
struct GoalEntity: AppEntity {
    let id: UUID
    let name: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "目标")
    static let defaultQuery = GoalQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct GoalQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [GoalEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [GoalEntity] { all() }

    /// 没选过时看第一个目标
    func defaultResult() async -> GoalEntity? { all().first }

    private func all() -> [GoalEntity] {
        (WidgetSnapshotFile.read()?.days.first?.goals ?? []).map { GoalEntity(id: $0.id, name: $0.name) }
    }
}

struct GoalIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "我的目标"
    static let description = IntentDescription("看哪一个目标。")

    @Parameter(title: "目标")
    var goal: GoalEntity?

    init() {}
}
