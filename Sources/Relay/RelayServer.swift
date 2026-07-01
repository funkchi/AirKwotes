import Foundation

/// The local relay endpoint. Phase 0/1: serves status + model list and
/// authenticates with the local key. Request forwarding arrives in Phase 2.
final class RelayServer {
    static let supportedModels = [
        "gpt-5", "gpt-5-codex", "gpt-5.5", "gpt-4o", "gpt-4o-mini", "o3", "o4-mini"
    ]
    static let geminiModels = [
        "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash", "gemini-2.0-flash-lite"
    ]

    private let port: UInt16
    private let localKey: String
    private var server: LoopbackHTTPServer?
    /// Returns the current upstream credentials (Phase 2 forwarding).
    var tokenProvider: (() -> CodexTokenSet?)?
    var geminiTokenProvider: (() -> GeminiCredential?)?
    /// Forwarders supplied by RelayManager (Code Assist upstream).
    var geminiForward: ((String, Data) async -> (Int, Data))?
    var geminiForwardStream: ((String, Data) -> AsyncThrowingStream<Data, Error>)?

    init(port: UInt16, localKey: String) {
        self.port = port
        self.localKey = localKey
    }

    func start() throws {
        let s = try LoopbackHTTPServer(port: port) { [weak self] request, respond in
            self?.route(request, respond: respond)
        }
        try s.start()
        server = s
    }

    func stop() {
        server?.stop()
        server = nil
    }

    var isRunning: Bool { server?.isRunning ?? false }

    // MARK: - Routing
    private func route(_ request: LoopbackHTTPServer.Request,
                       respond: @escaping (LoopbackHTTPServer.Response) -> Void) {
        switch request.path {
        case "/":
            respond(landingPage())
        case "/health":
            respond(.json(200, ["service": "AirKwotes Relay", "status": "ok"]))
        case "/v1/models":
            authed(request, respond: respond) { respond(modelList()) }
        case "/v1/responses":
            authed(request, respond: respond) {
                respond(.json(501, [
                    "error": ["type": "not_implemented",
                              "message": "Request forwarding lands in Phase 2."]
                ]))
            }
        case "/v1/chat/completions":
            authed(request, respond: respond) {
                respond(.json(501, ["error": ["type": "not_implemented",
                                              "message": "Chat-completions translation lands in a later phase."]]))
            }
        case "/v1beta/models":
            authed(request, respond: respond) { respond(geminiModelList()) }
        case let p where p.hasPrefix("/v1beta/models/") && p.contains(":streamGenerateContent"):
            authed(request, respond: respond) {
                guard let forward = geminiForwardStream else {
                    respond(.json(503, ["error": ["message": "Gemini forwarding unavailable."]])); return
                }
                let model = Self.model(from: p)
                let stream = forward(model, request.body)
                respond(.stream(200, headers: ["Content-Type": "text/event-stream",
                                      "Cache-Control": "no-cache"], producer: { writer in
                    do { for try await chunk in stream { await writer.send(chunk) } } catch {}
                }))
            }
        case let p where p.hasPrefix("/v1beta/models/") && p.contains(":generateContent"):
            authed(request, respond: respond) {
                guard let forward = geminiForward else {
                    respond(.json(503, ["error": ["message": "Gemini forwarding unavailable."]])); return
                }
                let model = Self.model(from: p)
                let body = request.body
                Task {
                    let (status, data) = await forward(model, body)
                    respond(LoopbackHTTPServer.Response(status: status,
                                                         headers: ["Content-Type": "application/json"],
                                                         body: data))
                }
            }
        default:
            respond(.json(404, ["error": ["type": "not_found", "message": "Unknown path."]]))
        }
    }

    private static func model(from path: String) -> String {
        let prefix = "/v1beta/models/"
        guard path.hasPrefix(prefix) else { return "" }
        let rest = String(path.dropFirst(prefix.count))
        return rest.split(separator: ":").first.map(String.init) ?? rest
    }

    private func authed(_ request: LoopbackHTTPServer.Request,
                        respond: @escaping (LoopbackHTTPServer.Response) -> Void,
                        then body: () -> Void) {
        let header = request.headers["authorization"] ?? ""
        guard header.hasPrefix("Bearer "), header.dropFirst("Bearer ".count).trimmingCharacters(in: .whitespaces) == localKey else {
            respond(.json(401, ["error": ["type": "invalid_api_key",
                                          "message": "Invalid or missing API key."]]))
            return
        }
        body()
    }

    private func modelList() -> LoopbackHTTPServer.Response {
        let data = Self.supportedModels.map { id in
            ["id": id, "object": "model", "owned_by": "codex"]
        }
        return .json(200, ["object": "list", "data": data])
    }

    private func geminiModelList() -> LoopbackHTTPServer.Response {
        let data = Self.geminiModels.map { id in
            ["name": "models/\(id)", "version": "1", "displayName": id,
             "description": "Gemini model via AirKwotes Relay"]
        }
        return .json(200, ["models": data])
    }

    /// Human-facing landing page shown when a user opens the relay URL in a browser.
    private func landingPage() -> LoopbackHTTPServer.Response {
        let account = tokenProvider?()?.email ?? "Not signed in"
        let geminiAccount = geminiTokenProvider?()?.email ?? "Not signed in"
        let models = Self.supportedModels.map { "<li>\($0)</li>" }.joined()
        let geminiModels = Self.geminiModels.map { "<li>\($0)</li>" }.joined()
        let html = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
          body{font-family:-apple-system,system-ui,sans-serif;max-width:640px;margin:48px auto;padding:0 24px;color:#1a1a1a}
          h1{font-size:28px;margin-bottom:4px}
          h3{margin-top:28px}
          .muted{color:#6b6b70}
          .ok{color:#16a34a;font-weight:600}
          .card{background:#f5f5f7;border-radius:12px;padding:16px 18px;margin:16px 0}
          code,pre{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
          pre{background:#fff;border:1px solid #e5e5ea;border-radius:8px;padding:12px;overflow:auto}
          li{margin:2px 0}
          .acct{display:inline-block;margin-right:18px}
        </style></head><body>
        <h1>⚡ AirKwotes Relay</h1>
        <p><span class="ok">● Online</span> · listening on <code>127.0.0.1:\(port)</code></p>
        <p class="muted"><span class="acct">Codex: \(account)</span><span class="acct">Gemini: \(geminiAccount)</span></p>
        <div class="card">
        <pre>OPENAI_BASE_URL=http://127.0.0.1:\(port)/v1
        OPENAI_API_KEY=&lt;your AirKwotes relay key&gt;</pre>
        <p class="muted">Copy your local API key from the AirKwotes → Relay tab.</p>
        </div>
        <h3>Supported models</h3>
        <ul>\(models)</ul>
        <h3>Gemini endpoint</h3>
        <div class="card"><pre>http://127.0.0.1:\(port)/v1beta</pre>
        <ul>\(geminiModels)</ul></div>
        <p class="muted">JSON status at <code>/health</code> · models at <code>/v1/models</code> &amp; <code>/v1beta/models</code></p>
        </body></html>
        """
        return .html(200, html)
    }
}
