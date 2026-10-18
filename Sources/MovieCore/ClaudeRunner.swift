import Foundation

public enum ClaudeEvent: Equatable {
    case session(String)
    case textDelta(String)
    case toolUse(id: String, name: String, input: String)
    case toolResult(id: String, isError: Bool)
    case finished(isError: Bool, result: String, cost: Double?)
    case failed(String)

    /// One line of `claude --output-format stream-json` output.
    public static func parse(_ line: String) -> [ClaudeEvent] {
        guard let data = line.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        switch json["type"] as? String {
        case "system":
            if json["subtype"] as? String == "init", let id = json["session_id"] as? String { return [.session(id)] }
        case "stream_event":
            if let event = json["event"] as? [String: Any], event["type"] as? String == "content_block_delta",
               let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String { return [.textDelta(text)] }
        case "assistant":
            let blocks = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return blocks.compactMap { b in
                guard b["type"] as? String == "tool_use", let id = b["id"] as? String, let name = b["name"] as? String else { return nil }
                let input = (b["input"]).flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
                return .toolUse(id: id, name: name, input: input.map { String(decoding: $0, as: UTF8.self) } ?? "{}")
            }
        case "user":
            let blocks = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return blocks.compactMap { b in
                guard b["type"] as? String == "tool_result", let id = b["tool_use_id"] as? String else { return nil }
                return .toolResult(id: id, isError: b["is_error"] as? Bool ?? false)
            }
        case "result":
            return [.finished(isError: json["is_error"] as? Bool ?? false, result: json["result"] as? String ?? "",
                              cost: json["total_cost_usd"] as? Double)]
        default: break
        }
        return []
    }
}

/// Runs the user's installed `claude` command for one chat turn, wired to this editor's MCP server.
/// Uses the user's own Claude login (no API key handled here) and only allows the editor's tools.
public enum ClaudeRunner {
    public static let serverName = "movie-maker"

    /// Base instructions plus the list of director skills (full text is fetched on demand with get_skill).
    public static func systemPrompt() -> String {
        let all = Skills.all()
        let skills = all.filter { !$0.fromAgent }.map { "- \($0.name): \($0.summary)" }.joined(separator: "\n")
        let own = all.filter(\.fromAgent).map { "- \($0.name): \($0.summary)" }.joined(separator: "\n")
        let ownBlock = own.isEmpty ? "" : "\n\nSkills from the user's own agent. Read one with get_skill when it clearly fits the request (writing, research, design); ignore the rest:\n\(own)"
        return """
        You are the director's assistant built into Lumacut, a video editor. You control it only through the movie-maker MCP tools.
        For any creative request (making or reshaping a film, pacing, music, titles, look, effects) first read the skill director-brief with get_skill, \
        then the skills it routes you to. You are a DIRECTOR: look at the clips (inspect_asset, watch_asset, transcribe_asset), choose the moments, vary the cut lengths, \
        pick joins, sound and effects on purpose, build the film with build_edit, then review it with watch_timeline. Never use auto_movie for creative requests. Do NOT add sound effects (whooshes, hits) unless the user asks for them: films get music and the original sound only. Look at footage (inspect_asset, watch_asset) before judging it. Call get_project before editing and \
        use get_frame to check visual results. Times are milliseconds. Prefer small edits (the user can undo), say briefly what you changed, \
        mention assumptions, and never invent file paths.

        Be imaginative but restrained. Before planning a creative film read creative-thinking and creative-toolbox, then call suggest_treatments (obey at least one constraint card): choose a specific direction (not the same arc every time), use few tools with intent, stay inside the spice budget, and leave out any effect, join, overlay or title that does not add something the plain cut lacks. Never repeat the look or structure of the last film in this project unless asked.

        Plain is the default. Effects, overlays and joins are never decoration: do NOT add cinemaBars, grain or glow unless the treatment you chose calls for them, and never all three. build_edit refuses plans that skip suggest_treatments, stack the usual tricks, or repeat the previous film's look, so plan within the budget from the start.\(Privacy.offline ? "\n\n" + Privacy.offlinePrompt : "")\(ScriptMode.level == .off ? "" : "\n\n" + ScriptMode.prompt())
        
        Folders: the user can open folders in the Files tab. browse_folder lists them (names, lengths, sizes only); tell the user what a folder contains and what looks usable, and import_media only the files that are needed.

        Two kinds of request. A SPECIFIC change (add this transition, this effect, this template, a title, trim a clip, set the volume) you simply do with the matching tool: no workflow, no questions. A CREATIVE job (make a film, a reel, improve the pacing) is where you direct. If the message starts with [GUIDED EDIT], read the skill guided-edit and interview the user with ask_user. If it starts with [GHOST EDIT], you are working on a COPY of the timeline that the user will accept or reject: change only the part they named.

        Director skills (read with get_skill):
        \(skills)\(ownBlock)
        """
    }

    /// Where the CLI usually lives; GUI apps don't inherit the shell's PATH.
    public static func locate() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = ["\(home)/.local/bin/claude", "/usr/local/bin/claude", "/opt/homebrew/bin/claude", "\(home)/.claude/local/claude"]
        if let found = shellLookup() { candidates.insert(found, at: 0) }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    private static func shellLookup() -> String? {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = ["-lic", "command -v claude"]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return out.split(separator: "\n").last.map(String.init)
    }

    /// Prompt first: the flags after it include variadic ones that would swallow a trailing prompt.
    static func arguments(prompt: String, sessionID: String?, mcpConfig: URL) -> [String] {
        var args = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                    "--tools", "",                       // no file or shell access: only the editor's tools
                    "--strict-mcp-config", "--mcp-config", mcpConfig.path,
                    "--allowedTools", "mcp__\(serverName)", "--permission-mode", "dontAsk",
                    "--setting-sources", "", "--disable-slash-commands",
                    "--append-system-prompt", systemPrompt()]
        if let sessionID { args += ["--resume", sessionID] }
        return args
    }

    public static func workingDirectory() throws -> URL {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MovieMaker/assistant", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Config file with the bearer token, readable only by the user.
    static func writeMCPConfig(port: UInt16, token: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("mcp.json")
        let config: [String: Any] = ["mcpServers": [serverName: ["type": "http", "url": "http://127.0.0.1:\(port)/mcp",
                                                                   "headers": ["Authorization": "Bearer \(token)"]]]]
        try JSONSerialization.data(withJSONObject: config, options: [.withoutEscapingSlashes]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock(); private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }

    /// Events for one turn. Pass the `.session` id of an earlier turn to continue that conversation.
    public static func run(prompt: String, sessionID: String?, port: UInt16, token: String,
                           executable: URL? = nil, configDir: String? = nil, kind: AgentKind = .claude) -> (events: AsyncStream<ClaudeEvent>, cancel: @Sendable () -> Void) {
        if kind != .claude, let executable { return runOther(kind, executable: executable, prompt: prompt, port: port, token: token) }
        let process = Process()
        let cancelled = CancelFlag()
        let stream = AsyncStream<ClaudeEvent> { continuation in
            Task.detached {
                defer { continuation.finish() }
                guard let exe = executable ?? locate() else {
                    continuation.yield(.failed("Claude Code isn't installed (looked in ~/.local/bin, /usr/local/bin, /opt/homebrew/bin). Install it from claude.com/claude-code, then try again."))
                    return
                }
                do {
                    let dir = try workingDirectory()
                    let config = try writeMCPConfig(port: port, token: token, in: dir)
                    process.executableURL = exe
                    process.arguments = arguments(prompt: prompt, sessionID: sessionID, mcpConfig: config)
                    process.currentDirectoryURL = dir
                    var env = ProcessInfo.processInfo.environment
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    env["PATH"] = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", env["PATH"] ?? ""].joined(separator: ":")
                    if let configDir { env["CLAUDE_CONFIG_DIR"] = configDir }
                    process.environment = env
                    let out = Pipe(), err = Pipe()
                    process.standardOutput = out; process.standardError = err; process.standardInput = FileHandle.nullDevice
                    try process.run()
                    let errors = Task.detached { (try? err.fileHandleForReading.readToEnd()) ?? Data() }
                    var finished = false
                    for try await line in out.fileHandleForReading.bytes.lines {
                        for event in ClaudeEvent.parse(line) {
                            if case .finished = event { finished = true }
                            continuation.yield(event)
                        }
                    }
                    process.waitUntilExit()
                    if !finished && !cancelled.isSet {
                        let tail = String(decoding: await errors.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).suffix(600)
                        continuation.yield(.failed(tail.isEmpty ? "Claude stopped unexpectedly (exit status \(process.terminationStatus))." : String(tail)))
                    }
                } catch { continuation.yield(.failed("\(error)")) }
            }
        }
        return (stream, { cancelled.set(); if process.isRunning { process.terminate() } })
    }

    // MARK: Other agents (experimental)

    /// Codex and OpenCode, wired to the editor's MCP server through their documented options. Unlike Claude they cannot be limited to
    /// the editor's tools, so the app refuses to use them in offline mode.
    static func runOther(_ kind: AgentKind, executable: URL, prompt: String, port: UInt16, token: String) -> (events: AsyncStream<ClaudeEvent>, cancel: @Sendable () -> Void) {
        let process = Process(), cancelled = CancelFlag()
        let url = "http://127.0.0.1:\(port)/mcp"
        let full = systemPrompt() + "\n\nUse only the \(serverName) MCP tools to edit. Do not run shell commands or touch files.\n\nUser request:\n" + prompt
        let stream = AsyncStream<ClaudeEvent> { continuation in
            Task.detached {
                defer { continuation.finish() }
                do {
                    let dir = try workingDirectory()
                    process.executableURL = executable
                    process.currentDirectoryURL = dir
                    var env = ProcessInfo.processInfo.environment
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    env["PATH"] = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", executable.deletingLastPathComponent().path, env["PATH"] ?? ""].joined(separator: ":")
                    switch kind {
                    case .codex:
                        env["LUMACUT_MCP_TOKEN"] = token
                        process.arguments = ["exec", "--json", "--skip-git-repo-check", "-s", "read-only",
                                             "-c", "mcp_servers.\(serverName).url=\"\(url)\"", "-c", "mcp_servers.\(serverName).bearer_token_env_var=\"LUMACUT_MCP_TOKEN\"", full]
                    default:
                        let config: [String: Any] = ["mcp": [serverName: ["type": "remote", "url": url, "headers": ["Authorization": "Bearer \(token)"], "enabled": true]]]
                        env["OPENCODE_CONFIG_CONTENT"] = (try? JSONSerialization.data(withJSONObject: config)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                        process.arguments = ["run", full]
                    }
                    process.environment = env
                    let out = Pipe(), err = Pipe()
                    process.standardOutput = out; process.standardError = err; process.standardInput = FileHandle.nullDevice
                    try process.run()
                    let errors = Task.detached { (try? err.fileHandleForReading.readToEnd()) ?? Data() }
                    var finished = false
                    for try await line in out.fileHandleForReading.bytes.lines {
                        for event in kind == .codex ? parseCodex(line) : [.textDelta(stripANSI(line) + "\n")] {
                            if case .finished = event { finished = true }
                            if case .failed = event { finished = true }
                            continuation.yield(event)
                        }
                    }
                    process.waitUntilExit()
                    if !finished && !cancelled.isSet {
                        if process.terminationStatus == 0 { continuation.yield(.finished(isError: false, result: "", cost: nil)) }
                        else {
                            let tail = String(decoding: await errors.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).suffix(600)
                            continuation.yield(.failed(tail.isEmpty ? "\(kind.title) stopped unexpectedly (exit status \(process.terminationStatus))." : String(tail)))
                        }
                    }
                } catch { continuation.yield(.failed("\(error)")) }
            }
        }
        return (stream, { cancelled.set(); if process.isRunning { process.terminate() } })
    }

    static func stripANSI(_ s: String) -> String { s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression) }

    /// One line of `codex exec --json`.
    public static func parseCodex(_ line: String) -> [ClaudeEvent] {
        guard let data = line.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let item = json["item"] as? [String: Any]
        switch json["type"] as? String {
        case "thread.started": return (json["thread_id"] as? String).map { [.session($0)] } ?? []
        case "item.started", "item.completed":
            guard let item, let id = item["id"] as? String else { return [] }
            let done = json["type"] as? String == "item.completed"
            switch item["type"] as? String {
            case "agent_message": return done ? [.textDelta((item["text"] as? String ?? "") + "\n\n")] : []
            case "mcp_tool_call":
                if !done {
                    let input = (item["arguments"]).flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
                    return [.toolUse(id: id, name: "mcp__\(serverName)__\(item["tool"] as? String ?? "tool")", input: input.map { String(decoding: $0, as: UTF8.self) } ?? "{}")]
                }
                return [.toolResult(id: id, isError: item["status"] as? String == "failed" || item["error"] != nil)]
            default: return []
            }
        case "turn.completed": return [.finished(isError: false, result: "", cost: nil)]
        case "turn.failed":
            let raw = (json["error"] as? [String: Any])?["message"] as? String ?? "Codex failed."
            if let d = raw.data(using: .utf8), let inner = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let m = (inner["error"] as? [String: Any])?["message"] as? String { return [.failed(m)] }
            return [.failed(raw)]
        default: return []
        }
    }
}
