// 设置 → FreeGrid → 使用说明：App 里能读的说明书。先是章节列表，点一章进去读。
// 内容和仓库根目录的 `使用说明.md` 是同一份，只去掉了链接和 App 里用不上的话；改功能时两处一起改。
// 粗体用 Markdown 的 **…** 写在字符串里。

import SwiftUI

struct ManualChapter: Identifiable {
    let title: String
    let icon: String
    let blocks: [ManualBlock]
    var id: String { title }
}

enum ManualBlock {
    /// 一段话
    case text(String)
    /// 段内小标题
    case heading(String)
    /// 一组要点
    case bullets([String])
    /// 提醒：左边一道细线
    case note(String)
}

enum UserManual {
    static let chapters: [ManualChapter] = [
        ManualChapter(title: "自由天数怎么算", icon: "square.grid.3x3", blocks: [
            .text("FreeGrid 只回答一个问题：**按现在的花法，你的钱还能撑多少天？** 这个数字叫自由天数。"),
            .note("自由天数 = 计入自由天数的钱 ÷（日常日均 − 被动收入日均）"),
            .text("再加上三条规则："),
            .bullets([
                "**固定支出按日历扣**。房租、水电、会员这类隔一段时间付一次的钱，在 Assets 里填一次，到日子自动记一笔。自由天数按日历往后推，到期那天再扣这笔钱。交房租那天数字只少一天，不会突然掉一大截。",
                "**大额支出先摊开**。记账不满 90 天时，单笔特别大的支出（比如第一周买的电脑）按 90 天摊进日均，日均不会一下翻好几倍。记满 90 天以后就是总支出 ÷ 记账天数。",
                "**不是所有钱都要算进去**。房子、车子、留给以后的储蓄，可以选不计入自由天数。不计入的钱仍在净值里，只是不进自由天数。",
            ]),
            .heading("数字怎么变"),
            .bullets([
                "收入到账、攒下钱，自由天数变多，格子点亮。",
                "花钱，自由天数变少，格子熄灭。",
                "被动收入（租金、利息、股息这类不靠上班的钱）覆盖了全部开销（日常开销加上固定支出），钱就不会再被消耗，自由天数变成 **∞**。",
            ]),
            .text("大数字会自动换单位：不到 1 年显示天，1 到 10 年显示月，10 年以上显示年。"),
            .note("刚开始只记了几天账时，日均还不准，自由天数会跳得厉害。记一两周后会稳定下来。"),
        ]),
        ManualChapter(title: "首页", icon: "chart.line.uptrend.xyaxis", blocks: [
            .heading("大数字"),
            .bullets([
                "自由天数，下面一行写着大约能撑到哪一天。",
                "卡里底部是最近 12 周的趋势，点这一行展开或收起。",
                "右上角的按钮换大数字的位置，左上角的按钮切换深色浅色。",
            ]),
            .heading("格子"),
            .bullets([
                "一格是一天自由；天数多了，一格换成一月或一年。",
                "金色来自资产，蓝色来自现金。有钱不计入时，图例旁会写出来。",
                "**Pro** 有贷款时，还款日那一格打一个孔；最后那个淡色的孔，是钱撑不到的下一次还款。",
            ]),
            .heading("记支出、记收入"),
            .bullets([
                "填金额、分类（收入填来源）、日期，「今天」「昨天」一点就选。",
                "下面实时显示这一笔会让净值、日均和自由天数怎么变，保存前不会记进去。",
                "支出从现金扣，收入进现金。记完顶部会出现「撤销」，点一下就当没记过。",
                "**Pro** 现金拆成多个账户时，可以选从哪个账户扣、存进哪个账户。",
            ]),
            .heading("模拟一笔"),
            .text("花钱之前先来试：输入一个金额，看这笔会让自由天数少几天，再看格子熄灭哪几格。只是模拟，不改余额。决定买了，点「就这么花了，记为支出」。"),
            .heading("数字小卡"),
            .bullets([
                "**日均**：每天平均花多少。小字拆成「日常 · 固定」，固定是固定支出折成的每天。",
                "**被动收入覆盖**：被动收入能覆盖多少开销。",
                "**记账天数**：从第一笔支出到今天。",
                "**今天**：今天花了多少，只和日常开销比，不算房租这类固定支出。",
            ]),
        ]),
        ManualChapter(title: "Assets", icon: "banknote", blocks: [
            .heading("资产和现金"),
            .text("净值 = 资产 + 现金，自动算出来。**资产**（金色）是不打算马上花的钱：定期、股票、基金、房子。**现金**（蓝色）是随时能花的钱：活期、微信、支付宝。点一行改金额。"),
            .text("**Pro** 资产可以拆成「房」「定期」「基金」各一项，现金可以拆成「微信」「支付宝」「招行卡」各一个账户。"),
            .bullets([
                "新加一项时，选这笔钱是从已有的拆出（总数不变），还是新增的钱（总数变多）。",
                "现金账户有先后：记支出时，从排第一个、钱够的账户整笔扣。按住右边拖动调整顺序。",
                "想回到一个总数，点「合并成一个总数」，金额不变。",
            ]),
            .heading("计入自由天数"),
            .bullets([
                "免费：「资产」前面的方格是开关，选资产整体计不计入。现金总是计入。",
                "**Pro**：每个资产项前面的方格、每个现金账户前面的序号，都是它自己的开关。新加的默认计入。",
            ]),
            .heading("调拨"),
            .text("钱在资产和现金之间挪，用调拨，净值不变。比如拿活钱买了基金：从现金调到资产。"),
            .heading("固定支出和贷款"),
            .bullets([
                "**固定支出**（免费）：房租、水电、会员。填每次付多少、几个月付一次、下次哪天付。不按月付时，金额填一次付的总数。",
                "**贷款**（Pro）：房贷、车贷、分期。填每月还多少、几号还、还剩几期。",
                "到期那天自动记一笔支出，从现金扣。只在 App 里记账，不会动你的银行卡。",
                "现金不够、没扣成的那期会标出来，展开后选从现金扣，或者「从别处还的」。",
                "添加时，如果以前手动记过同样金额的支出，App 会找出来，勾上的不再重复算进日均。",
            ]),
            .heading("被动收入"),
            .text("租金、利息、股息这类不靠上班、预计能一直到账的钱。填每次到账多少、几个月到账一次。"),
            .note("被动收入只用来算自由天数，到账时不会自动记账。收到了照常记一笔收入。"),
            .heading("钱与时间（Pro）"),
            .text("Settings → 外观 → Assets 页面，可以选经典或钱与时间。账本完全一样，只是样子不同。"),
            .bullets([
                "右上角切到钟，整页的金额换成「够日常花几天」。",
                "净值下面那条线一段是一个账户，点一段跳到它那一边。",
                "「资产」「现金」两张标签点着切换，中间的圆钮是调拨。",
                "最下面「每月」把进（被动收入）和出（固定支出、贷款）放在一起比。",
            ]),
        ]),
        ManualChapter(title: "History", icon: "clock.arrow.circlepath", blocks: [
            .bullets([
                "按月看，按天分组。点月份打开月度汇总，跳到任意一个月；旁边的箭头前后翻月。",
                "点一行，修改金额、分类、日期或备注。",
                "向左滑一行，撤销这笔。撤销前会告诉你现金会怎么变。",
                "右上角搜索备注或金额，旁边的按钮按分类筛选。",
                "自动扣的固定支出、贷款也在这里。标「不计日均」的不算进日均。",
            ]),
        ]),
        ManualChapter(title: "Settings", icon: "gearshape", blocks: [
            .text("Settings 是一叠卡，点卡头抽出来，再点一下收回。"),
            .bullets([
                "**财富自由自检**：八个里程碑，全部按你的账自动判断。点进去看每一项还差多少。",
                "**我的自由卡**：30 天银卡，180 天香槟金，1 年黑卡；被动收入覆盖全部开销是 ∞ 卡。卡上只写天数，不写金额。**Pro** 可以分享成卡片或海报。",
                "**外观**：主题（浅色、深色、跟随系统）、首页大数字的位置、Assets 页面的样式。",
                "**账本**：支出分类、备份与恢复。免费版是默认九类；**Pro** 可以添加自己的分类、配图标、改名、排序、合并。",
                "**FreeGrid Pro**：看免费版和 Pro 各有什么，免费试用、购买或恢复购买。",
            ]),
        ]),
        ManualChapter(title: "备份与换手机", icon: "externaldrive", blocks: [
            .text("FreeGrid 没有账号，账本只存在这台手机里，不上传。"),
            .note("删了 App，数据就没了。JSON 备份是唯一的安全绳。"),
            .text("在 Settings → 账本 → 备份与恢复："),
            .bullets([
                "**导出 JSON**：完整备份，能原样导回。换手机、重装前一定先导一份。",
                "**导出 CSV**：用 Excel、Numbers 打开看的流水表，不能导回。",
                "**从 JSON 导入**：写入前先给你看预览，重复的跳过，资产和现金怎么处理由你选。",
                "**清空记账数据**：不能撤销，先导出一份 JSON 再清空。",
            ]),
            .text("外观这类本机设置不在备份里，换手机后要重新选。建议每个月导一次 JSON，存到「文件」或 iCloud Drive。"),
            .heading("换手机"),
            .text("旧手机导出 JSON，存到新手机能拿到的地方，新手机装好 FreeGrid，再从 JSON 导入。"),
        ]),
        ManualChapter(title: "常见问题", icon: "questionmark.circle", blocks: [
            .heading("自由天数一直是「—」？"),
            .text("要两样都有：Assets 里填了钱，并且记过至少一笔支出。如果提示「有一笔金额不对」，去 History 找特别大或负数的那笔。"),
            .heading("和我心算的不一样？"),
            .text("它不是「净值 ÷ 月开销」。日均是记账以来的平均值，不满 90 天时大额支出会摊开；被动收入会从每天的消耗里减掉；固定支出按日历扣；不计入的钱不算。"),
            .heading("房租以前当普通支出记的，要删吗？"),
            .text("不用删。在 Assets 加上这笔固定支出后，以后到日子自动记。添加时 App 会找出以前手记的同样金额的支出，问你要不要不再算进日均。"),
            .heading("被动收入到账了，余额怎么没变？"),
            .text("被动收入只用来算自由天数，不会自动记账。收到了照常记一笔收入。"),
            .heading("系统换了深色，App 没跟着变？"),
            .text("Settings → 外观 → 主题，选「系统」。"),
            .heading("Pro 能先试用吗？"),
            .text("能。购买页点「免费试用 7 天」，Pro 全部打开。每个 Apple 账户一次，不扣费，到期不会自动续费。从开始试用起 14 天内买断用试用专属价，之后是原价。"),
            .heading("试用结束后，记下的东西会怎样？"),
            .text("都还在。分类回到默认九类可选，Assets 回到经典样式，自由卡不能导出；已经拆好的子账户、加过的贷款照常显示、照常计算、照常自动扣，只是不能再新增和修改。买断后全部恢复。"),
            .heading("买过 Pro，换手机后怎么找回？"),
            .text("打开 Pro 的购买页，点「恢复购买」，用同一个 Apple 账户就能找回。"),
            .heading("数据会被上传吗？"),
            .text("不会。账本不联网，没有账号、没有埋点。只有购买和恢复 Pro 时经过 Apple。"),
        ]),
    ]
}

/// 章节列表，和「使用指引」那一页同一种样子
struct UserManualPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("每个功能在哪、怎么用、数字怎么算。想在页面上看着学，用「使用指引」。")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.lg)
                VaultCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(UserManual.chapters.enumerated()), id: \.offset) { index, chapter in
                            if index > 0 {
                                Hairline().padding(.leading, Spacing.lg + 26 + Spacing.md)
                            }
                            NavigationLink {
                                ManualChapterPage(chapter: chapter)
                            } label: {
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: chapter.icon)
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color.inkMuted)
                                        .frame(width: 26, alignment: .center)
                                    Text(chapter.title)
                                        .font(.system(.body, design: .rounded))
                                        .foregroundStyle(Color.ink)
                                    Spacer(minLength: Spacing.sm)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color.inkGhost)
                                }
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("manual-chapter-\(index)")
                        }
                    }
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle("使用说明")
        .inlineNavTitle()
    }
}

/// 一章：小标题、段落、要点、提醒，从上往下排
private struct ManualChapterPage: View {
    let chapter: ManualChapter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(Array(chapter.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle(chapter.title)
        .inlineNavTitle()
    }

    @ViewBuilder
    private func blockView(_ block: ManualBlock) -> some View {
        switch block {
        case .heading(let title):
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color.ink)
                .padding(.top, Spacing.sm)
        case .text(let text):
            paragraph(text)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.inkFaint)
                            .frame(width: 4, height: 4)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        paragraph(item)
                    }
                }
            }
        case .note(let text):
            HStack(spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.skyDeep)
                    .frame(width: 2)
                paragraph(text, color: .inkMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func paragraph(_ text: String, color: Color = .ink) -> some View {
        Text(Self.styled(text))
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(color)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 只认 **粗体**；解析不了就原样显示
    private static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
