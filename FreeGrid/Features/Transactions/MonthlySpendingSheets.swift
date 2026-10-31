// 「每月一个数」的界面（2.2，免费）：首页的胶囊、填数面板、切换记账方式的两张面板。
// 问哪个月见 `MonthlyTracking.prompt`，日均怎么算见 `FreedomMath.burnEstimate(_:tracking:…)`。

import SwiftData
import SwiftUI

/// 首页原来「记支出、记收入」的位置：问这个月花了多少，写过就显示数字，点了能改
struct MonthlySpendingPill: View {
    let prompt: MonthlyTracking.Prompt
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: Spacing.sm) {
                    if let amount = prompt.amount {
                        Text("\(prompt.month.name())花了")
                        Spacer(minLength: Spacing.sm)
                        Text("¥\(FinancialFormatting.wholeNumber(amount))")
                            .monospacedDigit()
                    } else {
                        Text("\(prompt.month.name())你花了多少")
                        Spacer(minLength: Spacing.sm)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .font(.system(.body, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, 14)
                .foregroundStyle(Color.skyDeep)
                .overlay(Capsule().stroke(Color.skyDeep, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("monthly-spending-pill")
            // 只是一行小字：不推送、不加角标、不催（用户 2026-10-30 定）
            if prompt.amount == nil, prompt.isEarly {
                Text("建议月底去记")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }
}

/// 写一个月的总花销，顺带核对现金：填这个数不扣现金，现金对不对要用户自己看一眼。
/// `adopting`：还没记过账的人，从这里选定每月一个数；可以先不写，月底再回来。
struct MonthlySpendingSheet: View {
    let month: YearMonth
    var adopting = false

    @AppStorage(MonthlyTracking.key, store: AppPreferences.store) private var storedTracking = ""
    @Query private var assetsArr: [UserAssets]
    @Query private var cashAccounts: [CashAccount]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var field = MonthlySpendingField()
    @State private var editingCash = false
    @FocusState private var focused: Bool

    private var cash: Double { assetsArr.first?.cash ?? 0 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                MonthlySpendingInput(month: month, field: $field, focused: $focused)
                cashRow
                Text("填这个数不扣现金。")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
            .background(Color.paper)
            .navigationTitle("每月花销")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if adopting {
                        Button("月底再记") { save(nil) }
                            .foregroundStyle(Color.inkMuted)
                            .accessibilityIdentifier("monthly-spending-later")
                    } else {
                        Button("取消") { dismiss() }
                            .foregroundStyle(Color.inkMuted)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 选定方式时要写了数才能保存；改一个月时空着表示清空这个月
                    let canSave = field.parsed != nil && (!adopting || field.parsed != .some(nil))
                    Button("保存") {
                        if let value = field.parsed { save(value) }
                    }
                    .disabled(!canSave)
                    .foregroundStyle(canSave ? Color.skyDeep : Color.inkFaint)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("monthly-spending-save")
                }
            }
            .onAppear {
                field.load(MonthlyTracking.decode(storedTracking).amount(for: month))
                focused = true
            }
            .sheet(isPresented: $editingCash) {
                EditBucketSheet(bucket: .cash, currentAmount: cash, onSave: { value in
                    try LedgerStore.updateAssets(in: modelContext) { assets in
                        assets.cash = value
                        assets.updatedAt = .now
                    }
                })
            }
        }
        .iosSheetDetents()
    }

    /// 拆成多个账户的现金要逐个改，这里只提醒去钱包
    private var cashRow: some View {
        Button { editingCash = true } label: {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.cashBlue)
                    .frame(width: 9, height: 9)
                Text("现金")
                    .foregroundStyle(Color.inkMuted)
                Text(FinancialFormatting.yuan(cash, precision: 0))
                    .foregroundStyle(Color.ink)
                    .monospacedDigit()
                Spacer(minLength: Spacing.sm)
                if cashAccounts.isEmpty {
                    Text("还对吗？")
                        .foregroundStyle(Color.skyDeep)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.skyDeep)
                } else {
                    Text("去钱包改")
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .font(.system(.subheadline, design: .rounded))
            .padding(.horizontal, 18)
            .padding(.vertical, Spacing.lg)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.mist))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!cashAccounts.isEmpty)
        .padding(.top, Spacing.sm)
        .accessibilityIdentifier("monthly-spending-cash")
    }

    private func save(_ value: Double?) {
        var tracking = MonthlyTracking.decode(storedTracking)
        if adopting { tracking.adopt(startingAt: month) }
        tracking.set(value, for: month)
        storedTracking = tracking.encoded
        dismiss()
    }
}

/// 切换记账方式：入口都打开这一张，按现状决定是哪个面板
struct TrackingSwitchSheet: View {
    @AppStorage(MonthlyTracking.key, store: AppPreferences.store) private var storedTracking = ""
    @Query private var expenses: [Expense]

    var body: some View {
        if MonthlyTracking.decode(storedTracking).isMonthly {
            SwitchBackSheet()
        } else if FreedomMath.burnEntries(expenses).isEmpty {
            // 还没记过账，没有旧数据要比，和引导第 3 步一样
            MonthlySpendingSheet(month: YearMonth(.now), adopting: true)
        } else {
            SwitchToMonthlySheet()
        }
    }
}

/// 老用户改成每月一个数：写一个数，实时看前后对比，不劝退（用户 2026-10-30 定）
private struct SwitchToMonthlySheet: View {
    @AppStorage(MonthlyTracking.key, store: AppPreferences.store) private var storedTracking = ""
    @Query private var expenses: [Expense]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]
    @Query private var assetItems: [AssetItem]
    @Query private var loans: [Loan]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    @Environment(\.dismiss) private var dismiss
    @State private var field = MonthlySpendingField()
    @FocusState private var focused: Bool

    private func snapshot(_ tracking: MonthlyTracking) -> FinancialSnapshot {
        FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                          assetItems: assetItems, cashAccounts: cashAccounts, loans: ProFeatures.loansInEffect(loans),
                          tracking: tracking)
    }

    /// 写了这个数以后的样子；没写时是 nil
    private func tracking(amount: Double?, month: YearMonth) -> MonthlyTracking? {
        guard let amount else { return nil }
        var tracking = MonthlyTracking.decode(storedTracking)
        tracking.adopt(startingAt: month)
        tracking.set(amount, for: month)
        return tracking
    }

    var body: some View {
        let before = snapshot(MonthlyTracking.decode(storedTracking))
        let month = MonthlyTracking.firstMonth(firstRecord: before.firstExpenseDate)
        let amount = field.parsed ?? nil
        let next = tracking(amount: amount, month: month)
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                MonthlySpendingInput(month: month, field: $field, focused: $focused)
                if let next {
                    comparison(before: before, after: snapshot(next))
                        .padding(.top, Spacing.xs)
                }
                Text("\(before.burnEntries.count) 笔记录都留着，不计入日均，随时能切回来。分类统计和记账里程碑暂停更新。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if before.fixedMonthly > 0 {
                    Text("已设的固定支出仍会到期扣现金。")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
            .background(Color.paper)
            .navigationTitle("改成每月一个数")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("切换") {
                        guard let next else { return }
                        storedTracking = next.encoded
                        dismiss()
                    }
                    .disabled(next == nil)
                    .foregroundStyle(next == nil ? Color.inkFaint : Color.skyDeep)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("tracking-switch-confirm")
                }
            }
            .onAppear { focused = true }
        }
        .iosSheetDetents()
    }

    private func comparison(before: FinancialSnapshot, after: FinancialSnapshot) -> some View {
        VStack(spacing: Spacing.sm) {
            TrackingCompareRow(label: String(localized: "日均"),
                               before: before.hasExpenses && before.dailyCost.isFinite ? dailyText(before.dailyCost) : nil,
                               after: dailyText(after.dailyCost))
            TrackingCompareRow(label: String(localized: "能撑"), before: freedomText(before.freedom),
                               after: freedomText(after.freedom) ?? "—")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, Spacing.md)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.mist))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
    }

    private func freedomText(_ state: FreedomState) -> String? {
        switch state {
        case .finite(let days): return String(localized: "\(FinancialFormatting.wholeNumber(days.rounded(.down))) 天自由")
        case .covered: return "∞"
        case .insufficientData, .invalidData: return nil
        }
    }
}

private struct TrackingCompareRow: View {
    let label: String
    let before: String?
    let after: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(label)
                .foregroundStyle(Color.inkMuted)
            Spacer(minLength: Spacing.sm)
            if let before {
                Text(before)
                    .foregroundStyle(Color.inkFaint)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.inkFaint)
            }
            Text(after)
                .foregroundStyle(Color.ink)
        }
        .font(.system(.subheadline, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// 改回逐笔记账：写过的数留着，日均用 30 天过渡
private struct SwitchBackSheet: View {
    @AppStorage(MonthlyTracking.key, store: AppPreferences.store) private var storedTracking = ""
    @Query private var expenses: [Expense]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetsArr: [UserAssets]
    @Query private var assetItems: [AssetItem]
    @Query private var loans: [Loan]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 80

    var body: some View {
        let snapshot = FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                                         assetItems: assetItems, cashAccounts: cashAccounts,
                                         loans: ProFeatures.loansInEffect(loans),
                                         tracking: MonthlyTracking.decode(storedTracking))
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("之后记的每笔支出都会从现金扣。")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if snapshot.hasExpenses {
                    Text("日均会在 30 天里慢慢改按记账算。")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    TrackingCompareRow(label: String(localized: "现在的日均"), before: nil, after: dailyText(snapshot.dailyCost))
                        .padding(.horizontal, 18)
                        .padding(.vertical, Spacing.md)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.mist))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
                        .padding(.top, Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.paper)
            .navigationTitle("改回逐笔记账")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("切换") {
                        var tracking = MonthlyTracking.decode(storedTracking)
                        tracking.switchBack()
                        storedTracking = tracking.encoded
                        dismiss()
                    }
                    .foregroundStyle(Color.skyDeep)
                    .fontWeight(.medium)
                    .accessibilityIdentifier("tracking-switch-confirm")
                }
            }
        }
        // 这张没有输入框，话也少：面板跟内容一样高，不留半屏空白。加的是导航栏和底部安全区
        #if os(iOS)
        .presentationDetents([.height(contentHeight + 100)])
        .presentationDragIndicator(.visible)
        #endif
    }
}

private func dailyText(_ value: Double) -> String {
    value.isFinite ? "¥" + value.formatted(.number.precision(.fractionLength(1))) : "—"
}

/// 金额输入框里的字和它代表的数
private struct MonthlySpendingField {
    var text = ""

    /// 外层 nil：填得不对；里层 nil：空着
    var parsed: Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), let valid = MonthlyTracking.valid(value) else { return nil }
        return .some(valid)
    }

    mutating func load(_ amount: Double?) {
        guard let amount else { return }
        text = amount.formatted(.number.grouping(.never).precision(.fractionLength(0...2))
            .locale(Locale(identifier: "en_US_POSIX")))
    }
}

/// 问句、输入框和下面那行小字。过完的月份问实际花了多少；还没过完的建议月底记，也能先写个大概
private struct MonthlySpendingInput: View {
    let month: YearMonth
    @Binding var field: MonthlySpendingField
    var focused: FocusState<Bool>.Binding

    var body: some View {
        KickerLabel(text: String(localized: "\(month.name())一共花了多少钱？"))
        UnderlinedField(isFocused: focused.wrappedValue) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("¥")
                    .font(.system(size: 24, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                TextField("0", text: $field.text)
                    .decimalKeyboard()
                    .font(.system(size: 32, weight: .ultraLight, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.5)
                    .focused(focused)
                    .accessibilityIdentifier("monthly-spending-field")
            }
        }
        Text(MonthlyTracking.isEarly(in: month) ? "建议月底去记。想先看自由天数，可以先写个大概。" : "记下你的实际支出。")
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Color.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
        if field.parsed == nil {
            Text("要填大于 0 的数字")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.flame)
        }
    }
}
