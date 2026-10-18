import Foundation
import MovieCore

@MainActor
func runToolChecks(_ f: Fixtures) async throws {
    let h = try await McpHarness(editor: Editor()); defer { h.stop() }
    let a = McpHarness.field(try await h.call("import_media", ["path": f.busy.url.path]).text, "asset_id")
    let b = McpHarness.field(try await h.call("import_media", ["path": f.red.url.path]).text, "asset_id")

    check(try await h.call("list_overlays").text.contains("confetti") && h.editor.project.tracks.isEmpty, "list_overlays")
    try await h.call("add_clip", ["asset_id": a])
    let overlay = try await h.call("add_overlay", ["kind": "snow", "start_ms": 500, "duration_ms": 2_000, "amount": 0.7])
    check(!overlay.isError && h.editor.project.tracks.flatMap(\.clips).contains { $0.generator == .snow && $0.generatorAmount == 0.7 }, "add_overlay over MCP")
    check(try await h.call("add_overlay", ["kind": "lasers"]).isError, "unknown overlay rejected")
    let title = try await h.call("add_title", ["text": "Night", "start_ms": 0, "duration_ms": 2_000, "preset": "neon"])
    let titleClip = h.editor.project.tracks.flatMap(\.clips).first { $0.id.uuidString == McpHarness.field(title.text, "clip_id") }
    check(titleClip?.style.glow == true && titleClip?.style.colorHex == "35F0FF", "add_title with a preset")
    check(try await h.call("add_title", ["text": "x", "start_ms": 5_000, "preset": "bogus"]).isError, "unknown title style rejected")
    try await h.call("set_text_style", ["clip_id": McpHarness.field(title.text, "clip_id"), "tracking": 0.4, "uppercase": true, "glow": false])
    let restyled = h.editor.project.tracks.flatMap(\.clips).first { $0.id == titleClip?.id }!.style
    check(restyled.tracking == 0.4 && restyled.uppercase && !restyled.glow, "set_text_style typography over MCP")

    let built = try await h.call("build_edit", ["replace": true, "cuts": [["asset_id": a, "start_ms": 0, "end_ms": 2_000], ["asset_id": b, "start_ms": 0, "end_ms": 2_000, "transition": "whipLeft", "transition_ms": 300]],
                                                   "overlays": [["kind": "sparkles", "start_ms": 500, "duration_ms": 1_500, "amount": 0.4]], "titles": [["text": "Hi", "preset": "wide", "start_ms": 200]]])
    check(!built.isError && h.editor.project.transitions.first?.type == .whipLeft && h.editor.project.tracks.flatMap(\.clips).contains { $0.generator == .sparkles }, "build_edit with overlays and new transitions: \(built.text)")
    check(try await h.call("build_edit", ["replace": true, "cuts": [["asset_id": a]], "overlays": [["kind": "lasers"]]]).isError, "unknown overlay in build_edit rejected")

    // skills: sound effects only on request; new content
    let hl = try await h.call("get_skill", ["name": "highlight-reel"]).text, edl = try await h.call("get_skill", ["name": "edit-decision-list"]).text
    check(!hl.localizedCaseInsensitiveContains("whoosh") && hl.contains("No sound effects unless the user asks"), "highlight reel skill does not add sound effects")
    check(edl.contains("only for when the user asks") && !edl.contains("\"sfx\": [{\"name\": \"Whoosh\""), "edit list skill: sfx only on request")
    let transitionsSkill = try await h.call("get_skill", ["name": "transitions"]).text, effectsSkill = try await h.call("get_skill", ["name": "scene-effects"]).text
    check(transitionsSkill.contains("whipLeft") && effectsSkill.contains("fireflies"), "skills describe the new transitions and overlays")
    let sounds = try await h.call("list_sounds").text
    check(sounds.contains("Neon Nights") && sounds.contains("only add them when the user asks"), "list_sounds groups 40 songs and warns about effects")
}
