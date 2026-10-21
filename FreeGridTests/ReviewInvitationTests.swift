import Foundation
import Testing
@testable import FreeGrid

@MainActor
struct ReviewInvitationTests {
    private func withStore(_ test: (ReviewInvitationStore, UserDefaults) throws -> Void) rethrows {
        let suite = "ReviewInvitationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try test(ReviewInvitationStore(defaults: defaults), defaults)
    }

    @Test(arguments: [0, 9, 10, 100])
    func eligibilityUsesTenRecordedDays(_ days: Int) {
        #expect(ReviewInvitation.shouldRequest(recordedDays: days, lastRequestedAt: nil, now: .now) == (days >= 10))
    }

    @Test func intervalUsesCalendarDaysAcrossDaylightSavingTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        let boundary = calendar.date(byAdding: .day, value: 90, to: first)!
        #expect(!ReviewInvitation.shouldRequest(recordedDays: 10, lastRequestedAt: first, now: boundary.addingTimeInterval(-1), calendar: calendar))
        #expect(ReviewInvitation.shouldRequest(recordedDays: 10, lastRequestedAt: first, now: boundary, calendar: calendar))
        #expect(!ReviewInvitation.shouldRequest(recordedDays: 10, lastRequestedAt: boundary, now: first, calendar: calendar))
    }

    @Test func launchOrImportedRecordsAloneDoNotCreateAnOpportunity() {
        withStore { store, defaults in
            var requests = 0
            #expect(!store.requestIfEligible(UUID(), recordedDays: 100) { requests += 1 })
            #expect(store.opportunity == nil)
            #expect(defaults.object(forKey: ReviewInvitationStore.lastRequestedKey) == nil)
            #expect(requests == 0)
        }
    }

    @Test func successfulRequestIsRecordedBeforeCallingStoreKitAndPersists() {
        withStore { store, defaults in
            let now = TestSupport.day("2026-10-21")
            store.didSave(transactionID: UUID(), now: now)
            let id = store.opportunity!.id
            var requests = 0
            let requested = store.requestIfEligible(id, recordedDays: 10, now: now) {
                #expect(store.lastRequestedAt == now)
                requests += 1
            }
            #expect(requested)
            #expect(!store.requestIfEligible(id, recordedDays: 10, now: now) { requests += 1 })
            let relaunched = ReviewInvitationStore(defaults: defaults)
            #expect(relaunched.opportunity == nil)
            #expect(relaunched.lastRequestedAt == now)
            relaunched.didSave(transactionID: UUID(), now: now.addingTimeInterval(60))
            #expect(!relaunched.requestIfEligible(relaunched.opportunity!.id, recordedDays: 100, now: now.addingTimeInterval(60)) { requests += 1 })
            #expect(requests == 1)
        }
    }

    @Test func cooldownAllowsANewSaveAfterNinetyDays() {
        withStore { store, defaults in
            let first = TestSupport.day("2026-01-01")
            defaults.set(first.timeIntervalSince1970, forKey: ReviewInvitationStore.lastRequestedKey)
            let now = Calendar.current.date(byAdding: .day, value: 90, to: first)!
            store.didSave(transactionID: UUID(), now: now)
            #expect(store.requestIfEligible(store.opportunity!.id, recordedDays: 10, now: now) {})
        }
    }

    @Test func numericLaunchArgumentAlsoPreservesTheCooldown() {
        withStore { store, defaults in
            let now = TestSupport.day("2026-10-21")
            defaults.set(String(now.timeIntervalSince1970), forKey: ReviewInvitationStore.lastRequestedKey)
            #expect(store.lastRequestedAt == now)
            store.didSave(transactionID: UUID(), now: now)
            #expect(!store.requestIfEligible(store.opportunity!.id, recordedDays: 10, now: now) {})
        }
    }

    @Test func cancelAndUndoDoNotConsumeTheCooldown() {
        withStore { store, defaults in
            let transaction = UUID()
            store.didSave(transactionID: transaction)
            let discarded = store.opportunity!.id
            store.discard(discarded)
            #expect(!store.requestIfEligible(discarded, recordedDays: 10) { Issue.record("已跳过的邀请不能发布") })
            store.didSave(transactionID: transaction)
            let undone = store.opportunity!.id
            store.didUndo(transactionID: transaction)
            #expect(!store.requestIfEligible(undone, recordedDays: 10) { Issue.record("已撤销的记账不能邀请") })
            #expect(defaults.object(forKey: ReviewInvitationStore.lastRequestedKey) == nil)
        }
    }

    @Test func obsoleteTaskCannotConsumeANewerSave() {
        withStore { store, _ in
            let now = TestSupport.day("2026-10-21")
            let oldTransaction = UUID()
            store.didSave(transactionID: oldTransaction, now: now)
            let old = store.opportunity!.id
            store.didSave(transactionID: UUID(), now: now)
            let latest = store.opportunity!.id
            store.didUndo(transactionID: oldTransaction)
            store.discard(old)
            #expect(!store.requestIfEligible(old, recordedDays: 10, now: now) { Issue.record("旧任务不能请求") })
            #expect(store.opportunity?.id == latest)
            #expect(store.requestIfEligible(latest, recordedDays: 10, now: now) {})
        }
    }

    @Test func expiredOrClockReversedOpportunityDoesNotRequest() {
        withStore { store, _ in
            let now = TestSupport.day("2026-10-21")
            for age in [-1.0, 120, 500] {
                store.didSave(transactionID: UUID(), now: now)
                #expect(!store.requestIfEligible(store.opportunity!.id, recordedDays: 10, now: now.addingTimeInterval(age)) {
                    Issue.record("过时或时钟回拨的记账不能邀请")
                })
            }
        }
    }

    @Test func insufficientDaysDoNotStartCooldownAndCanTryAfterAnotherSave() {
        withStore { store, _ in
            store.didSave(transactionID: UUID())
            #expect(!store.requestIfEligible(store.opportunity!.id, recordedDays: 9) {})
            #expect(store.lastRequestedAt == nil)
            store.didSave(transactionID: UUID())
            #expect(store.requestIfEligible(store.opportunity!.id, recordedDays: 10) {})
        }
    }
}
