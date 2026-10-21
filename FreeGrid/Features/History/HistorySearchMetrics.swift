import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 专项验收才启用；只记录时间，不记录查询文字、金额或账本内容。
enum HistorySearchMetrics {
    #if DEBUG
    private struct Sample: Codable, Sendable {
        let opening: Int
        let event: String
        let milliseconds: Double
    }
    private static let output: URL? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UseInMemoryStore"),
              let index = arguments.firstIndex(of: "-HistorySearchMetricsFile"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }()
    private static var started: CFAbsoluteTime?
    private static var opening = 0
    private static var samples: [Sample] = []
    #endif

    static func begin() {
        #if DEBUG
        guard output != nil else { return }
        opening += 1
        started = CFAbsoluteTimeGetCurrent()
        #endif
    }

    static func mark(_ event: String) {
        #if DEBUG
        guard let output, let started else { return }
        samples.append(Sample(opening: opening, event: event, milliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000))
        if event == "keyboard-shown", let data = try? JSONEncoder().encode(samples) {
            Task.detached(priority: .utility) { try? data.write(to: output, options: .atomic) }
        }
        #endif
    }
}

extension View {
    @ViewBuilder
    func historySearchKeyboardMetrics() -> some View {
        #if DEBUG && os(iOS)
        onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            HistorySearchMetrics.mark("keyboard-shown")
        }
        #else
        self
        #endif
    }
}
