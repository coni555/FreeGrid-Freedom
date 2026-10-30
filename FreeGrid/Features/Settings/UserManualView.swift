// 设置 → FreeGrid → 使用说明：App 里能读的说明书。先是章节列表，点一章进去读。
// 内容和仓库根目录的 `使用说明.md` 是同一份，只去掉了链接和 App 里用不上的话；改功能时两处一起改。
// 粗体用 Markdown 的 **…** 写在字符串里；文字按系统语言从 String Catalog 取。

import SwiftUI

struct ManualChapter: Identifiable {
    let title: LocalizedStringResource
    let icon: String
    let blocks: [ManualBlock]
    var id: String { title.key }
}

enum ManualBlock {
    /// 一段话
    case text(LocalizedStringResource)
    /// 段内小标题
    case heading(LocalizedStringResource)
    /// 一组要点
    case bullets([LocalizedStringResource])
    /// 提醒：左边一道细线
    case note(LocalizedStringResource)
}

enum UserManual {
    static let chapters: [ManualChapter] = [
        ManualChapter(title: "自由天数怎么算", icon: "square.grid.3x3", blocks: [
            .text("**自由天数**：按现在的钱和花法，你的钱预计还能撑多少天。"),
            .note("自由天数 ≈ 可动用资产 ÷（日常日均 − 被动收入日均）"),
            .text("实际推算时，还会按日历扣掉以后的固定支出和贷款，所以首页的数字和直接套公式会有出入。"),
            .heading("三条规则"),
            .bullets([
                "**固定支出按付款日扣**。房租、水电、会员这类定期付的钱，在钱包里设好金额、周期和下次付款日。推算时到哪天扣哪笔，到期自动记账。因为早已算进去，交房租那天数字不会突然掉一大截。",
                "**记账初期，大额支出摊开算**。记账不满 90 天时，单笔特别大的支出（比如刚开始记账就买的电脑）按 90 天摊进日均。满 90 天后，日均就是支出总额 ÷ 记账天数。",
                "**算哪些钱，你来定**。房子、长期投资、暂时不动的储蓄，可以不计入自由天数：它们仍算在净值里，但不算进可动用资产。免费版按资产整体选；**Pro** 可以逐个资产项、逐个现金账户选。",
            ]),
            .heading("数字为什么会变"),
            .bullets([
                "**收入到账、攒下钱**：自由天数变多，格子点亮。",
                "**花钱**：自由天数变少，格子熄灭。",
                "**被动收入覆盖全部开销**（日常加固定）：钱不再被消耗，自由天数显示 **∞**。",
            ]),
            .text("不到 1 年按天显示，1 到 10 年按月，10 年以上按年。"),
            .note("刚开始记账时日均还不准，数字会跳得厉害。记一两周就会稳定。"),
        ]),
        ManualChapter(title: "首页", icon: "chart.line.uptrend.xyaxis", blocks: [
            .heading("自由天数与趋势"),
            .text("大数字是当前的自由天数，下面写着大约能撑到哪一天。卡片底部是最近 12 周的趋势，点一下展开或收起。"),
            .text("左上角按钮切换深色、浅色，右上角按钮调整大数字的位置。"),
            .heading("格子"),
            .bullets([
                "一格是一天自由；天数多了，一格换成一月或一年。",
                "**金色**来自资产，**蓝色**来自现金。有钱没计入时，图例旁会写出来。",
                "**Pro** 有贷款时，还款日那一格中间打一个孔；最后那个淡色带孔的格子，是钱撑不到的下一次还款。",
            ]),
            .heading("记支出、记收入"),
            .bullets([
                "填金额、分类（收入选来源）和日期，「今天」「昨天」一点就选。",
                "保存前，下面会预览这一笔对净值、日均和自由天数的影响。**预览不改数据。**",
                "保存后，支出从现金扣，收入进现金。顶部出现「撤销」时，点一下就撤回这一笔。",
                "**Pro** 现金拆成多个账户时，可以选从哪个账户扣、存进哪个账户。",
            ]),
            .heading("模拟一笔"),
            .text("想买东西前，先输入金额，看自由天数会少几天、哪些格子会熄灭。模拟不改账本和余额。决定买了，点「就这么花了，记为支出」。"),
            .heading("数字小卡"),
            .text("底部的卡片放哪些、什么顺序由你定。在首页上按住一张卡，浮起来后拖到想放的位置。点任意一张卡，或点下面的「编辑卡片」，打开编辑面板：上面是首页上的卡，点左边的减号移除，按住右边的把手也能拖动换顺序；移除的卡回到下面「还可以添加」，点加号加回来，也可以「全部添加」；改乱了点「恢复默认」。卡片多于一行时，下面左边有「收起 / 展开其余 N 张」，收起后只留第一行，把最想看的拖到第一行就行。可选的小卡有："),
            .bullets([
                "**日均**：平均每天花多少。小字拆成「日常 · 固定」，固定是固定支出折成的每天。",
                "**本月花销**：本月 1 号到今天花了多少，和上个月同一段比。自动扣的房租、月供也算在内。",
                "**今日花销**：今天的日常支出，比日常日均高还是低。",
                "**记账天数**：从第一笔支出到今天。不满 90 天时写着再记多少天，日均趋势会更清晰。",
                "**可动用资产**：算进自由天数的现金和资产一共多少，小字是资产和现金各占几成。",
                "**被动收入覆盖**：被动收入能覆盖多少开销。",
                "**下次固定支出**：最近一笔房租、订阅或月供还有几天扣。",
            ]),
            .text("**今日对比长条**：今天的日常支出和日常日均比，房租这类固定支出不算在内。它和小卡一样能拖、能移除，只是总占一整行。"),
            .text("**目标长条**（Pro）：每个自己的目标都能放一条，没加时不在首页上，想天天看的从「还可以添加」加进来。左边是现在的自由天数和目标，右边是还差多少；定了日子的，下面写还有几天。点它改这个目标，和自检里「我的目标」是同一份。"),
            .heading("桌面和锁屏小组件"),
            .text("在桌面或锁屏上长按空白处，点「编辑」→「添加小组件」，找到 FreeGrid。小组件上的数和首页一样，每天零点自己往前走；记了账，回到桌面就会更新。"),
            .bullets([
                "**自由天数**：桌面小号；锁屏圆形、长条，以及日期旁边的一行。",
                "**自由看板**（Pro）：桌面中号，自由天数旁边放两项数字。长按小组件点「编辑小组件」，从日均、本月花销、记账天数这些里面选。",
                "**我的目标**（Pro）：桌面小号、中号，锁屏圆形和长条。写着还差多少天自由，定了日子的倒数还有几天。长按点「编辑小组件」选看哪个目标。",
            ]),
            .note("超过 30 天没打开 FreeGrid，小组件会停在最后一天，提示打开 App 更新。"),
        ]),
        ManualChapter(title: "钱包（资产与现金）", icon: "banknote", blocks: [
            .heading("资产和现金有什么区别"),
            .bullets([
                "**资产**（金色）：短期不打算花的钱，比如定期、股票、基金、房子。",
                "**现金**（蓝色）：随时能花的钱，比如活期、微信、支付宝。",
            ]),
            .text("**净值** = 资产 + 现金，自动算出。点一行改金额。"),
            .heading("拆成多个账户（Pro）"),
            .text("资产可以拆成「房」「定期」「基金」各一项，现金可以拆成「微信」「支付宝」「招行卡」各一个账户。新加一项时，先选钱从哪来："),
            .bullets([
                "**从已有的拆出**：把已记的钱分一部分出来，总数不变。",
                "**新增的钱**：之前没记过的钱，总数变多。",
            ]),
            .text("**扣款顺序**：记支出时，从排在最前、钱够的现金账户整笔扣。按住右边的三道横线拖动，调整顺序。"),
            .text("想回到一个总数，点「合并成一个总数」，金额不变。"),
            .heading("哪些钱计入自由天数"),
            .bullets([
                "**免费**：「资产」前面的方格是开关，选资产整体计不计入。现金总是计入。",
                "**Pro**：每个资产项前面的方格、每个现金账户前面的序号，都是它自己的开关。新加的默认计入。",
            ]),
            .text("不计入的钱仍算在净值里，只是不进自由天数。"),
            .heading("调拨"),
            .text("钱在资产和现金之间挪，用调拨。比如拿活期买了基金：从现金调到资产。调拨只换位置，**净值不变**。"),
            .heading("固定支出和贷款"),
            .bullets([
                "**固定支出**（免费）：房租、水电、会员。填每次付多少、几个月付一次、下次哪天付。几个月付一次的，填那一次付的总数。",
                "**贷款**（Pro）：房贷、车贷、分期。填每月还多少、几号还、还剩几期。",
            ]),
            .text("到期那天自动记一笔支出，从现金扣。**只是在 App 里记账，不会动你的银行卡，也不会替你还款。**"),
            .bullets([
                "现金不够、没扣成的那期会标出来。展开后选从现金扣，或「从别处还的」。",
                "**避免重复算**：添加时，如果以前手动记过同样金额的支出，App 会找出来。核对后勾上的，不再算进日均。",
            ]),
            .heading("被动收入"),
            .text("租金、利息、股息这类不靠上班、预计能一直到账的钱。填每次到账多少、几个月到账一次。"),
            .note("被动收入只用来算自由天数，到账时不会自动加进现金。收到了照常记一笔收入。"),
            .heading("钱与时间（Pro）"),
            .text("在设置 → 外观 → 钱包页面，选「经典」或「钱与时间」。只是样子不同，账本一样。"),
            .bullets([
                "右上角切到钟，整页金额换成「够日常花几天」。",
                "净值下面那条线按账户分段，点一段跳到对应的资产或现金。",
                "点「资产」「现金」标签切换，中间的圆钮是调拨。",
                "最下面「每月」把进（被动收入）和出（固定支出、贷款）放在一起比。",
            ]),
        ]),
        ManualChapter(title: "明细（历史记录）", icon: "clock.arrow.circlepath", blocks: [
            .bullets([
                "**浏览**：按月看，按天分组。点月份打开月度汇总，可以跳到任意一个月；旁边的箭头前后翻月。",
                "**修改**：点一行，改金额、分类、日期或备注。",
                "**撤销**：向左滑一行，点「撤销」。确认前会告诉你现金会怎么变。",
                "**查找**：右上角搜索金额或备注，旁边的按钮按分类筛选。**Pro**：搜到的支出可以一起移到别的分类，比如在「其他」里搜「咖啡」，把它们移到新建的「咖啡」。",
            ]),
            .text("固定支出、贷款自动记的支出也在这里。标「不计日均」的，不算进日均。"),
        ]),
        ManualChapter(title: "设置", icon: "gearshape", blocks: [
            .text("设置页是一叠卡片，点卡头展开，再点一下收起。"),
            .bullets([
                "**财富自由自检**：按你的账自动判断九个里程碑，分记录、自由天数、现金流三组，点组名可以收起。点进去看每一项还差多少；点「每月有结余」可以填每月到手收入，不填按近 90 天的收入记录。最下面可以加自己的目标（Pro，个数不限）：想要多少天自由，再选一个截止日（可不选），比如攒够半年的应急金，或者给 GAP 定个日子。目标直接和首页的自由天数比，写着现在多少、还差多少；不算进里程碑。",
                "**我的自由卡**：30 天银卡，180 天香槟金，1 年黑卡；被动收入覆盖全部开销是 ∞ 卡。卡上只写天数，不写金额。**Pro** 可以导出成卡片或海报分享。",
                "**外观**：主题（浅色、深色、跟随系统）、首页大数字的位置、钱包页的样式。",
                "**语言**：在外观卡的「语言」里选中文或 English，当场切换。没选过时跟 iOS 的语言走。",
                "**账本**：支出分类、备份与恢复。免费版是默认九类；**Pro** 可以添加分类、配图标、改名、排序；点一个分类 →「全部 N 笔移到…」，把它的账并进另一个分类。",
                "**FreeGrid Pro**：对比免费版和 Pro，开始免费体验、购买或恢复购买。",
            ]),
            .text("使用一段时间后，系统可能邀请你评分或写评论，可以直接关闭，不影响任何功能。也可以从设置 → FreeGrid → 评价与反馈主动评价。"),
        ]),
        ManualChapter(title: "备份与换手机", icon: "externaldrive", blocks: [
            .text("FreeGrid 没有账号，账本只存在这台设备上，**不会自动同步到新手机**。"),
            .note("删了 App，账本就没了。卸载、重装、换手机前，先导出 JSON 备份。"),
            .text("在设置 → 账本 → 备份与恢复："),
            .bullets([
                "**导出 JSON**：完整备份，能导回 FreeGrid。",
                "**导出 CSV**：用 Excel、Numbers 看的流水表，**不能导回**。",
                "**从 JSON 导入**：写入前先看预览，重复的跳过，资产和现金怎么处理由你选。",
                "**清空记账数据**：不能撤销。清空前先导出 JSON。",
            ]),
            .text("外观这类本机设置不在备份里，换手机后要重新选。建议每月导一次 JSON，存到「文件」或你常用的云盘。"),
            .heading("怎么换手机"),
            .text("旧手机导出 JSON，存到新手机拿得到的地方。新手机装好 FreeGrid，在备份与恢复里选「从 JSON 导入」。"),
        ]),
        ManualChapter(title: "常见问题", icon: "questionmark.circle", blocks: [
            .heading("自由天数为什么显示「—」？"),
            .text("要两样都有：钱包里填了钱，并且记过至少一笔支出。如果提示「有一笔金额不对」，去明细找特别大或负数的那笔。"),
            .heading("为什么和我自己算的不一样？"),
            .text("它不是「可动用资产 ÷ 月开销」。日均是记账以来的平均，不满 90 天时大额支出会摊开；被动收入从每天的消耗里减掉；固定支出和贷款按日历扣；不计入的钱不算。"),
            .text("对不上时，先看钱包里的计入设置、固定支出和被动收入，再看明细里的支出。"),
            .heading("以前把房租记成普通支出，要删吗？"),
            .text("不用。在钱包加上这笔固定支出，以后到日子自动记。添加时 App 会找出以前手记的同样金额的支出，核对后可以不再算进日均。"),
            .heading("加了被动收入，余额怎么没变？"),
            .text("被动收入只用来算自由天数。到账后记一笔收入，现金才会变。"),
            .heading("系统换了深色，App 没跟着变？"),
            .text("设置 → 外观 → 主题，选「系统」。"),
            .heading("可以先体验 Pro 吗？"),
            .text("可以。在购买页点「免费体验 7 天」，Pro 全部打开。每个 Apple 账户一次，到期自动回到免费版，**不会自动扣费**。买断优惠价在开启体验后保留 14 天，之后恢复原价；没开启过体验的，直接买也是优惠价。"),
            .heading("体验结束后，数据会丢吗？"),
            .text("不会，所有记账数据都保留。只是："),
            .bullets([
                "体验期间设置的分类继续可用，修改需 Pro。",
                "钱包页回到经典样式。",
                "自由卡可以查看，不能导出。",
                "拆好的资产、现金子账户照常显示和计算，不能修改；可以合并成一个总额继续编辑。",
                "贷款停用：不再自动记账，也不计入自由天数，可以删除。",
                "看板和目标小组件换成一句说明，自由天数小组件照常。",
            ]),
            .text("体验结束时会弹出说明，帮你一步步调整；关掉后可以从「设置 → FreeGrid Pro」再打开。买断后全部恢复。"),
            .heading("买过 Pro，换手机后怎么找回？"),
            .text("用同一个 Apple 账户，在购买页点「恢复购买」。"),
            .note("恢复购买只找回 Pro，不找回账本。账本要用之前导出的 JSON 导入。"),
            .heading("会上传我的记账数据吗？"),
            .text("不会。账本只存在本机，没有账号、没有埋点。只有购买和恢复 Pro 时经过 Apple。"),
            .text("JSON 备份存进 iCloud Drive 或别的云盘后，由你选的服务保存。"),
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
        .navigationTitle(Text(chapter.title))
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

    private func paragraph(_ text: LocalizedStringResource, color: Color = .ink) -> some View {
        Text(AppLanguage.attributed(text))
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(color)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
