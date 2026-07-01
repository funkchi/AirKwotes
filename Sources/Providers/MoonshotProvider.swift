import Foundation

/// Kimi / Moonshot — reports account balance.
/// GET https://api.moonshot.ai/v1/users/me/balance
/// Response tolerated across shapes: { available_balance } | { data: { available_balance } } | { balance }
struct MoonshotProvider: QuotaProvider {
    let kind: ProviderKind = .moonshot

    func fetch(apiKey: String) async throws -> QuotaSnapshot {
        do {
            let (data, _) = try await APIClient.shared.getBearer(
                "https://api.moonshot.ai/v1/users/me/balance", token: apiKey)
            let raw = data.extract("available_balance")
                ?? data.extract("data.available_balance")
                ?? data.extract("balance")
                ?? data.extract("data.balance")
            guard let balance = raw?.asDouble else {
                if data.extract("code")?.asString == "ok" || data.extract("success") != nil {
                    return fail(.unsupported)
                }
                throw QuotaError.missingField("balance")
            }
            let currency = data.extract("currency")?.asString ?? "CNY"
            return QuotaSnapshot(
                id: UUID(),
                remainingPercent: nil,
                remainingDisplay: Format.value(balance, currency: currency),
                usedDisplay: nil,
                totalDisplay: nil,
                unit: currency,
                status: balance < 1 ? .critical : (balance < 10 ? .low : .ok),
                fetchedAt: Date(),
                resetAt: nil,
                note: nil
            )
        } catch let HTTPError.status(401, _) {
            return fail(.invalid)
        }
    }
}
