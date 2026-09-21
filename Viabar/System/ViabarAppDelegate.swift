import AppKit

/// 接管 `viabar://` URL 事件，避免 SwiftUI 场景层处理时创建新窗口并激活应用。
///
/// 背景：`.onOpenURL` 挂在 WindowGroup 内的视图上，URL 到达时 SwiftUI 会为该场景
/// 新开一个窗口，并顺带把应用带到前台。外部工具（如 viabar-wechat）批量投递时
/// 这会连续弹窗，因此改由 AppKit 层接收并静默处理。
final class ViabarAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            ExternalURLRouter.shared.handle(urls)
        }
    }
}
