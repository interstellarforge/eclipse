import AVFoundation
import Foundation

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

struct Args {
    let d: [String: Any]
    func str(_ k: String) throws -> String {
        guard let v = d[k] as? String else { throw ToolError("missing string argument '\(k)'") }
        return v
    }
    func ms(_ k: String) throws -> Ms {
        guard let v = optMs(k) else { throw ToolError("missing number argument '\(k)'") }
        return v
    }
    func optMs(_ k: String) -> Ms? { (d[k] as? NSNumber).map { Ms(truncating: $0) } }
    func optDouble(_ k: String) -> Double? { (d[k] as? NSNumber)?.doubleValue }
    func optStr(_ k: String) -> String? { d[k] as? String }
    func id(_ k: String) throws -> UUID {
        guard let v = UUID(uuidString: try str(k)) else { throw ToolError("'\(k)' is not a valid id") }
        return v
    }
    func optID(_ k: String) -> UUID? { optStr(k).flatMap(UUID.init) }
}

extension Args {
    /// Applies any text-style keys present (size, color, x, y, bold, shadow, font, align, outline, box) on top of `base`.
    func textStyle(_ base: TextStyle) -> TextStyle {
        var st = base
        if let v = optDouble("size") { st.size = v }
        if let v = optStr("color") { st.colorHex = v }
        if let v = optDouble("x") { st.x = v }
        if let v = optDouble("y") { st.y = v }
        if let v = d["bold"] as? Bool { st.bold = v }
        if let v = d["shadow"] as? Bool { st.shadow = v }
        if let v = optStr("font") { st.fontName = v }
        if let v = optStr("align") { st.align = ["left": 0, "center": 1, "right": 2][v] ?? 1 }
        if let v = d["outline"] as? Bool { st.outline = v }
        if let v = d["box"] as? Bool { st.box = v }
        if let v = optStr("animation") { st.animation = TextAnimation(rawValue: v) ?? st.animation }
        if let v = optDouble("tracking") { st.tracking = v }
        if let v = d["uppercase"] as? Bool { st.uppercase = v }
        if let v = d["glow"] as? Bool { st.glow = v }
        if let v = optMs("animation_ms") { st.animationMs = v }
        return st
    }

    /// A keyframe from {time_ms, opacity, scale, offset_x, offset_y, rotation, smooth}.
    func keyframe() -> Keyframe {
        Keyframe(time: optMs("time_ms") ?? 0, opacity: optDouble("opacity") ?? 1, scale: optDouble("scale") ?? 1, offsetX: optDouble("offset_x") ?? 0,
                 offsetY: optDouble("offset_y") ?? 0, rotation: optDouble("rotation") ?? 0, smooth: d["smooth"] as? Bool ?? true)
    }

    /// Look fields present in the arguments, on top of `base`.
    func look(_ base: Look) -> Look {
        var l = base
        if let v = optDouble("brightness") { l.brightness = v }
        if let v = optDouble("contrast") { l.contrast = v }
        if let v = optDouble("saturation") { l.saturation = v }
        if let v = optDouble("sepia") { l.sepia = v }
        if let v = optDouble("blur") { l.blur = v }
        if let v = optDouble("vignette") { l.vignette = v }
        if let v = d["flip_horizontal"] as? Bool { l.flipX = v }
        if let v = d["flip_vertical"] as? Bool { l.flipY = v }
        if let v = optDouble("rotation") { l.rotation = v }
        if let v = optDouble("crop_left") { l.cropLeft = v }
        if let v = optDouble("crop_right") { l.cropRight = v }
        if let v = optDouble("crop_top") { l.cropTop = v }
        if let v = optDouble("crop_bottom") { l.cropBottom = v }
        if let v = optDouble("warmth") { l.warmth = v }
        if let v = optDouble("fade") { l.fade = v }
        if let v = optDouble("sharpen") { l.sharpen = v }
        if let v = optStr("split_shadows") { l.splitShadows = v.isEmpty ? nil : v }
        if let v = optStr("split_highlights") { l.splitHighlights = v.isEmpty ? nil : v }
        if let v = optDouble("split_amount") { l.splitAmount = v }
        return l
    }
}

/// One answer Claude offers in ask_user. `info` explains what the choice means and what Claude will do for the edit (shown on hover).
public struct AskOption: Equatable {
    public var label: String
    public var info: String
    public init(_ label: String, info: String = "") { self.label = label; self.info = info }
}

/// Things the app provides that the core can't do alone (thumbnails, playhead).
public struct MCPHost {
    public var importMedia: @MainActor (URL) async throws -> Asset
    public var playhead: @MainActor () -> Ms
    /// Shows a question to the user and returns the answer (a chosen option or typed text).
    public var ask: @MainActor (_ question: String, _ options: [AskOption], _ allowText: Bool) async -> String
    /// Opens the range picker (offline mode): the user marks start and end of the parts they want; returns them as text.
    public var pickRanges: @MainActor (_ reason: String, _ assetIDs: [UUID]) async -> String
    /// Shows a drafted script for the user to edit and approve; returns "APPROVED ..." or "CHANGES REQUESTED ...".
    public var reviewScript: @MainActor (_ draft: ScriptDraft) async -> String
    /// The folders the user opened in the Files tab.
    public var workspaceRoots: @MainActor () -> [URL]
    public init(importMedia: @escaping @MainActor (URL) async throws -> Asset, playhead: @escaping @MainActor () -> Ms,
                ask: @escaping @MainActor (String, [AskOption], Bool) async -> String = { _, _, _ in "(the app cannot ask the user here; choose sensible defaults and say what you chose)" },
                pickRanges: @escaping @MainActor (String, [UUID]) async -> String = { _, _ in "(the app cannot show the range picker here; ask the user in words)" },
                reviewScript: @escaping @MainActor (ScriptDraft) async -> String = { _ in "APPROVED (the app cannot show the script window here)" },
                workspaceRoots: @escaping @MainActor () -> [URL] = { [] }) {
        self.importMedia = importMedia; self.playhead = playhead; self.ask = ask; self.pickRanges = pickRanges
        self.reviewScript = reviewScript; self.workspaceRoots = workspaceRoots
    }
}

typealias Content = [[String: Any]]

struct Tool {
    let name: String
    let description: String
    let properties: [String: [String: Any]]
    let required: [String]
    let run: @MainActor (Args) async throws -> Content

    var definition: [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required] as [String: Any]]
    }
}

private func text(_ s: String) -> Content { [["type": "text", "text": s]] }
private func prop(_ type: String, _ desc: String) -> [String: Any] { ["type": type, "description": desc] }
private let idDesc = "Clip id from get_project"

@MainActor
func makeTools(editorProvider: @escaping @MainActor () -> Editor, host: MCPHost) -> [Tool] {
    var editor: Editor { editorProvider() }   // re-read on every call: a ghost edit swaps the editor underneath
    func clip(_ id: UUID) throws -> Clip {
        guard let c = editor.project.tracks.flatMap(\.clips).first(where: { $0.id == id }) else { throw ToolError("clip not found") }
        return c
    }
    var onlineResults: [String: OnlineSound] = [:]   // search results by id, so import_online_sound can find them
    func describe(_ c: Clip) -> String { "clip_id=\(c.id.uuidString) start_ms=\(c.start) duration_ms=\(c.duration)" }

    return [
        Tool(name: "ask_user",
             description: "Asks the user ONE question in the app and waits for the answer. Give 2-5 options (the first can be your recommendation); the user can also type their own answer. Every option should be {label, info}: label is a short answer, info is one or two plain sentences saying what that choice means and what you will do differently in the edit (the user sees it on hover). Use it for guided edits and for creative choices that matter. Do not ask what you can see or measure yourself.",
             properties: ["question": prop("string", "The question, one short sentence"),
                          "options": ["type": "array", "items": [:] as [String: Any], "description": "2-5 answers: each {label, info} (a plain string also works). info = what it means and what you will do for the edit"],
                          "allow_text": prop("boolean", "Let the user type something else. Default true")], required: ["question"]) { a in
            let options: [AskOption] = ((a.d["options"] as? [Any]) ?? []).compactMap { raw in
                if let label = raw as? String { return AskOption(label) }
                if let o = raw as? [String: Any], let label = o["label"] as? String { return AskOption(label, info: (o["info"] as? String) ?? (o["description"] as? String) ?? "") }
                return nil
            }
            let answer = await host.ask(try a.str("question"), options, a.d["allow_text"] as? Bool ?? true)
            return text("The user answered: \(answer)")
        },
        Tool(name: "request_selection",
             description: "OFFLINE MODE: opens a viewer in the app where the user watches their video files one by one and marks 'start here' and 'end here' for the parts that matter. Waits until they press Done and returns, per file, the ranges in milliseconds (use them as start_ms/end_ms in build_edit). You cannot see the footage yourself. Call it once, early.",
             properties: ["reason": prop("string", "One short sentence shown to the user, e.g. 'Mark the best moments of each clip'"),
                          "asset_ids": ["type": "array", "items": ["type": "string"], "description": "Optional: only these files (ids from get_project). Default all videos"]], required: ["reason"]) { a in
            let ids = ((a.d["asset_ids"] as? [String]) ?? []).compactMap(UUID.init(uuidString:))
            return text(await host.pickRanges(a.optStr("reason") ?? "Mark the parts that matter", ids))
        },
        Tool(name: "browse_folder",
             description: "Lists a folder the user opened in the Files tab (names, kinds, sizes, and the length and resolution of videos and audio, read from file headers only: nothing is decoded or viewed). Without a path it lists the opened folders. Paths outside them are refused. Use it to tell the user what a folder contains and what looks usable, then import_media the files that are needed.",
             properties: ["path": prop("string", "Absolute path of an opened folder or a folder inside one. Omit to list the opened folders"), "depth": prop("integer", "How many levels to show, 1...3 (default 1)")], required: []) { a in
            let roots = host.workspaceRoots()
            guard let path = a.optStr("path") else {
                return text(roots.isEmpty ? "No folders are open. Ask the user to open one with the Files tab (Open folder…)." : "Opened folders:\n" + roots.map { "- \($0.path)" }.joined(separator: "\n"))
            }
            let url = URL(fileURLWithPath: path)
            guard Workspace.isInside(url, roots: roots) else { throw ToolError("That folder is not open in the Files tab. Opened folders: \(roots.map(\.path).joined(separator: ", "))") }
            guard Workspace.isFolder(url) else { throw ToolError("not a folder") }
            return text(await Workspace.describe(url, depth: min(3, max(1, Int(a.optDouble("depth") ?? 1)))))
        },
        Tool(name: "propose_script",
             description: "SCRIPT MODES: shows the user a drafted script in a window where they can edit, reorder and approve it, and waits. Returns 'APPROVED' with the final script (build exactly that with build_edit) or 'CHANGES REQUESTED' with their feedback (revise and propose again). One beat per planned cut or title card.",
             properties: ["title": prop("string", "Working title of the film"), "logline": prop("string", "The idea in one or two sentences"),
                          "beats": ["type": "array", "description": "In playing order. Each: {title, detail, asset_id (optional), start_ms, end_ms (source range, optional), seconds (planned length), join (cut|crossfade|...), sound (keep|mute|music only...), text (title or caption, optional)}", "items": ["type": "object"]],
                          "notes": prop("string", "Music, look, alternative idea, anything else the user should know")], required: ["title", "beats"]) { a in
            let beats = ((a.d["beats"] as? [[String: Any]]) ?? []).map { raw -> ScriptBeat in
                let b = Args(d: raw)
                return ScriptBeat(title: b.optStr("title") ?? "", detail: b.optStr("detail") ?? "", assetID: b.optID("asset_id"), startMs: b.optMs("start_ms").map { Int($0) }, endMs: b.optMs("end_ms").map { Int($0) },
                                  seconds: b.optDouble("seconds") ?? 3, join: b.optStr("join") ?? "cut", sound: b.optStr("sound") ?? "", text: b.optStr("text") ?? "")
            }
            guard !beats.isEmpty else { throw ToolError("beats must not be empty") }
            let reply = await host.reviewScript(ScriptDraft(title: try a.str("title"), logline: a.optStr("logline") ?? "", beats: beats, notes: a.optStr("notes") ?? ""))
            if reply.hasPrefix("APPROVED") { ScriptMode.approved = true }
            return text(reply)
        },
        Tool(name: "list_skills",
             description: "Lists the director skills (editing craft guides). Start with director-brief for any creative request.",
             properties: [:], required: []) { _ in
            text(Skills.all().map { "\($0.name): \($0.summary)" }.joined(separator: "\n"))
        },
        Tool(name: "get_skill", description: "Returns the full text of a director skill by name (see list_skills).",
             properties: ["name": prop("string", "Skill name, e.g. director-brief")], required: ["name"]) { a in
            guard let skill = Skills.get(try a.str("name")) else { throw ToolError("unknown skill; call list_skills") }
            return text(skill.body)
        },
        Tool(name: "set_format",
             description: "Sets the movie canvas. Give a preset (16:9 = 1920x1080, 9:16 = 1080x1920, 1:1 = 1080x1080, 4:5 = 1080x1350) and/or width, height, fps. Clips are fitted inside; use set_transform to fill the frame.",
             properties: ["preset": ["type": "string", "enum": ["16:9", "9:16", "1:1", "4:5"], "description": "Aspect preset"],
                          "width": prop("integer", "Pixels, even"), "height": prop("integer", "Pixels, even"), "fps": prop("integer", "12...120, default keeps current")],
             required: []) { a in
            var (w, h) = (editor.project.width, editor.project.height)
            switch a.optStr("preset") {
            case "16:9": (w, h) = (1920, 1080)
            case "9:16": (w, h) = (1080, 1920)
            case "1:1": (w, h) = (1080, 1080)
            case "4:5": (w, h) = (1080, 1350)
            default: break
            }
            try editor.apply(.setFormat(width: a.optMs("width").map(Int.init) ?? w, height: a.optMs("height").map(Int.init) ?? h,
                                        fps: a.optMs("fps").map(Int.init) ?? editor.project.fps))
            return text("canvas \(editor.project.width)x\(editor.project.height) at \(editor.project.fps) fps")
        },
        Tool(name: "get_project",
             description: "Returns the whole project: assets, tracks with clips (times in ms), transitions, duration and playhead. Track 1 in the list is the top layer.",
             properties: [:], required: []) { _ in
            let data = try JSONEncoder().encode(editor.project)
            var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            obj["duration_ms"] = editor.project.duration
            obj["playhead_ms"] = host.playhead()
            let out = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
            return text(String(decoding: out, as: UTF8.self))
        },
        Tool(name: "import_media", description: "Imports a video or audio file (MP4/MOV/M4A/WAV/MP3...) by absolute path into the media bin.",
             properties: ["path": prop("string", "Absolute file path")], required: ["path"]) { a in
            let asset = try await host.importMedia(URL(fileURLWithPath: try a.str("path")))
            return text("asset_id=\(asset.id.uuidString) duration_ms=\(asset.duration) video=\(asset.hasVideo) audio=\(asset.hasAudio)")
        },
        Tool(name: "add_clip",
             description: "Puts an imported asset on the timeline. Defaults: appended after the last clip on the first matching track; whole asset.",
             properties: ["asset_id": prop("string", "Asset id"), "start_ms": prop("integer", "Timeline position"),
                          "source_in_ms": prop("integer", "Offset into the asset to start from"),
                          "duration_ms": prop("integer", "Length of the clip"),
                          "track_id": prop("string", "Specific track id")],
             required: ["asset_id"]) { a in
            let aid = try a.id("asset_id")
            guard let asset = editor.project.assets.first(where: { $0.id == aid }) else { throw ToolError("asset not found") }
            let c = try editor.addClip(asset: asset, start: a.optMs("start_ms"), sourceIn: a.optMs("source_in_ms") ?? 0,
                                       duration: a.optMs("duration_ms"), track: a.optID("track_id"))
            return text(describe(c))
        },
        Tool(name: "add_title", description: "Adds a text title overlay (drawn on top of the video).",
             properties: ["text": prop("string", "Title text"), "start_ms": prop("integer", "Default: playhead"),
                          "duration_ms": prop("integer", "Default 3000"),
                          "preset": ["type": "string", "enum": TitlePreset.allCases.map { $0.rawValue }, "description": "Ready-made style, see the titles-and-text skill"]], required: ["text"]) { a in
            let c = try editor.addTitle(try a.str("text"), start: a.optMs("start_ms") ?? host.playhead(), duration: a.optMs("duration_ms") ?? 3_000)
            if let name = a.optStr("preset") {
                guard let preset = TitlePreset.named(name) else { throw ToolError("unknown title style") }
                try editor.apply(.setTextStyle(c.id, preset.style))
            }
            return text(describe(c))
        },
        Tool(name: "set_title_text", description: "Changes the text of a title clip.",
             properties: ["clip_id": prop("string", idDesc), "text": prop("string", "New text")],
             required: ["clip_id", "text"]) { a in
            try editor.apply(.setText(try a.id("clip_id"), try a.str("text"))); return text("ok")
        },
        Tool(name: "move_clip", description: "Moves a clip to a new timeline position. Clips on a track may not overlap, except as a transition.",
             properties: ["clip_id": prop("string", idDesc), "start_ms": prop("integer", "New start")],
             required: ["clip_id", "start_ms"]) { a in
            try editor.apply(.moveClip(try a.id("clip_id"), start: try a.ms("start_ms"))); return text("ok")
        },
        Tool(name: "trim_clip", description: "Changes which part of the source a clip shows. Omitted values keep the current value.",
             properties: ["clip_id": prop("string", idDesc), "source_in_ms": prop("integer", "Offset into the source"),
                          "duration_ms": prop("integer", "New length"), "start_ms": prop("integer", "New timeline start")],
             required: ["clip_id"]) { a in
            let c = try clip(try a.id("clip_id"))
            try editor.apply(.trimClip(c.id, sourceIn: a.optMs("source_in_ms") ?? c.sourceIn,
                                       duration: a.optMs("duration_ms") ?? c.duration, start: a.optMs("start_ms") ?? c.start))
            return text("ok")
        },
        Tool(name: "split_clip", description: "Splits a clip in two at a timeline position inside it.",
             properties: ["clip_id": prop("string", idDesc), "at_ms": prop("integer", "Timeline position")],
             required: ["clip_id", "at_ms"]) { a in
            try editor.apply(.splitClip(try a.id("clip_id"), at: try a.ms("at_ms"))); return text("ok")
        },
        Tool(name: "remove_clip", description: "Deletes a clip (and its transitions). With ripple, later clips on the track move earlier to close the gap.",
             properties: ["clip_id": prop("string", idDesc), "ripple": prop("boolean", "Close the gap. Default false")],
             required: ["clip_id"]) { a in
            let id = try a.id("clip_id")
            try editor.apply(a.d["ripple"] as? Bool == true ? .rippleRemove(id) : .removeClip(id)); return text("ok")
        },
        Tool(name: "duplicate_clip", description: "Copies a clip to the end of its track.",
             properties: ["clip_id": prop("string", idDesc)], required: ["clip_id"]) { a in
            text(describe(try editor.duplicate(try a.id("clip_id"))))
        },
        Tool(name: "remove_asset", description: "Removes a file from the media library. Clips that use it are removed from the timeline too.",
             properties: ["asset_id": prop("string", "Asset id")], required: ["asset_id"]) { a in
            try editor.apply(.removeAsset(try a.id("asset_id"))); return text("ok")
        },
        Tool(name: "set_speed", description: "Plays a clip faster or slower (0.1...8, 1 = normal). The clip gets shorter or longer on the timeline and later clips on the track move with it.",
             properties: ["clip_id": prop("string", idDesc), "speed": prop("number", "Speed factor")], required: ["clip_id", "speed"]) { a in
            guard let speed = a.optDouble("speed") else { throw ToolError("missing number argument 'speed'") }
            try editor.apply(.setSpeed(try a.id("clip_id"), speed)); return text("ok")
        },
        Tool(name: "set_look", description: "Colour and geometry adjustments of a video clip. Omitted values keep the current value.",
             properties: ["clip_id": prop("string", idDesc), "brightness": prop("number", "-1...1"), "contrast": prop("number", "0...4, 1 = normal"),
                          "saturation": prop("number", "0...3, 0 = black and white"), "sepia": prop("number", "0...1"),
                          "blur": prop("number", "0...1"), "vignette": prop("number", "0...1"),
                          "flip_horizontal": prop("boolean", "Mirror left-right"), "flip_vertical": prop("boolean", "Mirror top-bottom"),
                          "rotation": prop("number", "Degrees, counter-clockwise"),
                          "crop_left": prop("number", "Trim this fraction (0...0.9) off the left edge"), "crop_right": prop("number", "Right edge"),
                          "crop_top": prop("number", "Top edge"), "crop_bottom": prop("number", "Bottom edge"),
                          "warmth": prop("number", "-1 cool ... +1 warm"), "fade": prop("number", "0...1 lifted blacks (matte film)"), "sharpen": prop("number", "0...1"),
                          "split_shadows": prop("string", "Tint for dark areas, hex e.g. 0B6E7F ('' removes)"), "split_highlights": prop("string", "Tint for bright areas, hex e.g. FF9A3C"),
                          "split_amount": prop("number", "0...1 strength of the two tints (teal and orange look: 0.5)")],
             required: ["clip_id"]) { a in
            let look = a.look(try clip(try a.id("clip_id")).look)
            try editor.apply(.setLook(try a.id("clip_id"), look)); return text("ok")
        },
        Tool(name: "set_track", description: "Track settings: mute audio, hide picture or titles, lock, duck (music under speech), name. Omitted values keep the current value.",
             properties: ["track_id": prop("string", "Track id"), "muted": prop("boolean", "Silence the track"), "hidden": prop("boolean", "Hide the track's picture/titles"),
                          "locked": prop("boolean", "Protect the track's clips from changes"), "duck": prop("boolean", "Audio tracks: dip the volume while other sound (speech, clip sound) plays, e.g. for music"),
                          "duck_level": prop("number", "How far a ducking track dips: 0.05...0.95 of its volume, default 0.3"),
                          "name": prop("string", "Track name")],
             required: ["track_id"]) { a in
            let id = try a.id("track_id")
            guard let t = editor.project.tracks.first(where: { $0.id == id }) else { throw ToolError("track not found") }
            try editor.transaction {
                try editor.apply(.setTrackFlags(id, muted: a.d["muted"] as? Bool ?? t.muted, hidden: a.d["hidden"] as? Bool ?? t.hidden))
                if let duck = a.d["duck"] as? Bool { try editor.apply(.setTrackDuck(id, duck)) }
                if let level = a.optDouble("duck_level") { try editor.apply(.setTrackDuckLevel(id, level)) }
                if let name = a.optStr("name") { try editor.apply(.setTrackName(id, name)) }
                if let locked = a.d["locked"] as? Bool { try editor.apply(.setTrackLocked(id, locked)) }
            }
            return text("ok")
        },
        Tool(name: "add_transition",
             description: "Adds a transition between a clip and the clip that starts exactly where it ends. The clips then overlap, so the timeline gets shorter by the duration.",
             properties: ["clip_id": prop("string", "The outgoing (first) clip"),
                          "type": ["type": "string", "enum": TransitionType.allCases.map(\.rawValue), "description": "Transition style"],
                          "duration_ms": prop("integer", "Default 1000, capped at half the shorter clip")],
             required: ["clip_id", "type"]) { a in
            guard let type = TransitionType(rawValue: try a.str("type")) else { throw ToolError("unknown transition type; use one of: \(TransitionType.allCases.map(\.rawValue).joined(separator: ", "))") }
            try editor.addTransition(after: try a.id("clip_id"), type: type, duration: a.optMs("duration_ms")); return text("ok")
        },
        Tool(name: "remove_transition", description: "Removes the transition that a clip is part of; later clips move back.",
             properties: ["clip_id": prop("string", idDesc)], required: ["clip_id"]) { a in
            try editor.removeTransition(involving: try a.id("clip_id")); return text("ok")
        },
        Tool(name: "set_audio", description: "Sets a clip's volume (1 = original, 0...2) and fades. Omitted values keep the current value.",
             properties: ["clip_id": prop("string", idDesc), "volume": prop("number", "0...2"),
                          "fade_in_ms": prop("integer", "Fade-in length"), "fade_out_ms": prop("integer", "Fade-out length")],
             required: ["clip_id"]) { a in
            let c = try clip(try a.id("clip_id"))
            try editor.apply(.setVolume(c.id, volume: a.optDouble("volume") ?? c.volume,
                                        fadeIn: a.optMs("fade_in_ms") ?? c.fadeIn, fadeOut: a.optMs("fade_out_ms") ?? c.fadeOut))
            return text("ok")
        },
        Tool(name: "add_sound_effect", description: "Adds a built-in sound effect: \(SoundEffects.names.joined(separator: ", ")). ONLY when the user asks for sound effects; films and highlight reels do not get automatic effects.",
             properties: ["name": prop("string", "Effect name"), "start_ms": prop("integer", "Default: playhead")],
             required: ["name"]) { a in
            let asset = try await host.importMedia(try SoundEffects.url(for: a.str("name")))
            return text(describe(try editor.addClip(asset: asset, start: a.optMs("start_ms") ?? host.playhead())))
        },
        Tool(name: "auto_movie",
             description: "QUICK MECHANICAL first pass on an EMPTY timeline: chains the busiest moments of the video assets at similar lengths with one kind of crossfade, optionally on the beat of music. It does not look at the pictures or judge them, so it is NOT directing. For a real film use the director skills and build_edit. Only use this when the user asks for a quick automatic cut.",
             properties: ["target_seconds": prop("number", "Approximate length, default 30"),
                          "asset_ids": ["type": "array", "items": ["type": "string"], "description": "Video assets to use, in order. Default: all video assets"],
                          "music_asset_id": prop("string", "Audio asset to cut on the beat of"),
                          "title": prop("string", "Opening title text"),
                          "transition_ms": prop("integer", "Crossfade length, default 400")],
             required: []) { a in
            let assets = editor.project.assets
            let videos = (a.d["asset_ids"] as? [String]).map { $0.compactMap(UUID.init).compactMap { id in assets.first { $0.id == id } } }
                ?? assets.filter(\.hasVideo)
            let music = a.optID("music_asset_id").flatMap { id in assets.first { $0.id == id } }
            let plan = try await AutoMovie.plan(videos: videos, options: AutoMovieOptions(
                targetMs: Ms((a.optDouble("target_seconds") ?? 30) * 1000), transitionMs: a.optMs("transition_ms") ?? 400,
                title: a.optStr("title"), music: music))
            try plan.apply(to: editor)
            return text("segments=\(plan.segmentCount) duration_ms=\(editor.project.duration) bpm=\(plan.bpm.map { String(format: "%.0f", $0) } ?? "none")")
        },
        Tool(name: "save_project", description: "Saves the project (not the rendered video) to an absolute path ending in .moviemaker. Media files are referenced by path, not copied.",
             properties: ["path": prop("string", "Output file path")], required: ["path"]) { a in
            let url = URL(fileURLWithPath: try a.str("path"))
            try editor.project.write(to: url)
            return text("saved to \(url.path)")
        },
        Tool(name: "set_transform",
             description: "Opacity, scale and position of a video clip. Omitted values keep the current value. Offsets are fractions of the frame (x + is right, y + is up).",
             properties: ["clip_id": prop("string", idDesc), "opacity": prop("number", "0...1"), "scale": prop("number", "0.1...10, 1 = fit frame"),
                          "offset_x": prop("number", "-1...1"), "offset_y": prop("number", "-1...1")],
             required: ["clip_id"]) { a in
            let c = try clip(try a.id("clip_id"))
            try editor.apply(.setTransform(c.id, opacity: a.optDouble("opacity") ?? c.opacity, scale: a.optDouble("scale") ?? c.scale,
                                           offsetX: a.optDouble("offset_x") ?? c.offsetX, offsetY: a.optDouble("offset_y") ?? c.offsetY))
            return text("ok")
        },
        Tool(name: "set_text_style",
             description: "Styles a title clip. Omitted values keep the current value. Position is the text centre as a fraction of the frame (x from the left, y from the bottom).",
             properties: ["clip_id": prop("string", "Title clip id"), "size": prop("number", "Fraction of frame height, 0.02...0.3"),
                          "color": prop("string", "Hex like FFCC00"), "x": prop("number", "0...1"), "y": prop("number", "0...1"),
                          "bold": prop("boolean", "Bold"), "shadow": prop("boolean", "Drop shadow"), "font": prop("string", "Font name, e.g. Helvetica Neue"),
                          "align": ["type": "string", "enum": ["left", "center", "right"], "description": "Text alignment; x is where the text starts, centres or ends"],
                          "outline": prop("boolean", "Black outline"), "box": prop("boolean", "Dark box behind the text"),
                          "animation": ["type": "string", "enum": TextAnimation.allCases.map(\.rawValue), "description": "How the title appears"],
                          "animation_ms": prop("integer", "Length of the entrance, default 500"),
                          "tracking": prop("number", "Letter spacing as a fraction of the size, e.g. 0.3"), "uppercase": prop("boolean", "ALL CAPS"), "glow": prop("boolean", "Glowing halo in the text colour")],
             required: ["clip_id"]) { a in
            let st = a.textStyle(try clip(try a.id("clip_id")).style)
            try editor.apply(.setTextStyle(try a.id("clip_id"), st)); return text("ok")
        },
        Tool(name: "update_transition", description: "Changes the style and/or overlap length of the transition a clip is part of. A longer overlap makes the timeline shorter.",
             properties: ["clip_id": prop("string", "Either clip of the transition"),
                          "type": ["type": "string", "enum": TransitionType.allCases.map(\.rawValue), "description": "New style"],
                          "duration_ms": prop("integer", "New overlap length")], required: ["clip_id"]) { a in
            let id = try a.id("clip_id")
            guard let tr = editor.project.transitions.first(where: { $0.fromClip == id || $0.toClip == id }) else { throw ToolError("clip has no transition") }
            let type = try a.optStr("type").map { name -> TransitionType in
                guard let t = TransitionType(rawValue: name) else { throw ToolError("unknown transition type; use one of: \(TransitionType.allCases.map(\.rawValue).joined(separator: ", "))") }
                return t
            } ?? tr.type
            try editor.apply(.setTransition(tr.id, type: type, duration: a.optMs("duration_ms") ?? tr.duration)); return text("ok")
        },
        Tool(name: "detach_audio", description: "Moves the sound of a video clip onto its own audio clip (same range) and mutes the video clip.",
             properties: ["clip_id": prop("string", "Video clip id")], required: ["clip_id"]) { a in
            try editor.detachAudio(try a.id("clip_id")); return text("ok")
        },
        Tool(name: "add_track", description: "Adds an empty track. A video track on top is a new layer above the others; the first track in the list is the top layer.",
             properties: ["kind": ["type": "string", "enum": ["video", "audio", "text"], "description": "Track kind"],
                          "on_top": prop("boolean", "Put it first (top layer). Default false")], required: ["kind"]) { a in
            guard let kind = TrackKind(rawValue: try a.str("kind")) else { throw ToolError("kind must be video, audio or text") }
            return text("track_id=\(try editor.addTrack(kind, onTop: a.d["on_top"] as? Bool ?? false).uuidString)")
        },
        Tool(name: "remove_track", description: "Deletes a track with all its clips.",
             properties: ["track_id": prop("string", "Track id from get_project")], required: ["track_id"]) { a in
            try editor.apply(.removeTrack(try a.id("track_id"))); return text("ok")
        },
        Tool(name: "list_sounds",
             description: "Built-in free sounds: sound effects and music beds with their tempo and mood. Use add_sound_effect / add_music, or search_online_sounds for more.",
             properties: [:], required: []) { _ in
            text("sound effects (only add them when the user asks for them): \(SoundEffects.names.joined(separator: ", "))\nmusic beds, \(MusicLibrary.tracks.count) songs by category:\n"
                 + MusicLibrary.categories.map { c in "\(c): " + MusicLibrary.tracks.filter { $0.category == c }.map { "\($0.name) (\(Int($0.bpm)) BPM, \($0.mood))" }.joined(separator: "; ") }.joined(separator: "\n"))
        },
        Tool(name: "add_music", description: "Adds a built-in music bed (about 1 minute, tempo known) on an audio track at a position, trimmed to the movie length if you give duration_ms. See list_sounds.",
             properties: ["name": prop("string", "Track name from list_sounds"), "start_ms": prop("integer", "Default 0"),
                          "duration_ms": prop("integer", "Default: the whole track, at most the movie length when the movie has clips")],
             required: ["name"]) { a in
            let asset = try await host.importMedia(try MusicLibrary.url(for: a.str("name")))
            let clip = try editor.addMusicBed(asset, start: a.optMs("start_ms") ?? 0, duration: a.optMs("duration_ms"))
            return text(describe(clip) + " (volume 0.6 with fades; adjust with set_audio)")
        },
        Tool(name: "search_online_sounds",
             description: "Searches free sounds online (Openverse: CC0, public domain, and optionally CC BY with credit). Returns ids; use import_online_sound to download one.",
             properties: ["query": prop("string", "What to look for, e.g. 'upbeat acoustic' or 'door slam'"),
                          "kind": ["type": "string", "enum": ["music", "effects", "images"], "description": "music (20 s or longer), effects (up to 1 minute) or images (photos; import them, then use add_clip)"],
                          "allow_attribution": prop("boolean", "Include CC BY sounds (you must credit them). Default true for music, false for effects")],
             required: ["query", "kind"]) { a in
            guard let kind = OnlineLibrary.Kind(rawValue: try a.str("kind")) else { throw ToolError("kind must be music, effects or images") }
            let results = try await OnlineLibrary.search(try a.str("query"), kind: kind, allowAttribution: a.d["allow_attribution"] as? Bool ?? (kind == .music))
            for r in results { onlineResults[r.id] = r }
            return text(results.isEmpty ? "no results" : results.prefix(12).map {
                "id=\($0.id) | \($0.title) | by \($0.creator) | \($0.license.uppercased()) | \($0.durationMs / 1000) s | \($0.provider)" }.joined(separator: "\n"))
        },
        Tool(name: "import_online_sound",
             description: "Downloads a sound found with search_online_sounds into the media library and returns its asset_id (then use add_clip). Credits are recorded; see get_credits.",
             properties: ["id": prop("string", "Result id from search_online_sounds")], required: ["id"]) { a in
            guard let sound = onlineResults[try a.str("id")] else { throw ToolError("unknown id: search first with search_online_sounds") }
            let asset = try await host.importMedia(try await OnlineLibrary.download(sound))
            return text("asset_id=\(asset.id.uuidString) duration_ms=\(asset.duration)" + (sound.needsCredit ? "\ncredit required: \(sound.credit)" : ""))
        },
        Tool(name: "get_credits", description: "Credit lines for all downloaded sounds that need attribution; paste them in the video description.",
             properties: [:], required: []) { _ in text(OnlineLibrary.creditsText(for: OnlineLibrary.credits())) },
        Tool(name: "list_effects", description: "Scene effects you can add to a video clip, with what each is for. Read the scene-effects skill for taste.",
             properties: [:], required: []) { _ in
            text(EffectType.allCases.map { "\($0.rawValue) (\($0.title)): \($0.summary)" }.joined(separator: "\n"))
        },
        Tool(name: "add_effect", description: "Adds a scene effect to a video clip (an effect of the same type is replaced). amount is the strength 0...1.",
             properties: ["clip_id": prop("string", idDesc), "type": ["type": "string", "enum": EffectType.allCases.map(\.rawValue), "description": "Effect type, see list_effects"],
                          "amount": prop("number", "0...1, default depends on the effect"), "color": prop("string", "Hex colour to remove, for chromaKey (default 00FF00)")],
             required: ["clip_id", "type"]) { a in
            guard let type = EffectType(rawValue: try a.str("type")) else { throw ToolError("unknown effect; call list_effects") }
            try editor.apply(.addEffect(try a.id("clip_id"), Effect(type, amount: a.optDouble("amount"), colorHex: a.optStr("color")))); return text("ok")
        },
        Tool(name: "remove_effect", description: "Removes a scene effect from a clip by type.",
             properties: ["clip_id": prop("string", idDesc), "type": ["type": "string", "enum": EffectType.allCases.map(\.rawValue), "description": "Effect type"]],
             required: ["clip_id", "type"]) { a in
            let c = try clip(try a.id("clip_id"))
            guard let type = EffectType(rawValue: try a.str("type")), let e = c.effects.first(where: { $0.type == type }) else { throw ToolError("clip has no such effect") }
            try editor.apply(.removeEffect(c.id, effect: e.id)); return text("ok")
        },
        Tool(name: "build_edit",
             description: "Builds a whole directed edit in ONE undoable step from an edit decision list: the cuts (which part of which clip, in order) with per-cut transition, speed, sound, look, framing and effects, plus titles, music and sound effects. This is the main tool for making a film. Read the edit-decision-list skill for the format.",
             properties: ["cuts": ["type": "array", "description": "In playing order. Each: {asset_id, start_ms, end_ms (source range), transition (none|crossfade|...; join with the previous cut), transition_ms, speed, sound (keep|mute|0..2), fade_in_ms, fade_out_ms, look (preset name or {brightness,contrast,saturation,sepia,blur,vignette}), scale, offset_x, offset_y, opacity, effects:[{type,amount}]}",
                                   "items": ["type": "object"]],
                          "titles": ["type": "array", "description": "Each: {text, start_ms (timeline), duration_ms, preset (center|lowerThird|subtitle), size, color, x, y, align, bold, shadow, outline, box, fade_in_ms, fade_out_ms}", "items": ["type": "object"]],
                          "music": ["type": "object", "description": "{name (built-in, see list_sounds) or asset_id, volume (default 0.6), start_ms, source_in_ms, duck (lower the music under clip sound)}"],
                          "sfx": ["type": "array", "description": "Sound effects. ONLY when the user asked for them. Each: {name, at_cut (cut index) or at_ms, offset_ms, volume}", "items": ["type": "object"]],
                          "overlays": ["type": "array", "description": "Drawn overlays, each: {kind (confetti|snow|rain|sparkles|bokeh|dust|sunbeams|frame|hearts|fireflies), start_ms (timeline), duration_ms, amount, fade_in_ms, fade_out_ms}", "items": ["type": "object"]],
                          "canvas": prop("string", "Optional 16:9, 9:16, 1:1 or 4:5"),
                          "replace": prop("boolean", "Start over when the timeline already has clips (the user can undo)")],
             required: ["cuts"]) { a in
            text(try await EditPlan.apply(a, editor: editor, host: host))
        },
        Tool(name: "relink_asset", description: "Points an asset whose file moved to its new location (same kind of media, long enough for the clips that use it).",
             properties: ["asset_id": prop("string", "Asset id"), "path": prop("string", "Absolute path of the file")], required: ["asset_id", "path"]) { a in
            let fresh = try await Asset.load(url: URL(fileURLWithPath: try a.str("path")))
            try editor.relink(try a.id("asset_id"), to: fresh); return text("ok")
        },
        Tool(name: "group_clips", description: "Links two or more clips so they move, split and delete together (e.g. a video clip and its detached sound).",
             properties: ["clip_ids": ["type": "array", "items": ["type": "string"], "description": "Clip ids to link"]], required: ["clip_ids"]) { a in
            guard let ids = (a.d["clip_ids"] as? [String])?.compactMap(UUID.init), ids.count >= 2 else { throw ToolError("clip_ids needs at least two clip ids") }
            try editor.apply(.group(ids)); return text("ok")
        },
        Tool(name: "ungroup_clip", description: "Dissolves the group a clip belongs to.", properties: ["clip_id": prop("string", idDesc)], required: ["clip_id"]) { a in
            try editor.apply(.ungroup(try a.id("clip_id"))); return text("ok")
        },
        Tool(name: "set_keyframes",
             description: "Animates a clip's opacity, scale, position and rotation over time with keyframes (time from the clip start). Values glide between keyframes and hold after the last. An empty list removes the animation. Omitted fields default to opacity 1, scale 1, offsets 0, rotation 0.",
             properties: ["clip_id": prop("string", idDesc),
                          "keyframes": ["type": "array", "description": "Each: {time_ms, opacity, scale, offset_x, offset_y, rotation, smooth (ease, default true)}", "items": ["type": "object"]]],
             required: ["clip_id", "keyframes"]) { a in
            guard let raw = a.d["keyframes"] as? [[String: Any]] else { throw ToolError("keyframes must be a list") }
            try editor.apply(.setKeyframes(try a.id("clip_id"), raw.map { Args(d: $0).keyframe() })); return text("ok")
        },
        Tool(name: "remove_silence",
             description: "Detects quiet stretches in a clip's sound and cuts them out, closing the gaps (the picture is cut too). Good for talking clips.",
             properties: ["clip_id": prop("string", idDesc), "min_silence_ms": prop("integer", "Shortest silence to remove, default 700")], required: ["clip_id"]) { a in
            let c = try clip(try a.id("clip_id"))
            guard let asset = editor.project.assets.first(where: { $0.id == c.assetID }), asset.hasAudio else { throw ToolError("the clip has no sound") }
            let ranges = try await AudioTools.silences(of: asset, sourceIn: c.sourceIn, length: c.sourceLength, minSilence: a.optMs("min_silence_ms") ?? 700)
            guard !ranges.isEmpty else { return text("no silences found") }
            return text("removed \(try editor.removeSilences(of: c.id, ranges: ranges)) ms of silence in \(ranges.count) places")
        },
        Tool(name: "normalize_audio", description: "Sets a clip's volume so its sound is at a standard level (about -20 dBFS), keeping its fades.",
             properties: ["clip_id": prop("string", idDesc)], required: ["clip_id"]) { a in
            let c = try clip(try a.id("clip_id"))
            guard let asset = editor.project.assets.first(where: { $0.id == c.assetID }), asset.hasAudio,
                  let gain = try await AudioTools.normalizedVolume(of: asset, sourceIn: c.sourceIn, length: c.sourceLength) else { throw ToolError("no usable sound in this clip") }
            try editor.apply(.setVolume(c.id, volume: gain, fadeIn: c.fadeIn, fadeOut: c.fadeOut))
            return text("volume set to \(String(format: "%.2f", gain))")
        },
        Tool(name: "reduce_noise", description: "Cleans a clip's sound: removes low rumble and gates the hiss in the pauses. A video clip's sound is detached onto its own audio clip first (grouped). Simple noise reduction.",
             properties: ["clip_id": prop("string", idDesc)], required: ["clip_id"]) { a in
            let c = try clip(try a.id("clip_id"))
            guard let asset = editor.project.assets.first(where: { $0.id == c.assetID }), asset.hasAudio else { throw ToolError("the clip has no sound") }
            let cleaned = try await host.importMedia(try await AudioTools.reduceNoise(of: asset))
            try editor.useCleanedAudio(of: c.id, cleaned: cleaned)
            return text("sound cleaned")
        },
        Tool(name: "auto_captions",
             description: "Transcribes the speech of a clip and adds subtitles on a Captions track, timed to the clip. Needs the Eclipse app (speech recognition permission).",
             properties: ["clip_id": prop("string", idDesc), "language": prop("string", "Locale like en-US or nl-NL")], required: ["clip_id"]) { a in
            let c = try clip(try a.id("clip_id"))
            guard let asset = editor.project.assets.first(where: { $0.id == c.assetID }), asset.hasAudio else { throw ToolError("the clip has no sound") }
            let phrases = try await Transcriber.phrases(url: asset.url, language: a.optStr("language"))
            return text("added \(try editor.addCaptions(for: c.id, phrases: phrases)) subtitles")
        },
        Tool(name: "export_srt", description: "Writes the subtitles (Captions track, or all titles) as an .srt file.",
             properties: ["path": prop("string", "Output path ending in .srt")], required: ["path"]) { a in
            let url = URL(fileURLWithPath: try a.str("path"))
            try Subtitles.srt(editor.project).write(to: url, atomically: true, encoding: .utf8)
            return text("saved to \(url.path)")
        },
        Tool(name: "add_sticker", description: "Adds an emoji sticker (a large animated title) at a timeline position. Move it with set_text_style x / y.",
             properties: ["emoji": prop("string", "One or a few emoji"), "start_ms": prop("integer", "Default: playhead"), "duration_ms": prop("integer", "Default 2500")],
             required: ["emoji"]) { a in
            text(describe(try editor.addSticker(try a.str("emoji"), start: a.optMs("start_ms") ?? host.playhead(), duration: a.optMs("duration_ms") ?? 2_500)))
        },
        Tool(name: "reset_clip", description: "Puts a clip back to plain: removes its look, framing, keyframes, effects, speed change and volume changes.",
             properties: ["clip_id": prop("string", idDesc)], required: ["clip_id"]) { a in
            try editor.resetClip(try a.id("clip_id")); return text("ok")
        },
        Tool(name: "asset_info", description: "File facts of an imported asset: size, format, resolution, frame rate, codecs, sound, and how it is used in the project.",
             properties: ["asset_id": prop("string", "Asset id")], required: ["asset_id"]) { a in
            let id = try a.id("asset_id")
            guard let asset = editor.project.assets.first(where: { $0.id == id }) else { throw ToolError("asset not found") }
            let info = await AssetInfo.load(asset)
            let uses = editor.project.tracks.flatMap(\.clips).filter { $0.assetID == id }
            return text(["name: \(info.fileName)", "path: \(info.path)", "size: \(info.fileSize / 1_000) KB", "duration: \(info.duration) ms",
                         "picture: \(info.video ?? "none")", "sound: \(info.audio ?? "none")", "used in \(uses.count) clips"].joined(separator: "\n"))
        },
        Tool(name: "list_overlays", description: "Drawn overlay layers you can add with add_overlay (confetti, snow, ...).", properties: [:], required: []) { _ in
            text(GeneratorKind.allCases.map { "\($0.rawValue) (\($0.title)): \($0.summary)" }.joined(separator: "\n"))
        },
        Tool(name: "add_overlay", description: "Adds a drawn overlay (confetti, snow, rain, sparkles, bokeh, dust, sunbeams, frame, hearts, fireflies) on a video layer above the picture.",
             properties: ["kind": ["type": "string", "enum": GeneratorKind.allCases.map(\.rawValue), "description": "Overlay type"],
                          "start_ms": prop("integer", "Default: playhead"), "duration_ms": prop("integer", "Default 4000"), "amount": prop("number", "Density 0...1, default 0.5")],
             required: ["kind"]) { a in
            guard let kind = GeneratorKind(rawValue: try a.str("kind")) else { throw ToolError("unknown overlay; call list_overlays") }
            return text(describe(try editor.addOverlay(kind, start: a.optMs("start_ms") ?? host.playhead(), duration: a.optMs("duration_ms") ?? 4_000, amount: a.optDouble("amount") ?? 0.5)))
        },
        Tool(name: "suggest_treatments", description: "Creative directions for a film: three DIFFERENT, coherent starting points (structure, joins, look, one signature touch, title style, speed use, restraint), varied on every call and avoiding the ones suggested last time. Call it before planning a creative film, pick one (or blend two) that fits the footage and the mood, and say which you chose and why. Read the creative-toolbox skill for how to use it.",
             properties: ["mood": prop("string", "Words for the feeling or kind of film, e.g. 'party highlight' or 'calm travel memories'"), "count": prop("integer", "How many, 2...5 (default 3)")],
             required: []) { a in
            CreativeGuard.noteTreatmentSuggested()
            let picks = Treatments.suggest(mood: a.optStr("mood"), count: min(5, max(2, Int(a.optDouble("count") ?? 3))))
            return text(picks.map(Treatments.describe).joined(separator: "\n\n") + "\n\nConstraint cards (obey at least one, it keeps the film from being the usual):\n- " + Treatments.drawConstraints().joined(separator: "\n- ") + "\n\nBefore choosing, read the creative-thinking skill: name the obvious default film for this request, then move away from it.")
        },
        Tool(name: "list_templates", description: "Complete film styles (colour grade, effects, joins, title look, overlay, suggested music) you can apply to the whole movie or to chosen clips with apply_template.",
             properties: [:], required: []) { _ in
            text(Templates.categories.map { c in "\(c):\n" + Templates.all.filter { $0.category == c }.map { "  - \($0.name): \($0.summary) Pace: \($0.pace)." + ($0.music.map { " Music: \($0)." } ?? "") }.joined(separator: "\n") }.joined(separator: "\n"))
        },
        Tool(name: "apply_template",
             description: "Applies a film style (see list_templates) in one undo step: colour grade and effects on the video clips, the join style between clips, title look, and an overlay over the movie. It replaces the clips' earlier look and effects. Use clip_ids to style only some clips.",
             properties: ["name": prop("string", "Template name, e.g. Blockbuster"),
                          "clip_ids": ["type": "array", "items": ["type": "string"], "description": "Only these clips. Default: all video clips"],
                          "transitions": prop("boolean", "Add/restyle the joins. Default true"), "titles": prop("boolean", "Restyle titles. Default true"),
                          "overlay": prop("boolean", "Add the template's overlay. Default true"), "music": prop("boolean", "Also add the template's suggested music bed. Default false")],
             required: ["name"]) { a in
            guard let template = Templates.named(try a.str("name")) else { throw ToolError("unknown template; call list_templates") }
            var options = Editor.TemplateOptions()
            options.transitions = a.d["transitions"] as? Bool ?? true; options.titles = a.d["titles"] as? Bool ?? true; options.overlay = a.d["overlay"] as? Bool ?? true
            let ids = (a.d["clip_ids"] as? [String])?.compactMap(UUID.init)
            var summary = try editor.applyTemplate(template, to: ids, options: options)
            if a.d["music"] as? Bool == true, let bed = template.music {
                let asset = try await host.importMedia(try MusicLibrary.url(for: bed))
                _ = try editor.addMusicBed(asset, start: 0)
                summary += "; music \(bed) added"
            }
            return text(summary)
        },
        Tool(name: "ramp_speed",
             description: "Speed Ramp Studio: smooth changes of speed inside one clip (slow motion into normal into fast), from a preset or your own curve. The clip becomes a chain of pieces; the movie gets longer or shorter by the difference and later clips follow. Presets: \(SpeedRamp.presets.map(\.name).joined(separator: ", ")).",
             properties: ["clip_id": prop("string", idDesc), "preset": prop("string", "A preset name"),
                          "points": ["type": "array", "description": "Or your own curve: [{position 0...1, speed 0.1...8}] with rising positions, e.g. [{position:0,speed:1},{position:0.5,speed:0.3},{position:1,speed:1}]", "items": ["type": "object"]],
                          "segments": prop("integer", "Smoothness: pieces to cut the clip into, 4...40, default 20")], required: ["clip_id"]) { a in
            let points: [RampPoint]
            if let name = a.optStr("preset") { guard let preset = SpeedRamp.preset(name) else { throw ToolError("unknown preset; use one of: \(SpeedRamp.presets.map(\.name).joined(separator: ", "))") }; points = preset }
            else if let raw = a.d["points"] as? [[String: Any]] { points = raw.map { RampPoint(position: Args(d: $0).optDouble("position") ?? 0, speed: Args(d: $0).optDouble("speed") ?? 1) } }
            else { throw ToolError("give a preset or points") }
            try editor.apply(.rampSpeed(try a.id("clip_id"), points, segments: Int(a.optMs("segments") ?? 20))); return text("ok")
        },
        Tool(name: "find_match_cuts",
             description: "Smart Match Cuts: finds pairs of moments in two clips that look alike (colour, brightness, where the bright shape sits) so a hard cut between them feels like one motion, e.g. a round sun into a spinning wheel. Returns times to cut out of one clip and into the other.",
             properties: ["asset_ids": ["type": "array", "items": ["type": "string"], "description": "Clips to compare. Default: all video assets"], "limit": prop("integer", "How many pairs, default 5")],
             required: []) { a in
            let assets = editor.project.assets
            let chosen = (a.d["asset_ids"] as? [String])?.compactMap(UUID.init).compactMap { id in assets.first { $0.id == id } } ?? assets.filter(\.hasVideo)
            let matches = await MatchCuts.find(chosen, limit: Int(a.optMs("limit") ?? 5))
            guard !matches.isEmpty else { return text("no convincing matches between these clips") }
            func name(_ id: UUID) -> String { assets.first { $0.id == id }?.label ?? "?" }
            return text(matches.map { "\(String(format: "%.0f", $0.score * 100)) % | cut out of \(name($0.assetA)) (asset_id=\($0.assetA.uuidString)) at \($0.timeA) ms, into \(name($0.assetB)) (asset_id=\($0.assetB.uuidString)) at \($0.timeB) ms | \($0.reason)" }.joined(separator: "\n"))
        },
        Tool(name: "add_match_cut", description: "Adds a match cut at the end of the timeline: the first clip plays up to time_a_ms, the second continues from time_b_ms (use the numbers from find_match_cuts).",
             properties: ["asset_a": prop("string", "First clip"), "time_a_ms": prop("integer", "Where the first clip ends"), "asset_b": prop("string", "Second clip"), "time_b_ms": prop("integer", "Where the second clip starts"),
                          "lead_ms": prop("integer", "How much of the first clip to show before the match, default 1800"), "tail_ms": prop("integer", "How much of the second clip after the match, default 2500")],
             required: ["asset_a", "time_a_ms", "asset_b", "time_b_ms"]) { a in
            let pair = try editor.addMatchCut(MatchCut(assetA: try a.id("asset_a"), timeA: try a.ms("time_a_ms"), assetB: try a.id("asset_b"), timeB: try a.ms("time_b_ms"), score: 1, reason: ""),
                                              lead: a.optMs("lead_ms") ?? 1_800, tail: a.optMs("tail_ms") ?? 2_500)
            return text(describe(pair.0) + "\n" + describe(pair.1))
        },
        Tool(name: "smart_reframe",
             description: "Smart Reframe: makes a landscape clip fill a vertical or square canvas and follows the main person or subject (faces first, then people, then the most eye-catching area). Set the canvas first (set_format) or pass aspect.",
             properties: ["clip_id": prop("string", idDesc), "aspect": ["type": "string", "enum": ["9:16", "1:1", "4:5"], "description": "Optional: set the movie canvas to this shape first"]], required: ["clip_id"]) { a in
            let c = try clip(try a.id("clip_id"))
            guard let asset = editor.project.assets.first(where: { $0.id == c.assetID }), asset.hasVideo else { throw ToolError("select a video clip") }
            if let aspect = a.optStr("aspect") {
                let sizes = ["9:16": (1080, 1920), "1:1": (1080, 1080), "4:5": (1080, 1350)]
                guard let s = sizes[aspect] else { throw ToolError("aspect must be 9:16, 1:1 or 4:5") }
                try editor.apply(.setFormat(width: s.0, height: s.1, fps: editor.project.fps))
            }
            let track = try await AVURLAsset(url: asset.url).loadTracks(withMediaType: .video).first
            let natural = try await track?.load(.naturalSize).applying(try await track?.load(.preferredTransform) ?? .identity) ?? CGSize(width: 16, height: 9)
            let followed = await SmartReframe.track(asset, sourceIn: c.sourceIn, length: c.sourceLength, speed: c.speed)
            let frames = try editor.reframeClip(c.id, subjects: followed.subjects, sourceAspect: abs(natural.width) / max(1, abs(natural.height)))
            return text("reframed on the \(followed.method) with \(frames) camera positions")
        },
        Tool(name: "undo", description: "Undoes the last edit.", properties: [:], required: []) { _ in
            guard editor.canUndo else { throw ToolError("nothing to undo") }
            editor.undo(); return text("ok")
        },
        Tool(name: "redo", description: "Redoes the last undone edit.", properties: [:], required: []) { _ in
            guard editor.canRedo else { throw ToolError("nothing to redo") }
            editor.redo(); return text("ok")
        },
        Tool(name: "inspect_asset",
             description: "Facts and an activity/loudness summary of an imported clip, plus suggested best moments and probable cuts. Use before watch_asset.",
             properties: ["asset_id": prop("string", "Asset id")], required: ["asset_id"]) { a in
            let id = try a.id("asset_id")
            guard let asset = editor.project.assets.first(where: { $0.id == id }) else { throw ToolError("asset not found") }
            return text(try await Vision.inspect(asset))
        },
        Tool(name: "watch_asset",
             description: "Contact sheet image of evenly spaced frames of an imported clip, each labelled with its time. Narrow start_ms/end_ms and raise frames to study a moment.",
             properties: ["asset_id": prop("string", "Asset id"), "start_ms": prop("integer", "Default 0"), "end_ms": prop("integer", "Default: end of clip"),
                          "frames": prop("integer", "Default 12, max 24")], required: ["asset_id"]) { a in
            let id = try a.id("asset_id")
            guard let asset = editor.project.assets.first(where: { $0.id == id }), asset.hasVideo else { throw ToolError("video asset not found") }
            let start = max(0, a.optMs("start_ms") ?? 0), end = min(asset.duration, a.optMs("end_ms") ?? asset.duration)
            guard end > start else { throw ToolError("end_ms must be after start_ms") }
            let times = Vision.evenTimes(start: start, end: end, count: min(24, max(1, Int(a.optMs("frames") ?? 12))))
            let png = try await Vision.contactSheet(of: AVURLAsset(url: asset.url), times: times)
            return [["type": "text", "text": "frames at: " + times.map(String.init).joined(separator: ", ") + " ms (left to right, top to bottom)"],
                    ["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"]]
        },
        Tool(name: "watch_timeline",
             description: "Contact sheet of the EDITED result (clips, transitions, titles, looks) between two timeline times. Use it to review your work.",
             properties: ["start_ms": prop("integer", "Default 0"), "end_ms": prop("integer", "Default: end of movie"),
                          "frames": prop("integer", "Default 12, max 24")], required: []) { a in
            let p = editor.project
            let built = try await CompositionBuilder.build(p)
            guard let vc = built.videoComposition else { throw ToolError("project has no video") }
            let start = max(0, a.optMs("start_ms") ?? 0), end = min(p.duration, a.optMs("end_ms") ?? p.duration)
            guard end > start else { throw ToolError("end_ms must be after start_ms") }
            let times = Vision.evenTimes(start: start, end: end, count: min(24, max(1, Int(a.optMs("frames") ?? 12))))
            let png = try await Vision.contactSheet(of: built.composition, videoComposition: vc, times: times)
            return [["type": "text", "text": "timeline frames at: " + times.map(String.init).joined(separator: ", ") + " ms"],
                    ["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"]]
        },
        Tool(name: "transcribe_asset",
             description: "Speech to text with timestamps (ms) for an imported clip, using Apple's recognizer. The first call may ask the user for permission.",
             properties: ["asset_id": prop("string", "Asset id"), "language": prop("string", "Locale like en-US or nl-NL. Default: the Mac's language")],
             required: ["asset_id"]) { a in
            let id = try a.id("asset_id")
            guard let asset = editor.project.assets.first(where: { $0.id == id }), asset.hasAudio else { throw ToolError("asset with sound not found") }
            return text(try await Transcriber.transcribe(url: asset.url, language: a.optStr("language")))
        },
        Tool(name: "get_frame", description: "Returns an image of the composited frame (clips, transitions, titles) at a timeline time, so you can check your edit.",
             properties: ["time_ms": prop("integer", "Timeline position")], required: ["time_ms"]) { a in
            let png = try await FrameRenderer.png(editor.project, atMs: try a.ms("time_ms"))
            return [["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"]]
        },
        Tool(name: "export", description: "Renders the project to an H.264/AAC MP4 at the given absolute path (can take a while). Optionally pick a preset: \(ExportPreset.allCases.map(\.rawValue).joined(separator: ", ")). Clips are fitted into the preset's frame.",
             properties: ["path": prop("string", "Output file path ending in .mp4"),
                          "preset": ["type": "string", "enum": ExportPreset.allCases.map(\.rawValue), "description": "Optional size preset; default is the movie's own canvas"]],
             required: ["path"]) { a in
            let url = URL(fileURLWithPath: try a.str("path"))
            let preset = try a.optStr("preset").map { name -> ExportPreset in
                guard let p = ExportPreset(rawValue: name) else { throw ToolError("unknown preset") }
                return p
            }
            try await Exporter.export(editor.project, to: url, settings: preset?.settings)
            return text("exported to \(url.path)")
        },
    ]
}
