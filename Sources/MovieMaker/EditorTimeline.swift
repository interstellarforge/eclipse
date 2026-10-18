import SwiftUI
import MovieCore

private let rulerHeight: CGFloat = 28
private let trackHeight: CGFloat = 64
private let trackGap: CGFloat = 5
private let headerWidth: CGFloat = 168
private let minClip: Ms = 100

private func trackName(_ index: Int, in tracks: [Track]) -> String {
    let kind = tracks[index].kind
    let number = tracks[...index].filter { $0.kind == kind }.count
    switch kind {
    case .video: return "Video \(number)"
    case .audio: return "Audio \(number)"
    case .text: return "Titles \(number)"
    }
}

struct EditorTimeline: View {
    @EnvironmentObject var model: AppModel
    private var ppm: Double { model.pxPerSec / 1000 }

    var body: some View {
        VStack(spacing: 0) {
            TimelineToolbar()
            Rectangle().fill(Theme.stroke).frame(height: 1)
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    TrackHeaders()
                    ScrollView(.horizontal) { TimelineContent(ppm: ppm) }
                        .scrollPosition($model.timelineScroll)
                        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, new in model.timelineOffsetX = new }
                        .onScrollGeometryChange(for: CGFloat.self, of: { $0.visibleRect.width }) { _, new in model.timelineViewportWidth = new }
                }
            }
        }
        .background(Theme.panel)
    }
}

struct TimelineToolbar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "scissors", help: "Split the clip under the playhead (S)") { model.splitAtPlayhead() }
            IconButton(symbol: "plus.square.on.square", help: "Duplicate the selected clip (⌘D)") { model.duplicateSelection() }
            IconButton(symbol: "trash", help: "Delete the selection (⌫)") { model.deleteSelection() }
            IconButton(symbol: "arrow.left.to.line", help: "Delete and close the gap (⇧⌫)") { model.rippleDeleteSelection() }
            Divider().frame(height: 16).padding(.horizontal, 4)
            IconButton(symbol: "link", help: "Group the selected clips (shift-click to pick more)") { model.groupSelection() }
            IconButton(symbol: "link.badge.plus", help: "Ungroup") { model.ungroupSelection() }
            IconButton(symbol: "speaker.slash", help: "Detach the sound of the selected video clip") { model.detachAudioOfSelection() }
            IconButton(symbol: "square.2.layers.3d.top.filled", help: "Add a video layer on top") { model.addLayer() }
            Divider().frame(height: 16).padding(.horizontal, 4)
            IconButton(symbol: "arrow.counterclockwise", help: "Reset the selected clip to plain") { model.resetSelection() }
            Menu {
                ForEach([15, 30, 60], id: \.self) { s in Button("\(s) seconds") { model.autoMovie(seconds: s) } }
            } label: { Image(systemName: "wand.and.stars").font(.system(size: 14)).foregroundStyle(Theme.text).frame(width: 30, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Quick automatic edit (needs an empty timeline)")
                .disabled(model.autoMaking || !model.project.assets.contains { $0.hasVideo })
            Spacer()
            IconButton(symbol: "magnet", help: "Snap clips to edges and the playhead", active: model.snapEnabled) { model.snapEnabled.toggle() }
            IconButton(symbol: "minus.magnifyingglass", help: "Zoom out") { model.pxPerSec = max(10, model.pxPerSec / 1.4) }
            Slider(value: $model.pxPerSec, in: 10...400).frame(width: 120).controlSize(.small)
            IconButton(symbol: "plus.magnifyingglass", help: "Zoom in") { model.pxPerSec = min(400, model.pxPerSec * 1.4) }
            IconButton(symbol: "arrow.left.and.right.square", help: "Fit the whole movie") { model.zoomToFit(width: Double(model.timelineViewportWidth > 100 ? model.timelineViewportWidth + 160 : 1200)) }
        }.padding(.horizontal, 10).frame(height: 38)
    }
}

struct TrackHeaders: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let tracks = model.project.tracks
        VStack(spacing: trackGap) {
            Color.clear.frame(width: headerWidth, height: rulerHeight - trackGap)
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                HStack(spacing: 8) {
                    Image(systemName: track.kind == .video ? "film" : track.kind == .audio ? (track.duck ? "music.note" : "waveform") : "textformat")
                        .font(.system(size: 13)).foregroundStyle(Theme.dim).frame(width: 18)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.name ?? trackName(i, in: tracks)).font(.system(size: 12, weight: .medium)).lineLimit(1).foregroundStyle(Theme.text)
                        HStack(spacing: 2) {
                            small(track.locked ? "lock.fill" : "lock.open", track.locked ? "Unlock track" : "Lock track (protect its clips)", active: track.locked) { model.setLocked(track, !track.locked) }
                            if track.kind == .audio {
                                small(track.muted ? "speaker.slash.fill" : "speaker.wave.2", track.muted ? "Unmute track" : "Mute track", active: track.muted) { model.setTrack(track, muted: !track.muted) }
                                small(track.duck ? "arrow.down.circle.fill" : "arrow.down.circle", track.duck ? "Ducking on: dips under speech and clip sound" : "Duck this track under speech and clip sound (music)", active: track.duck) { model.setDuck(track, !track.duck) }
                            } else {
                                small(track.hidden ? "eye.slash.fill" : "eye", track.hidden ? "Show track" : "Hide track", active: track.hidden) { model.setTrack(track, hidden: !track.hidden) }
                            }
                            small("xmark", "Remove this track and its clips", active: false) { model.removeTrack(track.id) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).frame(width: headerWidth - 8, height: trackHeight).card(radius: 10)
                .opacity(track.muted || track.hidden ? 0.55 : 1)
            }
            if model.ghost != nil {
                ForEach(Array((model.ghost?.project.tracks ?? []).enumerated()), id: \.element.id) { i, _ in
                    HStack { Image(systemName: "sparkles").foregroundStyle(Theme.accent); Text("Ghost \(i + 1)").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.accent); Spacer() }
                        .padding(.horizontal, 10).frame(width: headerWidth - 8, height: 36).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }.padding(.leading, 8).padding(.bottom, 4).frame(width: headerWidth + 4)
    }

    private func small(_ symbol: String, _ help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10.5)).foregroundStyle(active ? Theme.accent : Theme.dim).frame(width: 22, height: 20)
                .background(active ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).help(help)
    }
}

struct TimelineContent: View {
    @EnvironmentObject var model: AppModel
    let ppm: Double

    var body: some View {
        let width = max(Double(model.project.duration + 12_000) * ppm, Double(model.timelineViewportWidth))
        let tracks = model.project.tracks
        let ghostTracks = model.ghost?.project.tracks ?? []
        let rows = max(tracks.count, 1)
        let height = rulerHeight + CGFloat(rows) * (trackHeight + trackGap) + CGFloat(ghostTracks.count) * 40 + 8
        ZStack(alignment: .topLeading) {
            // Clicking or dragging anywhere on an empty part of the timeline moves the playhead to that frame.
            Color.clear.frame(width: width, height: height).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in model.seek(Ms(max(0, g.location.x) / ppm)) }
                    .onEnded { g in
                        if abs(g.translation.width) < 3, abs(g.translation.height) < 3, g.startLocation.y > rulerHeight { model.selection = nil; model.selectedTransition = nil; model.multiSelection = [] }
                    })
            Ruler(width: width, pxPerSec: model.pxPerSec)
            if let range = model.ghostRange {
                Rectangle().fill(Theme.accent.opacity(0.18)).frame(width: Double(range.upperBound - range.lowerBound) * ppm, height: height).offset(x: Double(range.lowerBound) * ppm).allowsHitTesting(false)
            }
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                let y = rulerHeight + CGFloat(i) * (trackHeight + trackGap)
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.035)).frame(width: width, height: trackHeight).allowsHitTesting(false).offset(y: y)
                ForEach(track.clips) { clip in ClipView(clip: clip, kind: track.kind, duck: track.duck, ppm: ppm, locked: track.locked).offset(y: y) }
                ForEach(model.project.transitions) { tr in
                    if let f = track.clips.first(where: { $0.id == tr.fromClip }), let t = track.clips.first(where: { $0.id == tr.toClip }) {
                        TransitionBand(transition: tr, width: max(Double(f.end - t.start) * ppm, 8)).offset(x: Double(t.start) * ppm, y: y)
                    }
                }
            }
            ForEach(Array(ghostTracks.enumerated()), id: \.element.id) { i, track in
                let y = rulerHeight + CGFloat(rows) * (trackHeight + trackGap) + CGFloat(i) * 40
                ForEach(track.clips) { clip in
                    RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.28))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                        .overlay(Text(model.project.assets.first { $0.id == clip.assetID }?.label ?? clip.text ?? clip.generator?.title ?? "").font(.system(size: 10)).foregroundStyle(.white).lineLimit(1).padding(.horizontal, 5), alignment: .leading)
                        .frame(width: max(Double(clip.duration) * ppm, 4), height: 32).offset(x: Double(clip.start) * ppm, y: y + 4).allowsHitTesting(false)
                }
            }
            Playhead(height: height).offset(x: Double(model.playhead) * ppm - 6)
        }
        .dropDestination(for: URL.self) { urls, _ in model.importFiles(urls); return !urls.isEmpty }
        .dropDestination(for: String.self) { items, location in
            guard let payload = items.first else { return false }
            let row = location.y >= rulerHeight ? Int((location.y - rulerHeight) / (trackHeight + trackGap)) : nil
            return model.handleDrop(payload, at: Ms(location.x / ppm), trackIndex: row)
        }
    }
}

struct TransitionBand: View {
    @EnvironmentObject var model: AppModel
    let transition: MovieCore.Transition
    let width: Double

    var body: some View {
        let selected = model.selectedTransition == transition.id
        RoundedRectangle(cornerRadius: 5).fill(Color.orange.opacity(0.85))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.white : .orange, lineWidth: selected ? 2 : 1))
            .overlay {
                VStack(spacing: 1) {
                    Image(systemName: "arrow.triangle.merge").font(.system(size: 10, weight: .bold))
                    if width > 64 { Text(transition.type.title).font(.system(size: 9, weight: .semibold)).lineLimit(1) }
                }.foregroundStyle(.white)
            }
            .frame(width: width, height: trackHeight)
            .contentShape(Rectangle())
            .help("\(transition.type.title), \(String(format: "%.1f", Double(transition.duration) / 1000)) s: click to edit")
            .onTapGesture { model.selectTransition(transition.id) }
            .contextMenu {
                Button("Edit transition") { model.selectTransition(transition.id) }
                Menu("Change style") {
                    ForEach(TransitionType.allCases, id: \.self) { type in
                        Button(type.title) { model.perform(.setTransition(transition.id, type: type, duration: transition.duration), quiet: true) }
                    }
                }
                Divider()
                Button("Remove transition", role: .destructive) { model.perform(.removeTransition(transition.id)); model.selectedTransition = nil }
            }
    }
}

struct Ruler: View {
    let width: Double
    let pxPerSec: Double

    var body: some View {
        let step = pxPerSec >= 200 ? 0.5 : pxPerSec >= 100 ? 1.0 : pxPerSec >= 40 ? 2.0 : pxPerSec >= 20 ? 5.0 : 10.0
        Canvas { ctx, size in
            var s = 0.0
            while s * pxPerSec < width {
                let x = s * pxPerSec
                ctx.fill(Path(CGRect(x: x, y: rulerHeight - 9, width: 1, height: 9)), with: .color(.white.opacity(0.35)))
                let minutes = Int(s) / 60, seconds = Int(s) % 60
                ctx.draw(Text(String(format: "%02d:%02d", minutes, seconds) + (s.truncatingRemainder(dividingBy: 1) != 0 ? ".5" : "")).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.55)),
                         at: CGPoint(x: x + 4, y: 9), anchor: .leading)
                s += step
            }
        }.frame(width: width, height: rulerHeight).allowsHitTesting(false)
    }
}

struct Playhead: View {
    let height: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 13)).foregroundStyle(Theme.accent).offset(y: 1)
            Rectangle().fill(Theme.accent).frame(width: 2, height: max(0, height - 13))
        }.frame(width: 12, height: height, alignment: .top).allowsHitTesting(false)
    }
}

/// Loudness drawn along a clip. The height follows the clip's volume and fades, so turning it down shows.
struct WaveformView: View {
    let levels: [Float]
    let clip: Clip
    let ppm: Double
    private let hopMs = 50.0

    var body: some View {
        Canvas { ctx, size in
            var x = 0.0
            let length = Double(clip.duration)
            while x < size.width {
                let timeline = x / ppm   // ms from the start of the clip
                let a = Int((Double(clip.sourceIn) + timeline * clip.speed) / hopMs)
                let b = Int((Double(clip.sourceIn) + (timeline + 2 / ppm) * clip.speed) / hopMs)
                if a < levels.count {
                    let peak = Double(levels[a...min(max(a, b), levels.count - 1)].max() ?? 0)
                    var gain = clip.volume
                    if clip.fadeIn > 0 { gain *= min(1, timeline / Double(clip.fadeIn)) }
                    if clip.fadeOut > 0 { gain *= min(1, (length - timeline) / Double(clip.fadeOut)) }
                    let h = max(1, CGFloat(min(1.15, peak * gain)) * size.height)
                    ctx.fill(Path(CGRect(x: x, y: (size.height - h) / 2, width: 1.5, height: h)), with: .color(.white.opacity(0.85)))
                }
                x += 2
            }
        }.allowsHitTesting(false)
    }
}

/// Frames of the clip laid side by side along its length.
struct FilmstripView: View {
    let frames: [CGImage]
    let clip: Clip
    let asset: Asset
    let ppm: Double

    var body: some View {
        Canvas { ctx, size in
            guard !frames.isEmpty else { return }
            let tile = size.height * 16 / 9
            var x: CGFloat = 0
            while x < size.width {
                let timeline = Double(x + tile / 2) / ppm
                let sourceTime = Double(clip.sourceIn) + timeline * clip.speed
                let index = max(0, min(frames.count - 1, Int(sourceTime / Double(max(1, asset.duration)) * Double(frames.count))))
                ctx.draw(ctx.resolve(Image(decorative: frames[index], scale: 1)), in: CGRect(x: x, y: 0, width: tile, height: size.height))
                x += tile
            }
        }.allowsHitTesting(false)
    }
}

/// Live drag deltas, committed as a command on release.
final class DragState: ObservableObject {
    @Published var moveMs: Ms = 0
    @Published var leftMs: Ms = 0
    @Published var rightMs: Ms = 0
}

struct ClipView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var chat: ChatModel
    let clip: Clip
    let kind: TrackKind
    var duck = false
    let ppm: Double
    var locked = false
    @StateObject private var drag = DragState()

    private var asset: Asset? { model.project.assets.first { $0.id == clip.assetID } }
    private var selected: Bool { model.selection == clip.id }
    private var multi: Bool { model.multiSelection.contains(clip.id) }
    private var fill: Color {
        if clip.generator != nil { return Theme.overlayClip }
        switch kind { case .video: return Theme.video; case .audio: return duck ? Theme.music : Theme.audio; case .text: return Theme.titleClip }
    }

    var body: some View {
        let start = clip.start + drag.moveMs + drag.leftMs
        let duration = clip.duration - drag.leftMs + drag.rightMs
        let width = max(Double(duration) * ppm, 6)
        let levels = model.waveforms[clip.assetID ?? UUID()] ?? []
        let strip = model.filmstrips[clip.assetID ?? UUID()] ?? []
        let _ = { if strip.isEmpty, kind == .video, let asset { model.ensureFilmstrip(asset) } }()
        let showWave = !levels.isEmpty && !(kind == .video && clip.muted)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9).fill(fill.opacity(0.8))
            if kind == .video, let asset, !strip.isEmpty {
                FilmstripView(frames: strip, clip: clip, asset: asset, ppm: ppm).frame(width: width, height: trackHeight).opacity(0.78)
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center).frame(width: width, height: trackHeight).allowsHitTesting(false)
            }
            if showWave {
                WaveformView(levels: levels, clip: clip, ppm: ppm)
                    .frame(width: width, height: kind == .audio ? trackHeight - 14 : trackHeight * 0.42)
                    .frame(height: trackHeight, alignment: kind == .audio ? .center : .bottom)
            }
            HStack(spacing: 4) {
                if kind == .video && clip.muted { Image(systemName: "speaker.slash.fill") }
                if clip.groupID != nil { Image(systemName: "link") }
                if locked { Image(systemName: "lock.fill") }
                if !clip.effects.isEmpty { Image(systemName: "sparkles") }
                if clip.speed != 1 { Text(String(format: "%.2g×", clip.speed)).font(.system(size: 9.5, weight: .bold)) }
                Text(asset?.label ?? clip.text ?? clip.generator?.title ?? "").lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 2).padding(.leading, 9).padding(.top, 6).allowsHitTesting(false)
            RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.white : multi ? Color.cyan : Color.white.opacity(0.18), lineWidth: selected || multi ? 2.2 : 1).allowsHitTesting(false)
            HStack {
                handle.gesture(trim(left: true))
                Spacer()
                handle.gesture(trim(left: false))
            }
        }
        .frame(width: width, height: trackHeight)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .shadow(color: selected ? Theme.accent.opacity(0.6) : .clear, radius: 6)
        .offset(x: Double(start) * ppm)
        .opacity(locked ? 0.6 : 1)
        .onTapGesture { model.clickClip(clip.id, shift: NSEvent.modifierFlags.contains(.shift)) }
        .gesture(DragGesture().onChanged { g in
            guard !locked else { return }
            model.selection = clip.id
            drag.moveMs = snapped(clip.start + Ms(g.translation.width / ppm), edgeOf: clip.duration) - clip.start
        }.onEnded { _ in
            guard !locked else { return }
            let target = max(0, clip.start + drag.moveMs)
            drag.moveMs = 0
            model.perform(.moveClip(clip.id, start: target), quiet: true)
        })
        .contextMenu { clipMenu }
    }

    @ViewBuilder private var clipMenu: some View {
        Button("Mention in Assistant") {
            let name = asset?.label ?? clip.text ?? clip.generator?.title ?? "clip"
            let source = clip.assetID == nil ? "" : ", source \(formatTime(clip.sourceIn))–\(formatTime(clip.sourceIn + clip.duration))"
            chat.mention("[clip \"\(name)\" clip_id=\(clip.id.uuidString), timeline \(formatTime(clip.start))–\(formatTime(clip.start + clip.duration))\(source)]")
            model.rightTab = .assistant; model.showRight = true
        }
        Divider()
        Button("Split at playhead") { model.splitClip(clip) }
        Button("Duplicate") { model.selection = clip.id; model.duplicateSelection() }
        Button("Delete") { model.selection = clip.id; model.deleteSelection() }
        Button("Delete & close gap") { model.selection = clip.id; model.rippleDeleteSelection() }
        Divider()
        if kind == .video && !clip.muted && asset?.hasAudio == true { Button("Detach audio") { model.selection = clip.id; model.detachAudioOfSelection() } }
        if kind == .video && asset?.hasAudio == true { Button(clip.muted ? "Unmute clip sound" : "Mute clip sound") { model.toggleMute(clip) } }
        Button(clip.groupID == nil ? "Group (shift-click others first)" : "Ungroup") { model.selection = clip.id; clip.groupID == nil ? model.groupSelection() : model.ungroupSelection() }
        Button("Reset clip") { model.selection = clip.id; model.resetSelection() }
        if kind == .video && clip.text == nil && clip.generator == nil {
            Divider()
            Menu("Add transition after this clip") {
                ForEach([TransitionType.crossfade, .fadeBlack, .whipLeft, .zoomBlur, .slide, .flashCut, .glitchCut, .wipe, .irisOpen, .pageCurl], id: \.self) { type in
                    Button(type.title) { model.addTransitionMenu(type, to: clip) }
                }
            }
            Menu("Add effect") {
                ForEach([EffectType.kenBurnsIn, .glow, .grain, .shake, .vhs, .flash, .cinemaBars, .duotone], id: \.self) { type in Button(type.title) { model.addEffect(type, to: clip.id) } }
            }
        }
        Divider()
        Button("Get info") { model.infoTarget = .clip(clip.id) }
        if let asset { Button("Show in Finder") { model.reveal(asset) } }
    }

    private var handle: some View {
        Rectangle().fill(Color.white.opacity(0.001)).frame(width: 7).contentShape(Rectangle())
            .overlay(Capsule().fill(Color.white.opacity(selected ? 0.8 : 0.0)).frame(width: 3, height: 24))
            .onHover { inside in if inside && !locked { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
    }

    private func trim(left: Bool) -> some Gesture {
        DragGesture().onChanged { g in
            guard !locked else { return }
            model.selection = clip.id
            let d = Ms(g.translation.width / ppm)
            if left {
                let lo = max(-clip.sourceIn, -clip.start)
                drag.leftMs = min(max(d, lo), clip.duration - minClip)
            } else {
                let hi = asset.map { $0.duration - clip.sourceIn - clip.sourceLength } ?? Ms.max
                drag.rightMs = min(max(d, minClip - clip.duration), Ms(Double(hi) / max(clip.speed, 0.01)))
            }
        }.onEnded { _ in
            guard !locked else { return }
            let l = drag.leftMs, r = drag.rightMs
            drag.leftMs = 0; drag.rightMs = 0
            model.perform(.trimClip(clip.id, sourceIn: clip.sourceIn + Ms((Double(l) * clip.speed).rounded()), duration: clip.duration - l + r, start: clip.start + l), quiet: true)
        }
    }

    /// Snaps the clip's start or end to 0, the playhead, or other clip edges (within 8 px).
    private func snapped(_ start: Ms, edgeOf duration: Ms) -> Ms {
        guard model.snapEnabled else { return start }
        let others = model.project.tracks.flatMap(\.clips).filter { $0.id != clip.id }
        let targets: [Ms] = [0, model.playhead] + others.flatMap { [$0.start, $0.end] }
        let threshold = Ms(8 / ppm)
        let s = snap(start, to: targets, threshold: threshold)
        if s != start { return s }
        return snap(start + duration, to: targets, threshold: threshold) - duration
    }
}
