import SwiftUI

// MARK: - 跨平台兼容层（macOS / iOS 共用同一份源码）

extension Color {
    /// 卡片背景色：macOS 用 controlBackgroundColor，iOS 用 secondarySystemBackground
    static var cardBackground: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }

    /// 窗口/页面底色
    static var surfaceBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
}

extension View {
    /// macOS 上按 Esc 取消编辑；iOS 无 Esc 键，原样返回
    @ViewBuilder
    func cancelOnExitCommand(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        self.onExitCommand(perform: action)
        #else
        self
        #endif
    }

    /// iOS 隐藏滚动条指示器差异的轻量包装（两端行为一致）
    func scrollContentInsetTop(_ value: CGFloat) -> some View {
        self.padding(.top, value)
    }
}
