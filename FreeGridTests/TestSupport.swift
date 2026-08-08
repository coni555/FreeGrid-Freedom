//
//  TestSupport.swift
//  FreeGridTests
//
//  测试公共支架：每个测试使用独立内存库，避免状态互相污染。
//

import Foundation
import SwiftData
@testable import FreeGrid

enum TestSupport {
    static func makeContext() throws -> ModelContext {
        ModelContext(try StoreBootstrap.makeContainer(isStoredInMemoryOnly: true))
    }

    static func day(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }
}
