import Foundation
import Testing
@testable import FreeGrid

/// 2.0 的 Pro 介绍：只给老用户弹一次
struct ProIntroTests {
    private func offer(_ audience: ProIntro.Audience, alreadyShown: Bool = false, ownsPro: Bool = false,
                       hasStartedTrial: Bool = false, canStartTrial: Bool = true) -> Bool {
        ProIntro.shouldOffer(audience: audience, alreadyShown: alreadyShown, ownsPro: ownsPro,
                             hasStartedTrial: hasStartedTrial, canStartTrial: canStartTrial)
    }

    @Test func aLedgerWithExpensesAtFirstLaunchIsAReturningUser() {
        #expect(ProIntro.audience(hasExpenses: true) == .returning)
        #expect(ProIntro.audience(hasExpenses: false) == .newcomer)
    }

    /// 换机后先打开、再导入备份的人第一次打开时账本是空的，被记成新用户；恢复了支出就改回老用户
    @Test func restoringExpensesTurnsANewcomerIntoAReturningUser() {
        #expect(ProIntro.audienceAfterRestoring(.newcomer, recapShown: false, restoredExpenses: 300) == .returning)
        #expect(ProIntro.audienceAfterRestoring(.newcomer, recapShown: false, restoredExpenses: 0) == .newcomer)
        // 已经看过新手小结的不改，免得两张卡都弹
        #expect(ProIntro.audienceAfterRestoring(.newcomer, recapShown: true, restoredExpenses: 300) == .newcomer)
        #expect(ProIntro.audienceAfterRestoring(.returning, recapShown: false, restoredExpenses: 300) == .returning)
        #expect(ProIntro.audienceAfterRestoring(nil, recapShown: false, restoredExpenses: 300) == nil)
    }

    @Test func newcomersNeverSeeIt() {
        #expect(!offer(.newcomer))
    }

    @Test func returningUsersSeeItRightAway() {
        #expect(offer(.returning))
    }

    @Test func itShowsOnlyOnce() {
        #expect(!offer(.returning, alreadyShown: true))
    }

    @Test func nobodyWhoBoughtOrAlreadyStartedTheTrialSeesIt() {
        #expect(!offer(.returning, ownsPro: true))
        #expect(!offer(.returning, hasStartedTrial: true))
    }

    @Test func withoutTheTrialProductItWaitsForNextTime() {
        // 没网读不到体验商品：先不弹，也不算弹过，下次打开再看
        #expect(!offer(.returning, canStartTrial: false))
    }
}
