import Foundation

/// Providers with no public quota API. They validate the API key against a
/// lightweight `/models` endpoint and report key validity instead of numbers.
struct KeyValidationProvider: QuotaProvider {
    let kind: ProviderKind
    private let endpoint: String
    private let asBearer: Bool

    init(kind: ProviderKind, endpoint: String, asBearer: Bool = true) {
        self.kind = kind
        self.endpoint = endpoint
        self.asBearer = asBearer
    }

    func fetch(apiKey: String) async throws -> QuotaSnapshot {
        do {
            if asBearer {
                _ = try await APIClient.shared.getBearer(endpoint, token: apiKey)
            } else {
                _ = try await APIClient.shared.getQuery(endpoint, query: ["key": apiKey])
            }
            return QuotaSnapshot(
                id: UUID(),
                remainingPercent: nil,
                remainingDisplay: "Key valid",
                usedDisplay: nil,
                totalDisplay: nil,
                unit: "",
                status: .ok,
                fetchedAt: Date(),
                resetAt: nil,
                note: kind.summary
            )
        } catch let HTTPError.status(401, _) {
            return fail(.invalid)
        } catch let HTTPError.status(403, _) {
            return fail(.invalid)
        } catch let HTTPError.status(code, _) where code == 429 {
            return QuotaSnapshot(
                id: UUID(), remainingPercent: nil, remainingDisplay: "Rate limited",
                usedDisplay: nil, totalDisplay: nil, unit: "", status: .low,
                fetchedAt: Date(), resetAt: nil, note: nil)
        }
    }
}

struct GeminiProvider: QuotaProvider {
    let kind: ProviderKind = .gemini
    private let inner = KeyValidationProvider(
        kind: .gemini,
        endpoint: "https://generativelanguage.googleapis.com/v1beta/models",
        asBearer: false)
    func fetch(apiKey: String) async throws -> QuotaSnapshot { try await inner.fetch(apiKey: apiKey) }
}

struct OpenAIProvider: QuotaProvider {
    let kind: ProviderKind = .openai
    private let inner = KeyValidationProvider(
        kind: .openai, endpoint: "https://api.openai.com/v1/models")
    func fetch(apiKey: String) async throws -> QuotaSnapshot { try await inner.fetch(apiKey: apiKey) }
}

struct QwenProvider: QuotaProvider {
    let kind: ProviderKind = .qwen
    private let inner = KeyValidationProvider(
        kind: .qwen, endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/models")
    func fetch(apiKey: String) async throws -> QuotaSnapshot { try await inner.fetch(apiKey: apiKey) }
}

struct AnthropicProvider: QuotaProvider {
    let kind: ProviderKind = .anthropic
    func fetch(apiKey: String) async throws -> QuotaSnapshot {
        do {
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
            req.httpMethod = "GET"
            req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, resp) = try await APIClient.shared.session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw HTTPError.status(0, "No response") }
            if http.statusCode == 401 { return fail(.invalid) }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                throw HTTPError.status(http.statusCode, String(body))
            }
            return QuotaSnapshot(id: UUID(), remainingPercent: nil, remainingDisplay: "Key valid",
                                 usedDisplay: nil, totalDisplay: nil, unit: "", status: .ok,
                                 fetchedAt: Date(), resetAt: nil, note: kind.summary)
        }
    }
}

struct MistralProvider: QuotaProvider {
    let kind: ProviderKind = .mistral
    private let inner = KeyValidationProvider(
        kind: .mistral, endpoint: "https://api.mistral.ai/v1/models")
    func fetch(apiKey: String) async throws -> QuotaSnapshot { try await inner.fetch(apiKey: apiKey) }
}

struct XAIProvider: QuotaProvider {
    let kind: ProviderKind = .xai
    private let inner = KeyValidationProvider(
        kind: .xai, endpoint: "https://api.x.ai/v1/models")
    func fetch(apiKey: String) async throws -> QuotaSnapshot { try await inner.fetch(apiKey: apiKey) }
}
