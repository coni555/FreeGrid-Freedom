// 模拟交易，只计算预览，不写入账本。

import SwiftUI
import SwiftData

struct SimulateSheet: View {

    @Environment(\.dismiss) private var dismiss

    /// 模拟完决定真的花了：把金额交给首页，由它接着打开记支出表单
    var onRecordExpense: ((String) -> Void)? = nil

    // 同样需要 @Query 当前数据,实时计算影响
    @Query private var expenses: [Expense]
    @Query private var assetsArr: [UserAssets]
    @Query private var passiveSources: [PassiveSource]
    @Query private var assetItems: [AssetItem]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    @Query private var loans: [Loan]

    // ===== 模拟状态 =====
    @State private var amount: String = ""
    @State private var mode: TransactionKind = .expense
    /// 格子推演动画三态
    @State private var demoPhase: SimDemoPhase = .idle
    /// 打开就弹键盘, 少点一下
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    modePicker
                    amountInput
                    if let impact = currentImpact {
                        // 格子是这个功能的看点, 放在数字表上面
                        gridDemoCard(impact: impact)
                        previewCard(impact: impact)
                        if mode == .expense, onRecordExpense != nil {
                            recordButton
                        }
                    } else {
                        hintCard
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .dismissKeyboardOnScroll()
            .background(Color.paper)
            .onAppear { amountFocused = true }
            // 金额或模式一变,演示回到静止态(旧网格),让用户重新观察这一笔
            .onChange(of: amount) { _, _ in demoPhase = .idle }
            .onChange(of: mode) { _, _ in demoPhase = .idle }
            // 停止输入一小会儿后自己播一遍, 不用再点按钮; 继续输入会取消这次等待
            .task(id: "\(amount)|\(mode)") {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, case .idle = demoPhase,
                      let impact = currentImpact, let demo = demoChange(for: impact) else { return }
                playDemo(delta: demo.delta, ignite: demo.ignite)
            }
            .navigationTitle("模拟决策")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
            }
        }
    }

    // ============================================================================
    // MARK: - 子组件
    // ============================================================================

    /// 金额有效时这笔模拟的结果
    private var currentImpact: TransactionImpact? {
        guard let amt = Double(amount), FinancialFormatting.validAmount(amt) else { return nil }
        return TransactionImpact(
            snapshot: FinancialSnapshot(expenses: expenses, passiveSources: passiveSources,
                                        assets: assetsArr.first, assetItems: assetItems, cashAccounts: cashAccounts, loans: ProFeatures.loansInEffect(loans)),
            kind: mode, amount: amt
        )
    }

    /// 这笔模拟会让几格变化; 数据不够、画不下或不足一格时没有可演示的
    private func demoChange(for o: TransactionImpact) -> (delta: Int, ignite: Bool)? {
        guard !isInvalid(o.before.freedom), !isInvalid(o.newFreedom),
              !isInsufficient(o.before.freedom), !isInsufficient(o.newFreedom) else { return nil }
        let unit = FreedomMath.gridUnit(for: o.before.freedom)
        let oldGrid = FreedomMath.gridState(for: o.before.freedom, lockedAssets: o.before.countedAssets,
                                            netWorth: o.before.freedomBase, unit: unit)
        let newGrid = FreedomMath.gridState(for: o.newFreedom, lockedAssets: o.before.countedAssets,
                                            netWorth: o.newFreedomBase, unit: unit)
        guard !oldGrid.isOverflow, !newGrid.isOverflow, newGrid.count != oldGrid.count else { return nil }
        return (abs(newGrid.count - oldGrid.count), newGrid.count > oldGrid.count)
    }

    /// 看完决定真的花了: 关掉模拟, 带着金额去记支出
    private var recordButton: some View {
        VStack(spacing: Spacing.sm) {
            VaultButton(title: String(localized: "就这么花了，记为支出"), icon: "arrow.right", style: .secondary) {
                onRecordExpense?(amount)
                dismiss()
            }
            .accessibilityIdentifier("simulate-record-expense")
            Text("会打开记支出表单并带上这个金额，保存前还可以改。")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
    }

    /// 切换支出/收入, 下面一行小字说明这只是模拟 (原来是一整块深蓝色的说明卡)
    private var modePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Picker("模拟类型", selection: $mode) {
                ForEach(TransactionKind.allCases, id: \.self) { kind in
                    Text(kind == .expense ? "模拟支出" : "模拟收入").tag(kind)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .light))
                Text("只是模拟：不会改余额，也不会记进账本。")
                    .font(.system(.caption2, design: .rounded))
            }
            .foregroundStyle(Color.inkFaint)
            .padding(.leading, Spacing.xs)
        }
    }

    /// 金额输入:VaultCard silverline 风
    private var amountInput: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                KickerLabel(text: mode == .expense ? String(localized: "假设花掉（元）") : String(localized: "假设收入（元）"))
                HStack(spacing: 6) {
                    Text("¥")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    TextField("0.00", text: $amount)
                        .decimalKeyboard()
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .focused($amountFocused)
                }
            }
        }
    }

    /// 未输入金额时的占位提示
    private var hintCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.inkFaint)
            Text("输入金额 · 实时看决策影响")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color.inkMuted)
        }
        .padding(.vertical, Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    /// 影响预览:VaultCard silverline
    private func previewCard(impact: TransactionImpact) -> some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                KickerLabel(text: mode == .expense ? String(localized: "这笔支出的影响") : String(localized: "这笔收入的影响"))

                TransactionImpactView(impact: impact)

                Text(mode == .expense
                     ? "花掉之后，净值、日均和自由天数会怎么变。"
                     : "收到之后，净值和自由天数会怎么变。")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }
        }
    }

    // ============================================================================
    // MARK: - 格子推演卡(动画演示)
    // ============================================================================

    /// 把"自由天数 from→to"翻译成可见的格子级联熄灭(支出)/ 点亮(收入)。
    @ViewBuilder
    private func gridDemoCard(impact o: TransactionImpact) -> some View {
        // 固定当前态的单位，跨档时不会在播放途中改变每格含义。
        let unit = FreedomMath.gridUnit(for: o.before.freedom)
        let oldGrid = FreedomMath.gridState(for: o.before.freedom, lockedAssets: o.before.countedAssets,
                                            netWorth: o.before.freedomBase, unit: unit)
        let newGrid = FreedomMath.gridState(for: o.newFreedom, lockedAssets: o.before.countedAssets,
                                            netWorth: o.newFreedomBase, unit: unit)
        let oldCount = oldGrid.count
        let newCount = newGrid.count
        let oldAssetCells = oldGrid.assetCells
        let newAssetCells = newGrid.assetCells
        let delta = abs(newCount - oldCount)
        let isShrinking = newCount < oldCount

        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: String(localized: "格子推演"))
                    Spacer()
                    Text("\(oldCount) → \(newCount) \(unit.label)")
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.inkFaint)
                }

                if isInvalid(o.before.freedom) || isInvalid(o.newFreedom) {
                    Text("有一笔金额不对，暂时演示不了。去明细找找特别大或负数的。")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.sm)
                } else if isInsufficient(o.before.freedom) || isInsufficient(o.newFreedom) {
                    Text("先记一笔支出，才能演示格子怎么变。")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.sm)
                } else if oldGrid.isOverflow || newGrid.isOverflow {
                    Text("格子放不下了，变化看上面的数字。")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                } else if delta == 0 {
                    Text("变化不到一格，看上面的数字。")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.sm)
                } else {
                    SimDemoGrid(unit: unit, oldCount: oldCount, newCount: newCount,
                                oldAssetCells: oldAssetCells, newAssetCells: newAssetCells, phase: demoPhase)
                        .padding(.vertical, Spacing.xs)

                    HStack(spacing: 6) {
                        Image(systemName: isShrinking ? "flame" : "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(isShrinking ? Color.flame : Color.skyDeep)
                        Text((isShrinking ? String(localized: "熄灭 \(delta) 格") : String(localized: "点亮 \(delta) 格"))
                             + " · " + unit.perCell)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                        Spacer()
                    }

                    demoButton(delta: delta, isShrinking: isShrinking)
                }
            }
        }
    }

    /// 演示 / 推演中 / 重播 三态按钮
    private func demoButton(delta: Int, isShrinking: Bool) -> some View {
        let title: String
        let isPlaying: Bool
        switch demoPhase {
        case .idle:    title = isShrinking ? String(localized: "演示这笔熄灭哪几格") : String(localized: "演示这笔点亮哪几格"); isPlaying = false
        case .playing: title = String(localized: "推演中…"); isPlaying = true
        case .done:    title = String(localized: "重播"); isPlaying = false
        }
        return VaultButton(title: title,
                           icon: demoPhase == .done ? "arrow.counterclockwise" : "play.fill",
                           style: isShrinking ? .destructive : .primary) {
            playDemo(delta: delta, ignite: !isShrinking)
        }
        .disabled(isPlaying)
        .opacity(isPlaying ? 0.5 : 1)
    }

    /// 触发一次推演:置 playing,计时到 totalDur 后落定到 done(停在新态)
    private func playDemo(delta: Int, ignite: Bool) {
        let start = Date()
        demoPhase = .playing(start)
        let total = simDemoTiming(delta: delta, ignite: ignite).total
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(total))
            if case .playing(let s) = demoPhase, s == start {
                demoPhase = .done
            }
        }
    }

    private func isInvalid(_ state: FreedomState) -> Bool {
        if case .invalidData = state { return true }
        return false
    }

    private func isInsufficient(_ state: FreedomState) -> Bool {
        if case .insufficientData = state { return true }
        return false
    }

}
