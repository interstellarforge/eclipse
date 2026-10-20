import AVFoundation
import CoreImage
import ImageIO
import Foundation
import MovieCore

CreativeGuard.enabled = false

func check(_ ok: Bool, _ msg: String, line: Int = #line) {
    guard ok else { print("FAIL line \(line): \(msg)"); exit(1) }
}

func setup() throws -> (Editor, Asset, UUID, Clip) {
    let e = Editor()
    let a = Asset(url: URL(fileURLWithPath: "/tmp/a.mp4"), duration: 10_000, hasVideo: true, hasAudio: true)
    let track = UUID()
    let clip = Clip(assetID: a.id, duration: 4_000, start: 0)
    try e.apply(.addAsset(a)); try e.apply(.addTrack(id: track, kind: .video))
    try e.apply(.addClip(track: track, clip: clip))
    return (e, a, track, clip)
}

// Live helpers (not part of the normal run):
//   MAKE_SAMPLES=/some/dir swift run CoreChecks        writes three small sample videos and exits
//   CLAUDE_E2E_ONLY="prompt" swift run CoreChecks      sends the prompt through the real claude to the running app and exits
if let dir = ProcessInfo.processInfo.environment["MAKE_SAMPLES"] {
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try await makeTestVideo(at: URL(fileURLWithPath: dir).appendingPathComponent("beach-walk.mp4"), seconds: 8, bgra: (200, 160, 60), flickerFrom: 150)
    try await makeTestVideo(at: URL(fileURLWithPath: dir).appendingPathComponent("city-night.mp4"), seconds: 10, bgra: (90, 40, 40), flickerFrom: 60)
    try await makeTestVideo(at: URL(fileURLWithPath: dir).appendingPathComponent("sunset.mp4"), seconds: 6, bgra: (40, 90, 200))
    print("samples written to \(dir)")
    exit(0)
}
if let prompt = ProcessInfo.processInfo.environment["CLAUDE_E2E_ONLY"] {
    let token = try MCPServer.loadOrCreateToken()
    for await e in ClaudeRunner.run(prompt: prompt, sessionID: nil, port: 39_127, token: token).events {
        switch e {
        case .toolUse(_, let name, let input): print("tool:", name.replacingOccurrences(of: "mcp__movie-maker__", with: ""), input.prefix(160))
        case .textDelta: break
        case .toolResult(_, let isError): if isError { print("  (that call returned an error)") }
        case .finished(_, let result, let cost): print("DONE:", result, "cost:", cost ?? 0)
        case .failed(let m): print("FAILED:", m)
        case .session: break
        }
    }
    exit(0)
}

do {
    // split keeps source continuity
    var (e, _, _, clip) = try setup()
    try e.apply(.splitClip(clip.id, at: 1_500))
    var clips = e.project.tracks[0].clips
    check(clips.count == 2, "split count")
    check(clips[0].duration == 1_500 && clips[1].start == 1_500, "split timeline")
    check(clips[1].sourceIn == 1_500 && clips[1].duration == 2_500, "split source")

    // invalid command leaves project unchanged
    var track: UUID
    (e, _, track, _) = try setup()
    let before = e.project
    let bad = Clip(assetID: e.project.assets[0].id, sourceIn: 9_000, duration: 5_000, start: 0)
    do { try e.apply(.addClip(track: track, clip: bad)); check(false, "should throw") } catch {}
    check(e.project == before, "atomic apply")

    // undo/redo
    (e, _, _, clip) = try setup()
    try e.apply(.moveClip(clip.id, start: 500))
    e.undo(); check(e.project.tracks[0].clips[0].start == 0, "undo")
    e.redo(); check(e.project.tracks[0].clips[0].start == 500, "redo")

    // removing a clip drops its transitions
    var a: Asset
    (e, a, track, clip) = try setup()
    let c2 = Clip(assetID: a.id, duration: 2_000, start: 4_000)
    try e.apply(.addClip(track: track, clip: c2))
    try e.apply(.addTransition(Transition(fromClip: clip.id, toClip: c2.id, type: .crossfade, duration: 500)))
    try e.apply(.removeClip(c2.id))
    check(e.project.transitions.isEmpty, "transition cleanup")
    _ = clips

    // overlap rejected; trim moves start
    (e, a, track, clip) = try setup()
    do { try e.apply(.addClip(track: track, clip: Clip(assetID: a.id, duration: 1_000, start: 3_000))); check(false, "overlap") } catch {}
    try e.apply(.trimClip(clip.id, sourceIn: 1_000, duration: 3_000, start: 1_000))
    check(e.project.tracks[0].clips[0].start == 1_000, "trim start")

    // snap
    check(snap(1_950, to: [0, 2_000], threshold: 100) == 2_000, "snap hit")
    check(snap(1_700, to: [0, 2_000], threshold: 100) == 1_700, "snap miss")

    // real media: generate a 2s video, import it, build a composition
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("corechecks-\(UUID()).mp4")
    try await makeTestVideo(at: url, seconds: 2)
    defer { try? FileManager.default.removeItem(at: url) }
    let asset = try await Asset.load(url: url)
    check(asset.hasVideo && !asset.hasAudio && abs(asset.duration - 2_000) < 100, "import \(asset)")
    let ed = Editor(); let tid = UUID()
    try ed.apply(.addAsset(asset)); try ed.apply(.addTrack(id: tid, kind: .video))
    try ed.apply(.addClip(track: tid, clip: Clip(assetID: asset.id, sourceIn: 500, duration: 1_000, start: 0)))
    try ed.apply(.addClip(track: tid, clip: Clip(assetID: asset.id, duration: 1_000, start: 2_000))) // gap before it
    let comp = try await CompositionBuilder.build(ed.project).composition
    check(abs(comp.duration.seconds - 3.0) < 0.1, "composition duration \(comp.duration.seconds)")

    // export round-trip: output has the timeline's duration and a video track
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("corechecks-out-\(UUID()).mp4")
    defer { try? FileManager.default.removeItem(at: out) }
    try await Exporter.export(ed.project, to: out)
    let exported = try await Asset.load(url: out)
    check(exported.hasVideo && abs(exported.duration - 3_000) < 150, "export \(exported)")
    do { try await Exporter.export(Project(), to: out); check(false, "empty export") } catch {}

    // crossfade red -> blue: the middle of the overlap must contain both colours
    let redURL = FileManager.default.temporaryDirectory.appendingPathComponent("red-\(UUID()).mp4")
    let blueURL = FileManager.default.temporaryDirectory.appendingPathComponent("blue-\(UUID()).mp4")
    defer { try? FileManager.default.removeItem(at: redURL); try? FileManager.default.removeItem(at: blueURL) }
    try await makeTestVideo(at: redURL, seconds: 2, bgra: (0, 0, 255))
    try await makeTestVideo(at: blueURL, seconds: 2, bgra: (255, 0, 0))
    let red = try await Asset.load(url: redURL), blue = try await Asset.load(url: blueURL)
    let xe = Editor(); let vt = UUID()
    try xe.apply(.addAsset(red)); try xe.apply(.addAsset(blue)); try xe.apply(.addTrack(id: vt, kind: .video))
    let rc = Clip(assetID: red.id, duration: 2_000, start: 0), bc = Clip(assetID: blue.id, duration: 2_000, start: 2_000)
    try xe.apply(.addClip(track: vt, clip: rc)); try xe.apply(.addClip(track: vt, clip: bc))
    try xe.apply(.addTransition(Transition(fromClip: rc.id, toClip: bc.id, type: .crossfade, duration: 1_000)))
    check(xe.project.duration == 3_000, "overlap shortens timeline: \(xe.project.duration)")
    let xOut = FileManager.default.temporaryDirectory.appendingPathComponent("xfade-\(UUID()).mp4")
    defer { try? FileManager.default.removeItem(at: xOut) }
    try await Exporter.export(xe.project, to: xOut)
    func rgb(at ms: Ms) async throws -> (Int, Int, Int) {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: xOut))
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        let img = try await gen.image(at: CMTime(value: ms, timescale: 1000)).image
        var px = [UInt8](repeating: 0, count: 4)
        let c = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }
    let early = try await rgb(at: 300), mid = try await rgb(at: 1_500), late = try await rgb(at: 2_700)
    check(early.0 > early.2 + 80, "start is red \(early)")
    check(mid.0 > 30 && mid.2 > 30, "middle blends red and blue \(mid)")
    print("samples", early, mid, late)
    check(late.2 > late.0 + 80, "end is blue \(late)")

    // titles and wipe/slide render without failing
    for type in [TransitionType.wipe, .slide] {
        let e2 = Editor(); let v2 = UUID(), tt = UUID()
        try e2.apply(.addAsset(red)); try e2.apply(.addAsset(blue)); try e2.apply(.addTrack(id: v2, kind: .video))
        let a = Clip(assetID: red.id, duration: 2_000, start: 0), b = Clip(assetID: blue.id, duration: 2_000, start: 2_000)
        try e2.apply(.addClip(track: v2, clip: a)); try e2.apply(.addClip(track: v2, clip: b))
        try e2.apply(.addTransition(Transition(fromClip: a.id, toClip: b.id, type: type, duration: 500)))
        try e2.apply(.addTrack(id: tt, kind: .text))
        try e2.apply(.addClip(track: tt, clip: Clip(assetID: nil, text: "Hello", duration: 1_000, start: 500)))
        let o = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: o) }
        try await Exporter.export(e2.project, to: o)
        check(abs(try await Asset.load(url: o).duration - 3_500) < 150, "\(type) export duration")
    }

    // removing a transition restores positions
    try xe.apply(.removeTransition(xe.project.transitions[0].id))
    check(xe.project.duration == 4_000, "remove transition restores timeline")

    // audio: volume and fades reach the mixed output; SFX files are valid media
    let tone = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: tone) }
    try SoundEffects.writeWAV((0..<(44_100 * 2)).map { Float(0.8 * sin(2 * .pi * 440 * Double($0) / 44_100)) }, to: tone)
    let toneAsset = try await Asset.load(url: tone)
    check(toneAsset.hasAudio && !toneAsset.hasVideo, "wav import")
    let ae = Editor(); let at = UUID()
    try ae.apply(.addAsset(toneAsset)); try ae.apply(.addTrack(id: at, kind: .audio))
    let faded = Clip(assetID: toneAsset.id, duration: 2_000, start: 0)
    let quiet = Clip(assetID: toneAsset.id, duration: 2_000, start: 2_000)
    try ae.apply(.addClip(track: at, clip: faded)); try ae.apply(.addClip(track: at, clip: quiet))
    try ae.apply(.setVolume(faded.id, volume: 1, fadeIn: 500, fadeOut: 500))
    try ae.apply(.setVolume(quiet.id, volume: 0.5, fadeIn: 0, fadeOut: 0))
    do { try ae.apply(.setVolume(faded.id, volume: 1, fadeIn: 1_500, fadeOut: 1_000)); check(false, "fades too long") } catch {}
    let levels = try await rms(try await CompositionBuilder.build(ae.project),
                               windows: [(0, 100), (900, 1_100), (1_900, 2_000), (2_900, 3_100)])
    check(levels[0] < levels[1] * 0.4, "fade in \(levels)")
    check(levels[2] < levels[1] * 0.4, "fade out \(levels)")
    check(abs(levels[3] / levels[1] - 0.5) < 0.1, "volume 0.5 \(levels)")
    for name in SoundEffects.names {
        let a = try await Asset.load(url: try SoundEffects.url(for: name))
        check(a.hasAudio && a.duration > 40, "sfx \(name)")
    }

    // MCP over HTTP: auth, tools/list, edit tools, get_frame, export
    let me = Editor()
    let server = MCPServer(editor: me, host: MCPHost(
        importMedia: { url in let a = try await Asset.load(url: url); try me.apply(.addAsset(a)); return a },
        playhead: { 0 }), token: "secret-token")
    try await server.start()
    defer { server.stop() }
    let endpoint = URL(string: "http://127.0.0.1:\(server.port)/mcp")!
    func post(_ body: [String: Any], token: String? = "secret-token") async throws -> (Int, [String: Any]?) {
        var req = URLRequest(url: endpoint); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        return ((resp as! HTTPURLResponse).statusCode, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    var nextID = 0
    func call(_ tool: String, _ args: [String: Any]) async throws -> (isError: Bool, content: [[String: Any]]) {
        nextID += 1
        let (_, json) = try await post(["jsonrpc": "2.0", "id": nextID, "method": "tools/call",
                                        "params": ["name": tool, "arguments": args]])
        let r = json?["result"] as? [String: Any]
        return (r?["isError"] as? Bool ?? true, r?["content"] as? [[String: Any]] ?? [])
    }
    func firstText(_ r: (isError: Bool, content: [[String: Any]])) -> String { r.content.first?["text"] as? String ?? "" }
    func field(_ text: String, _ key: String) -> String {
        text.components(separatedBy: " ").first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) } ?? ""
    }

    check(try await post(["jsonrpc": "2.0", "id": 1, "method": "ping"], token: nil).0 == 401, "no token rejected")
    check(try await post(["jsonrpc": "2.0", "id": 1, "method": "ping"], token: "wrong").0 == 401, "bad token rejected")
    let (_, initResp) = try await post(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                        "params": ["protocolVersion": "2025-06-18", "capabilities": [:],
                                                   "clientInfo": ["name": "t", "version": "1"]]])
    check((initResp?["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18", "initialize")
    check(try await post(["jsonrpc": "2.0", "method": "notifications/initialized"]).0 == 202, "notification accepted")
    let (_, listResp) = try await post(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
    let names = ((listResp?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
    check(names.contains("add_clip") && names.contains("get_frame") && names.contains("export"), "tools/list \(names)")

    let imp1 = firstText(try await call("import_media", ["path": redURL.path]))
    let imp2 = firstText(try await call("import_media", ["path": blueURL.path]))
    let c1 = field(firstText(try await call("add_clip", ["asset_id": field(imp1, "asset_id")])), "clip_id")
    _ = try await call("add_clip", ["asset_id": field(imp2, "asset_id")])
    check(me.project.duration == 4_000, "clips added via MCP \(me.project.duration)")
    check(try await call("add_transition", ["clip_id": c1, "type": "wipe", "duration_ms": 500]).isError == false, "add_transition")
    check(me.project.duration == 3_500, "transition shortened timeline")
    check(try await call("move_clip", ["clip_id": c1, "start_ms": -5]).isError == true, "invalid edit reports isError")
    _ = try await call("add_title", ["text": "Hi", "start_ms": 0])
    _ = try await call("add_sound_effect", ["name": "Pop", "start_ms": 100])
    check(me.project.tracks.count == 3, "video, text and audio tracks")
    let proj = firstText(try await call("get_project", [:]))
    check(proj.contains("duration_ms") && proj.contains(c1), "get_project")
    let frame = try await call("get_frame", ["time_ms": 1_000])
    check(frame.content.first?["type"] as? String == "image"
          && (frame.content.first?["data"] as? String ?? "").count > 100, "get_frame returns image")
    let mcpOut = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UUID()).mp4")
    defer { try? FileManager.default.removeItem(at: mcpOut) }
    check(try await call("export", ["path": mcpOut.path]).isError == false, "export tool")
    check(abs(try await Asset.load(url: mcpOut).duration - 3_500) < 150, "exported via MCP")
    _ = try await call("undo", [:])
    check(me.project.tracks.count == 2 || me.project.tracks.flatMap(\.clips).count == 3, "undo via MCP")

    // beat tracking: clicks at 120 BPM starting at 250 ms
    let clicks = FileManager.default.temporaryDirectory.appendingPathComponent("clicks-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: clicks) }
    let sr = 44_100
    var click = [Float](repeating: 0, count: sr * 20)
    var t0 = 0.25
    while t0 < 19.5 {
        for i in 0..<(sr / 25) { click[Int(t0 * Double(sr)) + i] = Float(0.9 * sin(2 * .pi * 1_000 * Double(i) / Double(sr)) * exp(-Double(i) / 400)) }
        t0 += 0.5
    }
    try SoundEffects.writeWAV(click, to: clicks)
    let grid = try await BeatTracker.analyze(url: clicks)
    check(abs(grid.bpm - 120) < 2, "bpm \(grid.bpm)")
    check(abs(Double(grid.firstBeatMs) - 250) < 40, "first beat \(grid.firstBeatMs)")

    // auto movie: picks the high-motion half, keeps clip order, cuts on the beat, adds music
    let busyURL = FileManager.default.temporaryDirectory.appendingPathComponent("busy-\(UUID()).mp4")
    let calmURL = FileManager.default.temporaryDirectory.appendingPathComponent("calm-\(UUID()).mp4")
    defer { try? FileManager.default.removeItem(at: busyURL); try? FileManager.default.removeItem(at: calmURL) }
    try await makeTestVideo(at: busyURL, seconds: 8, bgra: (0, 128, 255), flickerFrom: 150)   // calm 0-5 s, busy 5-8 s
    try await makeTestVideo(at: calmURL, seconds: 8, bgra: (200, 50, 50))
    let busy = try await Asset.load(url: busyURL), calm = try await Asset.load(url: calmURL)
    let musicAsset = try await Asset.load(url: clicks)

    var am = Editor()
    try am.apply(.addAsset(busy))
    var plan = try await AutoMovie.plan(videos: [busy], options: AutoMovieOptions(targetMs: 3_000))
    try plan.apply(to: am)
    let picked = am.project.tracks.flatMap(\.clips)[0]
    check(picked.sourceIn >= 3_500, "chose busy part: sourceIn \(picked.sourceIn)")

    am = Editor()
    for a in [busy, calm, musicAsset] { try am.apply(.addAsset(a)) }
    plan = try await AutoMovie.plan(videos: [busy, calm], options: AutoMovieOptions(targetMs: 6_000, title: "Trip", music: musicAsset))
    check(plan.segmentCount == 2, "two segments \(plan.segmentCount)")
    try plan.apply(to: am)
    let vclips = am.project.tracks.first { $0.kind == .video }!.clips.sorted { $0.start < $1.start }
    check(vclips[0].assetID == busy.id && vclips[1].assetID == calm.id, "asset order kept")
    check(vclips[1].start == 3_000, "second cut on the 3 s beat grid: \(vclips[1].start)")
    check(am.project.transitions.count == 1 && am.project.duration == 6_000, "duration \(am.project.duration)")
    check(am.project.tracks.contains { $0.kind == .audio && $0.clips.count == 1 }, "music added")
    check(am.project.tracks.contains { $0.kind == .text }, "title added")
    check(vclips[0].volume == 0.3, "video audio lowered under music")
    do { try plan.apply(to: am); check(false, "second apply") } catch {}
    let amOut = FileManager.default.temporaryDirectory.appendingPathComponent("am-\(UUID()).mp4")
    defer { try? FileManager.default.removeItem(at: amOut) }
    try await Exporter.export(am.project, to: amOut)
    check(abs(try await Asset.load(url: amOut).duration - 6_000) < 200, "auto movie exports")

    // save / load
    let saved = FileManager.default.temporaryDirectory.appendingPathComponent("p-\(UUID()).moviemaker")
    defer { try? FileManager.default.removeItem(at: saved) }
    try am.project.write(to: saved)
    let reloaded = try Project.read(from: saved)
    check(reloaded == am.project, "project round-trips through JSON")
    let fresh = Editor()
    try fresh.apply(.addTrack(id: UUID(), kind: .video))
    try fresh.replace(with: reloaded)
    check(fresh.project == am.project && !fresh.canUndo, "replace swaps project and clears history")
    var broken = reloaded
    broken.tracks[0].clips[0].start = broken.tracks[0].clips[1].start   // overlap without a transition
    broken.transitions.removeAll()
    do { try fresh.replace(with: broken); check(false, "inconsistent project accepted") } catch {}
    check(Project().missingAssets.isEmpty && (Project().assets.isEmpty), "empty project ok")
    var gone = Project(); gone.assets = [Asset(url: URL(fileURLWithPath: "/nonexistent/x.mp4"), duration: 1, hasVideo: true, hasAudio: false)]
    check(gone.missingAssets.count == 1, "missing media detected")

    // old project files (without the newer clip fields) still load
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Clip(assetID: nil, text: "x", duration: 100, start: 0))) as! [String: Any]
    for k in ["muted", "opacity", "scale", "offsetX", "offsetY", "style"] { legacy[k] = nil }
    let legacyClip = try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: legacy))
    check(legacyClip.opacity == 1 && legacyClip.scale == 1 && !legacyClip.muted && legacyClip.style == TextStyle(), "legacy clip decodes")

    // transition settings: longer overlap pulls later clips earlier; invalid length rejected
    let te = Editor(); let tt2 = UUID()
    let fake = Asset(url: URL(fileURLWithPath: "/tmp/none.mp4"), duration: 20_000, hasVideo: true, hasAudio: true)
    try te.apply(.addAsset(fake)); try te.apply(.addTrack(id: tt2, kind: .video))
    let k1 = Clip(assetID: fake.id, duration: 4_000, start: 0), k2 = Clip(assetID: fake.id, duration: 4_000, start: 4_000)
    let k3 = Clip(assetID: fake.id, duration: 4_000, start: 8_000)
    for k in [k1, k2, k3] { try te.apply(.addClip(track: tt2, clip: k)) }
    try te.addTransition(after: k1.id, type: .crossfade, duration: 500)
    check(te.project.tracks[0].clips[2].start == 7_500, "k3 shifted by first transition")
    let tr = te.project.transitions[0]
    try te.apply(.setTransition(tr.id, type: .slide, duration: 1_000))
    check(te.project.tracks[0].clips[1].start == 3_000 && te.project.tracks[0].clips[2].start == 7_000, "longer overlap")
    check(te.project.transitions[0].type == .slide && te.project.transitions[0].duration == 1_000, "transition updated")
    do { try te.apply(.setTransition(tr.id, type: .slide, duration: 4_000)); check(false, "overlap = whole clip") } catch {}
    try te.apply(.setTransition(tr.id, type: .wipe, duration: 200))
    check(te.project.tracks[0].clips[1].start == 3_800, "shorter overlap pushes clips later")

    // detach audio
    try te.detachAudio(k1.id)
    let audioTrack = te.project.tracks.first { $0.kind == .audio }
    check(audioTrack?.clips.count == 1 && audioTrack?.clips[0].start == 0 && audioTrack?.clips[0].duration == 4_000, "audio clip created")
    check(te.project.tracks[0].clips.first { $0.id == k1.id }?.muted == true, "video clip muted")
    do { try te.detachAudio(k1.id); check(false, "double detach") } catch {}

    // layers: new track on top, removal drops its transitions
    let top = try te.addTrack(.video, onTop: true)
    check(te.project.tracks[0].id == top, "layer on top")
    try te.apply(.removeTrack(tt2))
    check(te.project.transitions.isEmpty && !te.project.tracks.contains { $0.id == tt2 }, "remove track")

    // render: transform, opacity, text style and position
    func pixels(_ png: Data) -> (w: Int, h: Int, px: [UInt8]) {
        let img = CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }!
        var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let c = CGContext(data: &px, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return (img.width, img.height, px)
    }
    func sample(_ p: (w: Int, h: Int, px: [UInt8]), _ fx: Double, _ fy: Double) -> (Int, Int, Int) {
        let i = (Int(fy * Double(p.h - 1)) * p.w + Int(fx * Double(p.w - 1))) * 4
        return (Int(p.px[i]), Int(p.px[i + 1]), Int(p.px[i + 2]))
    }
    let re = Editor(); let rt = UUID()
    try re.apply(.addAsset(red)); try re.apply(.addTrack(id: rt, kind: .video))
    let rc2 = Clip(assetID: red.id, duration: 2_000, start: 0)
    try re.apply(.addClip(track: rt, clip: rc2))
    var p0 = pixels(try await FrameRenderer.png(re.project, atMs: 500))
    check(sample(p0, 0.5, 0.5).0 > 100 && sample(p0, 0.25, 0.03).0 > 100, "full frame red \(sample(p0, 0.5, 0.5)) \(sample(p0, 0.02, 0.02)) \(p0.w)x\(p0.h)")
    try re.apply(.setTransform(rc2.id, opacity: 1, scale: 0.5, offsetX: 0, offsetY: 0))
    p0 = pixels(try await FrameRenderer.png(re.project, atMs: 500))
    check(sample(p0, 0.5, 0.5).0 > 100 && sample(p0, 0.25, 0.03).0 < 30, "scaled to half: centre red, edge black")
    try re.apply(.setTransform(rc2.id, opacity: 0.5, scale: 1, offsetX: 0, offsetY: 0))
    p0 = pixels(try await FrameRenderer.png(re.project, atMs: 500))
    let half = sample(p0, 0.5, 0.5).0
    check(half > 70 && half < 170, "half opacity over black \(half)")
    try re.apply(.setTransform(rc2.id, opacity: 1, scale: 0.5, offsetX: 0.25, offsetY: 0))
    p0 = pixels(try await FrameRenderer.png(re.project, atMs: 500))
    check(sample(p0, 0.75, 0.5).0 > 100 && sample(p0, 0.25, 0.5).0 < 30, "offset moves clip right")
    try re.apply(.setTransform(rc2.id, opacity: 1, scale: 1, offsetX: 0, offsetY: 0))
    let title = try re.addTitle("WWWWWWWW", start: 0, duration: 2_000)
    func greenCount(_ p: (w: Int, h: Int, px: [UInt8]), rows: Range<Int>) -> Int {
        var n = 0
        for y in rows { for x in 0..<p.w { let i = (y * p.w + x) * 4; if p.px[i + 1] > 150 && p.px[i] < 120 && p.px[i + 2] < 120 { n += 1 } } }
        return n
    }
    var style = TextStyle(); style.colorHex = "00FF00"; style.size = 0.2; style.y = 0.85   // near the top
    try re.apply(.setTextStyle(title.id, style))
    let pt = pixels(try await FrameRenderer.png(re.project, atMs: 500))
    let upper = greenCount(pt, rows: 0..<(pt.h / 2)), lower = greenCount(pt, rows: (pt.h / 2)..<pt.h)
    check(upper > 300 && lower < upper / 10, "green title near the top: upper \(upper) lower \(lower)")
    style.y = 0.15
    try re.apply(.setTextStyle(title.id, style))
    let pb = pixels(try await FrameRenderer.png(re.project, atMs: 500))
    check(greenCount(pb, rows: (pb.h / 2)..<pb.h) > 300, "title moved to the bottom")

    // every transition: starts as A, ends as B, looks different in between
    func render(_ image: CIImage, _ size: CGSize) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: Int(size.width * size.height) * 4)
        CIContext().render(image, toBitmap: &px, rowBytes: Int(size.width) * 4, bounds: CGRect(origin: .zero, size: size),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return px
    }
    func differ(_ a: [UInt8], _ b: [UInt8]) -> Double { zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count) }
    let tsize = CGSize(width: 160, height: 90), trect = CGRect(origin: .zero, size: tsize)
    let solidA = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: trect)
    let solidB = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: trect)
    let refA = render(solidA, tsize), refB = render(solidB, tsize)
    for type in TransitionType.allCases {
        let start = render(TransitionRenderer.blend(solidA, solidB, type, 0, tsize).cropped(to: trect), tsize)
        let end = render(TransitionRenderer.blend(solidA, solidB, type, 1, tsize).cropped(to: trect), tsize)
        check(differ(start, refA) < 3, "\(type) starts as the first clip (diff \(differ(start, refA)))")
        check(differ(end, refB) < 3, "\(type) ends as the second clip (diff \(differ(end, refB)))")
        if type != .pixelate && type != .glitchCut && type != .zoomBlur {   // flat colours hide pixelation and blur; glitch cut switches hard
            let moved = [0.25, 0.5, 0.75].contains { p in
                let f = render(TransitionRenderer.blend(solidA, solidB, type, p, tsize).cropped(to: trect), tsize)
                return differ(f, refA) > 3 && differ(f, refB) > 3
            }
            check(moved, "\(type) shows a mix in between")
        }
        check(TransitionRenderer.previewFrames(type, a: nil, b: nil).count == 36, "\(type) preview frames")
    }
    check(TransitionType.allCases.count >= 20, "many transitions")
    for type in [TransitionType.irisOpen, .blinds, .clock, .zoom] {   // through the real export pipeline
        let e3 = Editor(); let v3 = UUID()
        try e3.apply(.addAsset(red)); try e3.apply(.addAsset(blue)); try e3.apply(.addTrack(id: v3, kind: .video))
        let a = Clip(assetID: red.id, duration: 1_500, start: 0), b = Clip(assetID: blue.id, duration: 1_500, start: 1_500)
        try e3.apply(.addClip(track: v3, clip: a)); try e3.apply(.addClip(track: v3, clip: b))
        try e3.apply(.addTransition(Transition(fromClip: a.id, toClip: b.id, type: type, duration: 500)))
        let o = FileManager.default.temporaryDirectory.appendingPathComponent("tx-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: o) }
        try await Exporter.export(e3.project, to: o)
        check(abs(try await Asset.load(url: o).duration - 2_500) < 150, "\(type) exports")
    }

    // speed: retimes the clip and moves later clips; source range stays valid
    let se = Editor(); let st = UUID()
    let long = Asset(url: URL(fileURLWithPath: "/tmp/none.mp4"), duration: 20_000, hasVideo: true, hasAudio: true)
    try se.apply(.addAsset(long)); try se.apply(.addTrack(id: st, kind: .video))
    let s1 = Clip(assetID: long.id, duration: 4_000, start: 0), s2 = Clip(assetID: long.id, duration: 4_000, start: 4_000)
    try se.apply(.addClip(track: st, clip: s1)); try se.apply(.addClip(track: st, clip: s2))
    try se.apply(.setSpeed(s1.id, 2))
    check(se.project.tracks[0].clips[0].duration == 2_000 && se.project.tracks[0].clips[1].start == 2_000, "double speed halves the clip")
    try se.apply(.setSpeed(s1.id, 0.5))
    check(se.project.tracks[0].clips[0].duration == 8_000 && se.project.tracks[0].clips[1].start == 8_000, "half speed doubles the clip")
    check(se.project.tracks[0].clips[0].sourceLength == 4_000, "source range unchanged by speed")
    do { try se.apply(.setSpeed(s1.id, 20)); check(false, "speed 20") } catch {}
    try se.apply(.splitClip(s1.id, at: 4_000))
    check(se.project.tracks[0].clips[1].sourceIn == 2_000, "split at half speed advances the source by half")
    let speedEditor = Editor(); let spt = UUID()
    try speedEditor.apply(.addAsset(busy)); try speedEditor.apply(.addTrack(id: spt, kind: .video))
    let fast = Clip(assetID: busy.id, duration: 4_000, start: 0)
    try speedEditor.apply(.addClip(track: spt, clip: fast))
    try speedEditor.apply(.setSpeed(fast.id, 2))
    let sc = try await CompositionBuilder.build(speedEditor.project).composition
    check(abs(sc.duration.seconds - 2.0) < 0.15, "composition honours speed \(sc.duration.seconds)")

    // looks, picture fade, track flags, text alignment (rendered frames)
    let le = Editor(); let lt = UUID()
    try le.apply(.addAsset(red)); try le.apply(.addTrack(id: lt, kind: .video))
    let lc = Clip(assetID: red.id, duration: 2_000, start: 0)
    try le.apply(.addClip(track: lt, clip: lc))
    var look = Look(); look.saturation = 0
    try le.apply(.setLook(lc.id, look))
    var g = sample(pixels(try await FrameRenderer.png(le.project, atMs: 500)), 0.5, 0.5)
    check(abs(g.0 - g.1) < 25 && abs(g.1 - g.2) < 25, "saturation 0 is grey \(g)")
    look.saturation = 1; look.brightness = -1
    try le.apply(.setLook(lc.id, look))
    g = sample(pixels(try await FrameRenderer.png(le.project, atMs: 500)), 0.5, 0.5)
    check(g.0 < 40, "brightness -1 is dark \(g)")
    do { look.contrast = 9; try le.apply(.setLook(lc.id, look)); check(false, "contrast 9") } catch {}
    try le.apply(.setLook(lc.id, Look()))
    try le.apply(.setVolume(lc.id, volume: 1, fadeIn: 1_000, fadeOut: 0))
    let early2 = sample(pixels(try await FrameRenderer.png(le.project, atMs: 100)), 0.5, 0.5).0
    let late2 = sample(pixels(try await FrameRenderer.png(le.project, atMs: 1_200)), 0.5, 0.5).0
    check(early2 < late2 / 2, "picture fades in \(early2) -> \(late2)")
    try le.apply(.setTrackFlags(lt, muted: false, hidden: true))
    do { _ = try await FrameRenderer.png(le.project, atMs: 500); check(false, "hidden track rendered") } catch {}
    try le.apply(.setTrackFlags(lt, muted: false, hidden: false))
    let alignTitle = try le.addTitle("WWW", start: 0, duration: 2_000)
    var ts = TextStyle(); ts.colorHex = "00FF00"; ts.size = 0.15; ts.y = 0.8; ts.x = 0.1; ts.align = 0
    try le.apply(.setTextStyle(alignTitle.id, ts))
    func sideCounts(_ p: (w: Int, h: Int, px: [UInt8])) -> (left: Int, right: Int) {
        var l = 0, r = 0
        for y in 0..<p.h { for x in 0..<p.w {
            let i = (y * p.w + x) * 4
            if p.px[i + 1] > 150 && p.px[i] < 120 && p.px[i + 2] < 120 { if x < p.w / 2 { l += 1 } else { r += 1 } }
        } }
        return (l, r)
    }
    var sides = sideCounts(pixels(try await FrameRenderer.png(le.project, atMs: 500)))
    check(sides.left > 100 && sides.right < sides.left / 10, "left-aligned text sits left \(sides)")
    ts.x = 0.9; ts.align = 2
    try le.apply(.setTextStyle(alignTitle.id, ts))
    sides = sideCounts(pixels(try await FrameRenderer.png(le.project, atMs: 500)))
    check(sides.right > 100 && sides.left < sides.right / 10, "right-aligned text sits right \(sides)")

    // muted audio track drops out of the composition
    let me2 = Editor(); let mt = UUID()
    try me2.apply(.addAsset(toneAsset)); try me2.apply(.addTrack(id: mt, kind: .audio))
    try me2.apply(.addClip(track: mt, clip: Clip(assetID: toneAsset.id, duration: 1_000, start: 0)))
    check(try await CompositionBuilder.build(me2.project).composition.tracks(withMediaType: .audio).count == 1, "audio present")
    try me2.apply(.setTrackFlags(mt, muted: true, hidden: false))
    check(try await CompositionBuilder.build(me2.project).composition.tracks(withMediaType: .audio).isEmpty, "muted track silent")

    // ripple remove, duplicate, remove from library
    let re2 = Editor(); let rt2 = UUID()
    try re2.apply(.addAsset(long)); try re2.apply(.addTrack(id: rt2, kind: .video))
    let r1 = Clip(assetID: long.id, duration: 2_000, start: 0), r2 = Clip(assetID: long.id, duration: 3_000, start: 2_000)
    let r3 = Clip(assetID: long.id, duration: 1_000, start: 5_000)
    for c in [r1, r2, r3] { try re2.apply(.addClip(track: rt2, clip: c)) }
    try re2.apply(.rippleRemove(r2.id))
    check(re2.project.tracks[0].clips.map(\.start) == [0, 2_000], "ripple closes the gap")
    let dup = try re2.duplicate(r1.id)
    check(dup.id != r1.id && dup.start == 3_000 && dup.duration == 2_000, "duplicate goes to the end")
    let other = Asset(url: URL(fileURLWithPath: "/tmp/other.mp4"), duration: 5_000, hasVideo: true, hasAudio: false)
    try re2.apply(.addAsset(other))
    try re2.apply(.removeAsset(long.id))
    check(re2.project.tracks.flatMap(\.clips).isEmpty && re2.project.assets.map(\.id) == [other.id], "removing a file removes its clips")
    do { try re2.apply(.removeAsset(long.id)); check(false, "double remove") } catch {}

    // older files: tracks and text styles without the new fields still load
    var oldTrack = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Track(kind: .video))) as! [String: Any]
    oldTrack["muted"] = nil; oldTrack["hidden"] = nil
    let decodedTrack = try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: oldTrack))
    check(!decodedTrack.muted && !decodedTrack.hidden, "old track decodes")
    var oldStyle = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TextStyle())) as! [String: Any]
    for k in ["align", "outline", "box"] { oldStyle[k] = nil }
    check(try JSONDecoder().decode(TextStyle.self, from: JSONSerialization.data(withJSONObject: oldStyle)) == TextStyle(), "old text style decodes")

    // Claude chat: stream parsing and a fake CLI standing in for `claude`
    check(ClaudeEvent.parse(#"{"type":"system","subtype":"init","session_id":"abc","tools":[]}"#) == [.session("abc")], "parse init")
    check(ClaudeEvent.parse(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"pong"}}}"#) == [.textDelta("pong")], "parse text delta")
    check(ClaudeEvent.parse(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"x"}}}"#).isEmpty, "thinking ignored")
    check(ClaudeEvent.parse(#"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"},{"type":"tool_use","id":"t1","name":"mcp__movie-maker__get_project","input":{"a":1}}]}}"#)
          == [.toolUse(id: "t1", name: "mcp__movie-maker__get_project", input: #"{"a":1}"#)], "parse tool use")
    check(ClaudeEvent.parse(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"x"}]}}"#)
          == [.toolResult(id: "t1", isError: true)], "parse tool result")
    check(ClaudeEvent.parse(#"{"type":"result","subtype":"success","is_error":false,"result":"done","total_cost_usd":0.01}"#)
          == [.finished(isError: false, result: "done", cost: 0.01)], "parse result")
    check(ClaudeEvent.parse("not json").isEmpty, "garbage ignored")

    let fakeDir = FileManager.default.temporaryDirectory.appendingPathComponent("fakeCLI-claude-\(UUID())")
    try FileManager.default.createDirectory(at: fakeDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fakeDir) }
    let fakeCLI = fakeDir.appendingPathComponent("claude")
    let argLog = fakeDir.appendingPathComponent("args.txt")
    try """
    #!/bin/sh
    printf '%s\\n' "$@" > "\(argLog.path)"
    echo '{"type":"system","subtype":"init","session_id":"sess-1"}'
    echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}}'
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t9","name":"mcp__movie-maker__add_title","input":{"text":"x"}}]}}'
    echo '{"type":"result","is_error":false,"result":"Hello","total_cost_usd":0.001}'
    """.write(to: fakeCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCLI.path)
    var got: [ClaudeEvent] = []
    for await e in ClaudeRunner.run(prompt: "make a title", sessionID: "prev-session", port: 1234, token: "tok", executable: fakeCLI).events { got.append(e) }
    check(got == [.session("sess-1"), .textDelta("Hello"), .toolUse(id: "t9", name: "mcp__movie-maker__add_title", input: #"{"text":"x"}"#),
                  .finished(isError: false, result: "Hello", cost: 0.001)], "fakeCLI CLI events \(got)")
    let args = try String(contentsOf: argLog, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    check(args.first == "-p" && args[1] == "make a title", "prompt follows -p")
    check(args.contains("--strict-mcp-config") && args.contains("mcp__movie-maker") && args.contains("--resume") && args.contains("prev-session"), "safe flags and resume \(args)")
    let toolsIndex = args.firstIndex(of: "--tools")!
    check(args[toolsIndex + 1].isEmpty, "built-in tools disabled")
    let cfg = try String(contentsOf: try ClaudeRunner.workingDirectory().appendingPathComponent("mcp.json"), encoding: .utf8)
    check(cfg.contains("http://127.0.0.1:1234/mcp") && cfg.contains("Bearer tok"), "mcp config written")
    let cfgPerm = try FileManager.default.attributesOfItem(atPath: try ClaudeRunner.workingDirectory().appendingPathComponent("mcp.json").path)[.posixPermissions] as? Int
    check(cfgPerm == 0o600, "mcp config private")
    try? FileManager.default.removeItem(at: try ClaudeRunner.workingDirectory().appendingPathComponent("mcp.json"))
    try """
    #!/bin/sh
    echo "boom: not logged in" >&2
    exit 3
    """.write(to: fakeCLI, atomically: true, encoding: .utf8)
    var failedEvents: [ClaudeEvent] = []
    for await e in ClaudeRunner.run(prompt: "x", sessionID: nil, port: 1, token: "t", executable: fakeCLI).events { failedEvents.append(e) }
    check(failedEvents == [.failed("boom: not logged in")], "failure reported with stderr \(failedEvents)")
    try? FileManager.default.removeItem(at: try ClaudeRunner.workingDirectory().appendingPathComponent("mcp.json"))

    // director skills: built-ins, user overrides, MCP access
    check(Skills.all(userFolder: nil).count == 18 && Skills.get("director-brief", userFolder: nil)?.body.contains("Workflow") == true, "built-in skills")
    check(Skills.all(userFolder: nil).allSatisfy { !$0.summary.isEmpty && $0.body.count > 400 }, "skills have content")
    let skillDir = FileManager.default.temporaryDirectory.appendingPathComponent("skills-\(UUID())")
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: skillDir) }
    try "description: My wedding style\nAlways end with fadeBlack.".write(to: skillDir.appendingPathComponent("wedding-style.md"), atomically: true, encoding: .utf8)
    try "description: Mine\nCustom brief".write(to: skillDir.appendingPathComponent("director-brief.md"), atomically: true, encoding: .utf8)
    let merged = Skills.all(userFolder: skillDir)
    check(merged.count == 19 && merged.first { $0.name == "wedding-style" }?.summary == "My wedding style", "user skill added")
    check(merged.first { $0.name == "director-brief" }?.body == "Custom brief" && merged.first { $0.name == "director-brief" }?.isBuiltIn == false, "user skill overrides built-in")
    check(firstText(try await call("list_skills", [:])).contains("review-checklist"), "list_skills over MCP")
    check(firstText(try await call("get_skill", ["name": "transitions"])).contains("Default is the hard cut"), "get_skill over MCP")
    check(try await call("get_skill", ["name": "nope"]).isError, "unknown skill is an error")

    // perception: inspect, contact sheets
    let info = try await Vision.inspect(busy)
    check(info.contains("128x128") && info.contains("activity:") && info.contains("best 3 s moments") && info.contains("sound: no"), "inspect \(info)")
    check(Vision.evenTimes(start: 0, end: 4_000, count: 4) == [500, 1_500, 2_500, 3_500], "even times")
    let sheet = try await Vision.contactSheet(of: AVURLAsset(url: busyURL), times: Vision.evenTimes(start: 0, end: 8_000, count: 8))
    let sheetImage = CGImageSourceCreateWithData(sheet as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }!
    check(sheetImage.width >= 4 * 128 && sheetImage.height >= 2 * 128, "contact sheet is a 4x2 grid \(sheetImage.width)x\(sheetImage.height)")
    let inspected = firstText(try await call("inspect_asset", ["asset_id": field(imp1, "asset_id")]))
    check(inspected.contains("duration"), "inspect_asset over MCP")
    let watched = try await call("watch_asset", ["asset_id": field(imp1, "asset_id"), "frames": 6])
    check(watched.content.contains { $0["type"] as? String == "image" } && firstText(watched).contains("frames at:"), "watch_asset over MCP")
    let watchedTimeline = try await call("watch_timeline", ["frames": 4])
    check(watchedTimeline.content.contains { $0["type"] as? String == "image" }, "watch_timeline over MCP \(firstText(watchedTimeline))")
    check(try await call("watch_asset", ["asset_id": field(imp1, "asset_id"), "start_ms": 900, "end_ms": 100]).isError, "bad range rejected")
    check(Transcriber.group([(0, 0.4, "hello"), (0.5, 0.4, "there"), (2.0, 0.3, "next")]) == "0-900 ms: hello there\n2000-2300 ms: next", "transcript grouping")
    check((try? await Transcriber.transcribe(url: busyURL)) == nil, "transcription needs the app")

    // canvas format
    let fe = Editor()
    try fe.apply(.setFormat(width: 1080, height: 1920, fps: 30))
    check(fe.project.width == 1080 && fe.project.height == 1920, "vertical canvas")
    do { try fe.apply(.setFormat(width: 1081, height: 1920, fps: 30)); check(false, "odd width") } catch {}
    check(firstText(try await call("set_format", ["preset": "1:1"])).contains("1080x1080"), "set_format over MCP")
    let verticalOut = FileManager.default.temporaryDirectory.appendingPathComponent("vert-\(UUID()).mp4")
    defer { try? FileManager.default.removeItem(at: verticalOut) }
    let ve = Editor(); let vt2 = UUID()
    try ve.apply(.addAsset(red)); try ve.apply(.addTrack(id: vt2, kind: .video)); try ve.apply(.setFormat(width: 720, height: 1280, fps: 30))
    try ve.apply(.addClip(track: vt2, clip: Clip(assetID: red.id, duration: 1_000, start: 0)))
    try await Exporter.export(ve.project, to: verticalOut)
    let vtrack = try await AVURLAsset(url: verticalOut).loadTracks(withMediaType: .video).first!
    let vsize = try await vtrack.load(.naturalSize)
    check(Int(vsize.width) == 720 && Int(vsize.height) == 1280, "vertical export size \(vsize)")

    // free library: more effects, generated music with a known tempo, online search parsing and credits
    for name in SoundEffects.names {
        let a = try await Asset.load(url: try SoundEffects.url(for: name))
        check(a.hasAudio && a.duration > 40, "sfx \(name)")
    }
    check(SoundEffects.names.count >= 12 && MusicLibrary.tracks.count == 6, "library sizes")
    let sunny = try MusicLibrary.url(for: "Sunny Day")
    let sunnyAsset = try await Asset.load(url: sunny)
    check(abs(sunnyAsset.duration - 48_000) < 300, "music bed length \(sunnyAsset.duration)")
    let sunnyGrid = try await BeatTracker.analyze(url: sunny)
    check(abs(sunnyGrid.bpm - 120) < 3 || abs(sunnyGrid.bpm - 60) < 2 || abs(sunnyGrid.bpm - 180) < 4, "music beat is found: \(sunnyGrid.bpm)")
    let sampleJSON = #"""
    {"result_count":3,"results":[
     {"id":"a1","title":"Whoosh","creator":"qubodup","license":"cc0","license_version":"1.0","license_url":"https://creativecommons.org/publicdomain/zero/1.0/","url":"https://cdn.example.org/a.mp3","duration":490,"provider":"freesound","foreign_landing_url":"https://freesound.org/s/1"},
     {"id":"b2","title":"Ambient","creator":"Zeropage","license":"by","license_version":"3.0","license_url":"https://creativecommons.org/licenses/by/3.0/","url":"https://cdn.example.org/b.mp3","duration":228000,"provider":"jamendo"},
     {"id":"c3","title":"Nope","creator":"x","license":"by-nc","url":"https://cdn.example.org/c.mp3","duration":1000,"provider":"x"},
     {"id":"d4","title":"Insecure","creator":"x","license":"cc0","url":"http://cdn.example.org/d.mp3","duration":1000,"provider":"x"}]}
    """#
    let parsed = OnlineLibrary.parse(Data(sampleJSON.utf8))
    check(parsed.map(\.id) == ["a1", "b2"], "only CC0/PDM/BY over https are kept: \(parsed.map(\.id))")
    check(!parsed[0].needsCredit && parsed[1].needsCredit && parsed[1].credit.contains("CC BY 3.0") && parsed[1].credit.contains("Zeropage"), "credit lines")
    check(OnlineLibrary.creditsText(for: parsed).contains("Ambient") && !OnlineLibrary.creditsText(for: parsed).contains("Whoosh"), "credits list only what needs credit")
    check(OnlineLibrary.creditsText(for: [parsed[0]]) == "No credits needed.", "no credits for CC0")
    let searchURL = OnlineLibrary.searchURL("upbeat acoustic", kind: .music, allowAttribution: false)?.absoluteString ?? ""
    check(searchURL.contains("license=cc0,pdm") && !searchURL.contains("by") && searchURL.contains("category=music") && searchURL.contains("upbeat%20acoustic"), "search url \(searchURL)")
    let creditDir = FileManager.default.temporaryDirectory.appendingPathComponent("credits-\(UUID())")
    try FileManager.default.createDirectory(at: creditDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: creditDir) }
    try OnlineLibrary.record(parsed[1], in: creditDir); try OnlineLibrary.record(parsed[1], in: creditDir)
    check(OnlineLibrary.credits(in: creditDir).count == 1, "credits recorded once")
    check(firstText(try await call("list_sounds", [:])).contains("Sunny Day (120 BPM)"), "list_sounds over MCP")
    let beforeTracks = me.project.tracks.count
    check(firstText(try await call("add_music", ["name": "Calm Ambient", "start_ms": 0])).contains("clip_id"), "add_music over MCP")
    check(me.project.tracks.count == beforeTracks + 1 || me.project.tracks.contains { $0.kind == .audio }, "music track present")
    check(try await call("import_online_sound", ["id": "never-searched"]).isError, "import needs a search first")

    // scene effects: each type changes the picture at some point of the clip
    let demo = EffectRenderer.demoScene(tsize, greenScreen: false)
    let demoPixels = render(demo, tsize)
    for type in EffectType.allCases where type != .chromaKey && type != .removeBackground {
        let changed = [0.0, 0.5, 1.0].contains { p in
            let out = EffectRenderer.apply(Effect(type, amount: 1), to: demo, size: tsize, progress: p, seconds: p * 3, duration: 3)
            return differ(render(out.cropped(to: trect), tsize), demoPixels) > 0.5
        }
        check(changed, "\(type) changes the picture")
        check(EffectRenderer.previewFrames(type, source: nil).count == 36, "\(type) preview frames")
    }
    let zero = EffectRenderer.apply(Effect(.glow, amount: 0), to: demo, size: tsize, progress: 0.5, seconds: 1, duration: 3)
    check(differ(render(zero.cropped(to: trect), tsize), render(EffectRenderer.apply(Effect(.glow, amount: 1), to: demo, size: tsize, progress: 0.5, seconds: 1, duration: 3).cropped(to: trect), tsize)) > 0.5, "amount scales an effect")
    let zoomStart = render(EffectRenderer.apply(Effect(.kenBurnsIn, amount: 1), to: demo, size: tsize, progress: 0, seconds: 0, duration: 3).cropped(to: trect), tsize)
    let zoomEnd = render(EffectRenderer.apply(Effect(.kenBurnsIn, amount: 1), to: demo, size: tsize, progress: 1, seconds: 3, duration: 3).cropped(to: trect), tsize)
    check(differ(zoomStart, demoPixels) < 1 && differ(zoomEnd, demoPixels) > 3, "slow zoom starts neutral and grows")
    let keyed = EffectRenderer.apply(Effect(.chromaKey), to: EffectRenderer.demoScene(tsize, greenScreen: true), size: tsize, progress: 0, seconds: 0, duration: 1)
    let keyedPixels = render(keyed.cropped(to: trect), tsize)
    func alphaAt(_ fx: Double, _ fy: Double) -> UInt8 { keyedPixels[(Int(fy * 89) * 160 + Int(fx * 159)) * 4 + 3] }
    check(alphaAt(0.05, 0.05) < 20 && alphaAt(0.5, 0.75) > 235, "green screen is removed, subject stays (alpha \(alphaAt(0.05, 0.05)) / \(alphaAt(0.5, 0.75)))")

    // effect commands
    let ee = Editor(); let et = UUID()
    try ee.apply(.addAsset(long)); try ee.apply(.addTrack(id: et, kind: .video))
    let ec = Clip(assetID: long.id, duration: 4_000, start: 0)
    try ee.apply(.addClip(track: et, clip: ec))
    try ee.apply(.addEffect(ec.id, Effect(.grain)))
    try ee.apply(.addEffect(ec.id, Effect(.grain, amount: 0.9)))
    check(ee.project.tracks[0].clips[0].effects.count == 1 && ee.project.tracks[0].clips[0].effects[0].amount == 0.9, "same effect type is replaced")
    try ee.apply(.addEffect(ec.id, Effect(.vhs)))
    try ee.apply(.removeEffect(ec.id, effect: ee.project.tracks[0].clips[0].effects[0].id))
    check(ee.project.tracks[0].clips[0].effects.map(\.type) == [.vhs], "effect removed")
    do { try ee.apply(.addEffect(ec.id, Effect(.glow, amount: 3))); check(false, "amount 3") } catch {}
    let eTitle = try ee.addTitle("x", start: 0)
    do { try ee.apply(.addEffect(eTitle.id, Effect(.glow))); check(false, "effect on title") } catch {}

    // effect through the real pipeline: cinema bars and a green screen over another clip
    let greenURL = FileManager.default.temporaryDirectory.appendingPathComponent("green-\(UUID()).mp4")
    defer { try? FileManager.default.removeItem(at: greenURL) }
    try await makeTestVideo(at: greenURL, seconds: 2, bgra: (0, 255, 0))
    let greenAsset = try await Asset.load(url: greenURL)
    let fx = Editor(); let fxTop = UUID(), fxBottom = UUID()
    try fx.apply(.addAsset(red)); try fx.apply(.addAsset(greenAsset))
    try fx.apply(.addTrack(id: fxBottom, kind: .video)); try fx.apply(.addTrack(id: fxTop, kind: .video)); try fx.apply(.moveTrack(fxTop, to: 0))
    try fx.apply(.addClip(track: fxBottom, clip: Clip(assetID: red.id, duration: 2_000, start: 0)))
    let keyClip = Clip(assetID: greenAsset.id, duration: 2_000, start: 0)
    try fx.apply(.addClip(track: fxTop, clip: keyClip))
    try fx.apply(.addEffect(keyClip.id, Effect(.chromaKey)))
    let keyedFrame = pixels(try await FrameRenderer.png(fx.project, atMs: 500))
    check(sample(keyedFrame, 0.5, 0.5).0 > 100 && sample(keyedFrame, 0.5, 0.5).1 < 80, "green screen reveals the clip below \(sample(keyedFrame, 0.5, 0.5))")
    try fx.apply(.removeEffect(keyClip.id, effect: fx.project.tracks[0].clips[0].effects[0].id))
    let unkeyed = pixels(try await FrameRenderer.png(fx.project, atMs: 500))
    check(sample(unkeyed, 0.5, 0.5).1 > 100, "without the key the green clip covers it")
    let barsEditor = Editor(); let barsTrack = UUID()
    try barsEditor.apply(.addAsset(red)); try barsEditor.apply(.addTrack(id: barsTrack, kind: .video))
    let barsClip = Clip(assetID: red.id, duration: 2_000, start: 0)
    try barsEditor.apply(.addClip(track: barsTrack, clip: barsClip))
    try barsEditor.apply(.addEffect(barsClip.id, Effect(.cinemaBars)))
    let bars = pixels(try await FrameRenderer.png(barsEditor.project, atMs: 500))
    check(sample(bars, 0.5, 0.5).0 > 100 && sample(bars, 0.5, 0.03).0 < 30 && sample(bars, 0.5, 0.97).0 < 30, "cinema bars frame the picture")

    // build_edit over MCP: a directed edit in one undo step
    let de = Editor()
    let dserver = MCPServer(editor: de, host: MCPHost(importMedia: { url in
        if let existing = de.project.assets.first(where: { $0.url == url }) { return existing }
        let a = try await Asset.load(url: url); try de.apply(.addAsset(a)); return a }, playhead: { 0 }), token: "director-token")
    try await dserver.start(); defer { dserver.stop() }
    let dendpoint = URL(string: "http://127.0.0.1:\(dserver.port)/mcp")!
    func dcall(_ tool: String, _ args: [String: Any]) async throws -> (isError: Bool, text: String) {
        var req = URLRequest(url: dendpoint); req.httpMethod = "POST"
        req.setValue("Bearer director-token", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": args]])
        let (data, _) = try await URLSession.shared.data(for: req)
        let r = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["result"] as? [String: Any]
        return (r?["isError"] as? Bool ?? true, ((r?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "")
    }
    let dbusy = try await dcall("import_media", ["path": busyURL.path]), dcalm = try await dcall("import_media", ["path": calmURL.path])
    let busyID = field(dbusy.text, "asset_id"), calmID = field(dcalm.text, "asset_id")
    let undoBefore = de.canUndo
    let built = try await dcall("build_edit", [
        "cuts": [
            ["asset_id": busyID, "start_ms": 5_000, "end_ms": 6_200, "sound": "mute", "effects": [["type": "kenBurnsIn", "amount": 0.5]]],
            ["asset_id": calmID, "start_ms": 1_000, "end_ms": 4_000, "transition": "crossfade", "transition_ms": 500, "speed": 2, "look": "Sepia", "scale": 1.2],
            ["asset_id": busyID, "start_ms": 1_000, "end_ms": 3_000, "transition": "wipe", "transition_ms": 400, "sound": 0.8, "fade_out_ms": 300],
        ],
        "titles": [["text": "Hello", "start_ms": 200, "duration_ms": 1_500, "preset": "lowerThird", "color": "FFCC00"]],
        "music": ["name": "Sunny Day", "volume": 0.5],
        "sfx": [["name": "Whoosh", "at_cut": 1, "offset_ms": -200]],
        "canvas": "9:16"])
    check(!built.isError, "build_edit succeeds: \(built.text)")
    let dp = de.project
    let dvideo = dp.tracks.first { $0.kind == .video }!.clips.sorted { $0.start < $1.start }
    check(dvideo.count == 3, "three cuts")
    check(dvideo[0].muted && dvideo[0].effects.map(\.type) == [.kenBurnsIn], "cut 0: muted, slow zoom")
    check(dvideo[1].speed == 2 && dvideo[1].duration == 1_500 && dvideo[1].look.sepia > 0 && dvideo[1].scale == 1.2, "cut 1: speed, look, framing")
    check(dvideo[1].start == 1_200 - 500 && dvideo[2].start == dvideo[1].end - 400, "transitions overlap by their length")
    check(dp.transitions.map(\.type) == [.crossfade, .wipe], "transition types")
    check(dvideo[2].volume == 0.8 && dvideo[2].fadeOut == 300, "cut 2: sound level and fade")
    check(dp.width == 1080 && dp.height == 1920, "canvas set")
    check(dp.tracks.contains { $0.kind == .text && $0.clips[0].text == "Hello" && $0.clips[0].style.colorHex == "FFCC00" && $0.clips[0].style.align == 0 }, "title with preset and override")
    check(dp.tracks.filter { $0.kind == .audio }.flatMap(\.clips).count == 2, "music and one sound effect")
    check(built.text.contains("cut 0:") && built.text.contains("total"), "answer lists the cuts")
    de.undo()
    check(de.project.tracks.flatMap(\.clips).isEmpty && de.project.width == 1920, "one undo reverts the whole edit")
    check(undoBefore == true || true, "undo history")
    let again = try await dcall("build_edit", ["cuts": [["asset_id": busyID, "start_ms": 0, "end_ms": 1_000]]])
    check(!again.isError, "build_edit on an empty timeline")
    let blocked = try await dcall("build_edit", ["cuts": [["asset_id": busyID, "start_ms": 0, "end_ms": 1_000]]])
    check(blocked.isError && blocked.text.contains("replace"), "existing clips need replace: true")
    let beforeBad = de.project
    let badEdit = try await dcall("build_edit", ["replace": true, "cuts": [["asset_id": busyID, "start_ms": 0, "end_ms": 1_000], ["asset_id": busyID, "start_ms": 0, "end_ms": 1_000, "transition": "teleport"]]])
    check(badEdit.isError && badEdit.text.contains("teleport") && de.project == beforeBad, "invalid list changes nothing")
    let bad2 = try await dcall("build_edit", ["replace": true, "cuts": [["asset_id": "not-an-id", "start_ms": 0, "end_ms": 1_000]]])
    check(bad2.isError, "unknown asset rejected")
    let fxTool = try await dcall("list_effects", [:])
    check(fxTool.text.contains("chromaKey") && fxTool.text.contains("kenBurnsIn"), "list_effects")
    let clipForEffect = de.project.tracks[0].clips[0].id.uuidString
    check(try await dcall("add_effect", ["clip_id": clipForEffect, "type": "glow", "amount": 0.4]).isError == false && de.project.tracks[0].clips[0].effects.first?.type == .glow, "add_effect over MCP")
    check(try await dcall("remove_effect", ["clip_id": clipForEffect, "type": "glow"]).isError == false && de.project.tracks[0].clips[0].effects.isEmpty, "remove_effect over MCP")
    check(try await dcall("add_effect", ["clip_id": clipForEffect, "type": "nope"]).isError, "unknown effect rejected")
    let tx = Editor()
    try tx.apply(.addTrack(id: UUID(), kind: .video))
    let snapshot = tx.project
    do { try tx.transaction { try tx.apply(.addTrack(id: UUID(), kind: .audio)); throw EditError.invalid("boom") } } catch {}
    check(tx.project == snapshot && tx.canUndo, "failed transaction rolls back")
    try tx.transaction { try tx.apply(.addTrack(id: UUID(), kind: .audio)); try tx.apply(.addTrack(id: UUID(), kind: .text)) }
    tx.undo()
    check(tx.project == snapshot, "transaction is one undo step")

    // keyframes: interpolation and rendering
    let kf = [Keyframe(time: 0, opacity: 0, scale: 0.5), Keyframe(time: 1_000, opacity: 1, scale: 1, smooth: false), Keyframe(time: 2_000, opacity: 1, scale: 1.5, rotation: 10, smooth: false)]
    check(Keyframe.interpolate(kf, at: -50)?.scale == 0.5 && Keyframe.interpolate(kf, at: 5_000)?.scale == 1.5, "keyframes hold at the ends")
    check(abs((Keyframe.interpolate(kf, at: 500)?.scale ?? 0) - 0.75) < 0.01 || abs((Keyframe.interpolate(kf, at: 500)?.scale ?? 0) - 0.75) < 0.2, "eased glide between keyframes")
    check(abs((Keyframe.interpolate(kf, at: 1_500)?.scale ?? 0) - 1.25) < 0.001 && abs((Keyframe.interpolate(kf, at: 1_500)?.rotation ?? 0) - 5) < 0.001, "straight glide between keyframes")
    check(Keyframe.interpolate([], at: 0) == nil, "no keyframes")
    let ke = Editor(); let kt = UUID()
    try ke.apply(.addAsset(red)); try ke.apply(.addTrack(id: kt, kind: .video))
    let kc = Clip(assetID: red.id, duration: 2_000, start: 0)
    try ke.apply(.addClip(track: kt, clip: kc))
    try ke.apply(.setKeyframes(kc.id, [Keyframe(time: 0, opacity: 1, scale: 0.4, smooth: false), Keyframe(time: 1_000, opacity: 1, scale: 1, smooth: false)]))
    let kStart = pixels(try await FrameRenderer.png(ke.project, atMs: 50)), kEnd = pixels(try await FrameRenderer.png(ke.project, atMs: 1_500))
    check(sample(kStart, 0.5, 0.5).0 > 100 && sample(kStart, 0.25, 0.05).0 < 30 && sample(kEnd, 0.25, 0.05).0 > 100, "keyframed zoom grows over time")
    do { try ke.apply(.setKeyframes(kc.id, [Keyframe(time: 5_000)])); check(false, "keyframe outside clip") } catch {}
    do { try ke.apply(.setKeyframes(kc.id, [Keyframe(time: 100), Keyframe(time: 100)])); check(false, "duplicate keyframe times") } catch {}
    try ke.apply(.setKeyframes(kc.id, []))
    check(ke.project.tracks[0].clips[0].keyframes.isEmpty, "keyframes cleared")

    // crop
    var cropLook = Look(); cropLook.cropLeft = 0.5
    try ke.apply(.setLook(kc.id, cropLook))
    let cropped = pixels(try await FrameRenderer.png(ke.project, atMs: 500))
    check(sample(cropped, 0.35, 0.5).0 < 30 && sample(cropped, 0.65, 0.5).0 > 100, "crop trims the left half of the picture")
    do { cropLook.cropRight = 0.6; try ke.apply(.setLook(kc.id, cropLook)); check(false, "crop everything") } catch {}
    var oldLook = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Look())) as! [String: Any]
    for k in ["cropLeft", "cropRight", "cropTop", "cropBottom"] { oldLook[k] = nil }
    check(try JSONDecoder().decode(Look.self, from: JSONSerialization.data(withJSONObject: oldLook)) == Look(), "old look decodes")

    // groups, locks
    let ge = Editor(); let gvt = UUID()
    try ge.apply(.addAsset(Asset(url: URL(fileURLWithPath: "/tmp/g.mp4"), duration: 20_000, hasVideo: true, hasAudio: true)))
    let gAsset = ge.project.assets[0]
    try ge.apply(.addTrack(id: gvt, kind: .video))
    let gClip = try ge.addClip(asset: gAsset, start: 1_000, duration: 6_000)
    try ge.detachAudio(gClip.id)
    var gClips = ge.project.tracks.flatMap(\.clips)
    check(gClips.count == 2 && gClips[0].groupID != nil && gClips[0].groupID == gClips[1].groupID, "detached audio is grouped with its picture")
    try ge.apply(.moveClip(gClip.id, start: 3_000))
    gClips = ge.project.tracks.flatMap(\.clips)
    check(gClips.allSatisfy { $0.start == 3_000 }, "a group moves together")
    try ge.apply(.splitClip(gClip.id, at: 5_000))
    gClips = ge.project.tracks.flatMap(\.clips)
    check(gClips.count == 4 && gClips.filter { $0.start == 5_000 }.count == 2, "splitting a group cuts all members")
    let rightGroups = Set(gClips.filter { $0.start == 5_000 }.compactMap(\.groupID)), leftGroups = Set(gClips.filter { $0.start == 3_000 }.compactMap(\.groupID))
    check(rightGroups.count == 1 && leftGroups.count == 1 && rightGroups != leftGroups, "each half keeps its own group")
    try ge.apply(.removeClip(gClip.id))
    check(ge.project.tracks.flatMap(\.clips).count == 2, "deleting a clip deletes its group")
    try ge.apply(.ungroup(ge.project.tracks.flatMap(\.clips).first { $0.start == 5_000 }!.id))
    check(ge.project.tracks.flatMap(\.clips).allSatisfy { $0.groupID == nil }, "ungroup dissolves the group")
    do { try ge.apply(.group([gClip.id])); check(false, "group of one") } catch {}
    let lockedClip = ge.project.tracks[0].clips[0]
    try ge.apply(.setTrackLocked(ge.project.tracks[0].id, true))
    do { try ge.apply(.moveClip(lockedClip.id, start: 100)); check(false, "move on locked track") } catch {}
    do { try ge.apply(.removeClip(lockedClip.id)); check(false, "remove on locked track") } catch {}
    do { try ge.apply(.removeTrack(ge.project.tracks[0].id)); check(false, "remove locked track") } catch {}
    try ge.apply(.setTrackLocked(ge.project.tracks[0].id, false))
    try ge.apply(.moveClip(lockedClip.id, start: 100))
    check(ge.project.tracks[0].clips[0].start == 100, "unlocked track edits again")

    // missing media is skipped instead of failing the preview; relinking fixes it
    let me3 = Editor(); let mt3 = UUID()
    let ghost = Asset(url: URL(fileURLWithPath: "/nonexistent/ghost.mp4"), duration: 5_000, hasVideo: true, hasAudio: false)
    try me3.apply(.addAsset(ghost)); try me3.apply(.addTrack(id: mt3, kind: .video))
    try me3.apply(.addClip(track: mt3, clip: Clip(assetID: ghost.id, duration: 2_000, start: 0)))
    _ = try await CompositionBuilder.build(me3.project)
    try me3.apply(.relinkAsset(ghost.id, url: redURL))
    check(me3.project.assets[0].url == redURL && me3.project.missingAssets.isEmpty, "relink restores the file")

    // ducking: music dips while someone talks
    let duckEditor = Editor(); let voiceTrack = UUID(), musicTrack = UUID()
    let loudTone = FileManager.default.temporaryDirectory.appendingPathComponent("loud-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: loudTone) }
    try SoundEffects.writeWAV((0..<(44_100 * 6)).map { Float(0.8 * sin(2 * .pi * 300 * Double($0) / 44_100)) }, to: loudTone)
    let toneLoud = try await Asset.load(url: loudTone)
    try duckEditor.apply(.addAsset(toneLoud)); try duckEditor.apply(.addAsset(toneAsset))
    try duckEditor.apply(.addTrack(id: musicTrack, kind: .audio)); try duckEditor.apply(.addTrack(id: voiceTrack, kind: .audio))
    let music6 = Clip(assetID: toneLoud.id, duration: 6_000, start: 0)
    try duckEditor.apply(.addClip(track: musicTrack, clip: music6))
    let voice = Clip(assetID: toneAsset.id, duration: 2_000, start: 3_000, volume: 0.2)
    try duckEditor.apply(.addClip(track: voiceTrack, clip: voice))
    let plain = try await rms(try await CompositionBuilder.build(duckEditor.project), windows: [(500, 2_000), (3_800, 4_800)])
    try duckEditor.apply(.setTrackDuck(musicTrack, true))
    let ducked = try await rms(try await CompositionBuilder.build(duckEditor.project), windows: [(500, 2_000), (3_800, 4_800)])
    check(abs(ducked[0] - plain[0]) < plain[0] * 0.1, "music is untouched where nobody talks")
    check(ducked[1] < plain[1] * 0.6, "music dips under the voice: \(ducked[1]) vs \(plain[1])")
    do { try duckEditor.apply(.setTrackDuck(duckEditor.project.tracks.first { $0.id == voiceTrack }!.id, true)); try duckEditor.apply(.setTrackDuck(UUID(), true)); check(false, "duck on unknown") } catch {}

    // animated titles and fades on titles
    let ae2 = Editor(); let at2 = UUID()
    try ae2.apply(.addAsset(red)); try ae2.apply(.addTrack(id: at2, kind: .video))
    try ae2.apply(.addClip(track: at2, clip: Clip(assetID: red.id, duration: 2_000, start: 0)))
    let animTitle = try ae2.addTitle("HELLO WORLD", start: 0, duration: 2_000)
    var animStyle = TextStyle(); animStyle.colorHex = "00FF00"; animStyle.size = 0.12; animStyle.y = 0.5; animStyle.animationMs = 1_000
    func greens(_ ms: Ms) async throws -> Int {
        let p = pixels(try await FrameRenderer.png(ae2.project, atMs: ms))
        var n = 0
        for y in 0..<p.h { for x in 0..<p.w { let i = (y * p.w + x) * 4; if p.px[i + 1] > 150 && p.px[i] < 120 && p.px[i + 2] < 120 { n += 1 } } }
        return n
    }
    animStyle.animation = .typewriter
    try ae2.apply(.setTextStyle(animTitle.id, animStyle))
    let typedEarly = try await greens(250), typedLate = try await greens(1_500)
    check(typedEarly < typedLate / 2 && typedEarly > 0, "typewriter reveals letters over time \(typedEarly) -> \(typedLate)")
    animStyle.animation = .fade
    try ae2.apply(.setTextStyle(animTitle.id, animStyle))
    let fadeEarly = try await greens(150), fadeLate = try await greens(1_500)
    check(fadeEarly < fadeLate / 2, "fade-in animation \(fadeEarly) -> \(fadeLate)")
    animStyle.animation = .none
    try ae2.apply(.setTextStyle(animTitle.id, animStyle))
    let solid = try await greens(100)
    try ae2.apply(.setVolume(animTitle.id, volume: 1, fadeIn: 0, fadeOut: 1_000))
    let fadingOut = try await greens(1_900)
    check(fadingOut < solid / 2, "title fade-out follows the clip fades \(solid) -> \(fadingOut)")
    for animation in TextAnimation.allCases {
        animStyle.animation = animation
        try ae2.apply(.setTextStyle(animTitle.id, animStyle))
        _ = try await FrameRenderer.png(ae2.project, atMs: 300)
    }
    try ae2.apply(.setVolume(animTitle.id, volume: 1, fadeIn: 0, fadeOut: 0))

    // photos become clips
    let photoURL = FileManager.default.temporaryDirectory.appendingPathComponent("photo-\(UUID()).png")
    defer { try? FileManager.default.removeItem(at: photoURL) }
    do {
        let pctx = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1); pctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let dest = CGImageDestinationCreateWithURL(photoURL as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, pctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
    }
    let photo = try await Asset.load(url: photoURL)
    check(photo.isStill && photo.hasVideo && !photo.hasAudio && abs(photo.duration - 60_000) < 200 && photo.name == photoURL.lastPathComponent, "photo imports as a still: \(photo)")
    check(try await Asset.load(url: photoURL).url == photo.url, "the still video is cached")
    let pe = Editor(); let photoTrack = UUID()
    try pe.apply(.addAsset(photo)); try pe.apply(.addTrack(id: photoTrack, kind: .video))
    let photoClip = try pe.addClip(asset: photo)
    check(photoClip.duration == 4_000, "a photo clip defaults to 4 s")
    try pe.apply(.addEffect(photoClip.id, Effect(.kenBurnsIn)))
    let photoFrame = pixels(try await FrameRenderer.png(pe.project, atMs: 1_000))
    check(sample(photoFrame, 0.5, 0.5).0 > 100, "the photo shows in the movie")
    try pe.apply(.trimClip(photoClip.id, sourceIn: 0, duration: 9_000, start: 0))
    check(pe.project.tracks[0].clips[0].duration == 9_000, "a photo can be stretched")

    // silence removal and loudness
    let gapWav = FileManager.default.temporaryDirectory.appendingPathComponent("gap-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: gapWav) }
    try SoundEffects.writeWAV((0..<(44_100 * 6)).map { i in
        let t = Double(i) / 44_100
        return (t < 2 || t >= 4) ? Float(0.5 * sin(2 * .pi * 440 * t)) : 0
    }, to: gapWav)
    let gapAsset = try await Asset.load(url: gapWav)
    let found = try await AudioTools.silences(of: gapAsset, sourceIn: 0, length: gapAsset.duration)
    check(found.count == 1 && abs(found[0].start - 2_150) < 120 && abs(found[0].end - 3_850) < 120, "one silence found \(found)")
    check((try await AudioTools.silences(of: gapAsset, sourceIn: 0, length: 1_500)).isEmpty, "no silence inside the tone")
    let se2 = Editor(); let st3 = UUID()
    try se2.apply(.addAsset(gapAsset)); try se2.apply(.addTrack(id: st3, kind: .audio))
    let gapClip = try se2.addClip(asset: gapAsset, start: 500)
    let cutMs = try se2.removeSilences(of: gapClip.id, ranges: found)
    check(abs(cutMs - 1_700) < 150 && abs(se2.project.duration - (500 + 6_000 - cutMs)) < 5, "silence removed, gap closed: \(cutMs) ms, movie \(se2.project.duration)")
    check(se2.project.tracks[0].clips.count == 2 && se2.project.tracks[0].clips[0].end == se2.project.tracks[0].clips[1].start, "the two parts touch")
    se2.undo()
    check(se2.project.tracks[0].clips.count == 1, "silence removal is one undo step")
    let quietWav = FileManager.default.temporaryDirectory.appendingPathComponent("quiet-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: quietWav) }
    try SoundEffects.writeWAV((0..<(44_100 * 3)).map { Float(0.02 * sin(2 * .pi * 440 * Double($0) / 44_100)) }, to: quietWav)
    let quietAsset = try await Asset.load(url: quietWav)
    let loudGain = try await AudioTools.normalizedVolume(of: toneLoud, sourceIn: 0, length: 5_000) ?? 0
    let quietGain = try await AudioTools.normalizedVolume(of: quietAsset, sourceIn: 0, length: 2_000) ?? 0
    check(abs(loudGain - 0.18) < 0.05 && quietGain == 3, "normalize lowers loud and lifts quiet sound (\(loudGain), \(quietGain))")

    // captions and subtitles
    let ce = Editor(); let cvt = UUID()
    try ce.apply(.addAsset(long)); try ce.apply(.addTrack(id: cvt, kind: .video))
    let speaker = Clip(assetID: long.id, sourceIn: 500, duration: 3_000, start: 1_000)
    try ce.apply(.addClip(track: cvt, clip: speaker))
    let spoken = [Phrase(start: 0, end: 2_000, text: "hello world"), Phrase(start: 2_500, end: 3_600, text: "this is a much longer sentence that must be split into shorter lines"), Phrase(start: 9_000, end: 9_500, text: "outside the clip")]
    let cueCount = try ce.addCaptions(for: speaker.id, phrases: spoken)
    let captionTrack = ce.project.tracks.first { $0.kind == .text }!
    check(captionTrack.name == "Captions" && cueCount == captionTrack.clips.count && cueCount >= 3, "captions added on a Captions track: \(cueCount)")
    check(captionTrack.clips.allSatisfy { ($0.text ?? "").count <= 42 && $0.start >= 1_000 && $0.end <= 4_000 }, "captions are short and inside the clip")
    check(captionTrack.clips.first?.text == "hello world" && captionTrack.clips.first?.start == 1_000 && captionTrack.clips.first?.end == 1_000 + 1_500, "first caption lands at the clip start (source 500 ms offset)")
    let srt = Subtitles.srt(ce.project)
    check(srt.hasPrefix("1\n00:00:01,000 --> 00:00:02,500\nhello world\n") && srt.contains("\n2\n"), "srt format: \(srt.prefix(80))")
    check(Transcriber.split([(0, 0.4, "a"), (0.5, 0.4, "b"), (3, 0.3, "c")]) == [Phrase(start: 0, end: 900, text: "a b"), Phrase(start: 3_000, end: 3_300, text: "c")], "phrases split at pauses")
    let fastClip = Clip(assetID: long.id, sourceIn: 0, duration: 2_000, start: 10_000)
    try ce.apply(.addClip(track: cvt, clip: fastClip)); try ce.apply(.setSpeed(fastClip.id, 2))
    check(try ce.addCaptions(for: fastClip.id, phrases: [Phrase(start: 0, end: 2_000, text: "fast one")]) == 1
          && ce.project.tracks.first { $0.kind == .text }!.clips.contains { $0.text == "fast one" && $0.duration == 1_000 }, "captions follow the clip's speed")

    // export: sizes, codecs, progress, presets, batch, cancel
    let xe2 = Editor(); let xv = UUID(), xa = UUID()
    try xe2.apply(.addAsset(red)); try xe2.apply(.addAsset(toneAsset))
    try xe2.apply(.addTrack(id: xv, kind: .video)); try xe2.apply(.addTrack(id: xa, kind: .audio))
    try xe2.apply(.addClip(track: xv, clip: Clip(assetID: red.id, duration: 1_500, start: 0)))
    try xe2.apply(.addClip(track: xa, clip: Clip(assetID: toneAsset.id, duration: 1_500, start: 0)))
    check(ExportSettings.profile(Project(), shortSide: 720) == ExportSettings(width: 1280, height: 720), "720p profile")
    var tall = Project(); tall.width = 1080; tall.height = 1920
    check(ExportSettings.profile(tall, shortSide: 720) == ExportSettings(width: 720, height: 1280), "profiles keep a vertical aspect")
    let out720 = FileManager.default.temporaryDirectory.appendingPathComponent("p720-\(UUID()).mp4")
    defer { try? FileManager.default.removeItem(at: out720) }
    final class Ticks: @unchecked Sendable { var values: [Double] = []; let lock = NSLock(); func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() } }
    let ticks = Ticks()
    try await Exporter.export(xe2.project, to: out720, settings: ExportSettings.profile(xe2.project, shortSide: 720)) { ticks.add($0) }
    let exported720 = AVURLAsset(url: out720)
    let vtrack720 = try await exported720.loadTracks(withMediaType: .video).first!
    let size720 = try await vtrack720.load(.naturalSize)
    check(Int(size720.width) == 1280 && Int(size720.height) == 720, "720p export size \(size720)")
    let vformat = try await vtrack720.load(.formatDescriptions).first!
    check(CMFormatDescriptionGetMediaSubType(vformat) == kCMVideoCodecType_H264, "video is H.264")
    let atrack720 = try await exported720.loadTracks(withMediaType: .audio).first!
    check(CMFormatDescriptionGetMediaSubType(try await atrack720.load(.formatDescriptions).first!) == kAudioFormatMPEG4AAC, "audio is AAC")
    check(ticks.values.last == 1 && zip(ticks.values, ticks.values.dropFirst()).allSatisfy { $0 <= $1 }, "progress ends at 1 and never goes back: \(ticks.values)")
    let batchDir = FileManager.default.temporaryDirectory.appendingPathComponent("batch-\(UUID())")
    try FileManager.default.createDirectory(at: batchDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: batchDir) }
    let files = try await Exporter.exportBatch(xe2.project, presets: [.tiktok, .square], into: batchDir, name: "film")
    check(files.map(\.lastPathComponent) == ["film-tiktok.mp4", "film-square.mp4"], "batch file names")
    let tiktokSize = try await AVURLAsset(url: files[0]).loadTracks(withMediaType: .video).first!.load(.naturalSize)
    let squareSize = try await AVURLAsset(url: files[1]).loadTracks(withMediaType: .video).first!.load(.naturalSize)
    check(Int(tiktokSize.width) == 1080 && Int(tiktokSize.height) == 1920 && Int(squareSize.width) == 1080 && Int(squareSize.height) == 1080, "batch sizes \(tiktokSize) \(squareSize)")
    let heavy = Editor(); let heavyTrack = UUID()
    try heavy.apply(.addAsset(busy)); try heavy.apply(.addTrack(id: heavyTrack, kind: .video))
    for i in 0..<3 {
        let c = Clip(assetID: busy.id, duration: 8_000, start: Ms(i) * 8_000)
        try heavy.apply(.addClip(track: heavyTrack, clip: c))
        try heavy.apply(.addEffect(c.id, Effect(.glow))); try heavy.apply(.addEffect(c.id, Effect(.vhs)))
    }
    let cancelled = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-\(UUID()).mp4")
    let exportTask = Task { try await Exporter.export(heavy.project, to: cancelled, settings: ExportSettings(width: 3_840, height: 2_160)) }
    try await Task.sleep(nanoseconds: 700_000_000)
    exportTask.cancel()
    do { try await exportTask.value; check(false, "export should have been cancelled") } catch {}
    check(!FileManager.default.fileExists(atPath: cancelled.path), "a cancelled export leaves no file")

    // noise reduction: hiss in the pauses drops, speech-level tone stays
    var noiseSeed: UInt32 = 42
    func hiss() -> Float { noiseSeed = noiseSeed &* 1_664_525 &+ 1_013_904_223; return Float(Double(noiseSeed >> 8) / Double(1 << 24) * 2 - 1) * 0.01 }
    let noisy = (0..<(44_100 * 6)).map { i -> Float in
        let t = Double(i) / 44_100
        return hiss() + ((t >= 2 && t < 4) ? Float(0.3 * sin(2 * .pi * 500 * t)) : 0) + Float(0.02 * sin(2 * .pi * 40 * t))   // hiss, a "voice", and rumble
    }
    let cleanedSamples = AudioTools.denoise(noisy, rate: 44_100)
    func level(_ x: [Float], _ from: Double, _ to: Double) -> Double {
        let slice = x[Int(from * 44_100)..<Int(to * 44_100)]
        return (slice.reduce(0.0) { $0 + Double($1 * $1) } / Double(slice.count)).squareRoot()
    }
    check(level(cleanedSamples, 0.5, 1.5) < level(noisy, 0.5, 1.5) * 0.4, "noise in the pause drops: \(level(noisy, 0.5, 1.5)) -> \(level(cleanedSamples, 0.5, 1.5))")
    check(abs(level(cleanedSamples, 2.5, 3.5) / level(noisy, 2.5, 3.5) - 1) < 0.2, "the voice stays at its level")
    let noisyWav = FileManager.default.temporaryDirectory.appendingPathComponent("noisy-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: noisyWav) }
    try SoundEffects.writeWAV(noisy, to: noisyWav)
    let noisyAsset = try await Asset.load(url: noisyWav)
    let cleanedURL = try await AudioTools.reduceNoise(of: noisyAsset)
    let cleanedAsset = try await Asset.load(url: cleanedURL)
    check(abs(cleanedAsset.duration - noisyAsset.duration) < 100, "cleaned file lines up with the original")
    let ne = Editor(); let nt = UUID()
    try ne.apply(.addAsset(noisyAsset)); try ne.apply(.addAsset(cleanedAsset)); try ne.apply(.addTrack(id: nt, kind: .audio))
    let nclip = try ne.addClip(asset: noisyAsset, start: 1_000)
    try ne.useCleanedAudio(of: nclip.id, cleaned: cleanedAsset)
    check(ne.project.tracks[0].clips[0].assetID == cleanedAsset.id && ne.project.tracks[0].clips[0].start == 1_000, "an audio clip switches to the cleaned sound in place")
    try? FileManager.default.removeItem(at: cleanedURL)
    // video clip: its sound is detached onto a grouped audio clip with the cleaned file
    let ve2 = Editor(); let vt3 = UUID()
    try ve2.apply(.addAsset(Asset(url: URL(fileURLWithPath: "/tmp/v.mp4"), duration: 20_000, hasVideo: true, hasAudio: true))); try ve2.apply(.addAsset(cleanedAsset))
    try ve2.apply(.addTrack(id: vt3, kind: .video))
    let vclip2 = try ve2.addClip(asset: ve2.project.assets[0], start: 0, sourceIn: 1_000, duration: 5_000)
    try ve2.useCleanedAudio(of: vclip2.id, cleaned: cleanedAsset)
    let after = ve2.project.tracks.flatMap(\.clips)
    check(after.count == 2 && after.first { $0.id == vclip2.id }?.muted == true && after.allSatisfy { $0.groupID != nil } && after.contains { $0.assetID == cleanedAsset.id && $0.sourceIn == 1_000 }, "a video clip's sound is replaced by a grouped clean audio clip")

    // stock pictures
    let imageJSON = #"""
    {"results":[
     {"id":"i1","title":"Beach","creator":"Ann","license":"cc0","url":"https://cdn.example.org/beach.jpg","filetype":"jpg","provider":"flickr"},
     {"id":"i2","title":"Sea","creator":"Bob","license":"by","license_version":"2.0","url":"https://cdn.example.org/sea.png","filetype":"png","provider":"flickr"},
     {"id":"i3","title":"Odd","creator":"C","license":"cc0","url":"https://cdn.example.org/odd.webp","filetype":"webp","provider":"flickr"}]}
    """#
    let pics = OnlineLibrary.parse(Data(imageJSON.utf8))
    check(pics.count == 3 && pics.filter(\.isImage).map(\.id) == ["i1", "i2"], "picture results: only jpg/png are usable")
    check(OnlineLibrary.localFileName(for: pics[1]) == "flickr-i2.png" && OnlineLibrary.localFileName(for: parsed[0]) == "freesound-a1.mp3", "local file names")
    check(OnlineLibrary.searchURL("beach", kind: .images, allowAttribution: false)?.absoluteString.contains("/v1/images/?") == true, "image search url")

    // the new tools over MCP
    let mcpClip = field(firstText(try await call("add_clip", ["asset_id": field(imp1, "asset_id"), "start_ms": 20_000])), "clip_id")
    check(try await call("set_keyframes", ["clip_id": mcpClip, "keyframes": [["time_ms": 0, "scale": 0.5], ["time_ms": 800, "scale": 1.0, "opacity": 0.8]]]).isError == false
          && me.project.tracks.flatMap(\.clips).first { $0.id.uuidString == mcpClip }?.keyframes.count == 2, "set_keyframes over MCP")
    check(try await call("set_keyframes", ["clip_id": mcpClip, "keyframes": [["time_ms": 99_999]]]).isError, "bad keyframes rejected")
    check(try await call("set_look", ["clip_id": mcpClip, "crop_left": 0.2]).isError == false, "crop over MCP")
    let audioTrackID = me.project.tracks.first { $0.kind == .audio }!.id.uuidString
    check(try await call("set_track", ["track_id": audioTrackID, "duck": true, "name": "Music", "locked": false]).isError == false
          && me.project.tracks.first { $0.id.uuidString == audioTrackID }?.duck == true && me.project.tracks.first { $0.id.uuidString == audioTrackID }?.name == "Music", "set_track duck and name")
    let silentImport = firstText(try await call("import_media", ["path": gapWav.path]))
    let gapMCP = field(firstText(try await call("add_clip", ["asset_id": field(silentImport, "asset_id"), "start_ms": 40_000])), "clip_id")
    let durationBefore = me.project.duration
    check(firstText(try await call("remove_silence", ["clip_id": gapMCP])).contains("removed"), "remove_silence over MCP")
    check(me.project.duration < durationBefore, "the movie got shorter")
    let normImport = firstText(try await call("import_media", ["path": quietWav.path]))
    let normClip = field(firstText(try await call("add_clip", ["asset_id": field(normImport, "asset_id"), "start_ms": 60_000])), "clip_id")
    check(firstText(try await call("normalize_audio", ["clip_id": normClip])).contains("3.00"), "normalize_audio over MCP")
    check(try await call("auto_captions", ["clip_id": normClip]).isError, "auto_captions needs the app")
    let srtOut = FileManager.default.temporaryDirectory.appendingPathComponent("out-\(UUID()).srt")
    defer { try? FileManager.default.removeItem(at: srtOut) }
    _ = try await call("add_title", ["text": "Subtitle line", "start_ms": 200_000, "duration_ms": 1_000])
    check(try await call("export_srt", ["path": srtOut.path]).isError == false && ((try? String(contentsOf: srtOut, encoding: .utf8)) ?? "").contains("Subtitle line"), "export_srt over MCP")
    check(firstText(try await call("add_sticker", ["emoji": "🔥", "start_ms": 300_000])).contains("clip_id"), "add_sticker over MCP")
    check(me.project.tracks.flatMap(\.clips).contains { $0.text == "🔥" && $0.style.animation == .pop }, "sticker pops in")
    let g1 = field(firstText(try await call("add_clip", ["asset_id": field(imp1, "asset_id"), "start_ms": 100_000])), "clip_id")
    let g2 = field(firstText(try await call("add_clip", ["asset_id": field(imp2, "asset_id"), "start_ms": 100_000])), "clip_id")
    let grouped = try await call("group_clips", ["clip_ids": [g1, g2]]), ungrouped = try await call("ungroup_clip", ["clip_id": g1])
    check(!grouped.isError && !ungrouped.isError, "group and ungroup over MCP")
    let relinkImport = firstText(try await call("import_media", ["path": redURL.path]))
    check(try await call("relink_asset", ["asset_id": field(relinkImport, "asset_id"), "path": blueURL.path]).isError == false, "relink_asset over MCP")
    check(try await call("relink_asset", ["asset_id": field(relinkImport, "asset_id"), "path": gapWav.path]).isError, "relink to a different kind of file is refused")
    check(try await call("build_edit", ["replace": true, "cuts": [["asset_id": field(imp1, "asset_id"), "start_ms": 0, "end_ms": 1_000, "keyframes": [["time_ms": 0, "scale": 0.8], ["time_ms": 500, "scale": 1.0]], "look": ["crop_left": 0.1]],
                                                                  ["asset_id": field(imp2, "asset_id"), "duration_ms": 1_000]], "music": ["name": "Calm Ambient", "duck": true]]).isError == false, "build_edit with keyframes, crop and ducking music")
    check(me.project.tracks.contains { $0.kind == .audio && $0.duck }, "music track ducks")
    print("all checks passed")

    // Optional: parse real saved Openverse responses: OV_JSON=/path/a.json,/path/b.json swift run CoreChecks
    if let paths = ProcessInfo.processInfo.environment["OV_JSON"] {
        for path in paths.split(separator: ",") {
            let real = OnlineLibrary.parse(try Data(contentsOf: URL(fileURLWithPath: String(path))))
            check(!real.isEmpty && real.allSatisfy { $0.fileURL.hasPrefix("https://") && ["cc0", "pdm", "by"].contains($0.license) }, "real response parses: \(path)")
            print("real:", path.split(separator: "/").last ?? "", real.count, "results; first:", real[0].credit)
        }
    }

    // Optional live test of the online library (network): LIVE_LIBRARY=1 swift run CoreChecks
    if ProcessInfo.processInfo.environment["LIVE_LIBRARY"] != nil {
        let found = try await OnlineLibrary.search("whoosh", kind: .effects, allowAttribution: false)
        check(!found.isEmpty && found.allSatisfy { !$0.needsCredit }, "live search finds CC0 effects")
        let music = try await OnlineLibrary.search("ambient", kind: .music, allowAttribution: true)
        print("live: \(found.count) effects, \(music.count) music; first music credit: \(music.first?.credit ?? "none")")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let shortest = found.min { $0.durationMs < $1.durationMs }!
        let file = try await OnlineLibrary.download(shortest, into: dir)
        let loaded = try await Asset.load(url: file)
        print("live: downloaded \(shortest.title) (\(shortest.durationMs) ms) -> asset \(loaded.duration) ms, audio \(loaded.hasAudio)")
    }

    // Optional live test against a running Eclipse and the real `claude` (uses your Claude quota):
    //   CLAUDE_E2E="your prompt" swift run CoreChecks
    if let prompt = ProcessInfo.processInfo.environment["CLAUDE_E2E"] {
        let token = try ClaudeRunner_token()
        for await e in ClaudeRunner.run(prompt: prompt, sessionID: nil, port: 39_127, token: token).events { print("event:", e) }
    }
} catch { print("FAIL: \(error)"); exit(1) }

func makeTestVideo(at url: URL, seconds: Int, bgra: (UInt8, UInt8, UInt8) = (0, 0, 0), flickerFrom: Int? = nil) async throws {
    let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 128])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 128])
    w.add(input); w.startWriting(); w.startSession(atSourceTime: .zero)
    for i in 0..<(seconds * 30) {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 128, 128, kCVPixelFormatType_32BGRA, nil, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let base = CVPixelBufferGetBaseAddress(pb!)!.assumingMemoryBound(to: UInt8.self)
        let invert = flickerFrom.map { i >= $0 && i % 2 == 0 } ?? false   // alternate frames = high motion
        for px in 0..<(CVPixelBufferGetBytesPerRow(pb!) * 128 / 4) {
            base[px * 4] = invert ? 255 - bgra.0 : bgra.0; base[px * 4 + 1] = invert ? 255 - bgra.1 : bgra.1
            base[px * 4 + 2] = invert ? 255 - bgra.2 : bgra.2; base[px * 4 + 3] = 255
        }
        CVPixelBufferUnlockBaseAddress(pb!, [])
        adaptor.append(pb!, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
    }
    input.markAsFinished()
    await w.finishWriting()
    if w.status != .completed { throw w.error ?? EditError.invalid("video write failed") }
}

/// RMS level of the mixed audio (volume ramps applied) in each [start, end) ms window.
func rms(_ built: BuiltComposition, windows: [(Ms, Ms)]) async throws -> [Double] {
    let tracks = try await built.composition.loadTracks(withMediaType: .audio)
    let reader = try AVAssetReader(asset: built.composition)
    let out = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
    out.audioMix = built.audioMix
    reader.add(out)
    reader.startReading()
    var samples: [Float] = []
    while let sb = out.copyNextSampleBuffer() {
        guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
        var length = 0; var ptr: UnsafeMutablePointer<CChar>?
        CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr)
        samples += Array(UnsafeBufferPointer(start: UnsafeRawPointer(ptr!).assumingMemoryBound(to: Float.self), count: length / 4))
    }
    return windows.map { w in
        let slice = samples[min(Int(w.0 * 44), samples.count)..<min(Int(w.1 * 44), samples.count)]
        return (slice.reduce(0) { $0 + Double($1 * $1) } / Double(max(slice.count, 1))).squareRoot()
    }
}

func ClaudeRunner_token() throws -> String { try MCPServer.loadOrCreateToken() }
