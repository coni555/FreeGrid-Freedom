//
//  Platform.swift
//  FreeGrid
//
//  跨平台兼容层:把 iOS-only 的 View 修饰符封装成「iOS 生效 / 其它平台 no-op」,
//  让同一份 SwiftUI 代码同时编译到 iOS 与 macOS。
//  新增 iOS-only 调用时,优先在这里加一个修饰符,而不是在业务代码里散落 #if。
//

import SwiftUI

extension View {
    /// iOS 设小数键盘;macOS 无软键盘,no-op。
    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    /// iOS 设 inline 导航标题;macOS 无导航栏标题概念,no-op。
    func inlineNavTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// iOS 给 sheet 设 detents + 抓手;macOS sheet 是固定窗口,no-op。
    func iosSheetDetents() -> some View {
        #if os(iOS)
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        #else
        self
        #endif
    }

    /// iOS 隐藏导航栏;macOS 无导航栏,no-op。
    func hideNavBar() -> some View {
        #if os(iOS)
        navigationBarHidden(true)
        #else
        self
        #endif
    }

    /// iOS 滚动内容时可下拉收起键盘(兜底);macOS no-op。
    func dismissKeyboardOnScroll() -> some View {
        #if os(iOS)
        scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }
}
