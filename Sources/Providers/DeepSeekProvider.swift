import Foundation

/// DeepSeek — reports account balance (CNY).
/// GET https://api.deepseek.com/user/balance
/// -> { balance_infos: [ { currency, total_balance, granted_balance, topped_up_balance } ] }
struct DeepSeekProvider: QuotaProvider {
    let kind: ProviderKind = .deepseek

    func fetch(apiKey: String) async throws -> QuotaSnapshot {
        do {
            let (data, _) = try await APIClient.shared.getBearer(
                "https://api.deepseek.com/user/balance", token: apiKey)
            let currency = data.extract("balance_infos.first.currency")?.asString ?? "CNY"
            let total = data.extract("balance_infos.first.total_balance")?.asDouble ?? 0
            let granted = data.extract("balance_infos.first.granted_balance")?.asDouble ?? 0
            let topped = data.extract("balance_infos.first.topped_up_balance")?.asDouble ?? 0
            if total == 0 && granted == 0 && topped == 0 {
                return fail(.invalid)
            }
            return QuotaSnapshot(
                id: UUID(),
                remainingPercent: nil,
                remainingDisplay: Format.value(total, currency: currency),
                usedDisplay: nil,
                totalDisplay: nil,
                unit: currency ?? "CNY",
                status: total < 1 ? .critical : (total < 10 ? .low : .ok),
                fetchedAt: Date(),
                resetAt: nil,
                note: "Granted \(Format.value(granted, currency: currency)) · Topped up \(Format.value(topped, currency: currency))"
            )
        } catch let HTTPError.status(401, _) {
            return fail(.invalid)
        } catch let HTTPError.status(402, _) {
            return fail(.critical)
        }
    }
}
