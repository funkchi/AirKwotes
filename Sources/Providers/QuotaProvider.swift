import Foundation

protocol QuotaProvider {
    var kind: ProviderKind { get }
    var requiresAPIKey: Bool { get }
    func fetch(apiKey: String) async throws -> QuotaSnapshot
}

enum QuotaError: Error, LocalizedError {
    case invalidKey
    case missingField(String)
    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Invalid or unauthorized API key."
        case .missingField(let f): return "Unexpected response (missing \(f))."
        }
    }
}

extension QuotaProvider {
    var requiresAPIKey: Bool { true }

    func fail(_ snapshot: QuotaSnapshot.Status) -> QuotaSnapshot {
        QuotaSnapshot(id: UUID(), remainingPercent: nil, remainingDisplay: "—",
                      usedDisplay: nil, totalDisplay: nil, unit: "", status: snapshot,
                      fetchedAt: Date(), resetAt: nil, note: nil)
    }
}

/// Registry mapping provider kinds to their implementations.
enum Providers {
    static func registry() -> [ProviderKind: QuotaProvider] {
        [
            .deepseek:    DeepSeekProvider(),
            .moonshot:    MoonshotProvider(),
            .zhipu:       ZhipuProvider(host: "bigmodel.cn"),
            .zai:         ZhipuProvider(host: "api.z.ai"),
            .codex:       CodexProvider(),
            .claudeCode:  ClaudeCodeProvider(),
            .openrouter:  OpenRouterProvider(),
            .siliconflow: SiliconFlowProvider(),
            .gemini:      GeminiProvider(),
            .openai:      OpenAIProvider(),
            .qwen:        QwenProvider(),
            .anthropic:   AnthropicProvider(),
            .mistral:     MistralProvider(),
            .xai:         XAIProvider()
        ]
    }
}
