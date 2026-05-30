import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class UpdateService {
    private let updater: SPUUpdater
    private let userDriver: SPUStandardUserDriver

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    init() {
        userDriver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: nil
        )

        do {
            try updater.setFeedURL(URL(string: "https://raw.githubusercontent.com/tyrival/Viabar-Releases/main/appcast.xml")!)
        } catch {
            print("[UpdateService] Failed to set feed URL: \(error)")
        }
    }

    func start() {
        do {
            try updater.start()
        } catch {
            print("[UpdateService] Failed to start updater: \(error)")
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

extension ServiceContainer {
    var updateService: UpdateService? {
        resolve(UpdateService.self)
    }

    func registerUpdateService() -> UpdateService {
        let service = UpdateService()
        register(service)
        return service
    }
}
