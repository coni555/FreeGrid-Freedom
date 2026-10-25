// 新目标 / 编辑目标（Pro）：起个名字（可不填）、想要多少天自由、在哪天之前（可不选），两项至少一项。
// 收入收在「算得更准」里、不填按记录。底下实时写按这些算的结果。

import SwiftUI

struct FreedomGoalSheet: View {
    /// nil 是新目标
    let existing: FreedomGoal?
    let enteredIncome: Double?
    /// 近 90 天的收入记录折成每月；记录不够时为 nil
    let recordedIncome: Double?
    let snapshot: FinancialSnapshot
    let onSave: (FreedomGoal, Double?) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    /// nil 是不设；`customDays` 为 true 时用下面填的数
    @State private var targetDays: Int?
    @State private var customDays = false
    @State private var customText = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var income = ""
    @State private var showingIncome = false
    @FocusState private var focus: Field?

    private enum Field { case name, days, income }

    /// 自己填的天数：1 天到 100 年
    private var parsedCustom: Int? {
        guard let value = Int(customText.trimmingCharacters(in: .whitespaces)), (1...36_500).contains(value) else { return nil }
        return value
    }

    private var chosenDays: Int? { customDays ? parsedCustom : targetDays }

    /// 空着表示按记录；填了就必须是有效金额（可以是 0：已经没有收入了）
    private var parsedIncome: Double?? {
        let trimmed = income.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), FinancialFormatting.validAmount(value, allowsZero: true) else { return nil }
        return .some(value)
    }

    private var goal: FreedomGoal {
        FreedomGoal(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    targetDays: chosenDays, deadline: hasDeadline ? deadline : nil)
    }

    private var canSave: Bool { goal.isValid && parsedIncome != nil }

    private var preview: FreedomGoalMath.Result? {
        guard goal.isValid, let entered = parsedIncome else { return nil }
        let saving = FreedomGoalMath.saving(snapshot: snapshot, enteredIncome: entered, recordedIncome: recordedIncome)
        return FreedomGoalMath.evaluate(goal: goal, snapshot: snapshot, saving: saving)
    }

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
                    incomeSection
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
                        .disabled(!canSave)
                        .foregroundStyle(canSave ? Color.skyDeep : Color.inkFaint)
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
            if let days = existing.targetDays {
                if FreedomGoal.targetChoices.contains(days) {
                    targetDays = days
                } else {
                    customDays = true
                    customText = String(days)
                }
            }
            if let date = existing.deadline {
                hasDeadline = true
                deadline = max(date, tomorrow)
            }
        } else {
            // 新目标先给一个最常见的：一年
            targetDays = 365
        }
        if let enteredIncome {
            income = enteredIncome.formatted(.number.grouping(.never).precision(.fractionLength(0...2))
                .locale(Locale(identifier: "en_US_POSIX")))
            showingIncome = true
        }
    }

    // MARK: - 叫什么（可不填）

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            KickerLabel(text: String(localized: "叫什么 · 可不填"))
            UnderlinedField(isFocused: focus == .name) {
                TextField(goal.displayName, text: $name)
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
                    chip(String(localized: "不设"), on: !customDays && targetDays == nil) { pickDays(nil) }
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

    private func pickDays(_ days: Int?) {
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

    // MARK: - 算得更准：每月到手收入

    private var incomeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Button {
                withAnimation(.snappy) { showingIncome.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("算得更准：每月到手收入")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .rotationEffect(.degrees(showingIncome ? 180 : 0))
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("goal-income-toggle")

            if showingIncome {
                UnderlinedField(isFocused: focus == .income) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("¥")
                            .font(.system(size: 24, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                        TextField(recordedIncome.map { FinancialFormatting.wholeNumber($0) } ?? "0", text: $income)
                            .decimalKeyboard()
                            .font(.system(size: 32, weight: .ultraLight, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.ink)
                            .minimumScaleFactor(0.5)
                            .focused($focus, equals: .income)
                            .accessibilityIdentifier("goal-income")
                    }
                }
                Text(recordedIncome == nil
                     ? String(localized: "税后到手的工资。被动收入已经算在里面")
                     : String(localized: "不填就按近 90 天的收入记录，每月约 ¥\(FinancialFormatting.wholeNumber(recordedIncome ?? 0))"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 按这些算

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
                if let progress = preview.progress, preview.goal.deadline != nil {
                    CheckProgressBar(progress: progress)
                }
                if let note = preview.footnote {
                    Text(note)
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if parsedIncome == nil {
            Text("收入要填数字")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.flame)
        } else {
            Text("天数和日子至少选一项")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
    }

    /// 面板底下那一句：「现在 341 天自由，还差 24 天」「那天约 641 天自由，还差 89 天」
    static func summary(_ result: FreedomGoalMath.Result) -> String {
        guard case .finite = result.freedom, let days = result.freedomDaysText else { return result.freedomLine }
        let lead = result.goal.deadline == nil || !result.projected
            ? String(localized: "现在 \(days) 天自由") : String(localized: "那天约 \(days) 天自由")
        guard let target = result.goal.targetDays, result.enough == false,
              case .finite(let have) = result.freedom else {
            return result.enough == true ? String(localized: "\(lead)，够了") : lead
        }
        let short = FinancialFormatting.wholeNumber((Double(target) - have).rounded(.up))
        return String(localized: "\(lead)，还差 \(short) 天")
    }

    private func save() {
        guard canSave, let entered = parsedIncome else { return }
        onSave(goal, entered)
        dismiss()
    }
}
