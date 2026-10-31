// 老用户更新后在首页弹的公告卡片。文案是用户 2026-10-31 定的；怎么弹看 IntroCardLayer，什么时候弹看 UpdateNotice 和 ContentView。

import SwiftUI

extension View {
    /// 在整页上面盖一层更新公告。`onAppear`：真的出现在屏幕上时调用，用来记「看过了」
    func updateNotice(isPresented: Binding<Bool>, onAppear: @escaping () -> Void) -> some View {
        introCard(isPresented: isPresented, onAppear: onAppear) { close, _ in
            UpdateNoticeCard(onClose: close)
        }
    }
}

private struct UpdateNoticeCard: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 放得下就不滚动；字号调大或屏幕矮时只滚动内容，按钮一直在
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
                    .scrollIndicators(.hidden)
            }
            VaultButton(title: String(localized: "开始使用"), verticalPadding: 12, action: onClose)
                .accessibilityIdentifier("update-notice-close")
        }
        // 先包成一个容器再给标识，不然标识会盖到里面的按钮上
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("update-notice")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                KickerLabel(text: "FreeGrid \(UpdateNotice.version)")
                Text("让每一笔记录，都更从容。")
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 14) {
                item(String(localized: "分类支出，一目了然"),
                     String(localized: "点击明细页月份卡片中的「N 笔」，即可查看各分类的支出明细。同时新增扇形图。"))
                item(String(localized: "新增「按月记账」"),
                     String(localized: "适合不太想每天记账的小伙伴，每月只需填写支出总额。前往「设置 → 账本 → 记账方式」切换。原有记录将完整保留，切换后暂时隐藏。"))
                item(String(localized: "iCloud 自动备份"),
                     String(localized: "默认开启，每天最多自动备份一次。数据保存在你的 iCloud 中，可随时在「备份与恢复」中关闭。"))
                item(String(localized: "分类管理升级"),
                     String(localized: "支持批量合并账目分类，也可根据筛选结果灵活拆分。"),
                     showsProTag: !ProStore.shared.isUnlocked)
            }
        }
    }

    private func item(_ title: String, _ detail: String, showsProTag: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Color.mossGreen)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                    if showsProTag { IntroCardProTag() }
                }
                Text(detail)
                    .font(.system(.footnote, design: .rounded))
                    .lineSpacing(2)
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
