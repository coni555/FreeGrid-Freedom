import SwiftUI

/// 一笔交易是一行固定身份的 View；父列表更新时不展开整个标签和菜单。
struct HistoryTransactionRow: View, Equatable {
    let row: HistorySearch.Row
    let icon: String
    var showsDay = false
    let onEdit: () -> Void
    let onUndo: () -> Void

    // 搜索的操作闭包只捕获稳定的状态容器和记录 key，编辑时再查当前模型。
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.icon == rhs.icon && lhs.showsDay == rhs.showsDay
    }

    var body: some View {
        let tx = row.record
        // 支出有备注时备注才是这笔账的事实(「租房」), 分类(「其他」)退成小标签; 收入的来源本身就是事实。
        // 月供扣款的「分类」就是贷款名，它才是事实，备注「自动扣款」退到后面
        let noteLeads = !tx.key.isIncome && !tx.note.isEmpty && !tx.isLoanPayment
        return Button(action: onEdit) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Color.inkFaint)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                if showsDay {
                    Text("\(row.day)日")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.inkFaint)
                        .frame(width: 36, alignment: .leading)
                }
                Text(noteLeads ? tx.note : tx.title)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .layoutPriority(1)
                if noteLeads {
                    Text(tx.title)
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                } else if !tx.note.isEmpty {
                    Text(tx.note)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                }
                if tx.isExcludedFromBurn {
                    Text("不计日均")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkGhost)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: Spacing.sm)
                Text(row.amount)
                    .font(.system(.callout, design: .rounded).weight(.regular).monospacedDigit())
                    .foregroundStyle(tx.cashChange < 0 ? Color.flame : Color.skyDeep)
                    .layoutPriority(2)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("修改这笔记录")
        .accessibilityIdentifier("history-transaction-" + tx.id.uuidString)
        // 不用 destructive role: 它会在确认前就把行滑走
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("撤销", action: onUndo)
                .tint(Color.flame)
        }
        .contextMenu {
            Button("修改", systemImage: "pencil", action: onEdit)
            Button("撤销这笔", systemImage: "arrow.uturn.backward", role: .destructive, action: onUndo)
        }
    }
}
