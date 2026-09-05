// 分享已生成的备份文件；分别使用 iOS/macOS 原生面板。

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 导出分享: 点导出按钮 → 按需生成临时文件 → 系统分享面板(存 Files / AirDrop / 邮件)
struct ExportShareItem: Identifiable { let id = UUID(); let url: URL }

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#else
/// macOS: 用 SwiftUI 原生 ShareLink 呈现系统分享(文件已生成,分享或完成)。
struct ShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("导出文件已生成")
                .font(.headline)
            Text(url.lastPathComponent)
                .font(.callout)
                .foregroundStyle(.secondary)
            ShareLink("分享…", item: url)
                .buttonStyle(.borderedProminent)
            Button("完成") { dismiss() }
        }
        .padding(40)
        .frame(minWidth: 320)
    }
}
#endif
