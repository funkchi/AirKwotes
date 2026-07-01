import Foundation

/// Local Claude Code subscription usage reader.
///
/// Claude Code does not expose a simple public quota API. Recent Claude Code
/// builds can emit `rate_limits` objects for statusline integrations; this
/// provider reads AirKwotes' statusline capture file first, then falls back to
/// transcript JSONL files if a future Claude build persists those snapshots.
struct ClaudeCodeProvider: QuotaProvider {
    let kind: ProviderKind = .claudeCode
    let requiresAPIKey = false

    private let maxFilesToScan = 120
    private let maxTailBytes = 2_000_000

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    func fetch(apiKey: String) async throws -> QuotaSnapshot {
        // Primary (turnkey): live subscription usage from the API's rate-limit
        // headers, using the OAuth token Claude Code already stores. No setup.
        if let live = await ClaudeSubscriptionUsage.fetch() {
            return live
        }
        // Fallbacks: a rate_limits snapshot captured from the statusline hook,
        // then one persisted in the local transcript logs.
        if let captured = capturedStatuslineSnapshot() {
            return captured
        }
        if let observed = latestObservedSnapshot() {
            return observed
        }
        return QuotaSnapshot(
            id: UUID(),
            remainingPercent: nil,
            remainingDisplay: "Waiting for Claude Code usage",
            usedDisplay: nil,
            totalDisplay: nil,
            unit: "quota",
            status: .unsupported,
            fetchedAt: Date(),
            resetAt: nil,
            note: "No local Claude Code rate-limit snapshot found yet. Restart Claude Code so the AirKwotes statusline capture can receive rate_limits, then run one Claude Code request."
        )
    }

    private func capturedStatuslineSnapshot() -> QuotaSnapshot? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("airkwotes-rate-limits.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snapshot = snapshot(in: json),
              !snapshot.isStale else {
            return nil
        }
        return self.snapshot(from: snapshot, source: "Claude Code statusline")
    }

    private func latestObservedSnapshot() -> QuotaSnapshot? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")

        let files = jsonlFiles(in: root)
            .compactMap { url -> (URL, Date)? in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return (url, modified)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(maxFilesToScan)

        var best: ClaudeRateLimitSnapshot?
        for (url, _) in files {
            guard let snapshot = newestRateLimit(in: url) else { continue }
            guard !snapshot.isStale else { continue }
            if best == nil || snapshot.observedAt > best!.observedAt {
                best = snapshot
            }
        }
        guard let best else { return nil }
        return snapshot(from: best, source: "Local Claude Code log")
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

    private func newestRateLimit(in file: URL) -> ClaudeRateLimitSnapshot? {
        guard let text = tailText(from: file) else { return nil }
        for line in text.split(separator: "\n").reversed()
            where line.contains("\"rate_limits\"") || line.contains("\"rateLimits\"") {
            guard let data = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let snapshot = snapshot(in: json) else {
                continue
            }
            return snapshot
        }
        return nil
    }

    private func snapshot(in json: [String: Any]) -> ClaudeRateLimitSnapshot? {
        guard let observedAt = observedDate(in: json),
              let rateLimits = firstRateLimits(in: json) else {
            return nil
        }
        let windows = windows(from: rateLimits)
        guard !windows.isEmpty else { return nil }
        let primary = choosePrimary(from: windows)
        let secondary = chooseSecondary(from: windows, primary: primary)
        guard let primary else { return nil }
        return ClaudeRateLimitSnapshot(
            observedAt: observedAt,
            primary: primary,
            secondary: secondary
        )
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

    private func firstRateLimits(in value: Any) -> Any? {
        if let dict = value as? [String: Any] {
            if let rateLimits = dict["rate_limits"] { return rateLimits }
            if let rateLimits = dict["rateLimits"] { return rateLimits }
            for child in dict.values {
                if let found = firstRateLimits(in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstRateLimits(in: child) { return found }
            }
        }
        return nil
    }

    private func windows(from rateLimits: Any) -> [ClaudeRateLimitWindow] {
        if let array = rateLimits as? [[String: Any]] {
            return array.compactMap { window(from: $0, fallbackLabel: nil) }
        }
        guard let dict = rateLimits as? [String: Any] else { return [] }

        if let windows = dict["windows"] as? [[String: Any]] {
            return windows.compactMap { window(from: $0, fallbackLabel: nil) }
        }

        if let primary = window(from: dict, fallbackLabel: "5-hour window") {
            let nested = dict.compactMap { key, value -> ClaudeRateLimitWindow? in
                guard let child = value as? [String: Any] else { return nil }
                return window(from: child, fallbackLabel: key)
            }
            return nested.isEmpty ? [primary] : nested
        }

        return dict.compactMap { key, value -> ClaudeRateLimitWindow? in
            guard let child = value as? [String: Any] else { return nil }
            return window(from: child, fallbackLabel: key)
        }
    }

    private func window(from dict: [String: Any], fallbackLabel: String?) -> ClaudeRateLimitWindow? {
        let used = percent(
            firstValue(in: dict, keys: ["used_percentage", "used_percent", "usedPercentage", "usage_percentage", "usagePercent"])
        )
        let remaining = percent(
            firstValue(in: dict, keys: ["remaining_percentage", "remaining_percent", "remainingPercentage"])
        )

        let usedPercent: Double
        if let used {
            usedPercent = used
        } else if let remaining {
            usedPercent = 1 - remaining
        } else {
            return nil
        }

        let label = string(firstValue(in: dict, keys: ["label", "name", "key", "type", "window"])) ?? fallbackLabel
        let windowMinutes = integer(firstValue(in: dict, keys: ["window_minutes", "windowMinutes", "minutes"]))
        let resetAt = date(firstValue(in: dict, keys: ["resets_at", "reset_at", "resetsAt", "resetAt"]))
        return ClaudeRateLimitWindow(
            label: label,
            usedPercent: max(0, min(1, usedPercent)),
            windowMinutes: windowMinutes,
            resetAt: resetAt
        )
    }

    private func choosePrimary(from windows: [ClaudeRateLimitWindow]) -> ClaudeRateLimitWindow? {
        windows.first { $0.isFiveHour }
            ?? windows.first { $0.labelText.contains("primary") }
            ?? windows.first
    }

    private func chooseSecondary(from windows: [ClaudeRateLimitWindow],
                                 primary: ClaudeRateLimitWindow?) -> ClaudeRateLimitWindow? {
        windows.first { candidate in
            guard candidate != primary else { return false }
            return candidate.isWeekly
        } ?? windows.first { $0 != primary }
    }

    private func snapshot(from observed: ClaudeRateLimitSnapshot, source: String) -> QuotaSnapshot {
        let primary = observed.primary
        let remaining = primary.remainingPercent
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
            note: source,
            secondaryRemainingPercent: observed.secondary?.remainingPercent,
            secondaryLabel: observed.secondary?.secondaryLabel
        )
    }

    private func observedDate(in json: [String: Any]) -> Date? {
        if let timestamp = json["timestamp"] as? String {
            return Self.parseISO(timestamp)
        }
        if let message = json["message"] as? [String: Any],
           let timestamp = message["timestamp"] as? String {
            return Self.parseISO(timestamp)
        }
        return nil
    }

    private static func parseISO(_ string: String) -> Date? {
        isoFractional.date(from: string) ?? isoPlain.date(from: string)
    }

    private func firstValue(in dict: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = dict[key] { return value }
        }
        return nil
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

    private func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private func date(_ value: Any?) -> Date? {
        if let n = value as? NSNumber {
            let raw = n.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
        }
        guard let s = value as? String, !s.isEmpty else { return nil }
        if let parsed = Self.parseISO(s) { return parsed }
        if let raw = Double(s) {
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)
        }
        return nil
    }
}

private struct ClaudeRateLimitSnapshot {
    let observedAt: Date
    let primary: ClaudeRateLimitWindow
    let secondary: ClaudeRateLimitWindow?

    var isStale: Bool {
        guard let resetAt = primary.resetAt else { return false }
        return resetAt < Date()
    }
}

private struct ClaudeRateLimitWindow: Equatable {
    let label: String?
    let usedPercent: Double
    let windowMinutes: Int?
    let resetAt: Date?

    var remainingPercent: Double {
        max(0, min(1, 1 - usedPercent))
    }

    var labelText: String {
        (label ?? "").lowercased()
    }

    var isFiveHour: Bool {
        windowMinutes == 300
            || labelText.contains("five")
            || labelText.contains("5h")
            || labelText.contains("5_h")
            || labelText.contains("5-hour")
            || labelText.contains("5 hour")
            || (labelText.contains("5") && labelText.contains("hour"))
    }

    var isWeekly: Bool {
        windowMinutes == 10_080
            || labelText.contains("seven")
            || labelText.contains("7d")
            || labelText.contains("7_d")
            || labelText.contains("7-day")
            || labelText.contains("7 day")
            || labelText.contains("weekly")
            || labelText.contains("week")
    }

    var windowLabel: String {
        if isFiveHour { return "5-hour window" }
        if isWeekly { return "7-day window" }
        if let windowMinutes {
            if windowMinutes == 10_080 { return "7-day window" }
            if windowMinutes == 300 { return "5-hour window" }
            if windowMinutes >= 1_440 { return "\(windowMinutes / 1_440)-day window" }
            if windowMinutes >= 60 { return "\(windowMinutes / 60)-hour window" }
            return "\(windowMinutes)-minute window"
        }
        return label ?? "Usage window"
    }

    var secondaryLabel: String {
        isWeekly ? "Weekly" : windowLabel
    }
}
