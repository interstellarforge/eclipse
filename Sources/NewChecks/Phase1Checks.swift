import AVFoundation
import Foundation
import MovieCore

@MainActor
func runPhase1Checks(_ f: Fixtures) async throws {
    // favourites and renaming
    let e = Editor()
    try e.apply(.addAsset(f.red))
    try e.apply(.setAssetFavorite(f.red.id, true))
    try e.apply(.renameAsset(f.red.id, "  Hero shot "))
    check(e.project.assets[0].favorite && e.project.assets[0].label == "Hero shot", "favourite and rename")
    try e.apply(.renameAsset(f.red.id, ""))
    check(e.project.assets[0].label == f.red.url.lastPathComponent, "empty name restores the file name")
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(f.red)) as! [String: Any]
    legacy["favorite"] = nil
    check(try JSONDecoder().decode(Asset.self, from: JSONSerialization.data(withJSONObject: legacy)).favorite == false, "old assets decode")
    var oldTrack = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Track(kind: .audio))) as! [String: Any]
    oldTrack["duckLevel"] = nil
    check(try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: oldTrack)).duckLevel == 0.3, "old tracks get the default duck level")

    // asset info
    let info = await AssetInfo.load(f.busy)
    check(info.video?.contains("128x128") == true && info.video?.contains("30 fps") == true && info.video?.contains("H.264") == true && info.audio == nil && info.fileSize > 1_000, "video info: \(info.video ?? "nil")")
    let toneURL = try writeTone(1, amplitude: 0.3); defer { try? FileManager.default.removeItem(at: toneURL) }
    let toneInfo = await AssetInfo.load(try await Asset.load(url: toneURL))
    check(toneInfo.video == nil && toneInfo.audio?.contains("PCM") == true && toneInfo.audio?.contains("44.1 kHz") == true && toneInfo.audio?.contains("mono") == true, "audio info: \(toneInfo.audio ?? "nil")")

    // reset a clip to plain
    let r = Editor(); let rt = UUID()
    try r.apply(.addAsset(f.busy)); try r.apply(.addTrack(id: rt, kind: .video))
    let clip = try r.addClip(asset: f.busy, start: 0, duration: 4_000)
    var look = Look(); look.saturation = 0; look.cropLeft = 0.2; look.rotation = 30
    try r.apply(.setLook(clip.id, look)); try r.apply(.setSpeed(clip.id, 2)); try r.apply(.addEffect(clip.id, Effect(.glow)))
    try r.apply(.setTransform(clip.id, opacity: 0.5, scale: 2, offsetX: 0.1, offsetY: 0)); try r.apply(.setVolume(clip.id, volume: 0.4, fadeIn: 200, fadeOut: 200))
    try r.apply(.setKeyframes(clip.id, [Keyframe(time: 0), Keyframe(time: 500, scale: 2)])); try r.apply(.setMuted(clip.id, true))
    try r.resetClip(clip.id)
    let plain = r.project.tracks[0].clips[0]
    check(plain.look == Look() && plain.speed == 1 && plain.effects.isEmpty && plain.keyframes.isEmpty && plain.opacity == 1 && plain.scale == 1
          && plain.volume == 1 && plain.fadeIn == 0 && !plain.muted && plain.duration == 4_000, "reset gives a plain clip \(plain)")
    r.undo()
    check(r.project.tracks[0].clips[0].effects.count == 1, "reset is one undo step")
    let title = try r.addTitle("Keep me", start: 20_000)
    var style = TextStyle(); style.colorHex = "FF0000"
    try r.apply(.setTextStyle(title.id, style)); try r.apply(.setVolume(title.id, volume: 1, fadeIn: 100, fadeOut: 0))
    try r.resetClip(title.id)
    let keptTitle = r.project.tracks.flatMap(\.clips).first { $0.id == title.id }!
    check(keptTitle.text == "Keep me" && keptTitle.style.colorHex == "FF0000" && keptTitle.fadeIn == 0, "a title keeps its text and style")

    // duck level: a shallower dip leaves more music under the voice
    let loudURL = try writeTone(6, amplitude: 0.8, freq: 300), voiceURL = try writeTone(2, amplitude: 0.3, freq: 880)
    defer { try? FileManager.default.removeItem(at: loudURL); try? FileManager.default.removeItem(at: voiceURL) }
    let loud = try await Asset.load(url: loudURL), voice = try await Asset.load(url: voiceURL)
    let d = Editor(); let music = UUID(), speech = UUID()
    try d.apply(.addAsset(loud)); try d.apply(.addAsset(voice))
    try d.apply(.addTrack(id: music, kind: .audio)); try d.apply(.addTrack(id: speech, kind: .audio))
    try d.apply(.addClip(track: music, clip: Clip(assetID: loud.id, duration: 6_000, start: 0)))
    try d.apply(.addClip(track: speech, clip: Clip(assetID: voice.id, duration: 2_000, start: 3_000, volume: 0.06)))
    try d.apply(.setTrackDuck(music, true))
    let deep = try await rms(try await CompositionBuilder.build(d.project), windows: [(3_700, 4_700)])[0]
    try d.apply(.setTrackDuckLevel(music, 0.7))
    let shallow = try await rms(try await CompositionBuilder.build(d.project), windows: [(3_700, 4_700)])[0]
    check(shallow > deep * 1.8, "a higher duck level keeps more music: \(deep) vs \(shallow)")
    do { try d.apply(.setTrackDuckLevel(music, 2)); check(false, "level 2") } catch {}

    // tools over MCP
    let h = try await McpHarness(editor: Editor()); defer { h.stop() }
    let imported = try await h.call("import_media", ["path": f.busy.url.path])
    let assetID = McpHarness.field(imported.text, "asset_id")
    let infoText = try await h.call("asset_info", ["asset_id": assetID]).text
    check(infoText.contains("128x128") && infoText.contains("used in 0 clips"), "asset_info over MCP: \(infoText)")
    let added = try await h.call("add_clip", ["asset_id": assetID])
    let cid = McpHarness.field(added.text, "clip_id")
    try await h.call("set_look", ["clip_id": cid, "saturation": 0.2])
    try await h.call("reset_clip", ["clip_id": cid])
    check(h.editor.project.tracks.flatMap(\.clips)[0].look == Look(), "reset_clip over MCP")
    let trackID = try await h.call("add_track", ["kind": "audio"]).text
    check(try await h.call("set_track", ["track_id": McpHarness.field(trackID, "track_id"), "duck": true, "duck_level": 0.5]).isError == false
          && h.editor.project.tracks.last?.duckLevel == 0.5, "duck_level over MCP")
}
