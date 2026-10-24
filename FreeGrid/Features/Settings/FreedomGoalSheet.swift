// 设定 GAP：先定哪天走（上面实时倒数），可选「想撑多久」，收入收在「算得更准」里、不填按记录。底下写按这些算那天大约有多少天自由。

import SwiftUI

struct FreedomGoalSheet: View {
    let existing: FreedomGoal?
    let enteredIncome: Double?
    /// 近 90 天的收入记录折成每月；记录不够时为 nil
    let recordedIncome: Double?
    let snapshot: FinancialSnapshot
    let onSave: (FreedomGoal, Double?) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var leaveDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var targetDays: Int?
    @State private var income = ""
    @State private var showingIncome = false
    @FocusState private var incomeFocused: Bool

    /// 空着表示按记录；填了就必须是有效金额（可以是 0：已经没有收入了）
    private var parsedIncome: Double?? {
        let trimmed = income.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), FinancialFormatting.validAmount(value, allowsZero: true) else { return nil }
        return .some(value)
    }

    private var goal: FreedomGoal { FreedomGoal(leaveDate: leaveDate, targetDays: targetDays) }

    private var preview: FreedomGoalMath.Result? {
        guard let entered = parsedIncome else { return nil }
        let saving = FreedomGoalMath.saving(snapshot: snapshot, enteredIncome: entered, recordedIncome: recordedIncome)
        return FreedomGoalMath.evaluate(goal: goal, snapshot: snapshot, saving: saving)
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    private var daysUntil: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                        to: Calendar.current.startOfDay(for: leaveDate)).day ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    dateSection
                    targetSection
                    incomeSection
                    previewSection
                    if existing != nil {
                        Button("清除 GAP") {
                            onClear()
                            dismiss()
                        }
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.flame)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("gap-clear")
                    }
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(existing == nil ? "设定 GAP" : "编辑 GAP")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(parsedIncome == nil)
                        .foregroundStyle(parsedIncome == nil ? Color.inkFaint : Color.skyDeep)
                        .fontWeight(.medium)
                        .accessibilityIdentifier("gap-save")
                }
            }
            .onAppear {
                if let existing {
                    leaveDate = max(existing.leaveDate, tomorrow)
                    targetDays = existing.targetDays
                }
                if let enteredIncome {
                    income = enteredIncome.formatted(.number.grouping(.never).precision(.fractionLength(0...2))
                        .locale(Locale(identifier: "en_US_POSIX")))
                    showingIncome = true
                }
            }
        }
        .iosSheetDetents()
    }

    // MARK: - 哪天走

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            KickerLabel(text: String(localized: "哪天走"))
            GapCountdownNumber(daysUntil: daysUntil, size: 56)
                .animation(.snappy, value: daysUntil)
            UnderlinedField(isFocused: false) {
                DatePicker("离开的日期", selection: $leaveDate, in: tomorrow..., displayedComponents: .date)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .tint(Color.skyDeep)
                    .accessibilityIdentifier("gap-date")
            }
        }
    }

    // MARK: - 想撑多久（可选）

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            KickerLabel(text: String(localized: "想撑多久 · 可不选"))
            HStack(spacing: Spacing.sm) {
                choice(String(localized: "不设"), value: nil)
                ForEach(FreedomGoal.targetChoices, id: \.self) { days in
                    // 英文的「one year」放在句中是小写，单独当按钮时首字母大写
                    let name = FreedomGoal.targetName(days)
                    choice(name.prefix(1).uppercased() + name.dropFirst(), value: days)
                }
            }
        }
    }

    private func choice(_ title: String, value: Int?) -> some View {
        let on = targetDays == value
        return Button { withAnimation(.snappy) { targetDays = value } } label: {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(on ? Color.skyDeep : Color.inkMuted)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(Capsule().stroke(on ? Color.skyDeep : Color.hairline, lineWidth: 1))
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
            .accessibilityIdentifier("gap-income-toggle")

            if showingIncome {
                UnderlinedField(isFocused: incomeFocused) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("¥")
                            .font(.system(size: 24, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                        TextField(recordedIncome.map { FinancialFormatting.wholeNumber($0) } ?? "0", text: $income)
                            .decimalKeyboard()
                            .font(.system(size: 32, weight: .ultraLight, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.ink)
                            .minimumScaleFactor(0.5)
                            .focused($incomeFocused)
                            .accessibilityIdentifier("gap-income")
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
                Text(preview.freedomLine)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .accessibilityIdentifier("gap-preview")
                if let progress = preview.progress {
                    GapTargetBar(progress: progress, label: preview.targetLine, enough: preview.enough == true)
                }
                if let saving = preview.saving, preview.projected {
                    Text(FreedomGoalMath.savingText(saving))
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("收入要填数字")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.flame)
        }
    }

    private func save() {
        guard let entered = parsedIncome else { return }
        onSave(goal, entered)
        dismiss()
    }
}
