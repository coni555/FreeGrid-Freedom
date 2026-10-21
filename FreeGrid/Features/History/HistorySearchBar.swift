import SwiftUI

/// 把实时输入的观察限制在输入框内，不让每个按键重新生成结果行。
struct HistorySearchBar: View {
    let search: HistorySearchState
    @FocusState.Binding var focused: Bool
    let filterName: String?
    let onClearFilter: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkFaint)
                if let name = filterName {
                    Button(action: onClearFilter) {
                        HStack(spacing: 4) {
                            Text(name)
                            Image(systemName: "xmark").font(.system(size: 8, weight: .medium))
                        }
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Capsule().stroke(Color.ink, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("只在\(name)里搜索，点按改为搜索全部")
                    .accessibilityIdentifier("history-search-filter")
                }
                TextField("搜索备注或金额", text: Binding(get: { search.text }, set: { search.setText($0) }))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .accessibilityIdentifier("history-search-field")
                    // 只在字段已经插入列表后请求焦点，不使用固定等待时间。
                    .onAppear { HistorySearchMetrics.mark("field-appeared") }
                    .task { focused = true }
                if !search.text.isEmpty {
                    Button { search.setText("") } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.mist))
            .overlay(Capsule().stroke(Color.hairline, lineWidth: 1))

            Button("取消", action: onCancel)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Color.skyDeep)
                .buttonStyle(.plain)
        }
    }
}
