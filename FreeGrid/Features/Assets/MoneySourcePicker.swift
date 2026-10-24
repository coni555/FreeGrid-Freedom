// 新增一项资产或一个现金账户时，这笔钱从哪来：从已有的拆出（总数不变），或者是新增的钱（总数变大）。
// 两个选项并排摆出来，下面一行直接写保存后会变成什么，免得用户不知道钱是从哪一项扣的。

import SwiftUI

struct MoneySourcePicker<Source: Hashable>: View {

    /// 可以从这里拆出来的一项
    struct Option {
        let source: Source
        let name: String
        let amount: Double
    }

    let options: [Option]
    /// nil 表示新增的钱
    @Binding var selection: Source?
    /// 用户填的金额，还没填或填错时为 nil
    let amount: Double?
    /// 现在的资产或现金总数
    let total: Double
    /// 「资产」或「现金」
    let bucket: String
    let identifierPrefix: String

    /// 切到「新增的钱」再切回来时，回到刚才选的那一项
    @State private var lastSplit: Source?

    private var picked: Option? { options.first { $0.source == selection } }

    private var exceeds: Bool {
        guard let picked, let amount else { return false }
        return amount > picked.amount + FinancialLimits.assetChecksumTolerance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            KickerLabel(text: String(localized: "这笔钱从哪来"))
            Picker("这笔钱从哪来", selection: splitting) {
                Text("从已有的拆出").tag(true)
                Text("新增的钱").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("\(identifierPrefix)-source-picker")

            // 能从好几项里拆时，结果这一行本身就是选哪一项的菜单
            if picked != nil, options.count > 1 {
                Menu {
                    Picker("从哪一项拆出", selection: $selection) {
                        ForEach(options, id: \.source) { option in
                            Text("\(option.name) · ¥\(option.amount.formatted(.number))").tag(Optional(option.source))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        result
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.inkMuted)
                    }
                    .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
            } else {
                result
            }
        }
        .onAppear { lastSplit = selection ?? options.first?.source }
    }

    private var splitting: Binding<Bool> {
        Binding(
            get: { selection != nil },
            set: { split in
                if split {
                    selection = lastSplit ?? options.first?.source
                } else {
                    if selection != nil { lastSplit = selection }
                    selection = nil
                }
            }
        )
    }

    /// 「「资产」¥10,000 → ¥7,000，资产总数不变」或「资产总数 ¥10,000 → ¥13,000」
    private var result: some View {
        Text(resultText)
            .font(.system(.caption, design: .rounded).monospacedDigit())
            .foregroundStyle(exceeds ? Color.flame : Color.inkMuted)
            .accessibilityIdentifier("\(identifierPrefix)-source-result")
    }

    private var resultText: String {
        let entered = amount ?? 0
        guard let picked else {
            return String(localized: "\(bucket)总数 ¥\(total.formatted(.number)) → ¥\((total + entered).formatted(.number))")
        }
        if exceeds { return String(localized: "「\(picked.name)」只有 ¥\(picked.amount.formatted(.number))") }
        let left = max(0, picked.amount - entered)
        return String(localized: "「\(picked.name)」¥\(picked.amount.formatted(.number)) → ¥\(left.formatted(.number))，\(bucket)总数不变")
    }
}
