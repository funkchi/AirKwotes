import Foundation
import AppKit

enum CodexOAuthConfig {
    static let clientID      = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let authorizeURL  = "https://auth.openai.com/oauth/authorize"
    static let tokenURL      = "https://auth.openai.com/oauth/token"
    static let primaryPort: UInt16  = 1455
    static let fallbackPort: UInt16 = 1457
    static let scopes        = ["openid", "profile", "email", "offline_access"]

    static func redirectURI(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/callback"
    }
}

struct CodexTokenSet: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var accountID: String?
    var expiresAt: Date?

    var needsRefresh: Bool {
        guard let expiresAt else { return true }
        return expiresAt < Date().addingTimeInterval(60)
    }
    var email: String? {
        (idToken.flatMap { JWT.email(of: $0) }) ?? JWT.email(of: accessToken)
    }
    var planType: String? { JWT.planType(of: accessToken) }
}

enum OAuthError: Error, LocalizedError {
    case badURL, timeout, userCancelled, exchangeFailed(String), refreshFailed(String), listenerFailed
    var errorDescription: String? {
        switch self {
        case .badURL: return "Could not build the sign-in URL."
        case .timeout: return "Sign-in timed out."
        case .userCancelled: return "Sign-in cancelled."
        case .exchangeFailed(let m): return "Token exchange failed. \(m.prefix(200))"
        case .refreshFailed(let m): return "Token refresh failed. \(m.prefix(200))"
        case .listenerFailed: return "Could not start the local callback server."
        }
    }
}

/// Runs the ChatGPT (Codex) OAuth + PKCE flow exactly the way the official
/// Codex CLI does: loopback callback on 1455, public client id, code exchange.
final class CodexOAuth {
    static let keychainAccount = "relay.codex.tokens"
    private let queue = DispatchQueue(label: "ai.airkwotes.oauth.timeout")
    private let lock = NSLock()
    private var pending: CheckedContinuation<String, Error>?
    private var inflightVerifier: String?
    private var inflightState: String?

    // MARK: - Keychain persistence
    static func loadTokens() -> CodexTokenSet? {
        guard let raw = KeychainStore.getAPIKey(for: keychainAccount),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CodexTokenSet.self, from: data)
    }
    static func saveTokens(_ tokens: CodexTokenSet) {
        guard let data = try? JSONEncoder().encode(tokens),
              let s = String(data: data, encoding: .utf8) else { return }
        KeychainStore.setAPIKey(s, for: keychainAccount)
    }
    static func clearTokens() { KeychainStore.deleteAPIKey(for: keychainAccount) }

    // MARK: - Reuse existing ~/.codex login
    static func loadExistingCodexLogin() -> CodexTokenSet? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String,
              let refresh = tokens["refresh_token"] as? String else { return nil }
        return CodexTokenSet(
            accessToken: access,
            refreshToken: refresh,
            idToken: tokens["id_token"] as? String,
            accountID: JWT.accountID(of: access),
            expiresAt: JWT.expiry(of: access))
    }

    // MARK: - Interactive flow
    func authorize() async throws -> CodexTokenSet {
        let verifier = PKCE.generateVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.randomState()
        inflightVerifier = verifier
        inflightState = state

        let callback = try startCallbackServer(state: state)
        let redirectURI = CodexOAuthConfig.redirectURI(port: callback.port)
        defer { callback.server.stop() }

        guard let url = buildAuthorizeURL(challenge: challenge, state: state, redirectURI: redirectURI) else { throw OAuthError.badURL }
        NSWorkspace.shared.open(url)

        let code = try await waitForCode(timeout: 300)
        var tokens = try await exchangeCode(code, verifier: verifier, redirectURI: redirectURI)
        tokens.accountID = tokens.accountID ?? JWT.accountID(of: tokens.accessToken)
        Self.saveTokens(tokens)
        return tokens
    }

    private func buildAuthorizeURL(challenge: String, state: String, redirectURI: String) -> URL? {
        var comps = URLComponents(string: CodexOAuthConfig.authorizeURL)!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: CodexOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: CodexOAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        return comps.url
    }

    private func startCallbackServer(state: String) throws -> (server: LoopbackHTTPServer, port: UInt16) {
        for port in [CodexOAuthConfig.primaryPort, CodexOAuthConfig.fallbackPort] {
            let server = try LoopbackHTTPServer(port: port) { [weak self] request, respond in
                self?.handleCallback(request, expectedState: state, respond: respond)
            }
            do {
                try server.start()
                return (server, port)
            } catch {
                continue   // port in use, try next
            }
        }
        throw OAuthError.listenerFailed
    }

    private func handleCallback(_ request: LoopbackHTTPServer.Request,
                                expectedState: String,
                                respond: @escaping (LoopbackHTTPServer.Response) -> Void) {
        guard request.path == "/callback" else {
            respond(.html(404, "<h2>Not found</h2>")); return
        }
        let code = request.query["code"]
        let returnedState = request.query["state"]
        if let code, returnedState == expectedState {
            deliver(.success(code))
            respond(.html(200, """
            <html><body style='font-family:-apple-system,system-ui;text-align:center;padding:80px'>
            <h2>✅ Signed in to AirKwotes Relay</h2>
            <p>You can close this tab and return to AirKwotes.</p></body></html>
            """))
        } else {
            deliver(.failure(OAuthError.userCancelled))
            respond(.html(400, """
            <html><body style='font-family:-apple-system,system-ui;text-align:center;padding:80px'>
            <h2>Sign-in cancelled</h2><p>State mismatch or no code. Try again.</p></body></html>
            """))
        }
    }

    private func deliver(_ result: Result<String, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard let cont = pending else { return }
        pending = nil
        switch result {
        case .success(let code): cont.resume(returning: code)
        case .failure(let e): cont.resume(throwing: e)
        }
    }

    private func waitForCode(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            lock.lock(); pending = cont; lock.unlock()
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.deliver(.failure(OAuthError.timeout))
            }
        }
    }

    // MARK: - Token endpoint
    private func exchangeCode(_ code: String, verifier: String, redirectURI: String) async throws -> CodexTokenSet {
        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": CodexOAuthConfig.clientID,
            "redirect_uri": redirectURI
        ]
        let json = try await postToken(body: body, error: OAuthError.exchangeFailed)
        return CodexTokenSet(
            accessToken: json["access_token"] as? String ?? "",
            refreshToken: json["refresh_token"] as? String ?? "",
            idToken: json["id_token"] as? String,
            accountID: nil,
            expiresAt: (json["access_token"] as? String).flatMap { JWT.expiry(of: $0) })
    }

    func refresh(_ tokens: CodexTokenSet) async throws -> CodexTokenSet {
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": CodexOAuthConfig.clientID,
            "scope": CodexOAuthConfig.scopes.joined(separator: " ")
        ]
        let json = try await postToken(body: body, error: OAuthError.refreshFailed)
        let access = json["access_token"] as? String ?? tokens.accessToken
        return CodexTokenSet(
            accessToken: access,
            refreshToken: (json["refresh_token"] as? String) ?? tokens.refreshToken,
            idToken: (json["id_token"] as? String) ?? tokens.idToken,
            accountID: tokens.accountID ?? JWT.accountID(of: access),
            expiresAt: JWT.expiry(of: access))
    }

    private func postToken(body: [String: Any], error makeError: (String) -> OAuthError) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: CodexOAuthConfig.tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw makeError(String(data: data, encoding: .utf8) ?? "HTTP \(resp)")
            }
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        } catch let e as OAuthError {
            throw e
        } catch {
            throw makeError(error.localizedDescription)
        }
    }
}
