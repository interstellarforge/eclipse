import Foundation

/// How much the assistant plans before it builds. Medium, advanced and director modes first draft a script that the user approves.
public enum ScriptLevel: String, CaseIterable, Codable {
    case off = "Direct", medium = "Medium", advanced = "Advanced", director = "Director"

    public var summary: String {
        switch self {
        case .off: return "Builds straight away from your request."
        case .medium: return "Looks at the clips, drafts a short script (5 to 8 beats) for you to approve, then builds."
        case .advanced: return "Analyses every clip in depth, drafts a shot-by-shot script with timing, joins, sound and text, revises on your feedback, then builds."
        case .director: return "Interviews you first, develops a creative direction, drafts the script with an alternative, builds, reviews its own cut and fixes it."
        }
    }
}

public struct ScriptBeat: Equatable {
    public var title: String
    public var detail: String
    public var assetID: UUID?
    public var startMs: Int?
    public var endMs: Int?
    public var seconds: Double
    public var join: String
    public var sound: String
    public var text: String
    public init(title: String = "", detail: String = "", assetID: UUID? = nil, startMs: Int? = nil, endMs: Int? = nil, seconds: Double = 3, join: String = "cut", sound: String = "", text: String = "") {
        self.title = title; self.detail = detail; self.assetID = assetID; self.startMs = startMs; self.endMs = endMs; self.seconds = seconds; self.join = join; self.sound = sound; self.text = text
    }
}

public struct ScriptDraft: Equatable {
    public var title: String
    public var logline: String
    public var beats: [ScriptBeat]
    public var notes: String
    public init(title: String, logline: String, beats: [ScriptBeat], notes: String = "") { self.title = title; self.logline = logline; self.beats = beats; self.notes = notes }

    /// The script as plain text, with the exact clip ranges, so the assistant builds what was approved.
    public func render(assetName: (UUID) -> String?) -> String {
        var out = ["Script: \(title)", logline.isEmpty ? "" : "Idea: \(logline)"].filter { !$0.isEmpty }
        for (i, b) in beats.enumerated() {
            var line = "\(i + 1). \(b.title) (\(String(format: "%.1f", b.seconds)) s)"
            if let id = b.assetID {
                line += " clip \(assetName(id) ?? "?") asset_id=\(id.uuidString)"
                if let s = b.startMs, let e = b.endMs { line += " source \(s)-\(e) ms" }
            }
            line += " join: \(b.join)"
            if !b.sound.isEmpty { line += "; sound: \(b.sound)" }
            if !b.text.isEmpty { line += "; text: \"\(b.text)\"" }
            out.append(line + (b.detail.isEmpty ? "" : "\n   \(b.detail)"))
        }
        if !notes.isEmpty { out.append("Notes: \(notes)") }
        return out.joined(separator: "\n")
    }
}

public enum ScriptMode {
    public nonisolated(unsafe) static var level = ScriptLevel.off
    /// Set when the user approved a script; build_edit needs it in the script modes, and spends it.
    public nonisolated(unsafe) static var approved = false

    static func prompt() -> String {
        switch level {
        case .off: return ""
        case .medium: return """
            SCRIPT MODE: MEDIUM. For a creative film: first look at the clips (unless offline mode is on), then call propose_script with a short script of 5 to 8 beats (what each beat shows, about how long, the join, a line of text if any). \
            The user reviews and edits it in a window. Build only after the answer starts with APPROVED, and build exactly the approved script. If you get CHANGES REQUESTED, revise and propose again.
            """
        case .advanced: return """
            SCRIPT MODE: ADVANCED. For a creative film: analyse EVERY clip in depth first (inspect_asset, watch_asset, transcribe_asset when people speak; in offline mode use the ranges the user marked). \
            Write a shot-by-shot script with propose_script: one beat per cut with the exact source range, length, join, sound decision, and any text, plus music and the overall idea in notes. \
            Wait for APPROVED (revise on CHANGES REQUESTED), build exactly the approved script with build_edit, then review it once with watch_timeline (not in offline mode) and fix problems.
            """
        case .director: return """
            SCRIPT MODE: DIRECTOR. Work like a director on a real project. 1) Interview the user with ask_user, one question at a time (purpose, audience, the feeling, length, references, what must be in it; read the guided-edit skill). \
            2) Analyse every clip in depth (unless offline). 3) Read creative-thinking and creative-toolbox, call suggest_treatments, develop one concept and keep one alternative in mind. \
            4) Write the shot-by-shot script with propose_script, and name the alternative in notes so the user can pick it. 5) Wait for APPROVED, build exactly that, 6) review your own cut (watch_timeline, not in offline mode), fix what is weak, and 7) offer one variant.
            """
        }
    }
}
