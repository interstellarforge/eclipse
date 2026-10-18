import CoreImage
import Foundation
import MovieCore

@MainActor
func runOverlayTitleChecks(_ f: Fixtures) async throws {
    // overlays draw something, and move over time
    let size = CGSize(width: 320, height: 180), rect = CGRect(origin: .zero, size: size)
    func alphaCount(_ image: CIImage) -> Int {
        let bytes = renderBytes(image.cropped(to: rect), size)
        var n = 0; for i in stride(from: 3, to: bytes.count, by: 4) where bytes[i] > 20 { n += 1 }
        return n
    }
    check(GeneratorKind.allCases.count >= 19 && Set(GeneratorKind.allCases.map(\.title)).count == GeneratorKind.allCases.count, "19 overlays")
    for kind in GeneratorKind.allCases {
        let early = GeneratorRenderer.image(kind, amount: 0.6, size: size, seconds: 1.3)!, later = GeneratorRenderer.image(kind, amount: 0.6, size: size, seconds: 2.1)!
        check(alphaCount(early) > 40, "\(kind) draws something")
        if kind != .frame { check(meanDifference(renderBytes(early.cropped(to: rect), size), renderBytes(later.cropped(to: rect), size)) > 0.05, "\(kind) animates") }
        check(GeneratorRenderer.previewFrames(kind, source: nil).count == 36, "\(kind) preview frames")
    }
    let sparse = GeneratorRenderer.image(.snow, amount: 0.1, size: size, seconds: 1)!, dense = GeneratorRenderer.image(.snow, amount: 1, size: size, seconds: 1)!
    check(alphaCount(dense) > alphaCount(sparse), "amount sets the density")

    // overlay clips in a movie
    let e = Editor(); let vt = UUID()
    try e.apply(.addAsset(f.red)); try e.apply(.addTrack(id: vt, kind: .video))
    try e.apply(.addClip(track: vt, clip: Clip(assetID: f.red.id, duration: 3_000, start: 0)))
    let overlay = try e.addOverlay(.frame, start: 0, duration: 2_000, amount: 1)
    check(e.project.tracks.count == 2 && e.project.tracks[0].clips[0].id == overlay.id, "the overlay gets its own top layer")
    let framed = decodePNG(try await FrameRenderer.png(e.project, atMs: 500))
    check(pixel(framed, 0.5, 0.5).r > 100 && pixel(framed, 0.03, 0.5).r > 200 && pixel(framed, 0.03, 0.5).g > 200, "the frame is drawn over the picture, the picture shows inside")
    try e.apply(.setVolume(overlay.id, volume: 1, fadeIn: 1_000, fadeOut: 0))
    let faded = decodePNG(try await FrameRenderer.png(e.project, atMs: 100))
    check(pixel(faded, 0.03, 0.5).g < 150, "overlay fades in with its clip fades")
    try e.apply(.setGenerator(overlay.id, kind: .confetti, amount: 0.8))
    check(e.project.tracks[0].clips[0].generator == .confetti, "setGenerator changes the overlay")
    do { try e.apply(.addEffect(overlay.id, Effect(.glow))); check(false, "effect on overlay") } catch {}
    do { try e.apply(.setGenerator(e.project.tracks[1].clips[0].id, kind: .snow, amount: 0.5)); check(false, "generator on a video clip") } catch {}
    let secondOverlay = try e.addOverlay(.snow, start: 2_500, duration: 500)
    check(e.project.tracks.count == 2 && e.project.tracks[0].clips.contains { $0.id == secondOverlay.id }, "a later overlay reuses the layer when there is room")
    let exported = FileManager.default.temporaryDirectory.appendingPathComponent("ov-\(UUID()).mp4"); defer { try? FileManager.default.removeItem(at: exported) }
    try await Exporter.export(e.project, to: exported)
    check(abs(try await Asset.load(url: exported).duration - 3_000) < 150, "a movie with overlays exports")

    // titles: sixteen styles, lookup, typography
    check(TitlePreset.allCases.count >= 27, "27 title styles")
    check(TitlePreset.named("lowerThird") == .lowerThird && TitlePreset.named("Lower third") == .lowerThird && TitlePreset.named("cinematic wide") == .wide && TitlePreset.named("nope") == nil, "title lookup by name")
    let te = Editor(); let tv = UUID()
    try te.apply(.addAsset(f.red)); try te.apply(.addTrack(id: tv, kind: .video))
    try te.apply(.addClip(track: tv, clip: Clip(assetID: f.red.id, duration: 3_000, start: 0)))
    for preset in TitlePreset.allCases {
        let c = try te.addTitle(preset.text, start: 0, duration: 2_000)
        try te.apply(.setTextStyle(c.id, preset.style))
        let frame = decodePNG(try await FrameRenderer.png(te.project, atMs: 1_500))
        var nonRed = 0
        for i in stride(from: 0, to: frame.px.count, by: 4) where abs(Int(frame.px[i]) - 229) > 60 || frame.px[i + 1] > 60 { nonRed += 1 }
        check(nonRed > 30 || preset == .tag, "\(preset) draws text")
        try te.apply(.removeClip(c.id))
    }
    var plain = TitlePreset.center.style, wide = plain
    wide.tracking = 0.6; wide.uppercase = true
    let t1 = try te.addTitle("Spacing", start: 0, duration: 2_000)
    func textWidth() async throws -> Int {
        let p = decodePNG(try await FrameRenderer.png(te.project, atMs: 1_500))
        var minX = p.w, maxX = 0
        for y in 0..<p.h { for x in 0..<p.w { let i = (y * p.w + x) * 4; if p.px[i + 1] > 200 && p.px[i + 2] > 200 { minX = min(minX, x); maxX = max(maxX, x) } } }
        return maxX - minX
    }
    plain.size = 0.08; wide.size = 0.08
    try te.apply(.setTextStyle(t1.id, plain)); let narrow = try await textWidth()
    try te.apply(.setTextStyle(t1.id, wide)); let spaced = try await textWidth()
    check(Double(spaced) > Double(narrow) * 1.3, "letter spacing widens the text: \(narrow) -> \(spaced)")
    var oldStyle = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TextStyle())) as! [String: Any]
    for k in ["tracking", "uppercase", "glow"] { oldStyle[k] = nil }
    check(try JSONDecoder().decode(TextStyle.self, from: JSONSerialization.data(withJSONObject: oldStyle)) == TextStyle(), "old text styles decode")
}
