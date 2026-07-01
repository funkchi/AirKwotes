import Foundation

/// Local Codex usage reader inspired by codex-usage-tracker.
///
/// Codex does not expose a live ChatGPT subscription quota API for personal plans.
/// The best local signal is the newest `token_count.rate_limits` snapshot in
/// `~/.codex/sessions`, with an optional fallback to `~/.codex-usage-tracker/allowance.json`.
struct CodexProvider: QuotaProvider {
    let kind: ProviderKind = .codex
    let requiresAPIKey = false
    private let maxFilesToScan = 120
    private let maxTailBytes = 2_000_000

    /// Parses ISO-8601 timestamps with or without fractional seconds.
    /// Codex session logs use `2026-06-25T07:38:52.364Z`, which the default
    /// `ISO8601DateFormatter` (no `.withFractionalSeconds`) fails to parse.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func parseISO(_ string: String) -> Date? {
        Self.isoFractional.date(from: string) ?? Self.isoPlain.date(from: string)
    }

    func fetch(apiKey: String) async throws -> QuotaSnapshot {
        if let observed = latestObservedSnapshot() {
            return observed
        }
        if let allowance = allowanceSnapshot() {
            return allowance
        }
        return QuotaSnapshot(
            id: UUID(),
            remainingPercent: nil,
            remainingDisplay: "Waiting for next Codex usage",
            usedDisplay: nil,
            totalDisplay: nil,
            unit: "quota",
            status: .unsupported,
            fetchedAt: Date(),
            resetAt: nil,
            note: "The last observed Codex rate-limit window is stale or missing. Run one Codex request, use /status, or copy usage into ~/.codex-usage-tracker/allowance.json."
        )
    }

    private func latestObservedSnapshot() -> QuotaSnapshot? {
        let fm = FileManager.default
        let codexHome = fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let roots = [
            codexHome.appendingPathComponent("sessions"),
            codexHome.appendingPathComponent("archived_sessions")
        ]

        let files = roots.flatMap { jsonlFiles(in: $0) }
            .compactMap { url -> (URL, Date)? in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return (url, modified)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(maxFilesToScan)

        var best: CodexRateLimitSnapshot?
        for (url, _) in files {
            guard let snapshot = newestRateLimit(in: url) else { continue }
            guard !snapshot.isStale else { continue }
            if best == nil || snapshot.observedAt > best!.observedAt {
                best = snapshot
            }
        }
        guard let best else { return nil }
        return snapshot(from: best, source: "Local Codex log")
    }

    private func allowanceSnapshot() -> QuotaSnapshot? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-usage-tracker")
            .appendingPathComponent("allowance.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let windows = json["windows"] as? [[String: Any]] else {
            return nil
        }
        let fiveHour = windows.first { (($0["key"] as? String) ?? "").contains("five") }
            ?? windows.first { (($0["label"] as? String) ?? "").localizedCaseInsensitiveContains("5") }
        guard let fiveHour,
              let remaining = percent(fiveHour["remaining_percent"]) else {
            return nil
        }

        let weekly = windows.first { (($0["key"] as? String) ?? "").localizedCaseInsensitiveContains("week") }
        let weeklyRemaining = percent(weekly?["remaining_percent"])
        let resetAt = date(from: fiveHour["reset_at"])
        if let resetAt, resetAt < Date() { return nil }
        let capturedAt = date(from: fiveHour["captured_at"]) ?? Date()

        return QuotaSnapshot(
            id: UUID(),
            remainingPercent: remaining,
            remainingDisplay: "\(Format.percent(remaining)) remaining",
            usedDisplay: "\(Format.percent(1 - remaining))",
            totalDisplay: "5-hour window",
            unit: "quota",
            status: remaining < 0.15 ? .critical : (remaining < 0.40 ? .low : .ok),
            fetchedAt: capturedAt,
            resetAt: resetAt,
            note: "Copied allowance file",
            secondaryRemainingPercent: weeklyRemaining,
            secondaryLabel: weeklyRemaining != nil ? "Weekly" : nil
        )
    }

    private func jsonlFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            return url
        }
    }

    private func newestRateLimit(in file: URL) -> CodexRateLimitSnapshot? {
        guard let text = tailText(from: file) else { return nil }
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let data = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestamp = json["timestamp"] as? String,
                  let observedAt = Self.parseISO(timestamp),
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let rateLimits = payload["rate_limits"] as? [String: Any] else {
                continue
            }
            let primary = rateLimitWindow(rateLimits["primary"])
            let secondary = rateLimitWindow(rateLimits["secondary"])
            if primary == nil && !isExhausted(rateLimits) { continue }
            return CodexRateLimitSnapshot(
                observedAt: observedAt,
                limitID: rateLimits["limit_id"] as? String,
                planType: rateLimits["plan_type"] as? String,
                primary: primary,
                secondary: secondary,
                exhausted: isExhausted(rateLimits)
            )
        }
        return nil
    }

    private func tailText(from file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(maxTailBytes) ? size - UInt64(maxTailBytes) : 0
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        if offset > 0, let newline = data.firstRange(of: Data([0x0A])) {
            data.removeSubrange(data.startIndex..<newline.upperBound)
        }
        return String(data: data, encoding: .utf8)
    }

    private func rateLimitWindow(_ value: Any?) -> CodexRateLimitWindow? {
        guard let dict = value as? [String: Any],
              let used = percent(dict["used_percent"]) else {
            return nil
        }
        let windowMinutes = integer(dict["window_minutes"])
        let resetAt = integer(dict["resets_at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return CodexRateLimitWindow(usedPercent: used, windowMinutes: windowMinutes, resetAt: resetAt)
    }

    private func snapshot(from observed: CodexRateLimitSnapshot, source: String) -> QuotaSnapshot {
        guard let primary = observed.primary else {
            return QuotaSnapshot(
                id: UUID(),
                remainingPercent: 0,
                remainingDisplay: "0% remaining",
                usedDisplay: "100%",
                totalDisplay: "Codex allowance",
                unit: "quota",
                status: .critical,
                fetchedAt: observed.observedAt,
                resetAt: nil,
                note: "Codex reported the allowance as exhausted.",
                secondaryRemainingPercent: observed.secondary?.remainingPercent,
                secondaryLabel: observed.secondary != nil ? "Weekly" : nil
            )
        }

        let remaining = max(0, min(1, 1 - primary.usedPercent))
        var note = source
        if let limitID = observed.limitID { note += " · limit \(limitID)" }

        return QuotaSnapshot(
            id: UUID(),
            remainingPercent: remaining,
            remainingDisplay: "\(Format.percent(remaining)) remaining",
            usedDisplay: "\(Format.percent(primary.usedPercent))",
            totalDisplay: primary.windowLabel,
            unit: "quota",
            status: remaining < 0.15 ? .critical : (remaining < 0.40 ? .low : .ok),
            fetchedAt: observed.observedAt,
            resetAt: primary.resetAt,
            note: note,
            secondaryRemainingPercent: observed.secondary?.remainingPercent,
            secondaryLabel: observed.secondary != nil ? "Weekly" : nil
        )
    }

    private func percent(_ value: Any?) -> Double? {
        let raw: Double?
        if let n = value as? NSNumber {
            raw = n.doubleValue
        } else if let s = value as? String {
            raw = Double(s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: ""))
        } else {
            raw = nil
        }
        guard let raw else { return nil }
        return max(0, min(1, raw > 1 ? raw / 100 : raw))
    }

    private func integer(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private func date(from value: Any?) -> Date? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        if let date = Self.parseISO(string) { return date }
        if let seconds = Double(string) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private func isExhausted(_ rateLimits: [String: Any]) -> Bool {
        if let reached = rateLimits["rate_limit_reached_type"] as? String, !reached.isEmpty {
            return true
        }
        guard let credits = rateLimits["credits"] as? [String: Any] else { return false }
        if (credits["unlimited"] as? Bool) == true { return false }
        guard let balance = percentOrNumber(credits["balance"]) else { return false }
        return balance <= 0
    }

    private func percentOrNumber(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}

private struct CodexRateLimitSnapshot {
    let observedAt: Date
    let limitID: String?
    let planType: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let exhausted: Bool

    var isStale: Bool {
        guard let resetAt = primary?.resetAt else { return false }
        return resetAt < Date()
    }
}

private struct CodexRateLimitWindow {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetAt: Date?

    var remainingPercent: Double {
        max(0, min(1, 1 - usedPercent))
    }

    var windowLabel: String {
        guard let windowMinutes else { return "Usage window" }
        if windowMinutes == 300 { return "5-hour window" }
        if windowMinutes == 10_080 { return "Weekly window" }
        if windowMinutes >= 60 {
            return "\(windowMinutes / 60)-hour window"
        }
        return "\(windowMinutes)-minute window"
    }
}
