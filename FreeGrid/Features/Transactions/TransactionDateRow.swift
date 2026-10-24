// 记支出、记收入、修改记录共用的日期行：「今天」「昨天」一点就到，别的日子用右边的选择器。

import SwiftUI

struct TransactionDateRow: View {
    @Binding var date: Date
    /// 最晚能选到哪天
    var latestDate: Date = .now

    var body: some View {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
        HStack(spacing: Spacing.sm) {
            quickChip(String(localized: "今天"), selected: calendar.isDateInToday(date)) { date = .now }
            quickChip(String(localized: "昨天"), selected: calendar.isDate(date, inSameDayAs: yesterday)) { date = yesterday }
            Spacer()
            DatePicker("日期", selection: $date, in: ...latestDate, displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, AppLanguage.locale)
        }
    }

    /// 描边胶囊; 选中只加深描边和文字, 不填实心块
    private func quickChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(selected ? Color.ink : Color.inkMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .overlay(Capsule().stroke(selected ? Color.ink : Color.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        // Form 的行里放按钮, 不指定样式的话点整行任何位置都会触发
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
