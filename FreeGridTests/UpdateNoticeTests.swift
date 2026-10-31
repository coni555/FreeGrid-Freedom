import Testing
@testable import FreeGrid

/// 更新公告：老用户每个版本弹一次，空账本不弹
struct UpdateNoticeTests {
    @Test func anUpdatedLedgerSeesItUntilItIsShown() {
        #expect(UpdateNotice.isDue(seen: nil))
        #expect(!UpdateNotice.skipsForEmptyLedger(seen: nil, hasContent: true))
    }

    @Test func itShowsOncePerVersion() {
        #expect(!UpdateNotice.isDue(seen: UpdateNotice.version))
        #expect(UpdateNotice.isDue(seen: "2.1"))
    }

    /// 新装的 App：第一次打开是空账本，记成看过，之后记了账也不弹
    @Test func anEmptyLedgerSkipsItForGood() {
        #expect(UpdateNotice.skipsForEmptyLedger(seen: nil, hasContent: false))
        #expect(!UpdateNotice.skipsForEmptyLedger(seen: UpdateNotice.version, hasContent: false))
    }
}
