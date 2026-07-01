import Foundation

/// GLM via Zhipu (open.bigmodel.cn) or Z.ai (api.z.ai).
/// GET /api/monitor/usage/quota/limit -> token window (used / total) + MCP monthly quota.
struct ZhipuProvider: QuotaProvider {
    let kind: ProviderKind
    let host: String

    init(host: String) {
        self.host = host
        self.kind = (host == "api.z.ai") ? .zai : .zhipu
    }

    func fetch(apiKey: String) async throws -> QuotaSnapshot {
        do {
            let data = try await fetchQuotaLimit(apiKey: apiKey)

            let used = data.extract("tokenUsage.usedTokens")?.asDouble
                ?? data.extract("usedTokens")?.asDouble
                ?? data.extract("tokenWindow.used")?.asDouble
            let total = data.extract("tokenUsage.totalTokens")?.asDouble
                ?? data.extract("totalTokens")?.asDouble
                ?? data.extract("tokenWindow.total")?.asDouble
            let resetMs = data.extract("tokenUsage.resetTimestamp")?.asDouble
                ?? data.extract("tokenWindow.resetTimestamp")?.asDouble

            if let quota = codingPlanQuota(from: data) {
                return quota
            }

            guard let t = total, t > 0, let u = used else {
                if data.extract("code")?.asString != nil { return fail(.unsupported) }
                throw QuotaError.missingField("tokenUsage")
            }
            let remaining = max(0, t - u)
            let pct = max(0, min(1, remaining / t))
            let resetAt = resetMs.map { Date(timeIntervalSince1970: $0 / 1000) }

            var secondaryPct: Double? = nil
            var secondaryLabel: String? = nil
            if let mcpUsed = data.extract("mcpUsage.used")?.asDouble,
               let mcpTotal = data.extract("mcpUsage.total")?.asDouble, mcpTotal > 0 {
                secondaryPct = max(0, min(1, 1 - mcpUsed / mcpTotal))
                secondaryLabel = "Monthly"
            }
            return QuotaSnapshot(
                id: UUID(),
                remainingPercent: pct,
                remainingDisplay: "\(Format.tokens(remaining)) tokens",
                usedDisplay: "\(Format.tokens(u))",
                totalDisplay: "\(Format.tokens(t))",
                unit: "tokens",
                status: pct < 0.15 ? .critical : (pct < 0.40 ? .low : .ok),
                fetchedAt: Date(),
                resetAt: resetAt,
                note: nil,
                secondaryRemainingPercent: secondaryPct,
                secondaryLabel: secondaryLabel
            )
        } catch HTTPError.status(401, _) {
            return fail(.invalid)
        } catch HTTPError.status(403, _) {
            return fail(.invalid)
        }
    }

    private func fetchQuotaLimit(apiKey: String) async throws -> Data {
        let url = "https://\(host)/api/monitor/usage/quota/limit"
        do {
            let (data, _) = try await APIClient.shared.getAuthorized(
                url,
                authorization: apiKey,
                extraHeaders: [
                    "Accept-Language": "en-US,en",
                    "Content-Type": "application/json"
                ])
            return data
        } catch HTTPError.status(401, _) where !apiKey.localizedCaseInsensitiveContains("bearer ") {
            let (data, _) = try await APIClient.shared.getBearer(
                url,
                token: apiKey,
                extraHeaders: [
                    "Accept-Language": "en-US,en",
                    "Content-Type": "application/json"
                ])
            return data
        }
    }

    private func codingPlanQuota(from data: Data) -> QuotaSnapshot? {
        guard let json = data.asJSON() else { return nil }
        let root: Any
        if let dict = json as? [String: Any], let wrapped = dict["data"] {
            root = wrapped
        } else {
            root = json
        }
        guard let dict = root as? [String: Any],
              let limits = dict["limits"] as? [[String: Any]] else {
            return nil
        }

        let tokenLimit = limits.first { item in
            let type = (item["type"] as? String ?? "").uppercased()
            return type.contains("TOKEN")
        }
        guard let tokenLimit,
              let usedPercent = number(tokenLimit["percentage"]) else {
            return nil
        }

        let usedFraction = usedPercent > 1 ? usedPercent / 100 : usedPercent
        let remainingPct = max(0, min(1, 1 - usedFraction))
        var resetAt: Date?
        if let reset = number(tokenLimit["resetAt"] ?? tokenLimit["resetTimestamp"]) {
            resetAt = Date(timeIntervalSince1970: reset > 2_000_000_000 ? reset / 1000 : reset)
        }

        let mcpLimit = limits.first { item in
            let type = (item["type"] as? String ?? "").uppercased()
            return type.contains("TIME") || type.contains("MCP")
        }
        var secondaryPct: Double? = nil
        var secondaryLabel: String? = nil
        if let mcpLimit {
            let percent = number(mcpLimit["percentage"])
            let current = number(mcpLimit["currentValue"])
            let total = number(mcpLimit["usage"])
            if let current, let total, total > 0 {
                secondaryPct = max(0, min(1, 1 - current / total))
            } else if let percent {
                let used = percent > 1 ? percent / 100 : percent
                secondaryPct = max(0, min(1, 1 - used))
            }
            secondaryLabel = secondaryPct != nil ? "Monthly MCP" : nil
        }

        return QuotaSnapshot(
            id: UUID(),
            remainingPercent: remainingPct,
            remainingDisplay: "\(Format.percent(remainingPct)) remaining",
            usedDisplay: "\(Format.percent(usedFraction))",
            totalDisplay: "5-hour window",
            unit: "quota",
            status: remainingPct < 0.15 ? .critical : (remainingPct < 0.40 ? .low : .ok),
            fetchedAt: Date(),
            resetAt: resetAt,
            note: nil,
            secondaryRemainingPercent: secondaryPct,
            secondaryLabel: secondaryLabel
        )
    }

    private func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
