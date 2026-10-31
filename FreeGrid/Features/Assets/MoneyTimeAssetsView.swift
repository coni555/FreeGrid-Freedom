// Assets 新版「钱与时间」：从上到下是
//   净值（右上角 ¥ / 天 换单位；天的时候就是自由天数）+ 按账户分段的横线；
//   「资产 | 现金」两张标签，选中的那张和下面的面板连成一块，两张中间的圆钮是调拨；
//   「每月」：被动收入（进）和固定支出、贷款（出）放在一起比。
// 切到「天」时，整页的金额都换成「够日常花几天」。各行和增删改都用和经典版同一套 AssetRows / CashRows / LoanRows。

import SwiftUI
import SwiftData

struct MoneyTimeAssetsView: View {
    @Query private var assetsArr: [UserAssets]
    @Query private var expenses: [Expense]
    @Query private var passiveSources: [PassiveSource]
    @Query(sort: [SortDescriptor(\AssetItem.sortOrder), SortDescriptor(\AssetItem.createdAt)])
    private var assetItems: [AssetItem]
    @Query(sort: [SortDescriptor(\CashAccount.sortOrder), SortDescriptor(\CashAccount.createdAt)])
    private var cashAccounts: [CashAccount]
    @Query(sort: [SortDescriptor(\Loan.sortOrder), SortDescriptor(\Loan.createdAt)])
    private var loans: [Loan]
    @Environment(AppGuide.self) private var guide

    @AppStorage(FreedomSettings.countsAssetsKey, store: AppPreferences.store) private var countsAssets = true
    /// 记账方式和每月写下的数：改了要马上重算
    @AppStorage(MonthlyTracking.key, store: AppPreferences.store) private var storedTracking = ""
    /// 「money」或「days」，本机偏好
    @AppStorage("assetsUnit", store: AppPreferences.store) private var unitKey = "money"
    @AppStorage("assetsTab", store: AppPreferences.store) private var tabKey = Tab.assets.rawValue
    @AppStorage("monthlyIncomeOpen", store: AppPreferences.store) private var incomeOpen = false
    @AppStorage("monthlyLoansOpen", store: AppPreferences.store) private var loansOpen = true
    @State private var showingTransfer = false

    enum Tab: String { case assets, cash }

    private var tab: Tab { Tab(rawValue: tabKey) ?? .assets }
    private var isDays: Bool { unitKey == "days" }

    private var snapshot: FinancialSnapshot {
        FinancialSnapshot(expenses: expenses, passiveSources: passiveSources, assets: assetsArr.first,
                          assetItems: assetItems, cashAccounts: cashAccounts, loans: ProFeatures.loansInEffect(loans), countsAssets: countsAssets,
                          tracking: MonthlyTracking.decode(storedTracking))
    }

    private var lockedAssets: Double { assetsArr.first?.lockedAssets ?? 0 }
    private var cash: Double { assetsArr.first?.cash ?? 0 }
    private var netWorth: Double { lockedAssets + cash }

    @Environment(\.tabActivity) private var tabActivity
    @Environment(\.tabDataClock) private var tabDataClock
    @State private var freeze = TabFreezeState()

    /// 在后台时冻住，切回来、或记完账空闲时再按最新的账重画（见 TabFreeze）
    var body: some View {
        TabFreeze(activity: tabActivity, clock: tabDataClock, state: freeze) { page }.equatable()
    }

    private var page: some View {
        // 读整本账的都在这里算好：ScrollViewReader 里的内容会被单独重跑，在那里读 @Query 就冻不住了
        let snapshot = snapshot
        let unit: AmountUnit = isDays ? .days(perDay: snapshot.dailyBurn) : .money
        let loanSummary = LoanRows.Summary(loans: ProFeatures.loansInEffect(loans), expenses: expenses)
        return NavigationStack {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(snapshot)
                            .id(Self.topID)
                        vault(snapshot)
                            .padding(.top, 34)
                        monthly(snapshot, unit: unit, loanSummary: loanSummary)
                            .padding(.top, 36)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xl)
                    .environment(\.amountUnit, unit)
                    .environment(\.drawerHints, false)
                }
                #if os(macOS)
                .assetsTopScrollEdge()
                #endif
                // 「Assets 怎么用」：回到顶部、换回钱的单位，等位置排好再开始。讲这一版自己的那套
                .task(id: guide.replays(of: .assets)) {
                    guard guide.takeReplay(.assets) else { return }
                    unitKey = "money"
                    scroller.scrollTo(Self.topID, anchor: .top)
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled, !showingTransfer else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { guide.start(.moneyTimeAssets) }
                }
                // 讲到「每月」时它在屏幕下面，先滚上来
                .guideScroll(guide, tour: .moneyTimeAssets, scroller: scroller, anchors: [
                    .netWorth: (Self.topID, .top), .unitSwitch: (Self.topID, .top),
                    .buckets: (Self.topID, .top), .transfer: (Self.topID, .top),
                    .passive: (AppGuide.Target.passive, .center), .loans: (AppGuide.Target.loans, .center),
                ])
            }
            .scrollContentBackground(.hidden)
            .dismissKeyboardOnScroll()
            .background(Color.paper)
            .paperNavigationContent()
            .navigationTitle("钱包")
            .sheet(isPresented: $showingTransfer) { TransferSheet() }
            // 新用户（还没填钱）先看现金：起步引导要圈的「现金」那一行在现金标签下面
            .onAppear { if netWorth == 0 { tabKey = Tab.cash.rawValue } }
        }
        .paperNavigationBackground()
    }

    private static let topID = "assets-top"

    // MARK: - 净值 / 自由天数

    private func hero(_ snapshot: FinancialSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                KickerLabel(text: isDays ? String(localized: "Freedom · 自由天数") : String(localized: "Net Worth · 净值"))
                    .contentTransition(.opacity)
                Spacer()
                UnitSwitch(isDays: Binding(
                    get: { isDays },
                    set: { newValue in withAnimation(.snappy(duration: 0.4)) { unitKey = newValue ? "days" : "money" } }
                ))
                .guideTarget(.unitSwitch, in: guide)
            }

            Group {
                if isDays {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Self.daysText(snapshot.freedom))
                            .font(.system(size: 64, weight: .ultraLight, design: .rounded).monospacedDigit())
                        Text("天")
                            .font(.system(size: 22, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(Color.inkMuted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("assets-hero-days")
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("¥")
                            .font(.system(size: 28, weight: .ultraLight, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                        Text(netWorth.formatted(.number))
                            .font(.system(size: 64, weight: .ultraLight, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(value: netWorth))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("assets-hero-money")
                }
            }
            .foregroundStyle(Color.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .frame(height: 76, alignment: .bottomLeading)
            .padding(.top, Spacing.sm)
            .transition(.blurReplace)
            .id(isDays)

            strata(snapshot)
                .padding(.top, Spacing.lg)
            legend(snapshot)
                .padding(.top, Spacing.md)
        }
        .guideTarget(.netWorth, in: guide)
    }

    /// 自由天数写成整天；被动收入盖住开销时是 ∞
    static func daysText(_ state: FreedomState) -> String {
        switch state {
        case .finite(let days): return Int(max(0, days).rounded(.down)).formatted(.number)
        case .covered: return "∞"
        case .insufficientData, .invalidData: return "—"
        }
    }

    // MARK: - 横线：一项资产或一个现金账户一段

    private struct Segment: Identifiable {
        enum Kind { case asset, cash, reserved }
        let id: String
        let amount: Double
        let kind: Kind
        var isCash: Bool { kind == .cash }
    }

    /// 钱的单位下画净值的构成（不计入的资产也是净值）；天的单位下只画算进自由天数的钱
    private var segments: [Segment] {
        let assets: [Segment] = assetItems.isEmpty
            ? ((isDays && !countsAssets) ? [] : [Segment(id: "assets", amount: lockedAssets, kind: .asset)])
            : assetItems.filter { !isDays || $0.countsInFreedom }
                .map { Segment(id: $0.id.uuidString, amount: $0.amount, kind: .asset) }
        let cashParts: [Segment] = cashAccounts.isEmpty
            ? [Segment(id: "cash", amount: cash, kind: .cash)]
            : cashAccounts.filter { !isDays || $0.countsInFreedom }
                .map { Segment(id: $0.id.uuidString, amount: $0.amount, kind: .cash) }
        return (assets + cashParts).filter { $0.amount > 0 }
    }

    /// 天的单位下，这些钱光够日常花几天（不算固定支出、月供和被动收入）
    private func plainDays(_ snapshot: FinancialSnapshot) -> Double? {
        guard snapshot.dailyBurn > 0 else { return nil }
        return snapshot.freedomBase / snapshot.dailyBurn
    }

    /// 固定支出和月供留出了几天：光够日常花的天数 − 大数字。没有这回事时为 nil
    private func reservedDays(_ snapshot: FinancialSnapshot) -> Int? {
        guard isDays, case .finite(let days) = snapshot.freedom, let plain = plainDays(snapshot) else { return nil }
        let reserved = Int(plain.rounded(.down)) - Int(max(0, days).rounded(.down))
        return reserved > 0 ? reserved : nil
    }

    /// 天的单位下，横线末尾接一段淡灰：被固定支出和月供留出去的那些天。实心部分的长度正好对应大数字，两边对得上
    private func strataParts(_ snapshot: FinancialSnapshot) -> [Segment] {
        let parts = segments
        guard let reserved = reservedDays(snapshot), let plain = plainDays(snapshot), plain > 0 else { return parts }
        let solid = parts.reduce(0) { $0 + $1.amount }
        let kept = plain - Double(reserved)
        guard kept > 0 else { return [Segment(id: "reserved", amount: 1, kind: .reserved)] }
        return parts + [Segment(id: "reserved", amount: solid * Double(reserved) / kept, kind: .reserved)]
    }

    @ViewBuilder
    private func strata(_ snapshot: FinancialSnapshot) -> some View {
        let parts = strataParts(snapshot)
        let total = parts.reduce(0) { $0 + $1.amount }
        GeometryReader { geo in
            let gap: CGFloat = 2
            let usable = max(0, geo.size.width - gap * CGFloat(max(0, parts.count - 1)))
            HStack(spacing: gap) {
                if total > 0 {
                    ForEach(parts) { part in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(part.kind == .cash ? Color.cashBlue : part.kind == .asset ? Color.assetGold : Color.hairline)
                            .frame(width: max(4, usable * CGFloat(part.amount / total)))
                    }
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.mist2)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .contentShape(Rectangle().inset(by: -10))
            .onTapGesture { location in
                // 点在哪一段，就换到它所在的标签
                var x: CGFloat = 0
                for part in parts {
                    x += max(4, usable * CGFloat(part.amount / total)) + gap
                    if location.x < x {
                        guard part.kind != .reserved else { return }
                        withAnimation(.snappy(duration: 0.3)) { tabKey = (part.isCash ? Tab.cash : Tab.assets).rawValue }
                        return
                    }
                }
            }
        }
        .frame(height: 5)
        .animation(.snappy(duration: 0.45), value: parts.map(\.amount))
        .accessibilityElement()
        .accessibilityLabel(netWorth > 0
            ? "资产占 \(FinancialFormatting.percentage(lockedAssets / netWorth))，现金占 \(FinancialFormatting.percentage(cash / netWorth))"
            : "还没有录入金额")
    }

    private func legend(_ snapshot: FinancialSnapshot) -> some View {
        HStack(spacing: Spacing.md) {
            legendDot(.assetGold, isDays || netWorth <= 0 ? String(localized: "资产") : String(localized: "资产 \(Self.percent(lockedAssets, of: netWorth))"))
            legendDot(.cashBlue, isDays || netWorth <= 0 ? String(localized: "现金") : String(localized: "现金 \(Self.percent(cash, of: netWorth))"))
            Spacer(minLength: Spacing.sm)
            Text(legendNote(snapshot))
                .font(.system(.caption2, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func legendNote(_ snapshot: FinancialSnapshot) -> String {
        if isDays {
            guard snapshot.dailyBurn > 0 else {
                // 每月花销全被固定支出占了时日常是 0，这时候不该再叫人去记账
                if snapshot.tracking.hasNumber { return String(localized: "每月花销都是固定支出") }
                return snapshot.tracking.isMonthly ? String(localized: "写下每月花销就能换算") : String(localized: "记几天账就能换算")
            }
            // 换算成天用的是日常开销，固定支出另算在「留出 N 天」里
            let perDay = String(localized: "日常开销 ¥\(FinancialFormatting.wholeNumber(snapshot.dailyBurn))/天")
            if let reserved = reservedDays(snapshot) { return String(localized: "固定支出留出 \(reserved) 天 · \(perDay)") }
            return String(localized: "按\(perDay)换算")
        }
        guard netWorth != 0 else { return String(localized: "点下面的资产、现金录入金额") }
        // 钱的单位下也说一句和自由天数有关的：真正算进去的是多少
        return String(localized: "计入自由天数 ¥\(snapshot.freedomBase.formatted(.number))")
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(.caption2, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.inkMuted)
        }
    }

    static func percent(_ part: Double, of whole: Double) -> String {
        "\(Int((part / whole * 100).rounded()))%"
    }


    // MARK: - 资产 | 现金

    private static let tabHeight: CGFloat = 98

    private func vault(_ snapshot: FinancialSnapshot) -> some View {
        let left = tab == .assets
        return ZStack(alignment: .top) {
            FolderShape(leftSelected: left, tabHeight: Self.tabHeight).fill(Color.mist)
            FolderShape(leftSelected: left, tabHeight: Self.tabHeight).stroke(Color.hairline, lineWidth: 1)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    tabButton(.assets, snapshot: snapshot)
                    tabButton(.cash, snapshot: snapshot)
                }
                .frame(height: Self.tabHeight)

                // 每组行的第一条分隔线贴着标签，遮掉它，标签和面板才连成一块
                Group {
                    if left { AssetRows() } else { CashRows() }
                }
                .padding(.horizontal, 18)
                .padding(.top, -1)
                .mask(Rectangle().padding(.top, 1))
                .padding(.bottom, Spacing.xs)
            }

            transferPivot
                .offset(y: Self.tabHeight / 2 - 16)
        }
        .animation(.snappy(duration: 0.32), value: tabKey)
        .guideTarget(.buckets, in: guide)
    }

    private func tabButton(_ which: Tab, snapshot: FinancialSnapshot) -> some View {
        let selected = tab == which
        let isAssets = which == .assets
        let counted = assetItems.isEmpty ? (countsAssets ? lockedAssets : 0)
            : assetItems.filter(\.countsInFreedom).reduce(0) { $0 + $1.amount }
        let countedCash = cash - FreedomSettings.excludedCash(of: cashAccounts)
        let amount = isAssets ? lockedAssets : cash
        let dayAmount = isAssets ? counted : countedCash
        let subtitle = isAssets
            ? (isDays && counted < lockedAssets && counted > 0 ? String(localized: "只算计入的部分")
               : AssetRows.summary(items: assetItems, total: lockedAssets, countsAssets: countsAssets) ?? String(localized: "定期、股票、基金"))
            : (isDays && countedCash < cash && countedCash > 0 ? String(localized: "只算计入的部分")
               : CashRows.countsSummary(accounts: cashAccounts)
                   ?? (cashAccounts.count > 1 ? String(localized: "\(cashAccounts.count) 个账户") : String(localized: "随时能花的钱")))
        return Button {
            withAnimation(.snappy(duration: 0.32)) { tabKey = which.rawValue }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(isAssets ? Color.assetGold : Color.cashBlue)
                        .frame(width: 8, height: 8)
                    KickerLabel(text: isAssets ? String(localized: "资产") : String(localized: "现金"))
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if isDays {
                        Text(snapshot.dailyBurn > 0 ? Int((dayAmount / snapshot.dailyBurn).rounded()).formatted(.number) : "—")
                            .font(.system(size: 26, weight: .light, design: .rounded).monospacedDigit())
                        Text(" 天")
                            .font(.system(size: 14, weight: .light, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                    } else {
                        Text("¥")
                            .font(.system(size: 15, weight: .light, design: .rounded))
                            .foregroundStyle(Color.inkFaint)
                        Text(amount.formatted(.number))
                            .font(.system(size: 26, weight: .light, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(value: amount))
                    }
                }
                .foregroundStyle(selected ? Color.ink : Color.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                Text(subtitle)
                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.trailing, isAssets ? 14 : 0)   // 给中间的圆钮留出位置
            .padding(.leading, isAssets ? 0 : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAssets ? "资产" : "现金")
        .accessibilityValue(isDays ? String(localized: "\(Int(snapshot.dailyBurn > 0 ? (dayAmount / snapshot.dailyBurn).rounded() : 0)) 天")
                                   : "¥" + amount.formatted(.number))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(isAssets ? "assets-tab" : "cash-tab")
    }

    /// 两张标签中间的支点：钱在两边之间挪，就是调拨
    private var transferPivot: some View {
        Button { showingTransfer = true } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.skyDeep)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.mist))
                .overlay(Circle().stroke(Color.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .guideTarget(.transfer, in: guide)
        .accessibilityLabel("调拨，在资产和现金之间挪钱")
        .accessibilityIdentifier("transfer-toggle")
    }

    // MARK: - 每月：进和出

    private func monthly(_ snapshot: FinancialSnapshot, unit: AmountUnit, loanSummary: LoanRows.Summary) -> some View {
        let income = passiveSources.reduce(0) { $0 + $1.monthlyAmount }
        let outflow = loanSummary.monthlyTotal
        let largest = max(income, outflow, 1)
        let net = income - outflow
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                KickerLabel(text: String(localized: "Monthly · 每月固定收支"))
                Spacer()
                Text("差额 \(unit.text(abs(net), sign: net >= 0 ? "+" : "−")) / 月")
                    .font(.system(.footnote, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.inkMuted)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("monthly-net")
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                flowRow(isOpen: $incomeOpen, marker: .moss, title: String(localized: "进"),
                        caption: passiveSources.isEmpty ? String(localized: "租金、利息、股息") : String(localized: "被动收入"),
                        amount: unit.text(income, sign: "+"), amountColor: .mossGreen,
                        share: income / largest, shareColor: .mossGreen, identifier: "monthly-income")
                    .guideTarget(.passive, in: guide)
                    .id(AppGuide.Target.passive)
                if incomeOpen {
                    PassiveRows()
                        .padding(.horizontal, 18)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Hairline(color: .hairlineSoft).padding(.horizontal, 18)
                // 有贷款时记号打孔，和首页格子上的还款日一样；只有房租这类固定支出时不打
                flowRow(isOpen: $loansOpen, marker: ProFeatures.loansInEffect(loans).contains(where: \.punchesGrid) ? .punched : .plain,
                        title: String(localized: "出"),
                        // 有没扣成的就说出来（收起时也得看得到），平时只写是什么
                        caption: loans.isEmpty ? String(localized: "房租、房贷、会员")
                            : (loanSummary.hasPending ? loanSummary.line : String(localized: "固定支出")),
                        amount: unit.text(outflow, sign: "−"), amountColor: .ink,
                        share: outflow / largest, shareColor: .cashBlue, identifier: "monthly-loans")
                    .guideTarget(.loans, in: guide)
                    .id(AppGuide.Target.loans)
                if loansOpen {
                    LoanRows()
                        .padding(.horizontal, 18)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.bottom, Spacing.xs)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.mist))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private enum Marker { case moss, plain, punched }

    /// 一行：记号、进 / 出、一句说明、每月多少、展开箭头；下面一条长短条，进和出按同一个比例画
    private func flowRow(isOpen: Binding<Bool>, marker: Marker, title: String, caption: String,
                         amount: String, amountColor: Color, share: Double, shareColor: Color,
                         identifier: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.32)) { isOpen.wrappedValue.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Group {
                        switch marker {
                        case .moss:
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(Color.mossGreen)
                        case .plain:
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(Color.cashBlue)
                        case .punched:
                            PunchedCell(cornerRadius: 1.5).fill(Color.cashBlue, style: FillStyle(eoFill: true))
                        }
                    }
                    .frame(width: 9, height: 9)
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.ink)
                    Text(caption)
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.inkFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: Spacing.sm)
                    Text(amount)
                        .font(.system(size: 17, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(amountColor)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                        .rotationEffect(.degrees(isOpen.wrappedValue ? 180 : 0))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.mist2)
                        Capsule().fill(shareColor)
                            .frame(width: max(share > 0 ? 4 : 0, geo.size.width * CGFloat(min(1, share))))
                    }
                }
                .frame(height: 4)
                .padding(.trailing, 18)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOpen.wrappedValue ? "已展开" : "已收起")
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - ¥ / 天

/// 苹果分段控件的样子：一条浅色轨道，上面一块浮起的滑块。¥ 和钟两个符号
private struct UnitSwitch: View {
    @Binding var isDays: Bool
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            // 两边都用同一套线条图标：钱 = ¥，时间 = 钟（沙漏是实心的，和 ¥ 放一起会一轻一重）
            segment("yensign", label: String(localized: "钱"), selected: !isDays, identifier: "unit-money") { isDays = false }
            segment("clock", label: String(localized: "天"), selected: isDays, identifier: "unit-days") { isDays = true }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.mist2))
        .sensoryFeedback(.selection, trigger: isDays)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("单位")
    }

    private func segment(_ symbol: String, label: String, selected: Bool, identifier: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.ink : Color.inkFaint)
                .frame(width: 42, height: 28)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.mist)
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - 文件夹形状

/// 选中的那张标签和下面的面板连成一个轮廓：标签顶上两个圆角，和面板接上的地方有一个向内的小圆角
struct FolderShape: Shape {
    var leftSelected: Bool
    var tabHeight: CGFloat
    var radius: CGFloat = 20
    var inner: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height, mid = w / 2, r = radius, t = tabHeight
        if leftSelected {
            path.move(to: CGPoint(x: 0, y: r))
            path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: mid - r, y: 0))
            path.addArc(center: CGPoint(x: mid - r, y: r), radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: mid, y: t - inner))
            path.addArc(center: CGPoint(x: mid + inner, y: t - inner), radius: inner, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            path.addLine(to: CGPoint(x: w - r, y: t))
            path.addArc(center: CGPoint(x: w - r, y: t + r), radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: w, y: h - r))
            path.addArc(center: CGPoint(x: w - r, y: h - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: r, y: h))
            path.addArc(center: CGPoint(x: r, y: h - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.closeSubpath()
        } else {
            path.move(to: CGPoint(x: 0, y: t + r))
            path.addArc(center: CGPoint(x: r, y: t + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: mid - inner, y: t))
            path.addArc(center: CGPoint(x: mid - inner, y: t - inner), radius: inner, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
            path.addLine(to: CGPoint(x: mid, y: r))
            path.addArc(center: CGPoint(x: mid + r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: w - r, y: 0))
            path.addArc(center: CGPoint(x: w - r, y: r), radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: w, y: h - r))
            path.addArc(center: CGPoint(x: w - r, y: h - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: r, y: h))
            path.addArc(center: CGPoint(x: r, y: h - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - 被动收入的各行

/// 新版「每月 → 进」展开后的各行：点一行编辑（里面能删），最后一行添加
struct PassiveRows: View {
    @Query(sort: [SortDescriptor(\PassiveSource.createdAt)]) private var sources: [PassiveSource]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.amountUnit) private var unit
    @State private var adding = false
    @State private var editing: PassiveSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sources) { source in
                VStack(spacing: 0) {
                    Hairline(color: .hairlineSoft)
                    Button { editing = source } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.mossGreen)
                                .frame(width: 19, alignment: .leading)
                            Text(source.name)
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(Color.ink)
                                .lineLimit(1)
                            if let note = source.intervalNote {
                                Text(note)
                                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                                    .foregroundStyle(Color.inkFaint)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: Spacing.sm)
                            Text("\(unit.text(source.monthlyAmount, sign: "+"))/月")
                                .font(.system(.footnote, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.inkMuted)
                                .contentTransition(.numericText())
                        }
                        .frame(height: DrawerMetrics.rowHeight - 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("passive-row-\(source.name)")
                }
            }
            DrawerAddRow(title: String(localized: "添加被动收入"), showsPro: false, identifier: "add-passive-source") { adding = true }
        }
        .sheet(isPresented: $adding) {
            PassiveSourceSheet(existing: nil) { name, monthly, interval in
                try LedgerStore.savePassiveSource(nil, name: name, monthlyAmount: monthly, intervalMonths: interval, in: modelContext)
            }
        }
        .sheet(item: $editing) { source in
            PassiveSourceSheet(existing: source, onSave: { name, monthly, interval in
                try LedgerStore.savePassiveSource(source, name: name, monthlyAmount: monthly, intervalMonths: interval, in: modelContext)
            }, onDelete: {
                try LedgerStore.perform(in: modelContext) { modelContext.delete(source) }
            })
        }
    }
}

// MARK: - 顶部滚动边缘

#if os(macOS)
private extension View {
    @ViewBuilder
    func assetsTopScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }
}
#endif
