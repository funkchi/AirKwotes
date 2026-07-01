import Foundation

/// SiliconFlow — reports balance + total balance (CNY).
/// GET https://api.siliconflow.cn/v1/user/info -> { data: { balance, totalBalance, chargeBalance } }
struct SiliconFlowProvider: QuotaProvider {
    let kind: ProviderKind = .siliconflow

    func fetch(apiKey: String) async throws -> QuotaSnapshot {
        do {
            let (data, _) = try await APIClient.shared.getBearer(
                "https://api.siliconflow.cn/v1/user/info", token: apiKey)
            let balance = data.extract("data.balance")?.asDouble
                ?? data.extract("balance")?.asDouble
            let total = data.extract("data.totalBalance")?.asDouble
                ?? data.extract("data.total_balance")?.asDouble
            guard let bal = balance else {
                throw QuotaError.missingField("balance")
            }
            var pct: Double? = nil
            if let t = total, t > 0 { pct = max(0, min(1, bal / t)) }
            return QuotaSnapshot(
                id: UUID(),
                remainingPercent: pct,
                remainingDisplay: Format.value(bal, currency: "CNY"),
                usedDisplay: total.map { Format.value(max(0, $0 - bal), currency: "CNY") },
                totalDisplay: total.map { Format.value($0, currency: "CNY") },
                unit: "CNY",
                status: bal < 1 ? .critical : (bal < 10 ? .low : .ok),
                fetchedAt: Date(),
                resetAt: nil,
                note: nil
            )
        } catch let HTTPError.status(401, _) {
            return fail(.invalid)
        }
    }
}
