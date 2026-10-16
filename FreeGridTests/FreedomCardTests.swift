// Pro 自由卡：材质随自由天数升级的分界、首页升级提示只出现在新的最高等级、卡面格子亮几格。
import Testing
@testable import FreeGrid

struct FreedomCardTests {
    @Test func tiersFollowFreedomDays() {
        #expect(FreedomCardTier.tier(for: .insufficientData) == .paper)
        #expect(FreedomCardTier.tier(for: .finite(days: 29.9)) == .paper)
        #expect(FreedomCardTier.tier(for: .finite(days: 30)) == .silver)
        #expect(FreedomCardTier.tier(for: .finite(days: 179)) == .silver)
        #expect(FreedomCardTier.tier(for: .finite(days: 180)) == .champagne)
        #expect(FreedomCardTier.tier(for: .finite(days: 365)) == .obsidian)
        #expect(FreedomCardTier.tier(for: .covered) == .infinite)
    }

    @Test func promptAppearsOnlyForANewHighestTier() {
        // 第一次有了自由天数
        #expect(FreedomCardPrompt.text(current: .silver, highestSeen: -1, hasFreedomNumber: true) == "你有一张银卡了")
        // 还没有数字时不打扰
        #expect(FreedomCardPrompt.text(current: .paper, highestSeen: -1, hasFreedomNumber: false) == nil)
        // 纸卡是起点，不提示
        #expect(FreedomCardPrompt.text(current: .paper, highestSeen: -1, hasFreedomNumber: true) == nil)
        // 升级
        #expect(FreedomCardPrompt.text(current: .champagne, highestSeen: 1, hasFreedomNumber: true) == "自由卡升级成了香槟金卡")
        // 看过了，或者掉回去又升回来到看过的等级，都不再提示
        #expect(FreedomCardPrompt.text(current: .champagne, highestSeen: 2, hasFreedomNumber: true) == nil)
        #expect(FreedomCardPrompt.text(current: .silver, highestSeen: 2, hasFreedomNumber: true) == nil)
    }
}
