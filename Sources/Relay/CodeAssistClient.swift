import Foundation

/// Talks to Google's Code Assist backend (cloudcode-pa.googleapis.com), the
/// upstream a Gemini-CLI subscription actually uses. `generativelanguage` does
/// NOT accept the subscription OAuth scopes, so this internal protocol is required.
///
/// Protocol: loadCodeAssist → resolve project → generateContent with a wrapped
/// Vertex request → unwrap the `{response:{…}}` envelope back to standard Gemini.
enum CodeAssistClient {
    static let endpoint = "https://cloudcode-pa.googleapis.com/v1internal"

    // MARK: - Project resolution
    /// Resolves the user's cloudaicompanion project. Prefers ~/.gemini/projects.json
    /// (what gemini-cli uses for the current dir), falls back to loadCodeAssist.
    static func resolveProject(credential: GeminiCredential) async -> String? {
        if let fromFile = readProjectFromFile() { return fromFile }
        let body = [
            "cloudaicompanionProject": "cloudshell-gca",
            "metadata": ["ideType": "IDE_UNSPECIFIED",
                         "platform": "PLATFORM_UNSPECIFIED"] as [String: Any]
        ] as [String: Any]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let resp = try? await post(path: "loadCodeAssist", credential: credential, body: data) else {
            return nil
        }
        if let obj = try? JSONSerialization.jsonObject(with: resp) as? [String: Any],
           let project = obj["cloudaicompanionProject"] as? String, !project.isEmpty {
            return project
        }
        return nil
    }

    private static func readProjectFromFile() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/projects.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [String: String] else { return nil }
        // Prefer the entry matching the home directory, else the first.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return projects[home] ?? projects.values.first
    }

    // MARK: - Non-streaming
    /// Returns (status, body). On success, body is the unwrapped standard Gemini
    /// response JSON; on upstream error, the raw error JSON is passed through.
    static func generateContent(model: String, body: Data,
                                credential: GeminiCredential, project: String?) async -> (Int, Data) {
        guard let wrapped = wrapRequest(model: model, project: project, body: body) else {
            return (400, errorJSON("Could not encode request."))
        }
        do {
            let (data, resp) = try await postRaw(path: "generateContent",
                                                 credential: credential, body: wrapped)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 502
            if (200..<300).contains(status) {
                return (200, unwrapResponse(data))
            }
            return (status, data)
        } catch {
            return (502, errorJSON("Upstream error: \(error.localizedDescription)"))
        }
    }

    // MARK: - Streaming (SSE)
    /// Yields `data: {…}\n\n` frames with the Code Assist envelope unwrapped to
    /// standard Gemini partial responses.
    static func streamGenerateContent(model: String, body: Data, credential: GeminiCredential,
                                      project: String?) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let wrapped = wrapRequest(model: model, project: project, body: body) else {
                    continuation.finish(); return
                }
                guard let url = URL(string: "\(endpoint):streamGenerateContent?alt=sse") else {
                    continuation.finish(); return
                }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
                req.httpBody = wrapped
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 200
                    if status >= 300 {
                        // Collect body and forward as an error frame.
                        var collected = ""
                        for try await line in bytes.lines { collected += line }
                        let payload = collected.isEmpty ? "{}" : collected
                        continuation.yield(Data("data: ".utf8) + Data(payload.utf8) + Data("\n\n".utf8))
                        continuation.finish(); return
                    }
                    for try await line in bytes.lines where line.hasPrefix("data: ") {
                        let raw = String(line.dropFirst(6))
                        guard let d = raw.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let inner = obj["response"] else { continue }
                        let out = (try? JSONSerialization.data(withJSONObject: inner)) ?? d
                        continuation.yield(Data("data: ".utf8) + out + Data("\n\n".utf8))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Envelope helpers
    /// Standard Gemini request body → Code Assist `{model, project, user_prompt_id, request:{…}}`.
    private static func wrapRequest(model: String, project: String?, body: Data) -> Data? {
        var inner = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        inner["session_id"] = UUID().uuidString
        var wrapped: [String: Any] = [
            "model": model,
            "user_prompt_id": UUID().uuidString,
            "request": inner
        ]
        if let project, !project.isEmpty { wrapped["project"] = project }
        return try? JSONSerialization.data(withJSONObject: wrapped)
    }

    /// Code Assist `{traceId, response:{…}}` → standard Gemini response `{…}`.
    private static func unwrapResponse(_ data: Data) -> Data {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = obj["response"] else { return data }
        return (try? JSONSerialization.data(withJSONObject: inner)) ?? data
    }

    private static func postRaw(path: String, credential: GeminiCredential, body: Data) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: URL(string: "\(endpoint):\(path)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        return try await URLSession.shared.data(for: req)
    }

    private static func post(path: String, credential: GeminiCredential, body: Data) async throws -> Data {
        let (data, _) = try await postRaw(path: path, credential: credential, body: body)
        return data
    }

    private static func errorJSON(_ message: String) -> Data {
        let obj: [String: Any] = ["error": ["code": 500, "message": message, "status": "INTERNAL"]]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }
}

enum CodeAssistJSON {
    static func error(_ message: String) -> Data {
        let obj: [String: Any] = ["error": ["code": 401, "message": message, "status": "UNAUTHENTICATED"]]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }
}
