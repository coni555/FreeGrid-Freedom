import Foundation
import Testing
@testable import FreeGrid

/// 2.0 的 Pro 介绍：新老用户各一版，各弹一次
struct ProIntroTests {
    private func offer(_ audience: ProIntro.Audience, alreadyShown: Bool = false, ownsPro: Bool = false,
                       hasStartedTrial: Bool = false, canStartTrial: Bool = true, setupFinished: Bool = false) -> Bool {
        ProIntro.shouldOffer(audience: audience, alreadyShown: alreadyShown, ownsPro: ownsPro,
                             hasStartedTrial: hasStartedTrial, canStartTrial: canStartTrial,
                             setupFinished: setupFinished)
    }

    @Test func aLedgerWithExpensesAtFirstLaunchIsAReturningUser() {
        #expect(ProIntro.audience(hasExpenses: true) == .returning)
        #expect(ProIntro.audience(hasExpenses: false) == .newcomer)
    }

    @Test func newcomersWaitForTheSetupGuideToEnd() {
        #expect(!offer(.newcomer, setupFinished: false))
        #expect(offer(.newcomer, setupFinished: true))
    }

    @Test func returningUsersSeeItRightAway() {
        #expect(offer(.returning, setupFinished: false))
    }

    @Test func itShowsOnlyOnce() {
        #expect(!offer(.newcomer, alreadyShown: true, setupFinished: true))
        #expect(!offer(.returning, alreadyShown: true))
    }

    @Test func nobodyWhoBoughtOrAlreadyStartedTheTrialSeesIt() {
        for audience in [ProIntro.Audience.newcomer, .returning] {
            #expect(!offer(audience, ownsPro: true, setupFinished: true))
            #expect(!offer(audience, hasStartedTrial: true, setupFinished: true))
        }
    }

    @Test func withoutTheTrialProductItWaitsForNextTime() {
        // 没网读不到体验商品：先不弹，也不算弹过，下次打开再看
        #expect(!offer(.returning, canStartTrial: false))
        #expect(!offer(.newcomer, canStartTrial: false, setupFinished: true))
    }
}
