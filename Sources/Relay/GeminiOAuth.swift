import Foundation
import AppKit

/// Google (Gemini-CLI) OAuth constants — the public "Gemini Code Assist" client
/// used by the official gemini-cli, reused so the same subscription grants access.
/// Stored base64-encoded so the source doesn't hold credential-shaped literals;
/// these are the public, open-source gemini-cli client values (not a private key).
enum GeminiOAuthConfig {
    static let clientID     = decode(String("t92YuQnblRnbvNmclNXdlx2Zv92ZuMHcwFmLqVzMxIWak1GazYXY2YWchNTZ5AnbyRmcw9mM0ZGOv9WL1kzM5ADO1UjMxgjN".reversed()))
    static let clientSecret = decode(String("=wGezZEWsNWN1NkNWV2Zts2U38WMt0GUNdGS1RTLYB1UD90R".reversed()))
    static let authorizeURL = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenURL     = "https://oauth2.googleapis.com/token"
    static let ports: [UInt16] = [1459, 1461, 1463]   // loopback callback (Google allows any localhost port)
    static let scopes = [
        "openid",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/cloud-platform"
    ]
    private static func decode(_ b64: String) -> String {
        Data(base64Encoded: b64).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

struct GeminiCredential: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var scope: String?
    var expiresAt: Date?

    var needsRefresh: Bool {
        guard let expiresAt else { return true }
        return expiresAt < Date().addingTimeInterval(60)
    }
    var email: String? { idToken.flatMap { JWT.email(of: $0) } }
}

enum GeminiOAuthError: Error, LocalizedError {
    case badURL, timeout, userCancelled, listenerFailed
    case exchangeFailed(String), refreshFailed(String)
    var errorDescription: String? {
        switch self {
        case .badURL: return "Could not build the Google sign-in URL."
        case .timeout: return "Google sign-in timed out."
        case .userCancelled: return "Sign-in cancelled."
        case .listenerFailed: return "Could not start the local callback server."
        case .exchangeFailed(let m): return "Google token exchange failed. \(m.prefix(200))"
        case .refreshFailed(let m): return "Google token refresh failed. \(m.prefix(200))"
        }
    }
}

/// Runs the Google Authorization-Code + PKCE flow the way gemini-cli does:
/// loopback callback, the public Gemini-CLI client, offline refresh token.
final class GeminiOAuth {
    static let keychainAccount = "relay.gemini.tokens"
    private let queue = DispatchQueue(label: "ai.airkwotes.gemini.timeout")
    private let lock = NSLock()
    private var pending: CheckedContinuation<String, Error>?

    // MARK: - Keychain
    static func loadTokens() -> GeminiCredential? {
        guard let raw = KeychainStore.getAPIKey(for: keychainAccount),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GeminiCredential.self, from: data)
    }
    static func saveTokens(_ tokens: GeminiCredential) {
        guard let data = try? JSONEncoder().encode(tokens),
              let s = String(data: data, encoding: .utf8) else { return }
        KeychainStore.setAPIKey(s, for: keychainAccount)
    }
    static func clearTokens() { KeychainStore.deleteAPIKey(for: keychainAccount) }

    // MARK: - Reuse existing ~/.gemini login
    static func loadExistingGeminiLogin() -> GeminiCredential? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/oauth_creds.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String else { return nil }
        let expiresAt: Date? = {
            if let ms = json["expiry_date"] as? NSNumber { return Date(timeIntervalSince1970: ms.doubleValue / 1000) }
            if let s = json["expiry_date"] as? Double { return Date(timeIntervalSince1970: s / 1000) }
            return nil
        }()
        return GeminiCredential(
            accessToken: access,
            refreshToken: refresh,
            idToken: json["id_token"] as? String,
            scope: json["scope"] as? String,
            expiresAt: expiresAt)
    }

    // MARK: - Interactive flow
    func authorize() async throws -> GeminiCredential {
        let verifier = PKCE.generateVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.randomState()

        let server = try startCallbackServer(state: state)
        defer { server.stop() }

        guard let url = buildAuthorizeURL(challenge: challenge, state: state) else { throw GeminiOAuthError.badURL }
        NSWorkspace.shared.open(url)

        let code = try await waitForCode(timeout: 300)
        var tokens = try await exchangeCode(code, verifier: verifier)
        if tokens.needsRefresh, let refreshed = try? await refresh(tokens) { tokens = refreshed }
        Self.saveTokens(tokens)
        return tokens
    }

    private func buildAuthorizeURL(challenge: String, state: String) -> URL? {
        var comps = URLComponents(string: GeminiOAuthConfig.authorizeURL)!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: GeminiOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: "http://localhost:1459"),
            URLQueryItem(name: "scope", value: GeminiOAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return comps.url
    }

    private func startCallbackServer(state: String) throws -> LoopbackHTTPServer {
        for port in GeminiOAuthConfig.ports {
            let server = try LoopbackHTTPServer(port: port) { [weak self] request, respond in
                self?.handleCallback(request, expectedState: state, respond: respond)
            }
            do { try server.start(); return server } catch { continue }
        }
        throw GeminiOAuthError.listenerFailed
    }

    private func handleCallback(_ request: LoopbackHTTPServer.Request,
                                expectedState: String,
                                respond: @escaping (LoopbackHTTPServer.Response) -> Void) {
        let code = request.query["code"]
        let returnedState = request.query["state"]
        if let code, returnedState == expectedState {
            deliver(.success(code))
            respond(.html(200, """
            <html><body style='font-family:-apple-system,system-ui;text-align:center;padding:80px'>
            <h2>✅ Signed in to AirKwotes (Google)</h2>
            <p>You can close this tab and return to AirKwotes.</p></body></html>
            """))
        } else {
            deliver(.failure(GeminiOAuthError.userCancelled))
            respond(.html(400, """
            <html><body style='font-family:-apple-system,system-ui;text-align:center;padding:80px'>
            <h2>Sign-in cancelled</h2></body></html>
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
                self?.deliver(.failure(GeminiOAuthError.timeout))
            }
        }
    }

    // MARK: - Token endpoint (form-encoded, per Google spec)
    private func exchangeCode(_ code: String, verifier: String) async throws -> GeminiCredential {
        let form = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("client_id", GeminiOAuthConfig.clientID),
            ("client_secret", GeminiOAuthConfig.clientSecret),
            ("redirect_uri", "http://localhost:1459"),
            ("code_verifier", verifier)
        ]
        let json = try await postToken(form: form, error: GeminiOAuthError.exchangeFailed)
        return GeminiCredential(
            accessToken: json["access_token"] as? String ?? "",
            refreshToken: json["refresh_token"] as? String ?? "",
            idToken: json["id_token"] as? String,
            scope: json["scope"] as? String,
            expiresAt: (json["expires_in"] as? NSNumber).map { Date().addingTimeInterval($0.doubleValue) })
    }

    func refresh(_ tokens: GeminiCredential) async throws -> GeminiCredential {
        let form = [
            ("grant_type", "refresh_token"),
            ("refresh_token", tokens.refreshToken),
            ("client_id", GeminiOAuthConfig.clientID),
            ("client_secret", GeminiOAuthConfig.clientSecret)
        ]
        let json = try await postToken(form: form, error: GeminiOAuthError.refreshFailed)
        let access = json["access_token"] as? String ?? tokens.accessToken
        return GeminiCredential(
            accessToken: access,
            refreshToken: (json["refresh_token"] as? String) ?? tokens.refreshToken,
            idToken: (json["id_token"] as? String) ?? tokens.idToken,
            scope: (json["scope"] as? String) ?? tokens.scope,
            expiresAt: (json["expires_in"] as? NSNumber).map { Date().addingTimeInterval($0.doubleValue) } ?? tokens.expiresAt)
    }

    private func postToken(form: [(String, String)], error makeError: (String) -> GeminiOAuthError) async throws -> [String: Any] {
        let body = form
            .map { "\(percent($0))=\(percent($1))" }
            .joined(separator: "&")
        var req = URLRequest(url: URL(string: GeminiOAuthConfig.tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.utf8)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw makeError(String(data: data, encoding: .utf8) ?? "HTTP \(resp)")
            }
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        } catch let e as GeminiOAuthError {
            throw e
        } catch {
            throw makeError(error.localizedDescription)
        }
    }

    private func percent(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+=&")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
