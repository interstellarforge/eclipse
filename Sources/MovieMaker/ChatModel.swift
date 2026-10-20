import Foundation
import MovieCore

struct ChatMessage: Identifiable, Codable {
    enum Role: String, Codable { case user, assistant, tool, notice }
    var id = UUID()
    var role: Role
    var text: String
    var toolID: String?
    var done = true       // tools: result received; assistant: finished streaming
    var failed = false
}

struct StoredChat: Codable {
    var id: UUID
    var title: String
    var created: Date
    var updated: Date
    var sessionID: String?
    var messages: [ChatMessage]
}

struct ChatSummary: Identifiable {
    let id: UUID
    let title: String
    let updated: Date
}

/// Conversations kept as one JSON file each in Application Support/MovieMaker/chats.
enum ChatStore {
    private static var folder: URL? {
        let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MovieMaker/chats", isDirectory: true)
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    private static func file(_ id: UUID) -> URL? { folder?.appendingPathComponent("\(id.uuidString).json") }

    static func list() -> [ChatSummary] {
        guard let folder, let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(StoredChat.self, from: Data(contentsOf: $0)) }
            .map { ChatSummary(id: $0.id, title: $0.title, updated: $0.updated) }
            .sorted { $0.updated > $1.updated }
    }

    static func load(_ id: UUID) -> StoredChat? {
        guard let url = file(id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StoredChat.self, from: data)
    }

    static func save(_ chat: StoredChat) {
        guard let url = file(chat.id), let data = try? JSONEncoder().encode(chat) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func delete(_ id: UUID) { if let url = file(id) { try? FileManager.default.removeItem(at: url) } }
}

/// One conversation with the user's installed `claude`, which edits the project through the editor's MCP server.
@MainActor
final class ChatModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var running = false
    @Published var history: [ChatSummary] = ChatStore.list()
    @Published var showSkills = false
    @Published var ghostMode = false
    @Published var agents: [AgentProfile] = []
    @Published var agent: AgentProfile?
    @Published var agentSkillCount = 0
    /// Messages typed while Claude is busy: sent in order when it finishes, or at once with "Send now".
    @Published var queue: [String] = []
    private var nextUp: String?
    /// True when the current Claude session began while offline mode was on, so it has never seen any footage.
    private var sessionStartedOffline = false
    private var currentID = UUID()
    private var created = Date()
    private var sessionID: String?
    private var cancel: (@Sendable () -> Void)?

    private var customAgents: [AgentProfile] {
        get { (UserDefaults.standard.data(forKey: "customAgents").flatMap { try? JSONDecoder().decode([AgentProfile].self, from: $0) }) ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "customAgents") }
    }

    /// Finds the agents installed on this Mac (off the main thread: it asks the login shell) and restores the last choice.
    func refreshAgents() {
        Task {
            let found = await Task.detached { Agents.discover() }.value
            agents = found + customAgents.filter { c in !found.contains(c) && FileManager.default.isExecutableFile(atPath: c.executable) }
            let saved = UserDefaults.standard.string(forKey: "agentID")
            select(agents.first { $0.id == saved } ?? agents.first)
        }
    }

    func select(_ profile: AgentProfile?) {
        if profile?.id != agent?.id { sessionID = nil }   // a session belongs to one agent's login and history
        agent = profile
        UserDefaults.standard.set(profile?.id, forKey: "agentID")
        guard let profile else { Skills.agentSkills = []; agentSkillCount = 0; return }
        Task {
            let skills = await Task.detached { Agents.skills(of: profile) }.value
            guard agent?.id == profile.id else { return }
            Skills.agentSkills = skills; agentSkillCount = skills.count
        }
    }

    func addCustomAgent(_ url: URL) {
        let profile = AgentProfile(executable: url.path)
        customAgents = customAgents + [profile]
        if !agents.contains(profile) { agents.append(profile) }
        select(profile)
    }

    func send(using model: AppModel) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        send(text, using: model)
    }

    /// Opens the interview: Claude asks step by step (skill guided-edit) before building.
    func startGuidedEdit(using model: AppModel) {
        send("[GUIDED EDIT] Guide me step by step through making a film from my clips. Use the guided-edit skill and ask me one question at a time.", shown: "Guided edit: ask me step by step", using: model)
    }

    func enqueue(_ text: String) { queue.append(text) }

    func removeQueued(_ index: Int) { if queue.indices.contains(index) { queue.remove(at: index) } }

    /// Interrupts the running turn and sends this queued message right away (the conversation continues).
    func sendNow(_ index: Int, using model: AppModel) {
        guard queue.indices.contains(index) else { return }
        nextUp = queue.remove(at: index)
        if running { cancel?(); model.answerQuestion("(the user sent a new message)") } else { runNext(using: model) }
    }

    private func runNext(using model: AppModel) {
        if let next = nextUp { nextUp = nil; send(next, using: model) }
        else if !queue.isEmpty { let all = queue.joined(separator: "\n\n"); queue = []; send(all, using: model) }
    }

    /// Puts a reference to a clip or file into the message box.
    func mention(_ reference: String) {
        draft = draft.isEmpty ? reference + " " : draft + (draft.hasSuffix(" ") ? "" : " ") + reference + " "
    }

    func send(_ text: String, shown: String? = nil, using model: AppModel) {
        guard let token = model.mcpToken else { return }
        if running { queue.append(text); return }
        if model.offlineMode, let a = agent, a.kind != .claude {
            messages.append(ChatMessage(role: .notice, text: "Offline mode needs Claude: \(a.kind.title) cannot be limited to the editor's tools, so your files could be reached. Pick a Claude agent or switch offline mode off.", failed: true))
            return
        }
        // A session that already saw footage keeps it in its memory: when offline mode is on, start a clean one.
        if model.offlineMode, sessionID != nil, !sessionStartedOffline {
            sessionID = nil
            messages.append(ChatMessage(role: .notice, text: "Offline mode: started a fresh Claude session, so nothing it saw of your clips earlier is carried over. Claude now only knows what you tell it and the parts you mark."))
        }
        if sessionID == nil { sessionStartedOffline = model.offlineMode } else if !model.offlineMode { sessionStartedOffline = false }
        var request = text
        if ghostMode {
            ghostMode = false
            model.beginGhost()
            let range = model.ghostRange.map { "from \($0.lowerBound) ms to \($0.upperBound) ms" } ?? "(the whole movie)"
            request = "[GHOST EDIT] Work only on this part of the timeline \(range). You are working on a COPY: nothing changes in the user's real timeline until they accept it. Change only what the request needs and leave everything else exactly as it is. Request: \(text)"
        }
        messages.append(ChatMessage(role: .user, text: shown ?? text))
        persist()
        running = true
        let selected = model.selectedClip.map { "selected clip \($0.id.uuidString)" } ?? "nothing selected"
        let counts = "\(model.project.assets.count) imported files, \(model.project.tracks.flatMap(\.clips).count) clips on the timeline, movie length \(model.project.duration) ms"
        let prompt = "\(request)\n\n[Editor state: playhead at \(model.playhead) ms; \(selected); \(counts).]"
        let run = ClaudeRunner.run(prompt: prompt, sessionID: sessionID, port: model.mcpPort, token: token,
                                   executable: agent.map { URL(fileURLWithPath: $0.executable) }, configDir: agent?.configDir, kind: agent?.kind ?? .claude)
        cancel = run.cancel
        Task {
            var shownText = false
            for await event in run.events { shownText = handle(event, shownText: shownText) }
            finishStreaming()
            running = false
            cancel = nil
            persist()
            runNext(using: model)
        }
    }

    /// The user's answer to a question Claude asked with ask_user.
    func answer(_ text: String, using model: AppModel) {
        messages.append(ChatMessage(role: .user, text: text))
        model.answerQuestion(text)
        persist()
    }

    func stop() {
        queue = []; nextUp = nil
        cancel?()
        messages.append(ChatMessage(role: .notice, text: "Stopped. Edits already made stay in the timeline (undo with ⌘Z)."))
        persist()
    }

    func newChat() {
        cancel?()
        persist()
        messages = []; sessionID = nil; sessionStartedOffline = false; running = false
        currentID = UUID(); created = Date()
    }

    /// Switches to a saved conversation; Claude continues it with the stored session when it can.
    func open(_ id: UUID) {
        guard !running, id != currentID, let chat = ChatStore.load(id) else { return }
        persist()
        currentID = chat.id; created = chat.created; sessionID = chat.sessionID; sessionStartedOffline = false
        messages = chat.messages.map { var m = $0; m.done = true; return m }   // anything cut off by a quit is finished now
    }

    func delete(_ id: UUID) {
        ChatStore.delete(id)
        if id == currentID { cancel?(); messages = []; sessionID = nil; running = false; currentID = UUID(); created = Date() }
        history = ChatStore.list()
    }

    private func persist() {
        guard let first = messages.first(where: { $0.role == .user }) else { return }
        let title = String(first.text.prefix(48)) + (first.text.count > 48 ? "…" : "")
        ChatStore.save(StoredChat(id: currentID, title: title, created: created, updated: Date(), sessionID: sessionID, messages: messages))
        history = ChatStore.list()
    }

    private func handle(_ event: ClaudeEvent, shownText: Bool) -> Bool {
        switch event {
        case .session(let id):
            sessionID = id
        case .textDelta(let text):
            if let last = messages.indices.last, messages[last].role == .assistant, !messages[last].done {
                messages[last].text += text
            } else {
                messages.append(ChatMessage(role: .assistant, text: text, done: false))
            }
            return true
        case .toolUse(let id, let name, let input):
            finishStreaming()
            messages.append(ChatMessage(role: .tool, text: Self.describe(name, input), toolID: id, done: false))
        case .toolResult(let id, let isError):
            if let i = messages.firstIndex(where: { $0.toolID == id }) { messages[i].done = true; messages[i].failed = isError }
        case .finished(let isError, let result, _):
            finishStreaming()
            if isError { messages.append(ChatMessage(role: .notice, text: result.isEmpty ? "Claude reported an error." : result, failed: true)) }
            else if !shownText && !result.isEmpty { messages.append(ChatMessage(role: .assistant, text: result)) }
        case .failed(let message):
            finishStreaming()
            if message.localizedCaseInsensitiveContains("session") { sessionID = nil }   // a stale session id: start fresh next time
            messages.append(ChatMessage(role: .notice, text: message, failed: true))
        }
        return shownText
    }

    private func finishStreaming() {
        for i in messages.indices where messages[i].role == .assistant { messages[i].done = true }
    }

    /// "mcp__movie-maker__add_clip" + {"asset_id": ...} becomes "add_clip  asset_id: …".
    static func describe(_ name: String, _ input: String) -> String {
        let short = name.replacingOccurrences(of: "mcp__\(ClaudeRunner.serverName)__", with: "")
        let words = short.split(separator: "_").map(String.init).joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
