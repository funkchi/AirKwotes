import Foundation
import SwiftUI

@MainActor
final class RelayManager: ObservableObject {
    enum OAuthState: Equatable {
        case signedOut
        case signingIn
        case signedIn(email: String, plan: String?)
        case error(String)
    }

    @Published private(set) var oauthState: OAuthState = .signedOut
    @Published private(set) var tokens: CodexTokenSet?
    @Published private(set) var geminiState: OAuthState = .signedOut
    @Published private(set) var gemini: GeminiCredential?
    @Published private(set) var geminiProject: String?
    @Published var serverOn: Bool = false
    @Published private(set) var port: Int = 8787
    @Published private(set) var localKey: String = ""
    @Published private(set) var lastError: String?

    private let oauth = CodexOAuth()
    private let geminiOAuth = GeminiOAuth()
    private var relay: RelayServer?
    private let defaults = UserDefaults.standard
    private var secretsLoaded = false

    private static let localKeyAccount = "relay.localkey"
    private enum Keys {
        static let enabled = "ak.relay.enabled.v1"
        static let port = "ak.relay.port.v1"
    }

    init() {
        // Only read non-secret preferences at startup. Keychain secrets are
        // loaded lazily via ensureSecretsLoaded() when the relay is enabled
        // or the Relay UI is shown.
        port = Self.validPort(defaults.object(forKey: Keys.port) as? Int ?? 8787)
        if defaults.bool(forKey: Keys.enabled) {
            ensureSecretsLoaded()
            startServerWithRetry()
        }
    }

    /// Auto-start path: try once, and if the bind failed (typical cause: a
    /// previous instance is still releasing the port after a rebuild/relaunch),
    /// retry once after a short delay so the relay comes back reliably.
    func startServerWithRetry() {
        startServer()
        guard !serverOn else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self?.startServer()
        }
    }

    /// Loads the local relay key and any stored Codex credentials from the
    /// Keychain exactly once, only when actually needed.
    func ensureSecretsLoaded() {
        guard !secretsLoaded else { return }
        secretsLoaded = true
        if let existing = Self.loadLocalKey() {
            localKey = existing
        } else {
            let minted = Self.mintLocalKey()
            Self.saveLocalKey(minted)
            localKey = minted
        }
        if let stored = CodexOAuth.loadTokens() {
            tokens = stored
            oauthState = .signedIn(email: stored.email ?? "Codex account", plan: stored.planType)
        } else if let reused = CodexOAuth.loadExistingCodexLogin() {
            CodexOAuth.saveTokens(reused)
            tokens = reused
            oauthState = .signedIn(email: reused.email ?? "Codex account", plan: reused.planType)
        }
        if let stored = GeminiOAuth.loadTokens() {
            gemini = stored
            geminiState = .signedIn(email: stored.email ?? "Google account", plan: "Gemini")
            resolveGeminiProject()
        } else if let reused = GeminiOAuth.loadExistingGeminiLogin() {
            GeminiOAuth.saveTokens(reused)
            gemini = reused
            geminiState = .signedIn(email: reused.email ?? "Google account", plan: "Gemini")
            resolveGeminiProject()
        }
    }

    private func resolveGeminiProject() {
        guard let cred = gemini, geminiProject == nil else { return }
        Task { [weak self] in
            let project = await CodeAssistClient.resolveProject(credential: cred)
            await MainActor.run { self?.geminiProject = project }
        }
    }

    var baseURL: String { "http://127.0.0.1:\(port)/v1" }
    var geminiBaseURL: String { "http://127.0.0.1:\(port)/v1beta" }
    var signedInEmail: String? {
        if case .signedIn(let email, _) = oauthState { return email }
        return nil
    }
    var geminiSignedInEmail: String? {
        if case .signedIn(let email, _) = geminiState { return email }
        return nil
    }

    // MARK: - OAuth
    func signIn() {
        guard oauthState != .signingIn else { return }
        oauthState = .signingIn
        lastError = nil
        Task {
            do {
                var result = try await oauth.authorize()
                if result.needsRefresh { result = (try? await oauth.refresh(result)) ?? result }
                CodexOAuth.saveTokens(result)
                tokens = result
                oauthState = .signedIn(email: result.email ?? "Codex account", plan: result.planType)
            } catch {
                oauthState = .error(error.localizedDescription)
                lastError = error.localizedDescription
            }
        }
    }

    func useExistingLogin() {
        guard let reused = CodexOAuth.loadExistingCodexLogin() else {
            lastError = "No Codex login found at ~/.codex/auth.json. Run `codex login` first."
            return
        }
        CodexOAuth.saveTokens(reused)
        tokens = reused
        oauthState = .signedIn(email: reused.email ?? "Codex account", plan: reused.planType)
    }

    func signOut() {
        CodexOAuth.clearTokens()
        tokens = nil
        oauthState = .signedOut
    }

    // MARK: - Google Gemini OAuth
    func signInGemini() {
        guard geminiState != .signingIn else { return }
        geminiState = .signingIn
        lastError = nil
        Task {
            do {
                var result = try await geminiOAuth.authorize()
                if result.needsRefresh { result = (try? await geminiOAuth.refresh(result)) ?? result }
                GeminiOAuth.saveTokens(result)
                gemini = result
                geminiState = .signedIn(email: result.email ?? "Google account", plan: "Gemini")
                resolveGeminiProject()
            } catch {
                geminiState = .error(error.localizedDescription)
                lastError = error.localizedDescription
            }
        }
    }

    func useExistingGeminiLogin() {
        guard let reused = GeminiOAuth.loadExistingGeminiLogin() else {
            lastError = "No Gemini login found at ~/.gemini/oauth_creds.json. Run `gemini` and sign in first."
            return
        }
        GeminiOAuth.saveTokens(reused)
        gemini = reused
        geminiState = .signedIn(email: reused.email ?? "Google account", plan: "Gemini")
        resolveGeminiProject()
    }

    func signOutGemini() {
        GeminiOAuth.clearTokens()
        gemini = nil
        geminiProject = nil
        geminiState = .signedOut
    }

    // MARK: - Gemini forwarding (Code Assist)
    /// Ensures the access token is fresh, then forwards to cloudcode-pa.
    private func freshGeminiCredential() async -> GeminiCredential? {
        guard var cred = gemini else { return nil }
        if cred.needsRefresh, let refreshed = try? await geminiOAuth.refresh(cred) {
            cred = refreshed
            gemini = cred
            GeminiOAuth.saveTokens(cred)
        }
        return cred
    }

    func geminiForward(model: String, body: Data) async -> (Int, Data) {
        guard let cred = await freshGeminiCredential() else {
            return (401, CodeAssistJSON.error("Gemini not signed in."))
        }
        return await CodeAssistClient.generateContent(
            model: model, body: body, credential: cred, project: geminiProject)
    }

    nonisolated func geminiForwardStream(model: String, body: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let cred = await self.freshGeminiCredential() else {
                    continuation.finish(); return
                }
                let project = await MainActor.run { self.geminiProject }
                let stream = CodeAssistClient.streamGenerateContent(
                    model: model, body: body, credential: cred, project: project)
                do {
                    for try await chunk in stream { continuation.yield(chunk) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    // MARK: - Server
    func startServer() {
        ensureSecretsLoaded()
        guard relay == nil else { return }
        let server = RelayServer(port: UInt16(port), localKey: localKey)
        server.tokenProvider = { [weak self] in self?.tokens }
        server.geminiTokenProvider = { [weak self] in self?.gemini }
        server.geminiForward = { [weak self] model, body in
            guard let self else { return (502, CodeAssistJSON.error("Relay unavailable.")) }
            return await self.geminiForward(model: model, body: body)
        }
        server.geminiForwardStream = { [weak self] model, body in
            guard let self else { return AsyncThrowingStream { $0.finish() } }
            return self.geminiForwardStream(model: model, body: body)
        }
        do {
            try server.start()
            relay = server
            serverOn = true
            defaults.set(true, forKey: Keys.enabled)
            defaults.set(port, forKey: Keys.port)
            lastError = nil
        } catch {
            lastError = "Could not start relay on port \(port): \(error.localizedDescription)"
            relay = nil
            serverOn = false
        }
    }

    func stopServer() {
        relay?.stop()
        relay = nil
        serverOn = false
        lastError = nil
        defaults.set(false, forKey: Keys.enabled)
    }

    func setServerOn(_ enabled: Bool) {
        enabled ? startServer() : stopServer()
    }

    func toggleServer() { setServerOn(!serverOn) }

    func setPort(_ value: Int) {
        guard !serverOn else { return }
        let next = Self.validPort(value)
        port = next
        defaults.set(next, forKey: Keys.port)
    }

    // MARK: - Local key persistence
    private static func loadLocalKey() -> String? {
        KeychainStore.getAPIKey(for: localKeyAccount)
    }
    private static func saveLocalKey(_ key: String) {
        KeychainStore.setAPIKey(key, for: localKeyAccount)
    }
    private static func mintLocalKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return "sk-airkwotes-" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func validPort(_ value: Int) -> Int {
        min(65_535, max(1_024, value))
    }
}
