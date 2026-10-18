import CoreImage
import Foundation
import MovieCore

@MainActor
func runTemplateChecks(_ f: Fixtures) async throws {
    // grading primitives
    let size = CGSize(width: 64, height: 36), rect = CGRect(origin: .zero, size: size)
    func solid(_ v: Double) -> CIImage { CIImage(color: CIColor(red: v, green: v, blue: v)).cropped(to: rect) }
    func centre(_ image: CIImage) -> (Int, Int, Int) { let b = renderBytes(image.cropped(to: rect), size); let i = (18 * 64 + 32) * 4; return (Int(b[i]), Int(b[i + 1]), Int(b[i + 2])) }
    var warm = Look(); warm.warmth = 1
    var cool = Look(); cool.warmth = -1
    let w = centre(LookRenderer.apply(warm, to: solid(0.5), size: size)), c = centre(LookRenderer.apply(cool, to: solid(0.5), size: size))
    check(w.0 > w.2 + 15 && c.2 > c.0 + 15, "warmth warms and cools: \(w) \(c)")
    var split = Look(); split.splitShadows = "0000FF"; split.splitHighlights = "FF0000"; split.splitAmount = 1
    let dark = centre(LookRenderer.apply(split, to: solid(0.15), size: size)), bright = centre(LookRenderer.apply(split, to: solid(0.85), size: size))
    check(dark.2 > dark.0 + 10 && bright.0 > bright.2 + 10, "split toning tints shadows and highlights differently: \(dark) \(bright)")
    var fade = Look(); fade.fade = 1
    check(centre(LookRenderer.apply(fade, to: solid(0), size: size)).0 > 15, "fade lifts the blacks")
    var sharp = Look(); sharp.sharpen = 1
    _ = LookRenderer.apply(sharp, to: EffectRenderer.demoScene(size, greenScreen: false), size: size)
    var bad = Look(); bad.warmth = 3
    let e0 = Editor(); let t0 = UUID()
    try e0.apply(.addAsset(f.red)); try e0.apply(.addTrack(id: t0, kind: .video))
    let c0 = try e0.addClip(asset: f.red)
    do { try e0.apply(.setLook(c0.id, bad)); check(false, "warmth 3") } catch {}
    var oldLook = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Look())) as! [String: Any]
    for k in ["warmth", "fade", "sharpen", "splitShadows", "splitHighlights", "splitAmount"] { oldLook[k] = nil }
    check(try JSONDecoder().decode(Look.self, from: JSONSerialization.data(withJSONObject: oldLook)) == Look(), "old looks decode")
    check(Look.presetNames.count >= 18 && Look.presetNames.allSatisfy { Look.preset($0) != nil }, "every look preset exists")
    let teal = decodePNG(try await { () -> Data in
        var l = Look.preset("Teal & orange")!; l.vignette = 0
        try e0.apply(.setLook(c0.id, l)); return try await FrameRenderer.png(e0.project, atMs: 500) }())
    check(pixel(teal, 0.5, 0.5).r > 100, "a graded clip still renders")

    // templates
    let all = Templates.all
    check(all.count >= 30, "30+ templates: \(all.count)")
    check(Set(all.map(\.name)).count == all.count && Set(all.map(\.id)).count == all.count, "template names are unique")
    check(Templates.categories.count >= 5 && Templates.named("blockbuster")?.name == "Blockbuster" && Templates.named("Lo-fi chill")?.name == "Lo-fi Chill", "categories and lookup")
    let beds = Set(MusicLibrary.tracks.map(\.name))
    for t in all { check(t.music.map(beds.contains) ?? true, "\(t.name) suggests a song that exists: \(t.music ?? "-")") }
    var thumbs: [[UInt8]] = []
    for t in all {
        guard let image = TemplateRenderer.thumbnail(t, source: nil, size: CGSize(width: 96, height: 54)) else { check(false, "\(t.name) thumbnail"); continue }
        thumbs.append(renderBytes(CIImage(cgImage: image), CGSize(width: 96, height: 54)))
    }
    var distinct = 0
    for i in thumbs.indices { for j in thumbs.indices where j > i { if meanDifference(thumbs[i], thumbs[j]) > 3 { distinct += 1 } } }
    check(distinct > thumbs.count * (thumbs.count - 1) / 2 * 8 / 10, "template thumbnails look different from each other (\(distinct) distinct pairs)")

    // applying
    let e = Editor(); let vt = UUID()
    try e.apply(.addAsset(f.red)); try e.apply(.addAsset(f.blue)); try e.apply(.addTrack(id: vt, kind: .video))
    var clips: [Clip] = []
    for asset in [f.red, f.blue, f.red] { clips.append(try e.addClip(asset: asset, duration: 2_000)) }
    var framed = Look(); framed.flipX = true; framed.cropLeft = 0.1
    try e.apply(.setLook(clips[0].id, framed)); try e.apply(.addEffect(clips[0].id, Effect(.posterize)))
    let title = try e.addTitle("Hello", start: 100, duration: 1_000)
    var placed = TextStyle(); placed.x = 0.2; placed.y = 0.8
    try e.apply(.setTextStyle(title.id, placed))
    let blockbuster = Templates.named("Blockbuster")!
    let summary = try e.applyTemplate(blockbuster)
    let styled = e.project.tracks.first { $0.kind == .video && $0.clips.contains { $0.assetID != nil } }!.clips.sorted { $0.start < $1.start }
    check(styled.allSatisfy { $0.look.splitAmount > 0 && $0.effects.map(\.type).contains(.cinemaBars) } && !styled[0].effects.map(\.type).contains(.posterize), "look and effects applied, old effects replaced")
    check(styled[0].look.flipX && styled[0].look.cropLeft == 0.1, "framing (flip, crop) is kept")
    check(e.project.transitions.count == 2 && e.project.transitions.allSatisfy { $0.type == .crossfade && $0.duration == 800 }, "joins added: \(summary)")
    check(e.project.tracks.flatMap(\.clips).first { $0.id == title.id }!.style.fontName == "Georgia-Bold" && e.project.tracks.flatMap(\.clips).first { $0.id == title.id }!.style.x == 0.2, "titles restyled but not moved")
    check(e.project.tracks.flatMap(\.clips).contains { $0.generator != nil } == (blockbuster.overlay != nil), "overlay follows the template")
    e.undo()
    check(e.project.transitions.isEmpty && e.project.tracks.flatMap(\.clips).first { $0.id == clips[0].id }!.effects.map(\.type) == [.posterize], "a template is one undo step")
    // only some clips, hard cuts untouched
    let before = e.project.transitions.count
    try e.applyTemplate(Templates.named("Noir")!, to: [clips[1].id], options: { var o = Editor.TemplateOptions(); o.transitions = false; return o }())
    let after = e.project.tracks.flatMap(\.clips)
    check(after.first { $0.id == clips[1].id }!.look.saturation == 0 && after.first { $0.id == clips[2].id }!.look.saturation == 1 && e.project.transitions.count == before, "scope: only the chosen clip is styled")
    do { try Editor().applyTemplate(blockbuster); check(false, "empty project") } catch {}
    // restyling existing transitions keeps their overlap
    let e2 = Editor(); let v2 = UUID()
    try e2.apply(.addAsset(f.red)); try e2.apply(.addTrack(id: v2, kind: .video))
    let k1 = try e2.addClip(asset: f.red, duration: 2_000), k2 = try e2.addClip(asset: f.red, start: 2_000, sourceIn: 0, duration: 2_000)
    try e2.addTransition(after: k1.id, type: .crossfade, duration: 600)
    let lengthBefore = e2.project.duration
    var plain = Editor.TemplateOptions(); plain.overlay = false
    try e2.applyTemplate(Templates.named("Hype Montage")!, options: plain)
    check(e2.project.transitions[0].type == .whipLeft && e2.project.duration == lengthBefore && k2.id != k1.id, "an existing join changes style but keeps its length")

    // tools over MCP
    let h = try await McpHarness(editor: Editor()); defer { h.stop() }
    let a = McpHarness.field(try await h.call("import_media", ["path": f.busy.url.path]).text, "asset_id")
    try await h.call("add_clip", ["asset_id": a]); try await h.call("add_clip", ["asset_id": a])
    let listing = try await h.call("list_templates").text
    check(listing.contains("Blockbuster") && listing.contains("Pace:") && listing.contains("Emotional:"), "list_templates over MCP")
    let applied = try await h.call("apply_template", ["name": "Wedding Romance", "music": true, "overlay": false])
    check(!applied.isError && applied.text.contains("music Heartstrings") && h.editor.project.tracks.contains { $0.kind == .audio && !$0.clips.isEmpty }, "apply_template with music over MCP: \(applied.text)")
    check(h.editor.project.tracks.flatMap(\.clips).contains { $0.effects.contains { $0.type == .glow } } && h.editor.project.transitions.count == 1, "the style is on the clips")
    check(try await h.call("apply_template", ["name": "Nonsense"]).isError, "unknown template rejected")
    try await h.call("set_look", ["clip_id": h.editor.project.tracks[0].clips[0].id.uuidString, "warmth": 0.5, "split_shadows": "0B6E7F", "split_highlights": "FF9A3C", "split_amount": 0.5, "fade": 0.1, "sharpen": 0.2])
    let tuned = h.editor.project.tracks[0].clips[0].look
    check(tuned.warmth == 0.5 && tuned.splitShadows == "0B6E7F" && tuned.splitAmount == 0.5 && tuned.fade == 0.1 && tuned.sharpen == 0.2, "set_look grading over MCP")
}
