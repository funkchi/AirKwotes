import Foundation

enum HTTPError: Error, LocalizedError {
    case status(Int, String)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .status(let code, let body): return "HTTP \(code). \(body)"
        case .transport(let e): return e.localizedDescription
        case .decoding(let e): return "Decoding: \(e.localizedDescription)"
        }
    }
}

struct APIClient {
    static let shared = APIClient()
    let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    @discardableResult
    func getBearer(_ urlString: String,
                   token: String,
                   extraHeaders: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        try await getAuthorized(urlString,
                                authorization: "Bearer \(token)",
                                extraHeaders: extraHeaders)
    }

    @discardableResult
    func getAuthorized(_ urlString: String,
                       authorization: String,
                       extraHeaders: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else { throw HTTPError.status(0, "Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        return try await send(req)
    }

    @discardableResult
    func getQuery(_ urlString: String,
                  query: [String: String]) async throws -> (Data, HTTPURLResponse) {
        guard var comps = URLComponents(string: urlString) else { throw HTTPError.status(0, "Bad URL") }
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw HTTPError.status(0, "Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return try await send(req)
    }

    @discardableResult
    func postJSON(_ urlString: String,
                  token: String,
                  body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else { throw HTTPError.status(0, "Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw HTTPError.status(0, "No response")
            }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                throw HTTPError.status(http.statusCode, String(body))
            }
            return (data, http)
        } catch let e as HTTPError {
            throw e
        } catch {
            throw HTTPError.transport(error)
        }
    }
}

extension Data {
    func asJSON() -> Any? {
        return try? JSONSerialization.jsonObject(with: self, options: .fragmentsAllowed)
    }

    func extract(_ path: String) -> JSONVal? {
        guard let root = asJSON() else { return nil }
        if let raw = JSONPath.navigate(root, path: path) { return JSONVal(raw: raw) }
        return nil
    }
}

struct JSONVal {
    let raw: Any
    var asDouble: Double? {
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s) }
        return nil
    }
    var asString: String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }
}

enum JSONPath {
    static func navigate(_ root: Any, path: String) -> Any? {
        var current: Any? = root
        for part in path.split(separator: ".").map(String.init) {
            guard let c = current else { return nil }
            if let arr = c as? [Any], part == "first", let f = arr.first { current = f; continue }
            if let arr = c as? [Any], part == "last", let l = arr.last { current = l; continue }
            if let idx = Int(part), let arr = c as? [Any], arr.indices.contains(idx) {
                current = arr[idx]; continue
            }
            if let dict = c as? [String: Any], let v = dict[part] { current = v; continue }
            return nil
        }
        return current
    }
}
