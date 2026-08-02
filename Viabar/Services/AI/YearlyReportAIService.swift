import Foundation

protocol YearlyReportAIServicing: Sendable {
    func summarize(
        originalMarkdown: String,
        outputLanguage: EffectiveAppLanguage,
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String
}

struct YearlyReportAIService: YearlyReportAIServicing {
    private let client: any OpenAICompatibleServicing

    init(client: any OpenAICompatibleServicing = OpenAICompatibleService()) {
        self.client = client
    }

    func summarize(
        originalMarkdown: String,
        outputLanguage: EffectiveAppLanguage,
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String {
        try await client.complete(
            systemPrompt: systemPrompt(outputLanguage: outputLanguage),
            userContent: originalMarkdown,
            configuration: configuration,
            apiKey: apiKey
        )
    }

    private func systemPrompt(outputLanguage: EffectiveAppLanguage) -> String {
        """
        Summarize the supplied yearly report faithfully using only facts present in it. Do not invent projects, tasks, metrics, evaluations, or context. Write in \(languageName(outputLanguage)). Return Markdown only, without a code fence or conversational preface. When supported by the report, organize the summary into yearly overview, major achievements, patterns of progress, and directions worth continuing next year. Omit any section that lacks evidence.
        """
    }

    private func languageName(_ language: EffectiveAppLanguage) -> String {
        switch language {
        case .english: "English"
        case .simplifiedChinese: "Simplified Chinese"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .german: "German"
        case .french: "French"
        case .spanish: "Spanish"
        }
    }
}
