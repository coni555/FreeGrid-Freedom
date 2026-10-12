// 记支出、记收入、修改记录三个表单共用的输入区：金额、分类或来源、日期、备注。

import SwiftUI

struct TransactionFormFields: View {
    enum Mode { case expense, income }

    let mode: Mode
    @Binding var amount: String
    /// 支出是分类，收入是来源
    @Binding var title: String
    @Binding var note: String
    @Binding var date: Date

    /// 支出可选的分类
    var categories: [String] = []
    /// 日期最晚能选到哪天
    var latestDate: Date = .now
    /// 新记一笔时打开就弹键盘；修改已有记录时不抢焦点
    var focusesAmountOnAppear = true
    var amountIdentifier: String? = nil
    var noteIdentifier: String? = nil

    private enum Field { case amount, title, note }
    @FocusState private var focus: Field?

    private static let incomeSources = ["工资", "奖金", "投资", "副业"]

    private var accent: Color { mode == .expense ? .flame : .skyDeep }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            amountField
            switch mode {
            case .expense: categoryChips
            case .income: sourceField
            }
            dateRow
            noteField
        }
        .onAppear { if focusesAmountOnAppear { focus = .amount } }
    }

    // MARK: - 金额: 超细大数字 + 一条细线, 支出红、收入蓝
    private var amountField: some View {
        UnderlinedField(isFocused: focus == .amount, accent: accent) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("¥")
                    .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                amountTextField
                    .decimalKeyboard()
                    .font(.system(size: 52, weight: .ultraLight, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.5)
                    .focused($focus, equals: .amount)
            }
        }
    }

    @ViewBuilder
    private var amountTextField: some View {
        if let amountIdentifier {
            TextField("0.00", text: $amount).accessibilityIdentifier(amountIdentifier)
        } else {
            TextField("0.00", text: $amount)
        }
    }

    // MARK: - 分类: 一行, 点右边的胶囊弹出菜单选 (不把选项全摊在页面上)
    private var categoryChips: some View {
        HStack(spacing: Spacing.sm) {
            KickerLabel(text: "分类")
            Spacer()
            Menu {
                Picker("分类", selection: $title) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                menuCapsule(title.isEmpty ? "选择" : title)
            }
            .accessibilityIdentifier("category-menu")
        }
    }

    // MARK: - 来源: 自己填; 右边的小箭头弹出常用的几个
    private var sourceField: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KickerLabel(text: "来源")
            UnderlinedField(isFocused: focus == .title) {
                HStack(spacing: Spacing.sm) {
                    TextField("这笔钱从哪来", text: $title)
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .focused($focus, equals: .title)
                        .accessibilityIdentifier("income-source-field")
                    Menu {
                        ForEach(Self.incomeSources, id: \.self) { name in
                            Button(name) { title = name }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("常用来源")
                }
            }
        }
    }

    /// 弹出菜单的入口: 描边胶囊里写当前选中的, 右边上下箭头
    private func menuCapsule(_ label: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.ink)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.inkFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .overlay(Capsule().stroke(Color.hairline, lineWidth: 1))
        .contentShape(Capsule())
    }

    // MARK: - 日期: 今天和昨天一点就到, 别的日子用右边的选择器
    private var dateRow: some View {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
        return HStack(spacing: Spacing.sm) {
            choiceChip("今天", selected: calendar.isDateInToday(date)) { date = .now }
            choiceChip("昨天", selected: calendar.isDate(date, inSameDayAs: yesterday)) { date = yesterday }
            Spacer()
            DatePicker("日期", selection: $date, in: ...latestDate, displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }

    private var noteField: some View {
        UnderlinedField(isFocused: focus == .note) {
            noteTextField
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.ink)
                .focused($focus, equals: .note)
        }
    }

    @ViewBuilder
    private var noteTextField: some View {
        if let noteIdentifier {
            TextField("备注（可选）", text: $note).accessibilityIdentifier(noteIdentifier)
        } else {
            TextField("备注（可选）", text: $note)
        }
    }

    /// 描边胶囊; 选中只加深描边和文字, 不填实心块 (和 History 的分类块一致)
    private func choiceChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(selected ? Color.ink : Color.inkMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(Capsule().stroke(selected ? Color.ink : Color.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 记一笔表单底部的预览卡: 小标签 + 预览内容 + 一句说明
func impactCard<Content: View>(title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
    VaultCard(padding: Spacing.lg) {
        VStack(alignment: .leading, spacing: Spacing.md) {
            KickerLabel(text: title)
            content()
            Text(note)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
    }
}
