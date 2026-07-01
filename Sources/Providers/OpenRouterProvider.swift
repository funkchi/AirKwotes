import Foundation

/// OpenRouter — reports spend limit & usage (USD).
/// GET https://openrouter.ai/api/v1/key -> { data: { limit, usage, limit_remaining, is_free_tier } }
struct OpenRouterProvider: QuotaProvider {
    let kind: ProviderKind = .openrouter

    func fetch(apiKey: String) async throws -> QuotaSnapshot {
        do {
            let (data, _) = try await APIClient.shared.getBearer(
                "https://openrouter.ai/api/v1/key", token: apiKey)
            let limit = data.extract("data.limit")?.asDouble
            let usage = data.extract("data.usage")?.asDouble ?? 0
            let remaining = data.extract("data.limit_remaining")?.asDouble
                ?? (limit.map { max(0, $0 - usage) })

            if let l = limit, l > 0, let rem = remaining {
                let pct = max(0, min(1, rem / l))
                return QuotaSnapshot(
                    id: UUID(),
                    remainingPercent: pct,
                    remainingDisplay: Format.value(rem, currency: "USD"),
                    usedDisplay: Format.value(usage, currency: "USD"),
                    totalDisplay: Format.value(l, currency: "USD"),
                    unit: "USD",
                    status: pct < 0.15 ? .critical : (pct < 0.40 ? .low : .ok),
                    fetchedAt: Date(),
                    resetAt: nil,
                    note: nil
                )
            }
            // Unlimited / no limit set: report spend so far.
            return QuotaSnapshot(
                id: UUID(),
                remainingPercent: nil,
                remainingDisplay: "Unlimited",
                usedDisplay: Format.value(usage, currency: "USD"),
                totalDisplay: nil,
                unit: "USD",
                status: .ok,
                fetchedAt: Date(),
                resetAt: nil,
                note: "No spend limit set."
            )
        } catch let HTTPError.status(401, _) {
            return fail(.invalid)
        }
    }
}
