// 设定离职 / GAP 目标：想撑几个月、每月到手收入（不填按记录）、要不要定一个离开的日期。底下实时写按这些算出来的结论。

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
    @State private var months = 12
    @State private var income = ""
    @State private var hasLeaveDate = false
    @State private var leaveDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @FocusState private var incomeFocused: Bool

    private static let presets = [6, 12, 24, 36]

    /// 空着表示按记录；填了就必须是有效金额（可以是 0：已经没有收入了）
    private var parsedIncome: Double?? {
        let trimmed = income.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), FinancialFormatting.validAmount(value, allowsZero: true) else { return nil }
        return .some(value)
    }

    private var goal: FreedomGoal {
        FreedomGoal(months: months, leaveDate: hasLeaveDate ? leaveDate : nil)
    }

    private var preview: FreedomGoalMath.Result? {
        guard let entered = parsedIncome else { return nil }
        let saving = FreedomGoalMath.saving(snapshot: snapshot, enteredIncome: entered, recordedIncome: recordedIncome)
        return FreedomGoalMath.evaluate(goal: goal, snapshot: snapshot, saving: saving)
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    monthsSection
                    incomeSection
                    leaveSection
                    previewSection
                    if existing != nil {
                        Button("清除目标") {
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
            .navigationTitle(existing == nil ? "设定目标" : "编辑目标")
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
                    months = existing.months
                    if let date = existing.leaveDate {
                        hasLeaveDate = true
                        leaveDate = max(date, tomorrow)
                    }
                }
                if let enteredIncome {
                    income = enteredIncome.formatted(.number.grouping(.never).precision(.fractionLength(0...2))
                        .locale(Locale(identifier: "en_US_POSIX")))
                }
            }
        }
        .iosSheetDetents()
    }

    // MARK: - 想撑多久

    private var monthsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            KickerLabel(text: String(localized: "攒够能撑多久再走"))
            HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
                stepButton("minus", enabled: months > FreedomGoal.monthsRange.lowerBound) { months -= 1 }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(months)")
                        .font(.system(size: 52, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .contentTransition(.numericText())
                    Text("个月")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
                .frame(minWidth: 140)
                .accessibilityIdentifier("gap-months")
                stepButton("plus", enabled: months < FreedomGoal.monthsRange.upperBound) { months += 1 }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: Spacing.sm) {
                ForEach(Self.presets, id: \.self) { preset in
                    let on = preset == months
                    Button { withAnimation(.snappy) { months = preset } } label: {
                        Text(Self.presetLabel(preset))
                            .font(.system(.subheadline, design: .rounded).monospacedDigit())
                            .foregroundStyle(on ? Color.skyDeep : Color.inkMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Capsule().stroke(on ? Color.skyDeep : Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 预设按年写，英文也放得下一行
    private static func presetLabel(_ months: Int) -> String {
        months == 6 ? String(localized: "半年") : FreedomMath.GridUnit.year.amount(months / 12)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 36, height: 36)
                .foregroundStyle(enabled ? Color.ink : Color.inkGhost)
                .overlay(Circle().stroke(enabled ? Color.hairline : Color.hairlineSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - 每月到手收入

    private var incomeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KickerLabel(text: String(localized: "每月到手收入"))
            UnderlinedField(isFocused: incomeFocused) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("¥")
                        .font(.system(size: 28, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    TextField(recordedIncome.map { FinancialFormatting.wholeNumber($0) } ?? "0", text: $income)
                        .decimalKeyboard()
                        .font(.system(size: 36, weight: .ultraLight, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .minimumScaleFactor(0.5)
                        .focused($incomeFocused)
                        .accessibilityIdentifier("gap-income")
                }
            }
            Group {
                if let recordedIncome {
                    Text("不填就按近 90 天的收入记录：每月约 ¥\(FinancialFormatting.wholeNumber(recordedIncome))")
                } else {
                    Text("工资等上班的收入，按税后到手填。被动收入已经算在里面，不用重复填")
                }
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 离开的日期

    private var leaveSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: $hasLeaveDate.animation(.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("定一个离开的日期")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text("看那天的钱够不够撑满目标")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .tint(Color.skyDeep)
            .accessibilityIdentifier("gap-leave-toggle")
            if hasLeaveDate {
                Hairline(color: .hairlineSoft)
                DatePicker("哪天走", selection: $leaveDate, in: tomorrow..., displayedComponents: .date)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .tint(Color.skyDeep)
            }
        }
    }

    // MARK: - 按这些算

    @ViewBuilder
    private var previewSection: some View {
        if let preview {
            VStack(alignment: .leading, spacing: 6) {
                KickerLabel(text: String(localized: "按这些算"))
                Text(previewHeadline(preview))
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.skyDeep)
                    .accessibilityIdentifier("gap-preview")
                if let saving = preview.saving {
                    Text(FreedomGoalMath.savingText(saving))
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkMuted)
                }
                if let leave = preview.leaveLine {
                    Text(leave)
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkMuted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("收入要填数字")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.flame)
        }
    }

    private func previewHeadline(_ result: FreedomGoalMath.Result) -> String {
        if case .onTheWay(let days, let ready) = result.status {
            return String(localized: "还要 \(days) 天，预计 \(FreedomMath.depleteDateText(ready))")
        }
        return result.statusLine
    }

    private func save() {
        guard let entered = parsedIncome else { return }
        onSave(goal, entered)
        dismiss()
    }
}
