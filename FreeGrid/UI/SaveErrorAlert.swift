// 所有手动保存失败时使用同一提示；表单内容保留，用户可以重试。

import SwiftUI

extension View {
    func saveErrorAlert(_ message: Binding<String?>) -> some View {
        alert("保存失败", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("好", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
