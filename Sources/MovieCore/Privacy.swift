import Foundation

/// Offline mode: Claude never receives pictures, sound or speech of the user's footage.
/// The tools that would look at or listen to media are hidden and refused; Claude plans from names, lengths and
/// the ranges the user marks themselves (request_selection).
public enum Privacy {
    public nonisolated(unsafe) static var offline = false

    /// Everything that analyses footage or returns pictures or transcripts of it.
    public static let blocked: Set<String> = ["inspect_asset", "watch_asset", "watch_timeline", "get_frame", "transcribe_asset", "auto_captions", "find_match_cuts", "smart_reframe"]

    static let offlinePrompt = """
    OFFLINE MODE IS ON. The user keeps their footage private (it may show children): you must not look at it, listen to it or analyse it, and the tools that would are removed. \
    You work only from file names, lengths and what the user tells you. Do not ask to see frames and do not pretend to know what the clips show. \
    To find the important parts, call request_selection: it opens a viewer where the user watches their files and marks 'start here' and 'end here' for each part they want; you get the ranges back as text. \
    Ask for it once, early, with a short reason (for example 'mark the best moments of each clip'), then build the film from those ranges with build_edit. \
    Use ask_user for the mood and length. Choices that need no picture (joins, titles, music, look, pace) work as usual.
    """
}

/// Keeps films from all looking alike: build_edit is refused when the plan ignores the creative workflow or overdoes the tricks.
public enum CreativeGuard {
    public nonisolated(unsafe) static var enabled = true
    nonisolated(unsafe) static var treatmentSuggested = false
    nonisolated(unsafe) static var lastSignature = ""

    public static func noteTreatmentSuggested() { treatmentSuggested = true }
    public static func reset() { treatmentSuggested = false; lastSignature = "" }

    private static let camera: Set<String> = ["kenBurnsIn", "kenBurnsOut", "panLeft", "panRight", "punchIn"]

    /// A message describing what to change, or nil when the plan is fine (and it is remembered as the "last film").
    public static func check(cuts: [[String: Any]], overlays: [[String: Any]]) -> String? {
        guard enabled else { return nil }
        if ScriptMode.level != .off, !ScriptMode.approved {
            return "Script mode (\(ScriptMode.level.rawValue)) is on: draft the script with propose_script and wait for the user's APPROVED before build_edit."
        }
        guard treatmentSuggested else {
            return "Before build_edit: read the creative-toolbox skill, call suggest_treatments, choose a direction and tell the user which one and why. Then plan again."
        }
        var effects = Set<String>(), joins = Set<String>(), joinCount = 0, crossfades = 0, seconds = 0.0
        for c in cuts {
            for e in (c["effects"] as? [[String: Any]]) ?? [] { if let t = e["type"] as? String, !camera.contains(t) { effects.insert(t) } }
            if let t = c["transition"] as? String, !["none", "cut", ""].contains(t) { joins.insert(t); joinCount += 1; if t == "crossfade" { crossfades += 1 } }
            let start = (c["start_ms"] as? Double) ?? Double((c["start_ms"] as? Int) ?? 0), end = (c["end_ms"] as? Double) ?? Double((c["end_ms"] as? Int) ?? 0)
            seconds += max(0, end - start) / 1000
        }
        var problems: [String] = []
        let usual = effects.intersection(["cinemaBars", "grain", "glow"])
        if usual.count >= 2 { problems.append("cinemaBars, grain and glow together are the default look every film gets. Choose different ingredients from your treatment (or none).") }
        if effects.count > 2 { problems.append("\(effects.count) different effect types (\(effects.sorted().joined(separator: ", "))): at most 2 besides camera moves. Keep the signature touch and drop the rest.") }
        if joins.count > 2 { problems.append("\(joins.count) transition styles (\(joins.sorted().joined(separator: ", "))): use at most 2, mostly hard cuts.") }
        if cuts.count >= 4, Double(joinCount) / Double(cuts.count) > 0.5 { problems.append("Joins on \(joinCount) of \(cuts.count) cuts: most cuts should be hard cuts (at most about a third get a transition).") }
        if cuts.count >= 4, Double(crossfades) / Double(cuts.count) > 0.35 { problems.append("Crossfades on \(crossfades) of \(cuts.count) cuts: the plain crossfade is the usual default, use it only where time or place changes.") }
        if Double(overlays.count) > max(1, (seconds / 30).rounded(.up)) { problems.append("\(overlays.count) overlays for \(Int(seconds)) s: at most one per 30 s.") }
        let signature = effects.sorted().joined(separator: ",") + "|" + joins.sorted().joined(separator: ",")
        if signature != "|", signature == lastSignature { problems.append("Same effects and joins as the previous film in this session (\(signature)). Pick a different direction with suggest_treatments.") }
        if !problems.isEmpty { return "build_edit was NOT applied. Revise the plan:\n- " + problems.joined(separator: "\n- ") }
        lastSignature = signature; treatmentSuggested = false; ScriptMode.approved = false
        return nil
    }
}
