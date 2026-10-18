import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import MovieCore

/// A black 128 x 128 video with a white square (25 % wide) moving from 20 % to 80 % across the picture.
func makeMovingSquare(at url: URL, seconds: Int) async throws {
    let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 128])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 128])
    w.add(input); w.startWriting(); w.startSession(atSourceTime: .zero)
    let frames = seconds * 30
    for i in 0..<frames {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 128, 128, kCVPixelFormatType_32BGRA, nil, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let base = CVPixelBufferGetBaseAddress(pb!)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(pb!)
        let centreX = Int((0.2 + 0.6 * Double(i) / Double(frames - 1)) * 128)
        for y in 0..<128 { for x in 0..<128 {
            let on = abs(x - centreX) < 16 && abs(y - 64) < 16
            let p = y * stride + x * 4
            base[p] = on ? 255 : 0; base[p + 1] = on ? 255 : 0; base[p + 2] = on ? 255 : 0; base[p + 3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(pb!, [])
        adaptor.append(pb!, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
    }
    input.markAsFinished(); await w.finishWriting()
    if w.status != .completed { throw w.error ?? EditError.invalid("video write failed") }
}

func writePicture(_ draw: (CGContext, Double, Double) -> Void) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pic-\(UUID()).png")
    let ctx = CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx, 640, 360)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
    return url
}

@MainActor
func runRampMatchReframeChecks(_ f: Fixtures) async throws {
    // ---- speed ramps
    print("  ramps…")
    check(abs(SpeedRamp.speed(at: 0.5, SpeedRamp.preset("Slow-mo dip")!) - 0.3) < 0.01 && SpeedRamp.speed(at: 0, SpeedRamp.preset("slowmodip")!) == 1, "ramp curve values")
    check(SpeedRamp.presets.count >= 8 && SpeedRamp.preset("nope") == nil, "ramp presets")
    let e = Editor(); let vt = UUID()
    let long = Asset(url: URL(fileURLWithPath: "/tmp/none.mp4"), duration: 30_000, hasVideo: true, hasAudio: true)
    try e.apply(.addAsset(long)); try e.apply(.addTrack(id: vt, kind: .video))
    let main = try e.addClip(asset: long, start: 0, sourceIn: 2_000, duration: 8_000), next = try e.addClip(asset: long, start: 8_000, sourceIn: 0, duration: 3_000)
    try e.apply(.addEffect(main.id, Effect(.grain))); try e.apply(.addEffect(main.id, Effect(.kenBurnsIn)))
    try e.apply(.setVolume(main.id, volume: 0.7, fadeIn: 300, fadeOut: 400))
    try e.apply(.rampSpeed(main.id, SpeedRamp.preset("Slow-mo dip")!, segments: 20))
    var pieces = e.project.tracks[0].clips.filter { $0.id != next.id }.sorted { $0.start < $1.start }
    check(pieces.count == 20 && pieces[0].id == main.id, "20 pieces, the first keeps the clip's identity")
    check(abs(pieces[0].sourceIn - 2_000) <= 1 && abs(pieces.last!.sourceIn + pieces.last!.sourceLength - 10_000) <= 25, "pieces cover the whole source range")
    check(zip(pieces, pieces.dropFirst()).allSatisfy { abs($0.sourceIn + $0.sourceLength - $1.sourceIn) <= 4 && $0.end == $1.start }, "pieces follow each other in source and on the timeline")
    let slowest = pieces.map(\.speed).min() ?? 1
    check(slowest < 0.4 && pieces.first!.speed == 1 && pieces.last!.speed == 1, "slow in the middle, normal at the ends")
    let total = pieces.last!.end
    check(total > 8_000 && e.project.tracks[0].clips.first { $0.id == next.id }!.start == total, "the movie grew and the next clip followed: \(total)")
    check(pieces.first!.fadeIn == 300 && pieces.last!.fadeOut == 400 && pieces[5].fadeIn == 0 && pieces.allSatisfy { $0.volume == 0.7 }, "fades at the ends, volume everywhere")
    check(pieces.allSatisfy { $0.effects.map(\.type) == [.grain] }, "time-based effects are dropped, others stay")
    e.undo()
    check(e.project.tracks[0].clips.count == 2 && e.project.tracks[0].clips.first { $0.id == main.id }!.duration == 8_000, "one undo restores the clip")
    do { try e.apply(.rampSpeed(main.id, [RampPoint(position: 0.5, speed: 1), RampPoint(position: 0.2, speed: 2)], segments: 10)); check(false, "unsorted points") } catch {}
    do { try e.apply(.rampSpeed(main.id, [RampPoint(position: 0, speed: 20), RampPoint(position: 1, speed: 1)], segments: 10)); check(false, "speed 20") } catch {}
    do { try e.apply(.rampSpeed(main.id, SpeedRamp.presets[0].points, segments: 2)); check(false, "2 segments") } catch {}
    print("  ramps on real media…")
    let r2 = Editor(); let rv = UUID()
    try r2.apply(.addAsset(f.busy)); try r2.apply(.addAsset(f.red)); try r2.apply(.addTrack(id: rv, kind: .video))
    let c1 = try r2.addClip(asset: f.busy, duration: 4_000), c2 = try r2.addClip(asset: f.red, duration: 2_000)
    try r2.addTransition(after: c1.id, type: .crossfade, duration: 500)
    do { try r2.apply(.rampSpeed(c1.id, SpeedRamp.preset("Ramp up")!, segments: 12)); check(false, "ramp across a transition") } catch {
        check("\(error)".contains("Remove the transitions"), "a clip with transitions is not ramped: \(error)")
    }
    try r2.apply(.removeTransition(r2.project.transitions[0].id))
    try r2.apply(.rampSpeed(c1.id, SpeedRamp.preset("Ramp up")!, segments: 12))
    check(r2.project.tracks[0].clips.count == 13 && r2.project.tracks[0].clips.first { $0.id == c2.id }!.start == r2.project.tracks[0].clips.filter { $0.id != c2.id }.map(\.end).max()!, "after the ramp the next clip follows directly")
    let built = try await CompositionBuilder.build(r2.project)
    check(abs(built.composition.duration.seconds - Double(r2.project.duration) / 1000) < 0.2, "the composition matches the ramped timeline: \(built.composition.duration.seconds) vs \(r2.project.duration)")
    let h = try await McpHarness(editor: Editor()); defer { h.stop() }
    let a = McpHarness.field(try await h.call("import_media", ["path": f.busy.url.path]).text, "asset_id")
    let hc = McpHarness.field(try await h.call("add_clip", ["asset_id": a]).text, "clip_id")
    check(try await h.call("ramp_speed", ["clip_id": hc, "preset": "Hero pause"]).isError == false && h.editor.project.tracks[0].clips.count == 20, "ramp_speed preset over MCP")
    check(try await h.call("ramp_speed", ["clip_id": hc, "preset": "Nope"]).isError, "unknown ramp preset rejected")
    let first = h.editor.project.tracks[0].clips.sorted { $0.start < $1.start }[0].id.uuidString
    check(try await h.call("ramp_speed", ["clip_id": first, "points": [["position": 0, "speed": 2], ["position": 1, "speed": 0.5]], "segments": 6]).isError == false, "ramp_speed with points over MCP")

    // ---- match cuts
    print("  match cuts…")
    let sun = try writePicture { c, w, h in c.setFillColor(red: 0.05, green: 0.08, blue: 0.35, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: w, height: h)); c.setFillColor(red: 1, green: 0.55, blue: 0.1, alpha: 1); c.fillEllipse(in: CGRect(x: w / 2 - 70, y: h / 2 - 70, width: 140, height: 140)) }
    let wheel = try writePicture { c, w, h in c.setFillColor(red: 0.06, green: 0.1, blue: 0.4, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: w, height: h)); c.setFillColor(red: 1, green: 0.5, blue: 0.12, alpha: 1); c.fillEllipse(in: CGRect(x: w / 2 - 80, y: h / 2 - 78, width: 160, height: 156)) }
    let square = try writePicture { c, w, h in c.setFillColor(gray: 0.95, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: w, height: h)); c.setFillColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1); c.fill(CGRect(x: 40, y: 200, width: 120, height: 120)) }
    defer { [sun, wheel, square].forEach { try? FileManager.default.removeItem(at: $0) } }
    let sunA = try await Asset.load(url: sun), wheelA = try await Asset.load(url: wheel), squareA = try await Asset.load(url: square)
    let matches = await MatchCuts.find([sunA, wheelA, squareA], limit: 3, minScore: 0.5)
    var sunMatchesWheel = false
    if let top = matches.first { sunMatchesWheel = Set([top.assetA, top.assetB]) == Set([sunA.id, wheelA.id]) && top.score > 0.8 && top.reason.contains("orange") }
    check(sunMatchesWheel, "the sun matches the wheel: \(matches.map { ($0.score, $0.reason) })")
    check(matches.dropFirst().allSatisfy { $0.score < matches[0].score }, "other pairs score lower")
    let me = Editor(); let mv = UUID()
    try me.apply(.addAsset(sunA)); try me.apply(.addAsset(wheelA)); try me.apply(.addTrack(id: mv, kind: .video))
    let pair = try me.addMatchCut(MatchCut(assetA: sunA.id, timeA: 5_000, assetB: wheelA.id, timeB: 8_000, score: 1, reason: ""), lead: 1_500, tail: 2_000)
    check(pair.0.sourceIn == 3_500 && pair.0.duration == 1_500 && pair.1.sourceIn == 8_000 && pair.1.duration == 2_000 && pair.1.start == pair.0.end, "the match cut puts the clips side by side")
    let mh = try await McpHarness(editor: Editor()); defer { mh.stop() }
    let sunID = McpHarness.field(try await mh.call("import_media", ["path": sun.path]).text, "asset_id"), wheelID = McpHarness.field(try await mh.call("import_media", ["path": wheel.path]).text, "asset_id")
    try await mh.call("import_media", ["path": square.path])
    let found = try await mh.call("find_match_cuts", ["limit": 2]).text
    check(found.contains("cut out of") && found.contains(sunID) && found.contains(wheelID), "find_match_cuts over MCP: \(found)")
    check(try await mh.call("add_match_cut", ["asset_a": sunID, "time_a_ms": 4_000, "asset_b": wheelID, "time_b_ms": 6_000]).isError == false && mh.editor.project.tracks[0].clips.count == 2, "add_match_cut over MCP")

    // ---- smart reframe
    print("  reframe…")
    var subjectsLeftToRight: [SmartReframe.Subject] = []
    for i in 0..<8 { subjectsLeftToRight.append(SmartReframe.Subject(time: Ms(i) * 700, x: 0.2 + 0.6 * Double(i) / 7, y: 0.5)) }
    let framed = SmartReframe.keyframes(subjects: subjectsLeftToRight, sourceAspect: 16.0 / 9, canvas: CGSize(width: 1080, height: 1920), clipDuration: 5_600)
    let firstOffset = framed.frames.first?.offsetX ?? 0, lastOffset = framed.frames.last?.offsetX ?? 0
    let zoomsRight = abs(framed.scale - 3.16) < 0.02
    check(zoomsRight && framed.frames.count >= 2 && firstOffset > 0.8 && lastOffset < -0.8, "16:9 to 9:16 zooms about 3.2x and pans with the subject: \(framed.scale) \(framed.frames.map(\.offsetX))")
    let limit = (framed.scale - 1) / 2 + 1e-9
    check(framed.frames.allSatisfy { abs($0.offsetX) <= limit }, "the camera never leaves the picture")
    var centred: [SmartReframe.Subject] = []
    for i in 0..<5 { centred.append(SmartReframe.Subject(time: Ms(i) * 700, x: 0.5, y: 0.5)) }
    let still = SmartReframe.keyframes(subjects: centred, sourceAspect: 16.0 / 9, canvas: CGSize(width: 1080, height: 1920), clipDuration: 3_000)
    check(still.frames.count == 1 && still.frames[0].offsetX == 0, "a still subject needs no camera move")
    check(SmartReframe.keyframes(subjects: subjectsLeftToRight, sourceAspect: 9.0 / 16, canvas: CGSize(width: 1080, height: 1920), clipDuration: 5_000).frames.isEmpty, "already vertical: nothing to do")

    let squareURL = FileManager.default.temporaryDirectory.appendingPathComponent("moving-\(UUID()).mp4"); defer { try? FileManager.default.removeItem(at: squareURL) }
    try await makeMovingSquare(at: squareURL, seconds: 4)
    let moving = try await Asset.load(url: squareURL)
    let re = Editor(); let rt = UUID()
    try re.apply(.addAsset(moving)); try re.apply(.addTrack(id: rt, kind: .video)); try re.apply(.setFormat(width: 720, height: 1280, fps: 30))
    let clip = try re.addClip(asset: moving, start: 0)
    var truth: [SmartReframe.Subject] = []
    for i in 0..<6 { truth.append(SmartReframe.Subject(time: Ms(i) * 700, x: 0.2 + 0.6 * Double(i) * 0.7 / 4, y: 0.5)) }
    check(try re.reframeClip(clip.id, subjects: truth, sourceAspect: 1) >= 2, "reframeClip sets keyframes")
    let early = decodePNG(try await FrameRenderer.png(re.project, atMs: 100)), late = decodePNG(try await FrameRenderer.png(re.project, atMs: 3_800))
    check(pixel(early, 0.5, 0.5).r > 200 && pixel(late, 0.5, 0.5).r > 200, "the moving square stays in the middle of the vertical frame: \(pixel(early, 0.5, 0.5)) \(pixel(late, 0.5, 0.5))")
    re.undo()
    let tracked = await SmartReframe.track(moving, sourceIn: 0, length: 4_000)
    if let first = tracked.subjects.first, let last = tracked.subjects.last {
        print("  vision tracked the moving square via '\(tracked.method)': x \(String(format: "%.2f", first.x)) -> \(String(format: "%.2f", last.x))")
        check(last.x > first.x + 0.25, "the subject tracker follows a moving object")
    } else { check(false, "the subject tracker returned nothing") }
    let tool = try await McpHarness(editor: Editor()); defer { tool.stop() }
    let movingID = McpHarness.field(try await tool.call("import_media", ["path": squareURL.path]).text, "asset_id")
    let toolClip = McpHarness.field(try await tool.call("add_clip", ["asset_id": movingID]).text, "clip_id")
    let reframed = try await tool.call("smart_reframe", ["clip_id": toolClip, "aspect": "9:16"])
    check(!reframed.isError && tool.editor.project.width == 1080 && (tool.editor.project.tracks[0].clips[0].scale > 1.5 || !tool.editor.project.tracks[0].clips[0].keyframes.isEmpty), "smart_reframe over MCP: \(reframed.text)")
}
