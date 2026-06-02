import SwiftData
import SwiftUI

struct IOSPersistentRootView: View {
    @Query(sort: \Project.orderIndex) private var projects: [Project]
    @Query(sort: \ArchiveFolder.orderIndex) private var archiveFolders: [ArchiveFolder]
    @Query(sort: \AppSettings.createdAt) private var settingsRecords: [AppSettings]
    @State private var coordinator = IOSPersistenceCoordinator()

    var body: some View {
        @Bindable var coordinator = coordinator

        NavigationStack(path: $coordinator.navigationPath) {
            IOSPersistentOverviewView(
                coordinator: coordinator,
                projects: projects,
                archiveFolders: archiveFolders
            )
            .navigationDestination(for: UUID.self) { projectID in
                if let project = projects.first(where: { $0.projectId == projectID }) {
                    IOSPersistentProjectDetailView(
                        coordinator: coordinator,
                        project: project
                    )
                } else {
                    IOSPlaceholderView(symbol: "exclamationmark.triangle", title: "项目不存在")
                }
            }
        }
        .onOpenURL { url in
            guard let request = WidgetNavigationURL.navigationRequest(from: url) else { return }
            if let project = projects.first(where: { $0.projectId == request.projectID }),
               project.isArchived {
                coordinator.revealArchiveAncestors(for: project)
            }
            coordinator.navigate(to: request)
        }
        .environment(\.locale, effectiveLanguage.locale)
        .preferredColorScheme(preferredColorScheme)
    }

    private var effectiveLanguage: EffectiveAppLanguage {
        AppLanguage.effectiveLanguage(storedValue: settingsRecords.first?.language)
    }

    private var preferredColorScheme: ColorScheme? {
        switch AppTheme(rawValue: settingsRecords.first?.theme ?? "") ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
