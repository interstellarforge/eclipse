import Foundation

public enum AgentKind: String, Codable, CaseIterable {
    case claude, codex, opencode
    public var title: String { switch self { case .claude: return "Claude"; case .codex: return "Codex"; case .opencode: return "OpenCode" } }
    /// Claude is the tested path; the others are wired from their documented flags and have not been run against real projects.
    public var isExperimental: Bool { self != .claude }
}

/// One way to run an agent: an executable, optionally with its own config folder (CLAUDE_CONFIG_DIR for Claude).
public struct AgentProfile: Codable, Equatable, Hashable, Identifiable {
    public var executable: String
    public var configDir: String?
    var kindName: String?
    public var kind: AgentKind { kindName.flatMap(AgentKind.init(rawValue:)) ?? .claude }
    public var id: String { kind.rawValue + "|" + executable + "|" + (configDir ?? "") }
    public var name: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let exe = executable.replacingOccurrences(of: home, with: "~")
        let suffix = kind.isExperimental ? " (experimental)" : ""
        guard let configDir else { return "\(kind.title) · \(exe)\(suffix)" }
        return "\((configDir as NSString).lastPathComponent) · \(exe)"
    }
    public init(executable: String, configDir: String? = nil, kind: AgentKind = .claude) { self.executable = executable; self.configDir = configDir; self.kindName = kind == .claude ? nil : kind.rawValue }
    public var effectiveConfigDir: String { configDir ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path }
}

public enum Agents {
    /// Every claude executable found on this Mac, crossed with the config folders next to ~/.claude (~/.claude-work, …).
    public static func discover() -> [AgentProfile] {
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser.path
        var paths = ["\(home)/.local/bin/claude", "/usr/local/bin/claude", "/opt/homebrew/bin/claude", "\(home)/.claude/local/claude"]
        paths += shellLookup()
        var seen = Set<String>(), exes: [String] = []
        for p in paths where fm.isExecutableFile(atPath: p) {
            let real = (try? fm.destinationOfSymbolicLink(atPath: p)).map { URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: p).deletingLastPathComponent()).standardized.path } ?? p
            if seen.insert(real).inserted { exes.append(p) }
        }
        let extraDirs = ((try? fm.contentsOfDirectory(atPath: home)) ?? []).filter { $0.hasPrefix(".claude-") || $0.hasPrefix(".claude_") }
            .sorted().map { "\(home)/\($0)" }.filter { fm.fileExists(atPath: $0 + "/settings.json") || fm.fileExists(atPath: $0 + "/skills") || fm.fileExists(atPath: $0 + "/projects") }
        var out = exes.map { AgentProfile(executable: $0) }
        if let first = exes.first { out += extraDirs.map { AgentProfile(executable: first, configDir: $0) } }
        for kind in [AgentKind.codex, .opencode] {
            let name = kind.rawValue
            var candidates = ["\(home)/.local/bin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"] + shellLookup(name)
            let nvm = "\(home)/.nvm/versions/node"
            candidates += ((try? fm.contentsOfDirectory(atPath: nvm)) ?? []).sorted().map { "\(nvm)/\($0)/bin/\(name)" }
            var seenReal = Set<String>()
            for p in candidates where fm.isExecutableFile(atPath: p) {
                let real = URL(fileURLWithPath: p).resolvingSymlinksInPath().path
                if seenReal.insert(real).inserted { out.append(AgentProfile(executable: p, kind: kind)) }
            }
        }
        return out
    }

    private static func shellLookup(_ name: String = "claude") -> [String] {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = ["-lic", "whence -p -a \(name)"]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init).filter { $0.hasPrefix("/") }
    }

    /// Skills installed for this agent (its skills folder and plugins), so the assistant can read the ones that fit.
    public static func skills(of agent: AgentProfile) -> [Skill] {
        guard agent.kind == .claude else { return [] }
        let root = URL(fileURLWithPath: agent.effectiveConfigDir), fm = FileManager.default
        var found: [Skill] = [], names = Set(SkillContent.all.map(\.name))
        func add(_ file: URL) {
            guard found.count < 200, let text = try? String(contentsOf: file, encoding: .utf8), let meta = frontmatter(text) else { return }
            let name = meta.name ?? file.deletingLastPathComponent().lastPathComponent
            guard names.insert(name).inserted else { return }
            found.append(Skill(name: name, summary: meta.description ?? "Skill from your agent", body: meta.body, isBuiltIn: false))
        }
        for dir in [root.appendingPathComponent("skills")] {
            for sub in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { add(sub.appendingPathComponent("SKILL.md")) }
        }
        if let walker = fm.enumerator(at: root.appendingPathComponent("plugins"), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            var visited = 0
            for case let url as URL in walker {
                visited += 1; if visited > 20_000 || found.count >= 200 { break }
                if url.pathComponents.count - root.pathComponents.count > 9 { walker.skipDescendants(); continue }
                if url.lastPathComponent == "SKILL.md" { add(url) }
            }
        }
        return found.sorted { $0.name < $1.name }
    }

    static func frontmatter(_ text: String) -> (name: String?, description: String?, body: String)? {
        var lines = text.components(separatedBy: "\n"), name: String?, description: String?
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for l in lines[1..<end] {
                if l.hasPrefix("name:") { name = l.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
                if l.hasPrefix("description:") { description = l.dropFirst(12).trimmingCharacters(in: CharacterSet(charactersIn: " \"'>|")) }
            }
            lines.removeFirst(end + 1)
        }
        let desc = description.flatMap { $0.isEmpty ? nil : String($0.prefix(220)) }
        return (name, desc, lines.joined(separator: "\n"))
    }
}
