import Combine
import Foundation

@MainActor
final class AIProviderSettings: ObservableObject {
    static let shared = AIProviderSettings()
    static let keychainService = "com.tyrival.Viabar.ai"
    static let keychainAccount = "api-key"

    @Published var provider: AIProviderKind {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }

    @Published var baseURLText: String {
        didSet { defaults.set(baseURLText, forKey: Keys.baseURL) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }

    @Published var maxTokens: Int {
        didSet { defaults.set(maxTokens, forKey: Keys.maxTokens) }
    }

    @Published private(set) var fetchedModels: [String] = []

    private let defaults: UserDefaults
    private let secretStore: any KeychainSecretStoring

    convenience init() {
        self.init(defaults: .standard, secretStore: KeychainSecretStore())
    }

    init(defaults: UserDefaults, secretStore: any KeychainSecretStoring) {
        self.defaults = defaults
        self.secretStore = secretStore

        let savedProvider = defaults.string(forKey: Keys.provider)
            .flatMap(AIProviderKind.init(rawValue:)) ?? .openAI
        provider = savedProvider
        let savedBaseURL = defaults.string(forKey: Keys.baseURL) ?? ""
        baseURLText = savedBaseURL.isEmpty ? Self.presetBaseURL(for: savedProvider) : savedBaseURL
        model = defaults.string(forKey: Keys.model) ?? ""
        let savedMaxTokens = defaults.integer(forKey: Keys.maxTokens)
        maxTokens = savedMaxTokens > 0 ? savedMaxTokens : 65_536
    }

    func applyPreset(_ provider: AIProviderKind) {
        self.provider = provider
        if provider != .custom {
            baseURLText = Self.presetBaseURL(for: provider)
        }
        clearFetchedModels()
    }

    func configuration() throws -> AIProviderConfiguration {
        let baseURLValue = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: baseURLValue),
              let scheme = baseURL.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              maxTokens > 0 else {
            throw AIServiceError.invalidConfiguration
        }
        return AIProviderConfiguration(
            provider: provider,
            baseURL: baseURL,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            maxTokens: maxTokens
        )
    }

    func apiKey() throws -> String {
        try secretStore.read(
            service: Self.keychainService,
            account: Self.keychainAccount
        ) ?? ""
    }

    func apiKeyAsync() async throws -> String {
        let secretStore = secretStore
        return try await Task.detached(priority: .userInitiated) {
            try secretStore.read(
                service: Self.keychainService,
                account: Self.keychainAccount
            ) ?? ""
        }.value
    }

    func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try secretStore.delete(service: Self.keychainService, account: Self.keychainAccount)
        } else {
            try secretStore.write(
                trimmed,
                service: Self.keychainService,
                account: Self.keychainAccount
            )
        }
        clearFetchedModels()
    }

    func clearFetchedModels() {
        fetchedModels = []
    }

    func setFetchedModels(_ values: [String]) {
        fetchedModels = Array(Set(
            values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func presetBaseURL(for provider: AIProviderKind) -> String {
        switch provider {
        case .openAI:
            "https://api.openai.com"
        case .deepSeek:
            "https://api.deepseek.com"
        case .custom:
            ""
        }
    }

    private enum Keys {
        static let provider = "viabar.ai.provider"
        static let baseURL = "viabar.ai.baseURL"
        static let model = "viabar.ai.model"
        static let maxTokens = "viabar.ai.maxTokens"
    }
}
