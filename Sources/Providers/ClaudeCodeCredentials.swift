import Foundation
import Security

/// Zero-config discovery of a **genuine Anthropic Claude subscription** login
/// that Claude Code has stored on this machine, so AirKwotes can read the
/// subscription's 5h/7d usage without any user setup.
///
/// This deliberately only reads OAuth credentials created by signing in to an
/// Anthropic account. It does NOT read `ANTHROPIC_AUTH_TOKEN`/`ANTHROPIC_API_KEY`
/// from `~/.claude/settings.json` — those belong to whatever endpoint the user
/// points Claude Code at (e.g. a Z.ai / GLM gateway), which is tracked
/// separately by its own API-key provider. Mixing them here would hijack that
/// credential.
///
/// Resolution order (first hit wins):
///   1. macOS login Keychain item `Claude Code-credentials` (how the Claude
///      Code CLI stores its OAuth tokens on macOS). Reading another app's item
///      triggers a one-time "Always Allow" prompt, then stays silent.
///   2. `~/.claude/.credentials.json` (OAuth tokens on Linux / older installs).
struct ClaudeCredential {
    let token: String
    let baseURL = "https://api.anthropic.com"

    /// Applies Anthropic OAuth auth + versioning headers.
    func apply(to req: inout URLRequest) {
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    }
}

enum ClaudeCodeCredentials {
    static func discover() -> ClaudeCredential? {
        fromKeychain() ?? fromCredentialsFile()
    }

    // MARK: - 1. macOS Keychain ("Claude Code-credentials")
    private static func fromKeychain() -> ClaudeCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return parseOAuthBlob(data)
    }

    // MARK: - 2. ~/.claude/.credentials.json
    private static func fromCredentialsFile() -> ClaudeCredential? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseOAuthBlob(data)
    }

    /// Both the Keychain item and `.credentials.json` hold the same JSON shape:
    /// `{ "claudeAiOauth": { "accessToken": "...", "expiresAt": <ms>, ... } }`.
    private static func parseOAuthBlob(_ data: Data) -> ClaudeCredential? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let oauth = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let token = (oauth["accessToken"] as? String) ?? (oauth["access_token"] as? String),
              !token.isEmpty else { return nil }
        return ClaudeCredential(token: token)
    }
}
