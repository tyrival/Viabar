import Foundation

enum AIProviderKind: String, CaseIterable, Identifiable, Sendable {
    case openAI
    case deepSeek
    case custom

    var id: String { rawValue }
}

struct AIProviderConfiguration: Equatable, Sendable {
    let provider: AIProviderKind
    let baseURL: URL
    let model: String
    let maxTokens: Int
}

enum AIServiceError: Error, Equatable {
    case invalidConfiguration
    case authenticationFailed
    case rateLimited
    case timedOut
    case server(statusCode: Int, message: String?)
    case invalidResponse
    case emptyResult
}
