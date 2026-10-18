import Foundation

public struct Skill: Equatable {
    public var name: String
    public var summary: String
    public var body: String
    public var isBuiltIn: Bool
    /// Set for skills that come from the user's own agent rather than this app.
    public var fromAgent = false
}

/// Director skills Claude can read through MCP (`list_skills` / `get_skill`).
/// Built-ins ship with the app; your own `.md` files in the skills folder add to or replace them.
public enum Skills {
    /// Skills of the agent the user picked; listed after ours and readable with get_skill.
    public nonisolated(unsafe) static var agentSkills: [Skill] = []

    public static func userFolder() -> URL? {
        let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MovieMaker/skills", isDirectory: true)
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    /// Built-ins, then user files (a user file with a built-in's name replaces it).
    /// A user file's first line starting with `description:` becomes the summary.
    public static func all(userFolder: URL? = Skills.userFolder()) -> [Skill] {
        var skills = SkillContent.all.map { Skill(name: $0.name, summary: $0.summary, body: $0.body, isBuiltIn: true) }
        let files = (userFolder.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? [])
            .filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let name = file.deletingPathExtension().lastPathComponent
            var lines = text.components(separatedBy: "\n")
            var summary = "Your own skill"
            if let first = lines.first, first.lowercased().hasPrefix("description:") {
                summary = first.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
                lines.removeFirst()
            }
            let skill = Skill(name: name, summary: summary, body: lines.joined(separator: "\n"), isBuiltIn: false)
            if let i = skills.firstIndex(where: { $0.name == name }) { skills[i] = skill } else { skills.append(skill) }
        }
        for var extra in agentSkills where !skills.contains(where: { $0.name == extra.name }) { extra.fromAgent = true; skills.append(extra) }
        return skills
    }

    public static func get(_ name: String, userFolder: URL? = Skills.userFolder()) -> Skill? {
        all(userFolder: userFolder).first { $0.name == name }
    }
}
