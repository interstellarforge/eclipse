import Foundation

/// Every edit is a Command. The UI and the MCP server both go through `Editor.apply`.
public enum Command: Codable {
    case addAsset(Asset)
    case addTrack(id: UUID, kind: TrackKind)
    case addClip(track: UUID, clip: Clip)
    case removeClip(UUID)
    case moveClip(UUID, start: Ms)
    case trimClip(UUID, sourceIn: Ms, duration: Ms, start: Ms)
    case splitClip(UUID, at: Ms)   // at = timeline position
    case setVolume(UUID, volume: Double, fadeIn: Ms, fadeOut: Ms)
    case addTransition(Transition)
    case removeTransition(UUID)
    case setText(UUID, String)
    case setMuted(UUID, Bool)
    case setFormat(width: Int, height: Int, fps: Int)
    case setSpeed(UUID, Double)
    case rampSpeed(UUID, [RampPoint], segments: Int)   // a speed curve: the clip becomes a chain of pieces at changing speeds
    case setLook(UUID, Look)
    case addEffect(UUID, Effect)         // an effect of the same type on the clip is replaced
    case removeEffect(UUID, effect: UUID)
    case setTrackFlags(UUID, muted: Bool, hidden: Bool)
    case rippleRemove(UUID)
    case removeAsset(UUID)
    case moveTrack(UUID, to: Int)
    case removeTrack(UUID)
    case setTransform(UUID, opacity: Double, scale: Double, offsetX: Double, offsetY: Double)
    case setTextStyle(UUID, TextStyle)
    case setTransition(UUID, type: TransitionType, duration: Ms)
    case relinkAsset(UUID, url: URL)
    case replaceClipAsset(UUID, UUID)     // clip, new asset: same range of a different file (e.g. cleaned sound)
    case setTrackLocked(UUID, Bool)
    case setTrackDuck(UUID, Bool)
    case setTrackDuckLevel(UUID, Double)
    case setGenerator(UUID, kind: GeneratorKind, amount: Double)
    case setAssetFavorite(UUID, Bool)
    case renameAsset(UUID, String?)
    case setTrackName(UUID, String?)
    case group([UUID])                    // two or more clips that then move, split and delete together
    case ungroup(UUID)                    // the clip's whole group is dissolved
    case setKeyframes(UUID, [Keyframe])   // an empty list returns to the plain opacity/scale/offset values
}

public enum EditError: Error, Equatable, CustomStringConvertible {
    case notFound, invalid(String)

    public var description: String {
        switch self {
        case .notFound: return "not found"
        case .invalid(let message): return message
        }
    }
}

public final class Editor: ObservableObject {
    @Published public private(set) var project: Project
    private var undoStack: [Project] = []
    private var redoStack: [Project] = []

    public init(project: Project = Project()) { self.project = project }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Applies atomically: on error the project is unchanged.
    public func apply(_ command: Command) throws {
        var next = project
        try Self.run(command, on: &next)
        try Self.validate(next)
        for old in project.tracks where old.locked {   // locked tracks keep their clips as they are
            guard let new = next.tracks.first(where: { $0.id == old.id }), new.clips == old.clips else {
                throw EditError.invalid("That track is locked. Unlock it to change its clips.")
            }
        }
        undoStack.append(project)
        redoStack.removeAll()
        project = next
    }

    /// Runs several edits as ONE undo step; if any fails, nothing changes.
    public func transaction(_ body: () throws -> Void) throws {
        let savedProject = project, savedUndo = undoStack, savedRedo = redoStack
        do { try body() } catch {
            project = savedProject; undoStack = savedUndo; redoStack = savedRedo
            throw error
        }
        if project != savedProject { undoStack = savedUndo + [savedProject]; redoStack = [] }
    }

    /// Swaps in a whole project (open / new). Clears undo history. Rejects an inconsistent file.
    public func replace(with p: Project) throws {
        try Self.validate(p)
        project = p
        undoStack.removeAll(); redoStack.removeAll()
    }

    /// Swaps in a whole project as ONE undoable edit (accepting a ghost edit).
    public func replaceAsEdit(with p: Project) throws {
        try Self.validate(p)
        undoStack.append(project); redoStack.removeAll()
        project = p
    }

    public func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(project); project = prev
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project); project = next
    }

    private static func locate(_ clipID: UUID, in p: Project) throws -> (t: Int, c: Int) {
        for (t, track) in p.tracks.enumerated() {
            if let c = track.clips.firstIndex(where: { $0.id == clipID }) { return (t, c) }
        }
        throw EditError.notFound
    }

    /// The clip and everything grouped with it.
    private static func groupMembers(of id: UUID, in p: Project) -> [UUID] {
        guard let g = p.tracks.flatMap(\.clips).first(where: { $0.id == id })?.groupID else { return [id] }
        return p.tracks.flatMap(\.clips).filter { $0.groupID == g }.map(\.id)
    }

    /// Splits one clip at a timeline position and returns the new right-hand clip's id.
    private static func split(_ p: inout Project, _ id: UUID, at: Ms) throws -> UUID {
        let (t, c) = try locate(id, in: p)
        let clip = p.tracks[t].clips[c]
        guard at > clip.start, at < clip.end else { throw EditError.invalid("split outside clip") }
        let cut = at - clip.start
        var left = clip, right = clip
        left.duration = cut; left.fadeOut = 0
        right.id = UUID(); right.start = at
        right.sourceIn += Ms((Double(cut) * clip.speed).rounded()); right.duration -= cut; right.fadeIn = 0
        if !clip.keyframes.isEmpty {   // keep the animation continuous across the cut
            left.keyframes = clip.keyframes.filter { $0.time <= cut }
            right.keyframes = clip.keyframes.filter { $0.time >= cut }.map { var k = $0; k.time -= cut; return k }
        }
        p.tracks[t].clips[c] = left
        p.tracks[t].clips.insert(right, at: c + 1)
        for i in p.transitions.indices where p.transitions[i].fromClip == id {
            p.transitions[i].fromClip = right.id   // outgoing transition follows the tail
        }
        return right.id
    }

    private static func shift(_ track: inout Track, from start: Ms, by delta: Ms) {
        for i in track.clips.indices where track.clips[i].start >= start { track.clips[i].start += delta }
    }

    /// Clips on one track may only overlap as a transition: consecutive pair, neither fully covered.
    static func validate(_ p: Project) throws {
        for track in p.tracks {
            let s = track.clips.sorted { $0.start < $1.start }
            for i in s.indices {
                if i + 2 < s.count, s[i + 2].start < s[i].end { throw EditError.invalid("Clips on one track can't overlap, unless a transition joins them") }
                if i + 1 < s.count, s[i + 1].start < s[i].end {
                    let overlap = s[i].end - s[i + 1].start
                    guard overlap < s[i].duration, overlap < s[i + 1].duration,
                          p.transitions.contains(where: { $0.fromClip == s[i].id && $0.toClip == s[i + 1].id })
                    else { throw EditError.invalid("Clips on one track can't overlap, unless a transition joins them") }
                }
            }
        }
        for tr in p.transitions {
            let clips = p.tracks.first { $0.clips.contains { $0.id == tr.fromClip } }?.clips
            guard let from = clips?.first(where: { $0.id == tr.fromClip }),
                  let to = clips?.first(where: { $0.id == tr.toClip }),
                  from.start < to.start, to.start < from.end
            else { throw EditError.invalid("a transition needs two overlapping clips; remove it first") }
        }
    }

    private static func run(_ cmd: Command, on p: inout Project) throws {
        switch cmd {
        case .addAsset(let a):
            p.assets.append(a)
        case .addTrack(let id, let kind):
            p.tracks.append(Track(id: id, kind: kind))
        case .addClip(let trackID, let clip):
            guard let t = p.tracks.firstIndex(where: { $0.id == trackID }) else { throw EditError.notFound }
            if let aid = clip.assetID {
                guard let a = p.assets.first(where: { $0.id == aid }) else { throw EditError.notFound }
                guard clip.sourceIn >= 0, clip.sourceIn + clip.sourceLength <= a.duration else {
                    throw EditError.invalid("clip exceeds asset duration")
                }
            }
            guard clip.duration > 0, clip.start >= 0 else { throw EditError.invalid("bad clip range") }
            p.tracks[t].clips.append(clip)
        case .removeClip(let id):
            _ = try locate(id, in: p)
            let gone = Set(groupMembers(of: id, in: p))
            p.transitions.removeAll { gone.contains($0.fromClip) || gone.contains($0.toClip) }
            for t in p.tracks.indices { p.tracks[t].clips.removeAll { gone.contains($0.id) } }
        case .moveClip(let id, let start):
            guard start >= 0 else { throw EditError.invalid("negative start") }
            let (t, c) = try locate(id, in: p)
            let delta = start - p.tracks[t].clips[c].start
            let members = Set(groupMembers(of: id, in: p))
            for ti in p.tracks.indices { for ci in p.tracks[ti].clips.indices where members.contains(p.tracks[ti].clips[ci].id) {
                guard p.tracks[ti].clips[ci].start + delta >= 0 else { throw EditError.invalid("a grouped clip would start before 0") }
                p.tracks[ti].clips[ci].start += delta
            } }
        case .trimClip(let id, let sourceIn, let duration, let start):
            let (t, c) = try locate(id, in: p)
            let clip = p.tracks[t].clips[c]
            if let aid = clip.assetID, let a = p.assets.first(where: { $0.id == aid }) {
                guard sourceIn >= 0, sourceIn + Ms((Double(duration) * clip.speed).rounded()) <= a.duration else {
                    throw EditError.invalid("trim exceeds asset duration")
                }
            }
            guard duration > 0, start >= 0 else { throw EditError.invalid("bad clip range") }
            p.tracks[t].clips[c].sourceIn = sourceIn
            p.tracks[t].clips[c].duration = duration
            p.tracks[t].clips[c].start = start
        case .splitClip(let id, let at):
            let members = groupMembers(of: id, in: p)
            let spanning = members.filter { m in p.tracks.flatMap(\.clips).first { $0.id == m }.map { $0.start < at && at < $0.end } ?? false }
            guard spanning.contains(id) else { throw EditError.invalid("split outside clip") }
            let rights = try spanning.map { try split(&p, $0, at: at) }
            if members.count > 1, rights.count > 1 {   // the right-hand halves form their own group
                let g = UUID()
                for ti in p.tracks.indices { for ci in p.tracks[ti].clips.indices where rights.contains(p.tracks[ti].clips[ci].id) { p.tracks[ti].clips[ci].groupID = g } }
            }
        case .setVolume(let id, let volume, let fi, let fo):
            guard volume >= 0, fi >= 0, fo >= 0 else { throw EditError.invalid("negative value") }
            let (t, c) = try locate(id, in: p)
            guard fi + fo <= p.tracks[t].clips[c].duration else { throw EditError.invalid("fades longer than clip") }
            p.tracks[t].clips[c].volume = volume
            p.tracks[t].clips[c].fadeIn = fi
            p.tracks[t].clips[c].fadeOut = fo
        case .addTransition(let tr):
            let (t, c1) = try locate(tr.fromClip, in: p)
            let (t2, c2) = try locate(tr.toClip, in: p)
            let from = p.tracks[t].clips[c1], to = p.tracks[t2].clips[c2]
            guard t == t2, from.end == to.start else { throw EditError.invalid("clips must be adjacent on one track") }
            guard tr.duration > 0, tr.duration < from.duration, tr.duration < to.duration else {
                throw EditError.invalid("bad transition duration")
            }
            guard !p.transitions.contains(where: { $0.fromClip == from.id && $0.toClip == to.id }) else {
                throw EditError.invalid("transition already exists")
            }
            // The clips overlap by the transition length: the incoming clip and everything after it move earlier.
            shift(&p.tracks[t], from: to.start, by: -tr.duration)
            p.transitions.append(tr)
        case .removeTransition(let id):
            guard let tr = p.transitions.first(where: { $0.id == id }) else { throw EditError.notFound }
            let (t, c1) = try locate(tr.fromClip, in: p)
            let (_, c2) = try locate(tr.toClip, in: p)
            let overlap = p.tracks[t].clips[c1].end - p.tracks[t].clips[c2].start
            let toStart = p.tracks[t].clips[c2].start
            p.transitions.removeAll { $0.id == id }
            if overlap > 0 { shift(&p.tracks[t], from: toStart, by: overlap) }
        case .moveTrack(let id, let index):
            guard let i = p.tracks.firstIndex(where: { $0.id == id }) else { throw EditError.notFound }
            let track = p.tracks.remove(at: i)
            p.tracks.insert(track, at: max(0, min(index, p.tracks.count)))
        case .removeTrack(let id):
            guard let i = p.tracks.firstIndex(where: { $0.id == id }) else { throw EditError.notFound }
            let gone = Set(p.tracks[i].clips.map(\.id))
            p.transitions.removeAll { gone.contains($0.fromClip) || gone.contains($0.toClip) }
            p.tracks.remove(at: i)
        case .setFormat(let width, let height, let fps):
            guard (240...4_096).contains(width), (240...4_096).contains(height), width % 2 == 0, height % 2 == 0,
                  (12...120).contains(fps) else { throw EditError.invalid("size must be even numbers from 240 to 4096 and fps from 12 to 120") }
            p.width = width; p.height = height; p.fps = fps
        case .setSpeed(let id, let speed):
            guard speed >= 0.1, speed <= 8 else { throw EditError.invalid("speed must be between 0.1x and 8x") }
            let (t, c) = try locate(id, in: p)
            let clip = p.tracks[t].clips[c]
            let newDuration = max(1, Ms((Double(clip.sourceLength) / speed).rounded()))
            for i in p.tracks[t].clips.indices where p.tracks[t].clips[i].start > clip.start {
                p.tracks[t].clips[i].start += newDuration - clip.duration   // later clips follow
            }
            p.tracks[t].clips[c].speed = speed
            p.tracks[t].clips[c].duration = newDuration
            p.tracks[t].clips[c].fadeIn = min(clip.fadeIn, newDuration)
            p.tracks[t].clips[c].fadeOut = min(clip.fadeOut, newDuration - p.tracks[t].clips[c].fadeIn)
        case .addEffect(let id, let effect):
            guard (0...1).contains(effect.amount) else { throw EditError.invalid("effect amount must be 0...1") }
            let (t, c) = try locate(id, in: p)
            guard p.tracks[t].clips[c].text == nil, p.tracks[t].clips[c].generator == nil else { throw EditError.invalid("effects work on video clips, not titles or overlays") }
            if let i = p.tracks[t].clips[c].effects.firstIndex(where: { $0.type == effect.type || $0.id == effect.id }) {
                var kept = effect; kept.id = p.tracks[t].clips[c].effects[i].id
                p.tracks[t].clips[c].effects[i] = kept
            } else { p.tracks[t].clips[c].effects.append(effect) }
        case .removeEffect(let id, let effectID):
            let (t, c) = try locate(id, in: p)
            guard p.tracks[t].clips[c].effects.contains(where: { $0.id == effectID }) else { throw EditError.notFound }
            p.tracks[t].clips[c].effects.removeAll { $0.id == effectID }
        case .rampSpeed(let id, let points, let segments):
            let (t, c) = try locate(id, in: p)
            let clip = p.tracks[t].clips[c]
            guard clip.assetID != nil, clip.text == nil, clip.generator == nil else { throw EditError.invalid("speed ramps work on video and audio clips") }
            guard (4...40).contains(segments), points.count >= 2, points.allSatisfy({ (0...1).contains($0.position) && (0.1...8).contains($0.speed) }),
                  zip(points, points.dropFirst()).allSatisfy({ $0.position < $1.position }) else {
                throw EditError.invalid("a speed curve needs 2 or more points with rising positions 0...1 and speeds between 0.1x and 8x")
            }
            guard !p.transitions.contains(where: { $0.fromClip == id || $0.toClip == id }) else {
                throw EditError.invalid("Remove the transitions on this clip first: a speed ramp cuts it into small pieces, and a transition can't overlap several pieces. Add them again afterwards.")
            }
            let sourceLength = Double(clip.sourceLength)
            var pieces: [Clip] = []
            var cursor = clip.start
            let timeBased: Set<EffectType> = [.kenBurnsIn, .kenBurnsOut, .panLeft, .panRight, .blurIn, .blurOut, .flash]   // would restart on every piece
            for k in 0..<segments {
                let u0 = Double(k) / Double(segments), u1 = Double(k + 1) / Double(segments)
                let from = clip.sourceIn + Ms((u0 * sourceLength).rounded()), to = clip.sourceIn + Ms((u1 * sourceLength).rounded())
                let speed = SpeedRamp.speed(at: (u0 + u1) / 2, points)
                var piece = clip
                piece.id = k == 0 ? clip.id : UUID()
                piece.sourceIn = from; piece.speed = speed; piece.start = cursor
                piece.duration = max(1, Ms((Double(to - from) / speed).rounded()))
                piece.fadeIn = k == 0 ? clip.fadeIn : 0; piece.fadeOut = k == segments - 1 ? clip.fadeOut : 0
                piece.keyframes = []
                piece.effects = clip.effects.filter { !timeBased.contains($0.type) }
                pieces.append(piece)
                cursor += piece.duration
            }
            let delta = cursor - clip.end
            for ti in p.tracks.indices { for ci in p.tracks[ti].clips.indices where ti == t && p.tracks[ti].clips[ci].start > clip.start && p.tracks[ti].clips[ci].id != clip.id {
                p.tracks[ti].clips[ci].start += delta   // later clips follow
            } }
            p.tracks[t].clips.remove(at: c)
            p.tracks[t].clips.append(contentsOf: pieces)
        case .setLook(let id, let look):
            guard (-1...1).contains(look.brightness), (0...4).contains(look.contrast), (0...3).contains(look.saturation),
                  (0...1).contains(look.sepia), (0...1).contains(look.blur), (0...1).contains(look.vignette),
                  [look.cropLeft, look.cropRight, look.cropTop, look.cropBottom].allSatisfy({ (0...0.9).contains($0) }),
                  look.cropLeft + look.cropRight < 0.95, look.cropTop + look.cropBottom < 0.95,
                  (-1...1).contains(look.warmth), (0...1).contains(look.fade), (0...1).contains(look.sharpen), (0...1).contains(look.splitAmount)
            else { throw EditError.invalid("look value out of range") }
            let (t, c) = try locate(id, in: p)
            p.tracks[t].clips[c].look = look
        case .setTrackFlags(let id, let muted, let hidden):
            guard let t = p.tracks.firstIndex(where: { $0.id == id }) else { throw EditError.notFound }
            p.tracks[t].muted = muted; p.tracks[t].hidden = hidden
        case .rippleRemove(let id):
            _ = try locate(id, in: p)
            let gone = Set(groupMembers(of: id, in: p))
            p.transitions.removeAll { gone.contains($0.fromClip) || gone.contains($0.toClip) }
            for ti in p.tracks.indices {
                let removed = p.tracks[ti].clips.filter { gone.contains($0.id) }
                guard !removed.isEmpty else { continue }
                p.tracks[ti].clips.removeAll { gone.contains($0.id) }
                for r in removed.sorted(by: { $0.start > $1.start }) {   // close each gap, latest first
                    for i in p.tracks[ti].clips.indices where p.tracks[ti].clips[i].start >= r.end { p.tracks[ti].clips[i].start -= r.duration }
                }
            }
        case .removeAsset(let id):
            guard p.assets.contains(where: { $0.id == id }) else { throw EditError.notFound }
            let gone = Set(p.tracks.flatMap(\.clips).filter { $0.assetID == id }.map(\.id))
            p.transitions.removeAll { gone.contains($0.fromClip) || gone.contains($0.toClip) }
            for t in p.tracks.indices { p.tracks[t].clips.removeAll { gone.contains($0.id) } }
            p.assets.removeAll { $0.id == id }
        case .replaceClipAsset(let id, let assetID):
            let (t, c) = try locate(id, in: p)
            guard let a = p.assets.first(where: { $0.id == assetID }) else { throw EditError.notFound }
            guard p.tracks[t].clips[c].sourceIn + p.tracks[t].clips[c].sourceLength <= a.duration + 50 else { throw EditError.invalid("the new file is shorter than the clip") }
            p.tracks[t].clips[c].assetID = assetID
        case .relinkAsset(let id, let url):
            guard let i = p.assets.firstIndex(where: { $0.id == id }) else { throw EditError.notFound }
            p.assets[i].url = url
        case .setTrackLocked(let id, let locked):
            guard let t = p.tracks.firstIndex(where: { $0.id == id }) else { throw EditError.notFound }
            p.tracks[t].locked = locked
        case .setTrackDuck(let id, let duck):
            guard let t = p.tracks.firstIndex(where: { $0.id == id }) else { throw EditError.notFound }
            guard p.tracks[t].kind == .audio else { throw EditError.invalid("only audio tracks can duck") }
            p.tracks[t].duck = duck
        case .setGenerator(let id, let kind, let amount):
            let (t, c) = try locate(id, in: p)
            guard p.tracks[t].clips[c].generator != nil else { throw EditError.invalid("not an overlay clip") }
            guard (0...1).contains(amount) else { throw EditError.invalid("amount must be 0...1") }
            p.tracks[t].clips[c].generator = kind; p.tracks[t].clips[c].generatorAmount = amount
        case .setTrackDuckLevel(let id, let level):
            guard let t = p.tracks.firstIndex(where: { $0.id == id }) else { throw EditError.notFound }
            guard (0.05...0.95).contains(level) else { throw EditError.invalid("duck level must be between 5 % and 95 %") }
            p.tracks[t].duckLevel = level
        case .setAssetFavorite(let id, let favorite):
            guard let i = p.assets.firstIndex(where: { $0.id == id }) else { throw EditError.notFound }
            p.assets[i].favorite = favorite
        case .renameAsset(let id, let name):
            guard let i = p.assets.firstIndex(where: { $0.id == id }) else { throw EditError.notFound }
            let trimmed = name?.trimmingCharacters(in: .whitespaces)
            p.assets[i].name = (trimmed?.isEmpty ?? true) ? (p.assets[i].isStill ? p.assets[i].name : nil) : trimmed
        case .setTrackName(let id, let name):
            guard let t = p.tracks.firstIndex(where: { $0.id == id }) else { throw EditError.notFound }
            p.tracks[t].name = name
        case .group(let ids):
            guard Set(ids).count >= 2 else { throw EditError.invalid("select at least two clips to group") }
            let g = UUID()
            for id in ids { let (t, c) = try locate(id, in: p); p.tracks[t].clips[c].groupID = g }
        case .ungroup(let id):
            let (t, c) = try locate(id, in: p)
            guard let g = p.tracks[t].clips[c].groupID else { throw EditError.invalid("clip is not grouped") }
            for ti in p.tracks.indices { for ci in p.tracks[ti].clips.indices where p.tracks[ti].clips[ci].groupID == g { p.tracks[ti].clips[ci].groupID = nil } }
        case .setKeyframes(let id, let frames):
            let (t, c) = try locate(id, in: p)
            let clip = p.tracks[t].clips[c]
            guard frames.allSatisfy({ (0...clip.duration).contains($0.time) && (0...1).contains($0.opacity) && $0.scale > 0 && $0.scale <= 10 }),
                  Set(frames.map(\.time)).count == frames.count else { throw EditError.invalid("keyframes need distinct times inside the clip, opacity 0...1 and scale above 0") }
            p.tracks[t].clips[c].keyframes = frames.sorted { $0.time < $1.time }
        case .setMuted(let id, let muted):
            let (t, c) = try locate(id, in: p)
            p.tracks[t].clips[c].muted = muted
        case .setTransform(let id, let opacity, let scale, let ox, let oy):
            guard (0...1).contains(opacity), scale > 0, scale <= 10 else { throw EditError.invalid("bad opacity or scale") }
            let (t, c) = try locate(id, in: p)
            p.tracks[t].clips[c].opacity = opacity; p.tracks[t].clips[c].scale = scale
            p.tracks[t].clips[c].offsetX = ox; p.tracks[t].clips[c].offsetY = oy
        case .setTextStyle(let id, let style):
            guard style.size > 0, style.size <= 1 else { throw EditError.invalid("bad text size") }
            let (t, c) = try locate(id, in: p)
            guard p.tracks[t].clips[c].text != nil else { throw EditError.invalid("not a text clip") }
            p.tracks[t].clips[c].style = style
        case .setTransition(let id, let type, let duration):
            guard let i = p.transitions.firstIndex(where: { $0.id == id }) else { throw EditError.notFound }
            guard duration > 0 else { throw EditError.invalid("zero duration") }
            let (t, c1) = try locate(p.transitions[i].fromClip, in: p)
            let (_, c2) = try locate(p.transitions[i].toClip, in: p)
            let toStart = p.tracks[t].clips[c2].start
            let overlap = p.tracks[t].clips[c1].end - toStart
            shift(&p.tracks[t], from: toStart, by: overlap - duration)   // longer transition = later clips move earlier
            p.transitions[i].type = type; p.transitions[i].duration = duration
        case .setText(let id, let text):
            let (t, c) = try locate(id, in: p)
            guard p.tracks[t].clips[c].text != nil else { throw EditError.invalid("not a text clip") }
            p.tracks[t].clips[c].text = text
        }
    }
}
