import Foundation
import Network

/// Minimal loopback-only HTTP/1.1 server built on Network.framework.
/// Parses requests (Content-Length bodies), dispatches to a handler,
/// and writes a full response then closes (Connection: close).
/// SSE streaming support is added in a later phase.
final class LoopbackHTTPServer {
    struct Request {
        let method: String
        let fullPath: String
        let headers: [String: String]
        let body: Data

        var path: String {
            String(fullPath.prefix(while: { $0 != "?" }))
        }
        var query: [String: String] {
            var out: [String: String] = [:]
            guard let qMark = fullPath.firstIndex(of: "?") else { return out }
            let qs = fullPath[fullPath.index(after: qMark)...]
            for pair in qs.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    let k = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                    let v = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                    out[k] = v
                } else if kv.count == 1 {
                    out[String(kv[0])] = ""
                }
            }
            return out
        }
    }

    struct Response {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data()
        /// When set, the server streams chunks via this producer instead of `body`.
        var streamProducer: ((StreamWriter) async -> Void)?

        static func json(_ status: Int, _ object: Any) -> Response {
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            return Response(status: status,
                            headers: ["Content-Type": "application/json"],
                            body: data)
        }
        static func html(_ status: Int, _ string: String) -> Response {
            Response(status: status,
                     headers: ["Content-Type": "text/html; charset=utf-8"],
                     body: Data(string.utf8))
        }
        /// Streaming response (e.g. SSE). No Content-Length; body delimited by close.
        static func stream(_ status: Int, headers: [String: String],
                            producer: @escaping (StreamWriter) async -> Void) -> Response {
            var r = Response(status: status, headers: headers)
            r.streamProducer = producer
            return r
        }
    }

    /// Writes chunks to a streaming response connection.
    final class StreamWriter {
        private let connection: NWConnection
        init(_ connection: NWConnection) { self.connection = connection }
        @MainActor func send(_ data: Data) async {
            await withCheckedContinuation { cont in
                connection.send(content: data, completion: .contentProcessed { _ in cont.resume() })
            }
        }
    }

    typealias Handler = (Request, @escaping (Response) -> Void) -> Void

    private let port: NWEndpoint.Port
    private let handler: Handler
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "ai.airkwotes.http", qos: .userInitiated)
    private(set) var isRunning = false

    init(port: UInt16, handler: @escaping Handler) throws {
        guard let p = NWEndpoint.Port(rawValue: port) else { throw HTTPServerError.invalidPort }
        self.port = p
        self.handler = handler
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Bind to loopback only (host + port) — never expose on a public interface.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)

        // Port comes from requiredLocalEndpoint; do NOT also pass `on:`.
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.isRunning = true
            case .failed: self?.isRunning = false
            case .cancelled: self?.isRunning = false
            default: break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        isRunning = false
    }

    // MARK: - Connection handling
    private func handle(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.queue.async {
                    self?.connections.removeValue(forKey: id)
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel(); return
            }
            var buf = buffer
            if let data { buf.append(data) }

            if let parsed = self.parseHeaders(buf) {
                let needed = parsed.headerLength + parsed.contentLength
                if buf.count >= needed {
                    let body = parsed.contentLength > 0
                        ? buf.subdata(in: parsed.headerLength..<needed)
                        : Data()
                    let request = Request(method: parsed.method,
                                          fullPath: parsed.fullPath,
                                          headers: parsed.headers,
                                          body: body)
                    self.dispatch(request, connection)
                    return
                }
            }
            if isComplete {
                connection.cancel()
            } else {
                self.read(connection, buffer: buf)
            }
        }
    }

    private struct ParsedHeaders {
        let method: String
        let fullPath: String
        let headers: [String: String]
        let headerLength: Int
        let contentLength: Int
    }

    private func parseHeaders(_ data: Data) -> ParsedHeaders? {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headString = String(data: data.subdata(in: 0..<sep.lowerBound), encoding: .utf8) ?? ""
        let lines = headString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let fullPath = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let c = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<c]).trimmingCharacters(in: .whitespaces).lowercased()
            let val = String(line[line.index(after: c)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = val
        }
        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        return ParsedHeaders(method: method, fullPath: fullPath, headers: headers,
                             headerLength: sep.upperBound, contentLength: contentLength)
    }

    private func dispatch(_ request: Request, _ connection: NWConnection) {
        handler(request) { [weak self] response in
            self?.write(response, to: connection)
        }
    }

    private func write(_ response: Response, to connection: NWConnection) {
        if let producer = response.streamProducer {
            var head = "HTTP/1.1 \(response.status) \(Self.reason(for: response.status))\r\n"
            for (k, v) in response.headers where k.lowercased() != "content-length" {
                head += "\(k): \(v)\r\n"
            }
            head += "Cache-Control: no-cache\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in
                Task { await producer(StreamWriter(connection)); connection.cancel() }
            })
            return
        }
        var head = "HTTP/1.1 \(response.status) \(Self.reason(for: response.status))\r\n"
        for (k, v) in response.headers where k.lowercased() != "content-length" {
            head += "\(k): \(v)\r\n"
        }
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }
}

enum HTTPServerError: Error { case invalidPort }
