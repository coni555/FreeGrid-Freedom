// 新增或编辑被动收入：名称、每次到账多少、几个月到账一次。存的是折合的每月（见 `PassiveSource.monthlyAmount`）。

import SwiftUI

struct PassiveSourceSheet: View {

    let existing: PassiveSource?
    /// 名称、折合的每月、几个月到账一次
    let onSave: (String, Double, Int) throws -> Void
    /// 编辑时才有：删除这个被动收入源（新版 Assets 的行上没有删除按钮）
    var onDelete: (() throws -> Void)? = nil

    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var monthly: String = ""
    @State private var intervalMonths = 1
    private enum Field { case name, monthly }
    @FocusState private var focus: Field?
    @State private var confirmingDelete = false

    private var isEditing: Bool { existing != nil }
    private var title: String { isEditing ? "编辑被动收入" : "添加被动收入" }
    /// 填的是每次到账多少，折成每月再存
    private var enteredMonthly: Double? {
        guard let amount = Double(monthly), FinancialFormatting.validAmount(amount) else { return nil }
        return amount / Double(intervalMonths)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // 名字
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "名称")
                        UnderlinedField(isFocused: focus == .name) {
                            TextField("房租、股息、利息、副业…", text: $name)
                                .font(.system(.title3, design: .rounded))
                                .foregroundStyle(Color.ink)
                                .focused($focus, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focus = .monthly }
                        }
                    }

                    // 每次到账多少
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: intervalMonths == 1 ? "每月收入" : "每次到账多少")
                        UnderlinedField(isFocused: focus == .monthly, accent: .mossGreen) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("¥")
                                    .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                                    .foregroundStyle(Color.inkFaint)
                                TextField("0", text: $monthly)
                                    .decimalKeyboard()
                                    .accessibilityIdentifier("passive-monthly-field")
                                    .font(.system(size: 52, weight: .ultraLight, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Color.ink)
                                    .minimumScaleFactor(0.5)
                                    .focused($focus, equals: .monthly)
                            }
                        }

                    }

                    // 几个月到账一次，下面一行换算成每月、每天
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        KickerLabel(text: "几个月到账一次")
                        UnderlinedField(isFocused: false) {
                            Menu {
                                Picker("几个月到账一次", selection: $intervalMonths) {
                                    ForEach(LoanSchedule.intervals, id: \.self) {
                                        Text(LoanSchedule.intervalLabel($0)).tag($0)
                                    }
                                }
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(LoanSchedule.intervalLabel(intervalMonths))
                                        .font(.system(.title3, design: .rounded))
                                        .foregroundStyle(Color.ink)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.inkFaint)
                                }
                                .contentShape(Rectangle())
                            }
                            .menuIndicator(.hidden)
                            .accessibilityIdentifier("passive-interval-picker")
                        }
                        summary
                    }

                    if isEditing, onDelete != nil {
                        Button("删除这个被动收入") { confirmingDelete = true }
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color.flame)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("delete-passive-source")
                    }
                }
                .padding(Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(title)
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isValid)
                        .foregroundStyle(isValid ? Color.skyDeep : Color.inkFaint)
                        .fontWeight(.medium)
                }
            }
            .confirmationDialog("删除「\(existing?.name ?? "")」？", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    do {
                        try onDelete?()
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后被动覆盖率会下降。")
            }
            .onAppear {
                if let e = existing {
                    name = e.name
                    intervalMonths = LoanSchedule.intervals.contains(e.intervalMonths) ? e.intervalMonths : 1
                    // 存的是折合每月，乘回每次到账多少；按分取整，免得 1000 ÷ 3 × 3 带出一长串小数
                    let perPayment = (e.monthlyAmount * Double(intervalMonths) * 100).rounded() / 100
                    monthly = String(format: "%g", perPayment)
                }
                focus = isEditing ? nil : .name  // 新增聚焦名字, 编辑不自动弹键盘
            }
        }
        .saveErrorAlert($saveError)
        .iosSheetDetents()
    }

    /// 填了金额：每月写相当于每天多少；不按月到账时先折成每月。没填时说一句该填什么
    @ViewBuilder
    private var summary: some View {
        if let m = enteredMonthly {
            let perDay = "每天 ¥\(String(format: "%.1f", m / 30))"
            Text(intervalMonths == 1 ? "相当于\(perDay)" : "折合每月 ¥\(FinancialFormatting.wholeNumber(m)) · \(perDay)")
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.mossGreen)
                .accessibilityIdentifier("passive-summary")
        } else {
            Text(intervalMonths == 1 ? "不用持续工作也能稳定拿到的钱，按每月的金额填"
                                     : "不用持续工作也能稳定拿到的钱，填一次到账的总数")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isValid: Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        return !n.isEmpty && n.count <= FinancialLimits.nameCharacters && enteredMonthly != nil
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard isValid, let monthlyAmount = enteredMonthly else { return }
        do {
            try onSave(n, monthlyAmount, intervalMonths)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
