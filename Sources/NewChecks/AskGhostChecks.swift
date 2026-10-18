import Foundation
import MovieCore

@MainActor
func runAskGhostChecks(_ f: Fixtures) async throws {
    // Treatments: every ingredient exists, picks differ, repeats are avoided, mood steers
    check(Treatments.all.allSatisfy { Look.preset($0.look) != nil && $0.transitions.count <= 2 && $0.effects.count <= 2 }, "treatments use real looks, few joins and effects")
    let first = Treatments.suggest(mood: nil, count: 3), second = Treatments.suggest(mood: nil, count: 3)
    check(first.count == 3 && Set(first.map(\.look)).count == 3, "treatment picks have different looks")
    check(Set(first.map(\.name)).isDisjoint(with: second.map(\.name)), "treatments are not repeated back to back")
    check(Treatments.suggest(mood: "noir mystery", count: 3).contains { $0.name == "Noir" }, "mood steers treatments")
    check(Skills.get("creative-toolbox")?.body.contains("Spice budget") == true && ClaudeRunner.systemPrompt().contains("suggest_treatments"), "creative toolbox skill is routed")
    check(Skills.get("creative-thinking")?.body.contains("Name the default first") == true && Treatments.drawConstraints(2).count == 2 && Set(Treatments.constraints).count == Treatments.constraints.count, "creative-thinking skill and constraint cards")
    check(Skills.get("director-brief")?.body.contains("creative-thinking") == true && ClaudeRunner.systemPrompt().contains("constraint card"), "creative-thinking is routed")
    // Codex JSONL maps to the same events the chat already shows
    let codex = ["{\"type\":\"thread.started\",\"thread_id\":\"t1\"}", "{\"type\":\"item.started\",\"item\":{\"id\":\"i1\",\"type\":\"mcp_tool_call\",\"server\":\"movie-maker\",\"tool\":\"get_project\",\"arguments\":{}}}",
                 "{\"type\":\"item.completed\",\"item\":{\"id\":\"i1\",\"type\":\"mcp_tool_call\",\"status\":\"completed\"}}", "{\"type\":\"item.completed\",\"item\":{\"id\":\"i2\",\"type\":\"agent_message\",\"text\":\"Done\"}}",
                 "{\"type\":\"turn.completed\"}"].flatMap(ClaudeRunner.parseCodex)
    check(codex.count == 5 && codex[0] == .session("t1") && codex[1] == .toolUse(id: "i1", name: "mcp__movie-maker__get_project", input: "{}") && codex[2] == .toolResult(id: "i1", isError: false) && codex[3] == .textDelta("Done\n\n"), "codex events parsed")
    check(AgentProfile(executable: "/x/codex", kind: .codex).kind == .codex && AgentProfile(executable: "/x/claude").kind == .claude, "agent kinds")
    // Variety guard: refuses plans that skip the workflow or stack the usual tricks
    CreativeGuard.enabled = true; CreativeGuard.reset()
    func plan(_ effects: [[String]], joins: [String] = [], n: Int = 4) -> [[String: Any]] {
        (0..<n).map { i in ["start_ms": 0, "end_ms": 3_000, "transition": i == 0 ? "none" : (joins.isEmpty ? "none" : joins[i % joins.count]),
                            "effects": (i < effects.count ? effects[i] : []).map { ["type": $0] }] as [String: Any] }
    }
    check(CreativeGuard.check(cuts: plan([]), overlays: [])?.contains("suggest_treatments") == true, "guard asks for a treatment first")
    CreativeGuard.noteTreatmentSuggested()
    check(CreativeGuard.check(cuts: plan([["cinemaBars", "grain", "glow"]]), overlays: [])?.contains("default look") == true, "guard refuses the cinemaBars+grain+glow default")
    check(CreativeGuard.check(cuts: plan([["vhs"], ["glitch"], ["posterize"]]), overlays: [])?.contains("at most 2") == true, "guard limits effect types")
    check(CreativeGuard.check(cuts: plan([], joins: ["crossfade"], n: 6), overlays: [])?.contains("Crossfades") == true, "guard limits crossfades")
    check(CreativeGuard.check(cuts: plan([["vhs"]]), overlays: [["kind": "confetti"], ["kind": "snow"]])?.contains("overlays") == true, "guard limits overlays")
    check(CreativeGuard.check(cuts: plan([["vhs"]]), overlays: [["kind": "dust"]]) == nil, "a restrained plan passes")
    check(CreativeGuard.check(cuts: plan([["vhs"]]), overlays: []) != nil, "a new film needs a fresh treatment")
    CreativeGuard.noteTreatmentSuggested()
    check(CreativeGuard.check(cuts: plan([["vhs"]]), overlays: [])?.contains("previous film") == true, "guard refuses repeating the last film's look")
    CreativeGuard.enabled = false

    // Agent skills: read from a config folder, listed after ours, readable through Skills.get
    let cfg = FileManager.default.temporaryDirectory.appendingPathComponent("agentcfg-\(UUID().uuidString)")
    let skillDir = cfg.appendingPathComponent("skills/copywriter")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    try "---\nname: copywriter\ndescription: Writes punchy captions\n---\nWrite short.".write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    let found = Agents.skills(of: AgentProfile(executable: "/bin/echo", configDir: cfg.path))
    check(found.map(\.name) == ["copywriter"] && found[0].summary == "Writes punchy captions" && found[0].body.contains("Write short."), "agent skills parsed")
    Skills.agentSkills = found
    check(Skills.get("copywriter")?.fromAgent == true && ClaudeRunner.systemPrompt().contains("copywriter"), "agent skills offered to the assistant")
    Skills.agentSkills = []
    try? FileManager.default.removeItem(at: cfg)

    // ask_user waits for the host's answer and passes the options on
    var asked: [(String, [String], Bool)] = [], lastOptions: [AskOption] = []
    let editor = Editor()
    let server = MCPServer(editor: editor, host: MCPHost(importMedia: { url in
        let a = try await Asset.load(url: url); try editor.apply(.addAsset(a)); return a
    }, playhead: { 0 }, ask: { q, options, allowText in asked.append((q, options.map(\.label), allowText)); lastOptions = options; return options.first?.label ?? "free text" }), token: "ask")
    try await server.start(); defer { server.stop() }
    func call(_ tool: String, _ args: [String: Any]) async throws -> String {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/mcp")!); req.httpMethod = "POST"
        req.setValue("Bearer ask", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": args]])
        let (data, _) = try await URLSession.shared.data(for: req)
        let content = ((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        return (content?.first?["text"] as? String) ?? ""
    }
    let answer = try await call("ask_user", ["question": "Should I analyse all 3 clips?", "options": ["Yes, all (recommended)", "No"], "allow_text": false])
    check(answer.contains("Yes, all (recommended)") && asked.count == 1 && asked[0].1.count == 2 && asked[0].2 == false, "ask_user returns the answer: \(answer)")
    _ = try await call("ask_user", ["question": "Which look?", "options": [["label": "Warm", "info": "Golden tones; I will grade every clip warm."], "Plain"]])
    check(lastOptions == [AskOption("Warm", info: "Golden tones; I will grade every clip warm."), AskOption("Plain")], "options carry their explanations")
    check(try await call("ask_user", ["question": "Free question?"]).contains("free text") && asked[2].2 == true, "options are optional, typing is allowed by default")
    check(try await call("get_skill", ["name": "guided-edit"]).contains("ONE question per call"), "the guided-edit skill is served")

    // Folders: browse_folder only sees opened folders and reports media facts from headers
    let box = FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: box.appendingPathComponent("trip"), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: f.red.url, to: box.appendingPathComponent("trip/red.mp4"))
    try "x".write(to: box.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    let outside = FileManager.default.temporaryDirectory
    let wsServer = MCPServer(editor: Editor(), host: MCPHost(importMedia: { _ in throw EditError.notFound }, playhead: { 0 }, workspaceRoots: { [box] }), token: "ws")
    try await wsServer.start(); defer { wsServer.stop() }
    func wsCall(_ args: [String: Any]) async throws -> (Bool, String) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(wsServer.port)/mcp")!); req.httpMethod = "POST"
        req.setValue("Bearer ws", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "browse_folder", "arguments": args]])
        let (data, _) = try await URLSession.shared.data(for: req)
        let r = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["result"] as? [String: Any]
        return (r?["isError"] as? Bool ?? true, ((r?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "")
    }
    let roots = try await wsCall([:])
    check(!roots.0 && roots.1.contains(box.path), "browse_folder lists the opened folders")
    let deep = try await wsCall(["path": box.path, "depth": 2])
    check(!deep.0 && deep.1.contains("[folder] trip/  (1 media file)") && deep.1.contains("[video] red.mp4") && deep.1.contains("x") && deep.1.contains("1 video"), "browse_folder describes media: \(deep.1)")
    check(try await wsCall(["path": outside.path]).0, "browse_folder refuses folders that are not open")
    check(Workspace.isInside(box.appendingPathComponent("trip"), roots: [box]) && !Workspace.isInside(URL(fileURLWithPath: box.path + "-other"), roots: [box]), "path containment is exact")
    try? FileManager.default.removeItem(at: box)

    // Script modes: build_edit waits for an approved script; the script renders with exact ranges
    CreativeGuard.enabled = true; CreativeGuard.reset(); CreativeGuard.noteTreatmentSuggested()
    ScriptMode.level = .medium; ScriptMode.approved = false
    check(CreativeGuard.check(cuts: [["start_ms": 0, "end_ms": 3_000]], overlays: [])?.contains("propose_script") == true, "script mode blocks build_edit until approved")
    let approvedReply = try await call("propose_script", ["title": "Day out", "logline": "A day", "beats": [["title": "Hook", "seconds": 2, "join": "cut", "text": "Hi"]]])
    check(approvedReply.hasPrefix("APPROVED") && ScriptMode.approved, "propose_script approval is recorded: \(approvedReply)")
    check(CreativeGuard.check(cuts: [["start_ms": 0, "end_ms": 3_000]], overlays: [])?.contains("propose_script") != true, "approved script lets the plan through")
    check(CreativeGuard.check(cuts: [["start_ms": 0, "end_ms": 3_000]], overlays: [])?.contains("propose_script") == true || ScriptMode.approved == false, "approval is spent by a build")
    ScriptMode.level = .off; CreativeGuard.enabled = false
    let id = UUID()
    let rendered = ScriptDraft(title: "T", logline: "L", beats: [ScriptBeat(title: "A", assetID: id, startMs: 1_000, endMs: 4_000, seconds: 3, join: "crossfade", sound: "keep", text: "Hello")]).render { _ in "clip.mp4" }
    check(rendered.contains("asset_id=\(id.uuidString) source 1000-4000 ms") && rendered.contains("join: crossfade") && rendered.contains("text: \"Hello\""), "script renders exact ranges")
    check(ScriptLevel.allCases.count == 4 && ClaudeRunner.systemPrompt().contains("browse_folder"), "script levels and folder hint")


    // Offline mode hides and refuses the tools that would show footage to Claude
    Privacy.offline = true
    check(ClaudeRunner.systemPrompt().contains("OFFLINE MODE IS ON"), "offline prompt")
    func listed() async throws -> [String] {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/mcp")!); req.httpMethod = "POST"
        req.setValue("Bearer ask", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"])
        let (data, _) = try await URLSession.shared.data(for: req)
        return ((((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["result"] as? [String: Any])?["tools"]) as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
    }
    let offlineTools = try await listed()
    check(Privacy.blocked.isDisjoint(with: offlineTools) && offlineTools.contains("request_selection") && offlineTools.contains("build_edit"), "offline: analysis tools hidden, request_selection offered")
    check(try await call("get_frame", ["time_ms": 0]).contains("Offline mode"), "offline: get_frame refused")
    check(try await call("request_selection", ["reason": "Mark the best parts"]).contains("cannot show the range picker"), "request_selection reaches the host")
    Privacy.offline = false
    let onlineTools = try await listed()
    check(onlineTools.contains("watch_asset") && !onlineTools.contains("request_selection"), "online: normal tool set")


    // the editor can be swapped under a running server (ghost edits)
    var current = Editor(); let main = current, ghost = Editor()
    let routed = MCPServer(editorProvider: { current }, host: MCPHost(importMedia: { _ in throw EditError.notFound }, playhead: { 0 }), token: "ghost")
    try await routed.start(); defer { routed.stop() }
    func routedCall(_ tool: String, _ args: [String: Any]) async throws {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(routed.port)/mcp")!); req.httpMethod = "POST"
        req.setValue("Bearer ghost", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": args]])
        _ = try await URLSession.shared.data(for: req)
    }
    try await routedCall("add_track", ["kind": "video"])
    current = ghost
    try await routedCall("add_track", ["kind": "audio"]); try await routedCall("add_track", ["kind": "text"])
    check(main.project.tracks.count == 1 && ghost.project.tracks.count == 2, "tools follow the current editor: \(main.project.tracks.count) / \(ghost.project.tracks.count)")

    // accepting a ghost is one undoable edit
    try main.replaceAsEdit(with: ghost.project)
    check(main.project == ghost.project && main.canUndo, "the ghost replaces the project")
    main.undo()
    check(main.project.tracks.count == 1, "accepting a ghost can be undone in one step")
}
