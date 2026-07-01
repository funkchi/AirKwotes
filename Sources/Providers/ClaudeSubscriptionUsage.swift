import Foundation

/// Reads Claude Code subscription usage live from the API's rate-limit response
/// headers, using the OAuth token Claude Code already stores (see
/// `ClaudeCodeCredentials`). This is the turnkey path: no user configuration.
///
/// The cheapest way to elicit the headers is `POST /v1/messages/count_tokens`,
/// which is free and does not consume message quota.
///
/// NOTE ON HEADER NAMES: the documented `anthropic-ratelimit-*` headers cover
/// only the per-minute API-tier limits. The subscription 5-hour / 7-day windows
/// (what Claude Code's statusline shows) arrive as `anthropic-ratelimit-unified-*`
/// headers, which are currently undocumented. We therefore parse them
/// *generically* rather than hard-coding field names, and stash the raw header
/// names in the snapshot note when parsing fails so the exact mapping can be
/// confirmed against a real Anthropic subscription response.
enum ClaudeSubscriptionUsage {

    /// Returns a snapshot from live rate-limit headers, or `nil` if no
    /// credential is available or the response carried no usable unified data
    /// (caller then falls back to local-log reading).
    static func fetch() async -> QuotaSnapshot? {
        guard let cred = ClaudeCodeCredentials.discover() else { return nil }
        guard let http = await probe(cred) else { return nil }

        let headers = lowercasedHeaders(http)
        let unified = headers.filter { $0.key.hasPrefix("anthropic-ratelimit-unified-") }
        guard !unified.isEmpty else { return nil }

        let primary = window(in: unified, matching: ["5h", "5-hour", "five", "fivehour"])
        let secondary = window(in: unified, matching: ["7d", "7-day", "week", "sevenday"])
        // Some deployments expose a single, window-less unified block.
        let flat = primary == nil ? window(in: unified, matching: []) : nil

        guard let win = primary ?? flat else {
            // Unified headers exist but we couldn't interpret them — surface the
            // raw names so the mapping can be finalized on a real machine.
            return QuotaSnapshot(
                id: UUID(), remainingPercent: nil,
                remainingDisplay: "Claude subscription connected",
                usedDisplay: nil, totalDisplay: nil, unit: "quota",
                status: .unsupported, fetchedAt: Date(), resetAt: nil,
                note: "Unrecognized rate-limit headers: "
                    + unified.keys.sorted().joined(separator: ", "))
        }

        let remaining = win.remainingPercent
        return QuotaSnapshot(
            id: UUID(),
            remainingPercent: remaining,
            remainingDisplay: "\(Format.percent(remaining)) remaining",
            usedDisplay: Format.percent(win.usedPercent),
            totalDisplay: primary != nil ? "5-hour window" : "Usage window",
            unit: "quota",
            status: remaining < 0.15 ? .critical : (remaining < 0.40 ? .low : .ok),
            fetchedAt: Date(),
            resetAt: win.resetAt,
            note: "Claude subscription · live",
            secondaryRemainingPercent: secondary?.remainingPercent,
            secondaryLabel: secondary != nil ? "Weekly" : nil)
    }

    // MARK: - Request

    /// Fires a minimal probe and returns the response even on non-2xx (a 429
    /// still carries the rate-limit headers we want).
    ///
    /// The unified 5h/7d headers are only emitted by the message-serving path:
    /// `count_tokens` returns none (verified against the live API), so we send a
    /// tiny `max_tokens: 1` message. Negligible cost, and it's the only endpoint
    /// that reports subscription usage.
    private static func probe(_ cred: ClaudeCredential) async -> HTTPURLResponse? {
        guard let url = URL(string: cred.baseURL + "/v1/messages") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        cred.apply(to: &req)
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]]
        ])
        guard let (_, resp) = try? await APIClient.shared.session.data(for: req),
              let http = resp as? HTTPURLResponse else { return nil }
        return http
    }

    private static func lowercasedHeaders(_ http: HTTPURLResponse) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let key = (k as? String)?.lowercased(), let val = v as? String {
                out[key] = val
            }
        }
        return out
    }

    // MARK: - Generic window parsing

    private struct Window {
        let usedPercent: Double
        let resetAt: Date?
        var remainingPercent: Double { max(0, min(1, 1 - usedPercent)) }
    }

    /// Builds a usage window from whichever unified headers match a window's
    /// tokens (e.g. "5h", "week"). `matching: []` accepts window-less headers.
    private static func window(in unified: [String: String], matching tokens: [String]) -> Window? {
        // Suffix after "anthropic-ratelimit-unified-", keyed for this window.
        func belongs(_ suffix: String) -> Bool {
            tokens.isEmpty ? !suffix.contains(where: { $0.isNumber })
                           : tokens.contains { suffix.contains($0) }
        }
        var fields: [String: String] = [:]
        for (key, value) in unified {
            let suffix = String(key.dropFirst("anthropic-ratelimit-unified-".count))
            if belongs(suffix) { fields[suffix] = value }
        }
        guard !fields.isEmpty else { return nil }

        guard let used = usedPercent(from: fields) else { return nil }
        return Window(usedPercent: used, resetAt: fields.firstValue(containing: "reset").flatMap(parseDate))
    }

    /// Derives fraction-used (0…1). Anthropic's unified headers report it as
    /// `*-utilization` (a 0…1 fraction); older/other encodings are handled too.
    private static func usedPercent(from fields: [String: String]) -> Double? {
        if let p = fields.firstValue(containing: "utilization").flatMap(number) {
            return clampFraction(p)
        }
        if let p = fields.firstValue(containing: "used_perc").flatMap(number) {
            return clampFraction(p)
        }
        if let p = fields.firstValue(containing: "remaining_perc").flatMap(number) {
            return max(0, min(1, 1 - normalizeToFraction(p)))
        }
        let remaining = fields.firstValue(matchingAll: ["remaining"], excluding: ["perc"]).flatMap(number)
        let limit = fields.firstValue(containing: "limit").flatMap(number)
        let used = fields.firstValue(matchingAll: ["used"], excluding: ["perc"]).flatMap(number)
        if let used, let limit, limit > 0 { return max(0, min(1, used / limit)) }
        if let remaining, let limit, limit > 0 { return max(0, min(1, 1 - remaining / limit)) }
        return nil
    }

    private static func clampFraction(_ v: Double) -> Double { max(0, min(1, normalizeToFraction(v))) }
    private static func normalizeToFraction(_ v: Double) -> Double { v > 1 ? v / 100 : v }

    private static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: ""))
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    private static func parseDate(_ s: String) -> Date? {
        if let d = isoFractional.date(from: s) ?? isoPlain.date(from: s) { return d }
        if let raw = Double(s) { return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw) }
        return nil
    }
}

private extension Dictionary where Key == String, Value == String {
    func firstValue(containing needle: String) -> String? {
        first { $0.key.contains(needle) }?.value
    }
    func firstValue(matchingAll needles: [String], excluding: [String]) -> String? {
        first { entry in
            needles.allSatisfy { entry.key.contains($0) } && !excluding.contains { entry.key.contains($0) }
        }?.value
    }
}
