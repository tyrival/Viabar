import Foundation
import OSLog

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        return (data, httpResponse)
    }
}

protocol OpenAICompatibleServicing: Sendable {
    func fetchModels(
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> [String]

    func testConnection(
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws

    func complete(
        systemPrompt: String,
        userContent: String,
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String
}

struct OpenAICompatibleService: OpenAICompatibleServicing {
    private static let chatTimeout: TimeInterval = 300

    private let transport: any HTTPTransport
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tyrival.Viabar",
        category: "AI"
    )

    init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    func fetchModels(
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> [String] {
        let request = try authorizedRequest(
            url: endpoint(baseURL: configuration.baseURL, path: "v1/models"),
            apiKey: apiKey
        )
        let (data, response) = try await transport.data(for: request)
        try validate(response: response, data: data)
        guard let payload = try? decoder.decode(ModelListResponse.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        return Array(Set(
            payload.data.map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func testConnection(
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws {
        _ = try await fetchModels(configuration: configuration, apiKey: apiKey)
    }

    func complete(
        systemPrompt: String,
        userContent: String,
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String {
        let trimmedContent = userContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty, !configuration.model.isEmpty else {
            throw AIServiceError.invalidConfiguration
        }

        var request = try authorizedRequest(
            url: endpoint(baseURL: configuration.baseURL, path: "v1/chat/completions"),
            apiKey: apiKey
        )
        request.timeoutInterval = Self.chatTimeout
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(ChatRequest(
            model: configuration.model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userContent),
            ],
            maxTokens: configuration.maxTokens
        ))

        let diagnosticID = UUID().uuidString
        let startedAt = Date()
        logger.info(
            "Starting AI completion requestID=\(diagnosticID, privacy: .public) model=\(configuration.model, privacy: .public) inputCharacters=\(userContent.count, privacy: .public) timeoutSeconds=\(Int(Self.chatTimeout), privacy: .public) maxTokens=\(configuration.maxTokens, privacy: .public)"
        )

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            let elapsed = Date().timeIntervalSince(startedAt)
            logger.error("AI completion timed out requestID=\(diagnosticID, privacy: .public) elapsedSeconds=\(elapsed, privacy: .public)")
            throw AIServiceError.timedOut
        } catch {
            let elapsed = Date().timeIntervalSince(startedAt)
            logger.error(
                "AI completion transport failed requestID=\(diagnosticID, privacy: .public) elapsedSeconds=\(elapsed, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            throw error
        }

        try validate(response: response, data: data)
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? "missing"
        logger.info(
            "AI completion response requestID=\(diagnosticID, privacy: .public) status=\(response.statusCode, privacy: .public) contentType=\(contentType, privacy: .public) responseBytes=\(data.count, privacy: .public)"
        )

        let payload: ChatResponse
        do {
            payload = try decoder.decode(ChatResponse.self, from: data)
        } catch {
            logger.error(
                "AI completion decode failed requestID=\(diagnosticID, privacy: .public) topLevelKeys=\(topLevelKeys(in: data), privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            throw AIServiceError.invalidResponse
        }

        logger.info(
            "AI completion decoded requestID=\(diagnosticID, privacy: .public) choices=\(payload.choices.count, privacy: .public)"
        )
        for (index, choice) in payload.choices.enumerated() {
            let finishReason = choice.finishReason ?? "missing"
            let contentCharacters = choice.message.content?.count ?? 0
            let reasoningCharacters = choice.message.reasoningContent?.count ?? 0
            logger.info(
                "AI completion choice requestID=\(diagnosticID, privacy: .public) index=\(index, privacy: .public) finishReason=\(finishReason, privacy: .public) contentCharacters=\(contentCharacters, privacy: .public) reasoningCharacters=\(reasoningCharacters, privacy: .public)"
            )
        }

        guard let result = payload.choices.lazy
            .compactMap(\.message.content)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            logger.error(
                "AI completion contained no displayable content requestID=\(diagnosticID, privacy: .public) choices=\(payload.choices.count, privacy: .public)"
            )
            throw AIServiceError.emptyResult
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        logger.info(
            "AI completion succeeded requestID=\(diagnosticID, privacy: .public) elapsedSeconds=\(elapsed, privacy: .public) outputCharacters=\(result.count, privacy: .public)"
        )
        return result
    }

    private func authorizedRequest(url: URL, apiKey: String) throws -> URLRequest {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw AIServiceError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func endpoint(baseURL: URL, path: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL.appending(path: path)
        }
        let basePath = components.path.split(separator: "/").map(String.init)
        var suffix = path.split(separator: "/").map(String.init)
        if basePath.last?.lowercased() == "v1", suffix.first?.lowercased() == "v1" {
            suffix.removeFirst()
        }
        components.path = "/" + (basePath + suffix).joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url ?? baseURL.appending(path: path)
    }

    private func validate(response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data))?.error.message
            switch response.statusCode {
            case 401, 403:
                throw AIServiceError.authenticationFailed
            case 429:
                throw AIServiceError.rateLimited
            default:
                throw AIServiceError.server(statusCode: response.statusCode, message: message)
            }
        }
    }

    private func topLevelKeys(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return "non-object-or-invalid-json"
        }
        return dictionary.keys.sorted().joined(separator: ",")
    }
}

private struct ModelListResponse: Decodable {
    struct Item: Decodable {
        let id: String
    }

    let data: [Item]
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
}

private struct ErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError
}
