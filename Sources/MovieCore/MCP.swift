import Foundation
import Network
import Security

/// JSON-RPC layer of the Model Context Protocol (tools only).
@MainActor
final class MCPHandler {
    private let tools: [Tool]
    private let supported = ["2025-06-18", "2025-03-26", "2024-11-05"]

    init(editorProvider: @escaping @MainActor () -> Editor, host: MCPHost) { tools = makeTools(editorProvider: editorProvider, host: host) }

    /// Returns nil when nothing should be sent back (notifications only).
    func handle(_ body: Data) async -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            return encode(error(nil, -32700, "parse error"))
        }
        if let batch = json as? [[String: Any]] {
            var out: [[String: Any]] = []
            for m in batch { if let r = await respond(m) { out.append(r) } }
            return out.isEmpty ? nil : encode(out)
        }
        guard let msg = json as? [String: Any] else { return encode(error(nil, -32600, "invalid request")) }
        return await respond(msg).map(encode)
    }

    private func respond(_ msg: [String: Any]) async -> [String: Any]? {
        let id = msg["id"]
        guard let method = msg["method"] as? String else { return id == nil ? nil : error(id, -32600, "invalid request") }
        let params = msg["params"] as? [String: Any] ?? [:]
        guard id != nil else { return nil }   // notification
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return result(id, ["protocolVersion": supported.contains(asked) ? asked : supported[0],
                               "capabilities": ["tools": ["listChanged": false]],
                               "serverInfo": ["name": "movie-maker", "version": "0.1"],
                               "instructions": "Controls a video editor. Call get_project first. Times are milliseconds. Use get_frame to look at the result."])
        case "ping": return result(id, [:])
        case "tools/list":
            let visible = tools.filter { Privacy.offline ? !Privacy.blocked.contains($0.name) : $0.name != "request_selection" }
            return result(id, ["tools": visible.map(\.definition)])
        case "tools/call":
            guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
                return error(id, -32602, "unknown tool")
            }
            if Privacy.offline, Privacy.blocked.contains(name) {
                return result(id, ["content": [["type": "text", "text": "Offline mode is on: \(name) is disabled so the footage stays private. Use request_selection to let the user mark the important parts."]], "isError": true])
            }
            do {
                let content = try await tool.run(Args(d: params["arguments"] as? [String: Any] ?? [:]))
                return result(id, ["content": content, "isError": false])
            } catch {
                return result(id, ["content": [["type": "text", "text": "\(error)"]], "isError": true])
            }
        default: return error(id, -32601, "method not found")
        }
    }

    private func result(_ id: Any?, _ r: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": r] }
    private func error(_ id: Any?, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }
    private func encode(_ obj: Any) -> Data { (try? JSONSerialization.data(withJSONObject: obj)) ?? Data() }
}

/// Streamable-HTTP MCP endpoint on 127.0.0.1 only, protected by a bearer token.
public final class MCPServer {
    public let token: String
    public private(set) var port: UInt16
    private let handler: MCPHandler
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "mcp-server")

    /// `port` 0 picks a free port.
    @MainActor
    public init(editor: Editor, host: MCPHost, token: String, port: UInt16 = 0) {
        self.handler = MCPHandler(editorProvider: { editor }, host: host)
        self.token = token
        self.port = port
    }

    /// The editor can change while the server runs (a ghost edit works on a copy until you accept it).
    @MainActor
    public init(editorProvider: @escaping @MainActor () -> Editor, host: MCPHost, token: String, port: UInt16 = 0) {
        self.handler = MCPHandler(editorProvider: editorProvider, host: host)
        self.token = token
        self.port = port
    }

    /// Token stored in Application Support so the Claude configuration stays valid across launches.
    public static func loadOrCreateToken() throws -> String {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MovieMaker", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("mcp-token")
        if let t = try? String(contentsOf: file, encoding: .utf8), t.count >= 32 { return t }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw EditError.invalid("no randomness") }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try token.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return token
    }

    public func start() async throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let l = try NWListener(using: params, on: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var done = false
            l.stateUpdateHandler = { state in
                guard !done else { return }
                switch state {
                case .ready: done = true; cont.resume()
                case .failed(let e): done = true; cont.resume(throwing: e)
                default: break
                }
            }
            l.start(queue: queue)
        }
        listener = l
        port = l.port?.rawValue ?? port
    }

    public func stop() { listener?.cancel(); listener = nil }

    // MARK: HTTP

    private struct Request { var method = "", path = "", headers: [String: String] = [:], body = Data() }

    private func serve(_ conn: NWConnection) {
        conn.start(queue: queue)
        var buffer = Data()
        func receive() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, closed, err in
                guard let self else { return }
                if let data { buffer.append(data) }
                if buffer.count > 8 << 20 { self.send(conn, 413, "payload too large"); return }
                if let req = Self.parse(buffer) {
                    Task {
                        let (status, body, extra) = await self.route(req)
                        self.send(conn, status, body, extra)
                    }
                    return
                }
                if closed || err != nil { conn.cancel(); return }
                receive()
            }
        }
        receive()
    }

    private static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let line = head[0].split(separator: " ")
        var req = Request()
        guard line.count >= 2 else { return Request(method: "BAD") }
        req.method = String(line[0]); req.path = String(line[1])
        for h in head.dropFirst() {
            if let i = h.firstIndex(of: ":") {
                req.headers[h[..<i].lowercased()] = h[h.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let length = Int(req.headers["content-length"] ?? "0") ?? 0
        guard data.count >= end.upperBound + length else { return nil }
        req.body = data[end.upperBound..<(end.upperBound + length)]
        return req
    }

    private func route(_ req: Request) async -> (Int, String, [String: String]) {
        let hosts = ["127.0.0.1:\(port)", "localhost:\(port)", "[::1]:\(port)"]
        if let host = req.headers["host"], !hosts.contains(host) { return (403, "forbidden host", [:]) }
        if let origin = req.headers["origin"], !["127.0.0.1", "localhost", "[::1]"].contains(URL(string: origin)?.host ?? "") {
            return (403, "forbidden origin", [:])
        }
        guard req.headers["authorization"] == "Bearer \(token)" else {
            return (401, "unauthorized", ["WWW-Authenticate": "Bearer"])
        }
        guard req.path == "/mcp" else { return (404, "not found", [:]) }
        guard req.method == "POST" else { return (405, "use POST", ["Allow": "POST"]) }
        guard let reply = await handler.handle(req.body) else { return (202, "", [:]) }
        return (200, String(decoding: reply, as: UTF8.self), ["Content-Type": "application/json"])
    }

    private func send(_ conn: NWConnection, _ status: Int, _ body: String, _ extra: [String: String] = [:]) {
        let bytes = Data(body.utf8)
        var head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n"
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        if extra["Content-Type"] == nil { head += "Content-Type: text/plain\r\n" }
        head += "Content-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in conn.cancel() })
    }
}
