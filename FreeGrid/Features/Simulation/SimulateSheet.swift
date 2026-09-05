// 模拟交易，只计算预览，不写入账本。

import SwiftUI
import SwiftData

struct SimulateSheet: View {

    @Environment(\.dismiss) private var dismiss

    // 同样需要 @Query 当前数据,实时计算影响
    @Query private var expenses: [Expense]
    @Query private var assetsArr: [UserAssets]
    @Query private var passiveSources: [PassiveSource]

    // ===== 模拟状态 =====
    @State private var amount: String = ""
    @State private var mode: TransactionKind = .expense
    /// 格子推演动画三态
    @State private var demoPhase: SimDemoPhase = .idle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    bannerCard
                    modePicker
                    amountInput
                    if let amt = Double(amount), FinancialFormatting.validAmount(amt) {
                        let impact = TransactionImpact(
                            snapshot: FinancialSnapshot(expenses: expenses, passiveSources: passiveSources,
                                                        assets: assetsArr.first),
                            kind: mode, amount: amt
                        )
                        previewCard(impact: impact)
                        gridDemoCard(impact: impact)
                    } else {
                        hintCard
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            // 金额或模式一变,演示回到静止态(旧网格),让用户重新观察这一笔
            .onChange(of: amount) { _, _ in demoPhase = .idle }
            .onChange(of: mode) { _, _ in demoPhase = .idle }
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

    /// 顶部 banner: silverline 风 — 极淡 sky wash 底 + 深蓝字
    private var bannerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Color.skyDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text("模拟模式")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                Text("不会扣资产,不会写入账本,只是看看决策影响。")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer()
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.skyFaint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.sky.opacity(0.3), lineWidth: 1)
        )
    }

    private var modePicker: some View {
        Picker("模拟类型", selection: $mode) {
            ForEach(TransactionKind.allCases, id: \.self) { kind in
                Text(kind == .expense ? "模拟支出" : "模拟收入").tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    /// 金额输入:VaultCard silverline 风
    private var amountInput: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                KickerLabel(text: mode == .expense ? "假设花掉 (元)" : "假设收入 (元)")
                HStack(spacing: 6) {
                    Text("¥")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Color.inkFaint)
                    TextField("0.00", text: $amount)
                        .decimalKeyboard()
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.ink)
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
                KickerLabel(text: mode == .expense ? "戴维斯三杀预览" : "自由增长预览")

                TransactionImpactView(impact: impact)

                Text(mode == .expense
                     ? "这笔消费对自由天数的传导效应。"
                     : "这笔收入对自由天数的回血效应。")
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
        let oldGrid = FreedomMath.gridState(for: o.before.freedom, lockedAssets: o.before.lockedAssets,
                                            netWorth: o.before.netWorth, unit: unit)
        let newGrid = FreedomMath.gridState(for: o.newFreedom, lockedAssets: o.before.lockedAssets,
                                            netWorth: o.newNetWorth, unit: unit)
        let oldCount = oldGrid.count
        let newCount = newGrid.count
        let oldAssetCells = oldGrid.assetCells
        let newAssetCells = newGrid.assetCells
        let delta = abs(newCount - oldCount)
        let isShrinking = newCount < oldCount

        VaultCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KickerLabel(text: "格子推演")
                    Spacer()
                    Text("\(oldCount) → \(newCount) \(unit.label)")
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Color.inkFaint)
                }

                if isInvalid(o.before.freedom) || isInvalid(o.newFreedom) {
                    Text("现有财务数据异常, 暂时不能推演自由格。")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.sm)
                } else if isInsufficient(o.before.freedom) || isInsufficient(o.newFreedom) {
                    Text("先记一笔支出，建立可比较的基线后再推演自由格。")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.sm)
                } else if oldGrid.isOverflow || newGrid.isOverflow {
                    Text("网格已达到当前档位的显示上限，自由天数的变化见上方预览。")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                } else if delta == 0 {
                    Text("变化不足一格，自由天数的变化见上方预览。")
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
                        Text(isShrinking ? "熄灭 \(delta) 格 · 每格 1 \(unit.label)自由"
                                       : "点亮 \(delta) 格 · 每格 1 \(unit.label)自由")
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
        case .idle:    title = isShrinking ? "演示这笔熄灭哪几格" : "演示这笔点亮哪几格"; isPlaying = false
        case .playing: title = "推演中…"; isPlaying = true
        case .done:    title = "重播"; isPlaying = false
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
