//
//  StoreRecoveryView.swift
//  FreeGrid
//
//  SwiftData 无法打开时的非破坏性恢复页；不读取财务模型，也不提供自动删库。
//

import SwiftUI

struct StoreRecoveryView: View {
    let failure: StoreBootstrap.Failure
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.flame)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    KickerLabel(text: "Store Recovery")
                    Text("本地数据暂时无法打开")
                        .font(.system(.title, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                    Text("FreeGrid 没有删除、覆盖或重置任何数据。请先重试；不要卸载 App。")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VaultCard {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        KickerLabel(text: "下一步")
                        recoveryStep("1", "点“重试打开”再次连接本地数据库。")
                        recoveryStep("2", "若仍失败，分享诊断文本给开发者；诊断不含金额、备注、路径或备份内容。")
                        recoveryStep("3", "如你有 JSON 备份，待数据库恢复可打开后，在 Assets · 数据管理中导入。")
                    }
                }

                VaultButton(title: "重试打开", icon: "arrow.clockwise", style: .primary) {
                    onRetry()
                }
                .accessibilityIdentifier("store-retry-button")

                ShareLink(item: failure.diagnosticText) {
                    Label("分享安全诊断", systemImage: "square.and.arrow.up")
                        .font(.system(.body, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ink)
                .overlay(Capsule().stroke(Color.hairline, lineWidth: 1))

                Text("诊断代码 · \(failure.code)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.paper.ignoresSafeArea())
        .accessibilityIdentifier("store-recovery-view")
    }

    private func recoveryStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(number)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(Color.skyDeep)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.skyDeep, lineWidth: 1))
            Text(text)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
