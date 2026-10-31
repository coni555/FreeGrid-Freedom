import Foundation
import Testing
@testable import FreeGrid

/// 中英文切换：测试按中文界面跑（scheme 的测试语言是 zh-Hans），英文从 en.lproj 直接取出来对
@MainActor
struct LocalizationTests {
    /// App 包里的英文目录
    private var englishBundle: Bundle {
        get throws {
            let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
            return try #require(Bundle(path: path))
        }
    }

    @Test func testsRunInChinese() {
        #expect(AppLanguage.isChinese)
        #expect(String(localized: "设置") == "设置")
    }

    @Test func defaultCategoriesKeepTheirStoredNames() {
        for name in ExpenseCategory.canonical {
            #expect(ExpenseCategory.displayName(name) == name)
        }
        #expect(ExpenseCategory.displayName("咖啡") == "咖啡")
        #expect(ExpenseCategory.displayName("Coffee") == "Coffee")
    }

    @Test func englishCatalogCoversDefaultCategoriesAndTabs() throws {
        let en = try englishBundle
        let pairs = ["早餐": "Breakfast", "其他": "Other", "首页": "Dashboard", "钱包": "Assets",
                     "明细": "History", "设置": "Settings"]
        for (zh, expected) in pairs {
            #expect(en.localizedString(forKey: zh, value: nil, table: nil) == expected)
        }
    }

    /// 复数规则跟格式化用的地区走；测试进程是中文，得指定英文
    private let english = Locale(identifier: "en_US")

    @Test func englishDaysUseSingularAndPlural() throws {
        let format = try englishBundle.localizedString(forKey: "%lld 天", value: nil, table: nil)
        #expect(String(format: format, locale: english, 1) == "1 day")
        #expect(String(format: format, locale: english, 12) == "12 days")
    }

    @Test func englishPluralWorksWithSeveralArguments() throws {
        let format = try englishBundle.localizedString(forKey: "每月 %lld 日 · 还剩 %lld 期", value: nil, table: nil)
        #expect(String(format: format, locale: english, 15, 1) == "Day 15 monthly · 1 payment left")
        #expect(String(format: format, locale: english, 15, 24) == "Day 15 monthly · 24 payments left")
    }

    @Test func englishMonthlyTrackingLinesUsePlural() throws {
        let thin = try englishBundle.localizedString(forKey: "已有 %lld 笔支出，上次记录在 %lld 天前", value: nil, table: nil)
        #expect(String(format: thin, locale: english, 1, 30) == "1 expense logged. Last entry: 30 days ago.")
        #expect(String(format: thin, locale: english, 12, 1) == "12 expenses logged. Last entry: 1 day ago.")
        let switching = try englishBundle.localizedString(forKey: "上次记账是 %lld 天前。改用「按月记账」？", value: nil, table: nil)
        #expect(String(format: switching, locale: english, 30) == "Your last entry was 30 days ago. Switch to Monthly Total?")
        let average = try englishBundle.localizedString(forKey: "按 %lld 个月平均", value: nil, table: nil)
        #expect(String(format: average, locale: english, 2) == "Average of 2 months")
    }

    @Test func englishGapLinesUsePlural() throws {
        let countdown = try englishBundle.localizedString(forKey: "%@ · %lld 天后", value: nil, table: nil)
        #expect(String(format: countdown, locale: english, "GAP", 1) == "GAP · in 1 day")
        #expect(String(format: countdown, locale: english, "GAP", 189) == "GAP · in 189 days")
        let milestone = try englishBundle.localizedString(forKey: "当前 %@ / %lld 天", value: nil, table: nil)
        #expect(String(format: milestone, locale: english, "116", 180) == "Now 116 / 180 days")
    }

    @Test func autoPaymentNoteIsShownInTheInterfaceLanguage() throws {
        let loanID = UUID()
        let payment = Expense(amount: 3000, category: "房贷", note: LoanStore.autoPaymentNote, date: .now)
        payment.loanID = loanID
        #expect(LedgerTransaction.expense(payment).displayNote == "自动扣款")
        // 用户自己写的同样四个字不是 App 写的，原样显示
        let manual = Expense(amount: 30, category: "其他", note: "自动扣款", date: .now)
        #expect(LedgerTransaction.expense(manual).displayNote == "自动扣款")
        #expect(LedgerTransaction.expense(manual).displayTitle == "其他")
    }

    @Test func chineseDatesStayAsBefore() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        #expect(HistoryLedger.dayLabel(day, now: now, calendar: calendar) == "10月20日 周二")
        #expect(HistoryMonth(year: 2026, month: 10).label == "2026年10月")
    }
}
