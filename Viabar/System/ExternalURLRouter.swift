import AppKit
import Foundation
import SwiftData

/// 外部 URL（viabar://）的统一入口。
///
/// 由 AppKit 的 `application(_:open:)` 在 SwiftUI 场景之外调用，因此：
/// - `add` 指令静默写库：不激活应用、不创建或显示窗口；
/// - `navigate` 指令仍走运行时控制器，正常跳转并显示主面板（Widget 点击的预期行为）。
///
/// 之所以不放在 `ContentView.onOpenURL`：SwiftUI 的 WindowGroup 场景处理 URL 事件时
/// 会新开一个窗口并激活应用，导致外部工具每次投递都弹窗。
@MainActor
final class ExternalURLRouter {
    static let shared = ExternalURLRouter()

    private var modelContext: ModelContext?
    private var projectService: ProjectService?
    private var runtimeController: AppRuntimeController?

    private init() {}

    /// 由 ViabarApp 在启动时注入依赖。
    func configure(
        modelContext: ModelContext,
        projectService: ProjectService,
        runtimeController: AppRuntimeController
    ) {
        self.modelContext = modelContext
        self.projectService = projectService
        self.runtimeController = runtimeController
    }

    /// 处理一批外部 URL。
    func handle(_ urls: [URL]) {
        for url in urls {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        guard url.scheme == "viabar" else { return }

        if let request = ExternalAddURL.request(from: url) {
            performExternalAdd(request)
            return
        }

        guard let request = WidgetNavigationURL.navigationRequest(from: url) else { return }
        runtimeController?.navigate(to: request)
    }

    /// 静默添加：只写数据，不触碰窗口与激活状态。
    private func performExternalAdd(_ request: ExternalAddRequest) {
        guard let modelContext, let projectService else { return }
        let projects = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
        _ = ExternalAddHandler.perform(
            request,
            projects: projects,
            projectService: projectService
        )
    }
}
