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
