import Foundation
import Testing
@testable import FreeGrid

/// 试用和试用专属价的时间规则：每个人从自己开始试用那一刻起算
struct ProOfferTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ days: Double) -> Date { start.addingTimeInterval(days * 24 * 60 * 60) }

    @Test func beforeTheTrialThereIsNoTrialButTheSpecialPriceApplies() {
        // 直接买的人不该比先试用的人付得多
        let offer = ProOffer(trialStartedAt: nil)
        #expect(!offer.hasStartedTrial)
        #expect(!offer.isTrialActive(at: start))
        #expect(offer.hasSpecialPrice(at: day(400)))
        #expect(offer.nextChange(after: start) == nil)
    }

    @Test func trialRunsSevenDaysAndSpecialPriceFourteen() {
        let offer = ProOffer(trialStartedAt: start)
        #expect(offer.isTrialActive(at: start))
        #expect(offer.isTrialActive(at: day(6.99)))
        #expect(!offer.isTrialActive(at: day(7)))
        #expect(offer.hasSpecialPrice(at: day(7)))
        #expect(offer.hasSpecialPrice(at: day(13.99)))
        #expect(!offer.hasSpecialPrice(at: day(14)))
    }

    @Test func aTrialStartedMonthsAfterLaunchStillGetsItsOwnFourteenDays() {
        // 10 月发布、第二年 3 月才下载的人，窗口从他自己点试用算起
        let lateStart = day(150)
        let offer = ProOffer(trialStartedAt: lateStart)
        #expect(offer.isTrialActive(at: day(151)))
        #expect(offer.hasSpecialPrice(at: day(160)))
        #expect(!offer.hasSpecialPrice(at: day(164)))
    }

    @Test func nextChangeIsTrialEndThenSpecialPriceEnd() {
        let offer = ProOffer(trialStartedAt: start)
        #expect(offer.nextChange(after: day(1)) == day(7))
        #expect(offer.nextChange(after: day(8)) == day(14))
        #expect(offer.nextChange(after: day(15)) == nil)
    }

    @Test func daysLeftCountsAPartialDayAsOne() {
        #expect(ProOffer.daysLeft(until: day(7), from: start) == 7)
        #expect(ProOffer.daysLeft(until: day(7), from: day(0.5)) == 7)
        #expect(ProOffer.daysLeft(until: day(7), from: day(6.9)) == 1)
        #expect(ProOffer.daysLeft(until: day(7), from: day(8)) == 0)
    }
}
