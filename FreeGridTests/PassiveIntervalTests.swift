// 被动收入可以选几个月到账一次：存折合的每月，周期只用来填写和显示；备份带上周期，旧备份按每月读。

import Foundation
import SwiftData
import Testing
@testable import FreeGrid

@MainActor
struct PassiveIntervalTests {

    private func context() throws -> ModelContext {
        let context = try TestSupport.makeContext()
        try LedgerStore.updateAssets(in: context) { $0.cash = 10_000 }
        return context
    }

    private func sources(_ context: ModelContext) throws -> [PassiveSource] {
        try context.fetch(FetchDescriptor<PassiveSource>(sortBy: [SortDescriptor(\.name)]))
    }

    /// 一年一次 6,000 存成每月 500，算自由天数时就是每天 500 ÷ 30，和每月 500 一样
    @Test func yearlyPayoutCountsAsItsMonthlyShare() throws {
        let context = try context()
        try LedgerStore.savePassiveSource(nil, name: "分红", monthlyAmount: 6000.0 / 12, intervalMonths: 12, in: context)
        let source = try #require(try sources(context).first)
        #expect(source.monthlyAmount == 500 && source.intervalMonths == 12)
        #expect(source.intervalNote == "每年 ¥6,000")
        let snapshot = FinancialSnapshot(expenses: [], passiveSources: [source], assets: nil)
        #expect(abs(snapshot.dailyPassive - 500.0 / 30) < 1e-9)
    }

    @Test func monthlySourcesHaveNoNoteAndBadIntervalsAreRejected() throws {
        let context = try context()
        try LedgerStore.savePassiveSource(nil, name: "利息", monthlyAmount: 300, in: context)
        #expect(try sources(context).first?.intervalNote == nil)
        #expect(throws: LoanError.invalidInterval) {
            try LedgerStore.savePassiveSource(nil, name: "坏的", monthlyAmount: 300, intervalMonths: 5, in: context)
        }
        #expect(try sources(context).count == 1)
    }

    /// 备份写上周期（每月不写，和旧备份一样）；导回来周期和折合每月都不变
    @Test func backupKeepsTheIntervalAndOldBackupsReadAsMonthly() throws {
        let source = try context()
        try LedgerStore.savePassiveSource(nil, name: "分红", monthlyAmount: 500, intervalMonths: 12, in: source)
        try LedgerStore.savePassiveSource(nil, name: "利息", monthlyAmount: 300, in: source)
        let data = try DataIO.exportJSON(context: source)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.components(separatedBy: "\"interval_months\"").count == 2)

        let target = try TestSupport.makeContext()
        let preview = try DataIO.previewJSON(data: data, context: target)
        _ = try DataIO.commitImport(preview: preview, strategy: .replace, context: target)
        let restored = try sources(target)
        #expect(restored.map(\.name) == ["分红", "利息"])
        #expect(restored.map(\.monthlyAmount) == [500, 300])
        #expect(restored.map(\.intervalMonths) == [12, 1])
    }

    @Test func importRejectsAnUnknownInterval() throws {
        let source = try context()
        try LedgerStore.savePassiveSource(nil, name: "分红", monthlyAmount: 500, intervalMonths: 12, in: source)
        let text = String(decoding: try DataIO.exportJSON(context: source), as: UTF8.self)
        let broken = text.replacingOccurrences(of: "\"interval_months\" : 12", with: "\"interval_months\" : 5")
        #expect(broken != text)
        #expect(throws: ImportValidationError.invalidPassiveInterval) {
            _ = try DataIO.previewJSON(data: Data(broken.utf8), context: try TestSupport.makeContext())
        }
    }
}
