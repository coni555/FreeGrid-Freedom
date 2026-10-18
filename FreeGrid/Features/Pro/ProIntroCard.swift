// 老用户打开 2.0 时在首页弹的卡片（用户 2026-10-18 选的 A 版：不要整屏，弹一张卡）。
// 先讲 2.0 所有人都有的免费更新，分隔线下面才提一句 Pro；「知道了」和「看看 Pro」一样大，点「看看 Pro」才进购买页。
// 怎么弹看 IntroCardLayer，什么时候弹看 ProIntro 和 ContentView。

import SwiftUI

extension View {
    /// 在整页上面盖一层老用户的 2.0 卡片。`onAppear`：真的出现在屏幕上时调用，用来记「弹过了」
    func returningProIntro(isPresented: Binding<Bool>, onAppear: @escaping () -> Void) -> some View {
        introCard(isPresented: isPresented, onAppear: onAppear) { close, learnMore in
            ProIntroCard(onClose: close, onLearnMore: learnMore)
        }
    }
}

private struct ProIntroCard: View {
    let onClose: () -> Void
    let onLearnMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                KickerLabel(text: "FreeGrid 2.0")
                Text("这次更新了什么")
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
            }

            // 免费更新在前，写明所有人都有（AGENTS「宣发」）
            VStack(alignment: .leading, spacing: 12) {
                update("固定支出", "房租、订阅按到期日自动扣，自由天数不再跳水")
                update("日均更稳", "记账不满 90 天时，一笔大额不再让日均暴涨")
                Text("以上所有人都有，一直免费。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .padding(.leading, 32)
            }

            Hairline(color: .hairlineSoft)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    IntroCardProTag()
                    Text("新增 Pro，一次买断")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                }
                Text("自定义分类、子账户、贷款与分期、导出自由卡。\n可以先免费体验 \(ProOffer.trialDays) 天，到期自动回到免费版。")
                    .font(.system(.footnote, design: .rounded))
                    .lineSpacing(3)
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            IntroCardButtons(onClose: onClose, onLearnMore: onLearnMore)
        }
        // 先包成一个容器再给标识，不然标识会盖到里面每个按钮上
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro-intro-returning")
    }

    private func update(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Color.mossGreen)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
