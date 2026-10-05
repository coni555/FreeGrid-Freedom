import SwiftUI
import SwiftData
import Charts

struct FreedomHistoryView: View {
    @Query(sort: \FreedomObservation.sequence) private var entries: [FreedomObservation]
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @Query private var assets: [UserAssets]
    @Query private var passives: [PassiveSource]
    @State private var archive: UUID?
    @State private var metric = 0
    @State private var days = 30
    @State private var selected: UUID?

    private var archiveIDs: [UUID] {
        Array(Set(entries.filter(\.isImported).map(\.seriesID))).sorted { $0.uuidString < $1.uuidString }
    }
    private var values: [ObservationValue] {
        entries.filter { archive == nil ? !$0.isImported : $0.isImported && $0.seriesID == archive }
            .map(\.value).filter { days == 0 || $0.recordedAt >= Date.now.addingTimeInterval(-Double(days) * 86400) }
    }
    private var points: [ObservationValue] { ObservationHistory.dailyPoints(values) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("保存当时账本的状态。补录或调整不会改写先前记录；金额以你的账本为准。")
                    .font(.callout).foregroundStyle(Color.inkMuted)
                if !archiveIDs.isEmpty {
                    Picker("记录来源", selection: $archive) {
                        Text("本机记录").tag(nil as UUID?)
                        ForEach(archiveIDs, id: \.self) { id in
                            Text("备份记录 · \(id.uuidString.prefix(6))").tag(Optional(id))
                        }
                    }
                }
                Picker("时间范围", selection: $days) {
                    Text("近 30 天").tag(30)
                    Text("近 90 天").tag(90)
                    Text("全部").tag(0)
                }.pickerStyle(.segmented)
                Picker("指标", selection: $metric) {
                    Text("自由天数").tag(0)
                    Text("账本净值").tag(1)
                }.pickerStyle(.segmented)

                if let first = values.first, let last = values.last {
                    VaultCard {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text("\(first.recordedAt.formatted(date: .abbreviated, time: .omitted)) → \(last.recordedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(Color.inkMuted)
                            Text(metric == 0 ? "\(first.freedomDescription) → \(last.freedomDescription)"
                                 : "\(FinancialFormatting.yuan(first.netWorth)) → \(FinancialFormatting.yuan(last.netWorth))")
                                .font(.headline).textSelection(.enabled)
                            Chart(points) { point in
                                if metric == 1 {
                                    PointMark(x: .value("记录日期", point.recordedAt), y: .value("净值", point.netWorth))
                                        .foregroundStyle(Color.skyDeep)
                                } else if case .finite(let amount) = point.freedom {
                                    PointMark(x: .value("记录日期", point.recordedAt), y: .value("自由天数", amount))
                                        .foregroundStyle(Color.skyDeep)
                                }
                            }.frame(height: 170)
                            Text("每个点为当天最后记录；没有记录的日期留空。被动已覆盖不折算为固定天数。")
                                .font(.caption).foregroundStyle(Color.inkMuted)
                        }
                    }
                    if metric == 1 {
                        VaultCard {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("这段记录之间的净值变化").font(.headline)
                                Text(FinancialFormatting.signedYuan(last.netWorth - first.netWorth)).font(.title2)
                                ForEach(ObservationHistory.netChanges(values), id: \.reason) { item in
                                    HStack {
                                        Text(item.reason.title)
                                        Spacer()
                                        Text(FinancialFormatting.signedYuan(item.amount))
                                    }.font(.callout)
                                }
                                Text("资产调整、补录和导入可能是校正账本，不代表实际收益。")
                                    .font(.caption).foregroundStyle(Color.inkMuted)
                            }
                        }
                    }
                    Text("逐次变化 · 点选查看当时状态").font(.headline)
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(Array(values.reversed())) { value in
                            Button { selected = selected == value.id ? nil : value.id } label: {
                                observationRow(value)
                            }.buttonStyle(.plain)
                        }
                    }
                } else {
                    ContentUnavailableView("这段时间没有记录", systemImage: "chart.xyaxis.line",
                                           description: Text("从首次打开新版开始保留变化；可切换时间范围或记录来源。"))
                }
                if archive == nil { estimatedHistory }
            }.padding(Spacing.lg)
        }
        .background(Color.paper)
        .navigationTitle("自由变化记录")
        .inlineNavTitle()
        .showNavBar()
        .onChange(of: archive) { _, _ in selected = nil }
    }

    private func observationRow(_ value: ObservationValue) -> some View {
        VaultCard(padding: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(value.reason.title).font(.callout.weight(.medium))
                        Text(value.recordedAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption).foregroundStyle(Color.inkMuted)
                    }
                    Spacer()
                    Text(metric == 0 ? value.freedomDescription : FinancialFormatting.yuan(value.netWorth))
                        .font(.callout.monospacedDigit())
                }
                if selected == value.id {
                    if let effective = value.effectiveDate {
                        Text("关联账目日期：\(effective.formatted(date: .abbreviated, time: .omitted))")
                    }
                    Text("现金 \(FinancialFormatting.yuan(value.cash)) · 资产 \(FinancialFormatting.yuan(value.lockedAssets))")
                    Text("日均消费 \(FinancialFormatting.yuan(value.dailyBurn)) · 被动收入 \(FinancialFormatting.yuan(value.dailyPassive))/天")
                    Text("记录区间 \(value.trackDays) 天 · 自由状态 \(value.freedomDescription)")
                    Text("记录天数增长也会改变日均消费与自由天数，不等于财富增加。")
                }
            }.font(.caption).foregroundStyle(Color.ink)
        }
    }

    private var estimatedHistory: some View {
        DisclosureGroup("旧账本反推 · 估算") {
            let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: passives, assets: assets.first)
            let baseline = entries.first(where: { !$0.isImported })?.recordedAt ?? .now
            let history = FreedomMath.freedomDaysHistory(expenses: expenses, incomes: incomes,
                currentNetWorth: snapshot.netWorth, firstRecordDate: snapshot.firstExpenseDate,
                dailyPassive: snapshot.dailyPassive).filter { $0.date < Calendar.current.startOfDay(for: baseline) }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("按当前资产、被动收入与现有账目反推，会随补录和调整变化。与上面的实际记录分开展示。")
                ForEach(Array(history.enumerated()), id: \.offset) { _, point in
                    HStack {
                        Text(point.date, format: .dateTime.year().month().day())
                        Spacer()
                        Text(point.description)
                    }
                }
                if history.isEmpty { Text("尚无可反推的旧记录。") }
            }.font(.caption).foregroundStyle(Color.inkMuted).padding(.top, Spacing.sm)
        }
    }
}

struct FreedomHistoryLink: View {
    let values: [ObservationValue]
    var body: some View {
        NavigationLink {
            FreedomHistoryView()
        } label: {
            VaultCard(padding: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("自由变化记录").font(.headline)
                        if let first = values.first, let last = values.last, values.count > 1 {
                            Text("\(first.freedomDescription) → \(last.freedomDescription)").font(.callout)
                        } else {
                            Text("从现在开始，留下每次变化").font(.callout)
                        }
                        if let first = values.first {
                            Text("\(first.recordedAt.formatted(date: .abbreviated, time: .omitted)) 起 · 查看变化原因")
                                .font(.caption).foregroundStyle(Color.inkMuted)
                        }
                        Chart(ObservationHistory.dailyPoints(values)) { point in
                            if case .finite(let amount) = point.freedom {
                                PointMark(x: .value("记录日期", point.recordedAt), y: .value("自由天数", amount))
                                    .foregroundStyle(Color.skyDeep)
                            }
                        }.frame(height: 36).chartXAxis(.hidden).chartYAxis(.hidden)
                            .accessibilityLabel("每天最后记录的自由天数；覆盖状态不折算为天数")
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }.foregroundStyle(Color.ink)
            }
        }.buttonStyle(.plain).accessibilityIdentifier("freedom-history-link")
    }
}
