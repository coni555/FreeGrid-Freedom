// 新目标 / 编辑目标（Pro）：起个名字（可不填）、想要多少天自由、在哪天之前（可不选）。
// 底下实时写和首页自由天数比的结果：现在多少、还差多少。不按收入推算。

import SwiftUI

struct FreedomGoalSheet: View {
    /// nil 是新目标
    let existing: FreedomGoal?
    let snapshot: FinancialSnapshot
    let onSave: (FreedomGoal) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    /// `customDays` 为 true 时用下面填的数
    @State private var targetDays = 365
    @State private var customDays = false
    @State private var customText = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @FocusState private var focus: Field?

    private enum Field { case name, days }

    /// 自己填的天数：1 天到 100 年
    private var parsedCustom: Int? {
        guard let value = Int(customText.trimmingCharacters(in: .whitespaces)), (1...36_500).contains(value) else { return nil }
        return value
    }

    private var chosenDays: Int? { customDays ? parsedCustom : targetDays }

    /// 天数填对了才能存
    private var goal: FreedomGoal? {
        chosenDays.map {
            FreedomGoal(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        targetDays: $0, deadline: hasDeadline ? deadline : nil)
        }
    }

    private var preview: FreedomGoalProgress? { goal.map { FreedomGoalProgress(goal: $0, snapshot: snapshot) } }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    private var daysUntil: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                        to: Calendar.current.startOfDay(for: deadline)).day ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    nameSection
                    daysSection
                    deadlineSection
                    previewSection
                    if existing != nil {
                        Button("删除这个目标") {
                            onDelete()
                            dismiss()
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.flame)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("goal-delete")
                    }
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(existing == nil ? "新目标" : "编辑目标")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(goal == nil)
                        .foregroundStyle(goal == nil ? Color.inkFaint : Color.skyDeep)
                        .fontWeight(.medium)
                        .accessibilityIdentifier("goal-save")
                }
            }
            .onAppear(perform: load)
        }
        .iosSheetDetents()
    }

    private func load() {
        if let existing {
            name = existing.name
            if FreedomGoal.targetChoices.contains(existing.targetDays) {
                targetDays = existing.targetDays
            } else {
                customDays = true
                customText = String(existing.targetDays)
            }
            if let date = existing.deadline {
                hasDeadline = true
                deadline = max(date, tomorrow)
            }
        }
    }

    // MARK: - 叫什么（可不填）

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            KickerLabel(text: String(localized: "叫什么 · 可不填"))
            UnderlinedField(isFocused: focus == .name) {
                TextField(goal?.displayName ?? String(localized: "我的目标"), text: $name)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .focused($focus, equals: .name)
                    .submitLabel(.done)
                    .accessibilityIdentifier("goal-name")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(FreedomGoal.nameSuggestions, id: \.self) { suggestion in
                        chip(suggestion, on: name == suggestion) {
                            name = name == suggestion ? "" : suggestion
                        }
                    }
                }
            }
        }
    }

    // MARK: - 想要多少天自由

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            KickerLabel(text: String(localized: "想要多少天自由"))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(chosenDays.map { $0.formatted(.number) } ?? "—")
                    .font(.system(size: 56, weight: .ultraLight, design: .rounded).monospacedDigit())
                    .foregroundStyle(chosenDays == nil ? Color.inkGhost : Color.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: chosenDays)
                if chosenDays != nil {
                    Text("天")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(FreedomGoal.targetChoices, id: \.self) { days in
                        // 英文的「one year」放在句中是小写，单独当按钮时首字母大写
                        let label = FreedomGoal.targetName(days)
                        chip(label.prefix(1).uppercased() + label.dropFirst(), on: !customDays && targetDays == days) {
                            pickDays(days)
                        }
                    }
                    chip(String(localized: "自己填"), on: customDays) {
                        withAnimation(.snappy) { customDays = true }
                        focus = .days
                    }
                }
            }
            if customDays {
                UnderlinedField(isFocused: focus == .days) {
                    TextField(String(localized: "天数"), text: $customText)
                        .numberKeyboard()
                        .font(.system(.body, design: .rounded).monospacedDigit())
                        .focused($focus, equals: .days)
                        .accessibilityIdentifier("goal-custom-days")
                }
            }
        }
    }

    private func pickDays(_ days: Int) {
        withAnimation(.snappy) {
            customDays = false
            targetDays = days
        }
    }

    // MARK: - 在哪天之前（可不选）

    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            KickerLabel(text: String(localized: "在哪天之前 · 可不选"))
            Toggle(isOn: $hasDeadline.animation(.snappy)) {
                Text("定一个日子")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(hasDeadline ? Color.ink : Color.inkMuted)
            }
            .tint(Color.skyDeep)
            .accessibilityIdentifier("goal-has-deadline")
            if hasDeadline {
                HStack(alignment: .center) {
                    GapCountdownNumber(daysUntil: daysUntil, size: 44, unitFont: .body)
                        .animation(.snappy, value: daysUntil)
                    Spacer(minLength: Spacing.sm)
                    DatePicker("日子", selection: $deadline, in: tomorrow..., displayedComponents: .date)
                        .labelsHidden()
                        .tint(Color.skyDeep)
                        .accessibilityIdentifier("goal-date")
                }
            }
            Hairline()
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(on ? Color.skyDeep : Color.inkMuted)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(Capsule().stroke(on ? Color.skyDeep : Color.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 按这些算

    /// 和首页的自由天数比：「现在 341 天自由，还差 24 天」
    @ViewBuilder
    private var previewSection: some View {
        if let preview {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Hairline(color: .hairlineSoft)
                    .padding(.bottom, Spacing.xs)
                Text(Self.summary(preview))
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .accessibilityIdentifier("goal-preview")
                if let progress = preview.progress {
                    CheckProgressBar(progress: progress)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("天数要填 1 到 36500 之间的整数")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.flame)
        }
    }

    /// 面板底下那一句：「现在 341 天自由，还差 24 天」「现在 341 天自由，够了」
    static func summary(_ result: FreedomGoalProgress) -> String {
        guard let days = result.freedomDaysText else { return result.freedomLine }
        let lead = String(localized: "现在 \(days) 天自由")
        if result.enough == true { return String(localized: "\(lead)，够了") }
        guard let short = result.shortText else { return lead }
        return String(localized: "\(lead)，还差 \(short) 天")
    }

    private func save() {
        guard let goal else { return }
        onSave(goal)
        dismiss()
    }
}
