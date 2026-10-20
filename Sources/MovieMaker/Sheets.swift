import AVKit
import AppKit
import SwiftUI
import MovieCore

// MARK: Get info

struct InfoSheet: View {
    @EnvironmentObject var model: AppModel
    let target: InfoTarget
    @StateObject private var loaded = InfoLoader()

    final class InfoLoader: ObservableObject { @Published var info: AssetInfo? }

    private var asset: Asset? {
        switch target {
        case .asset(let id): return model.project.assets.first { $0.id == id }
        case .clip(let id): return model.project.tracks.flatMap(\.clips).first { $0.id == id }.flatMap { c in model.project.assets.first { $0.id == c.assetID } }
        }
    }
    private var clip: Clip? { if case .clip(let id) = target { return model.project.tracks.flatMap(\.clips).first { $0.id == id } } else { return nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(clip != nil ? "Clip info" : "File info").font(.title3.bold())
                Spacer()
                Button("Done") { model.infoTarget = nil }.keyboardShortcut(.defaultAction)
            }
            if let asset {
                HStack(alignment: .top, spacing: 14) {
                    if let image = model.thumbnails[asset.id] { Image(decorative: image, scale: 1).resizable().scaledToFit().frame(width: 190).cornerRadius(8) }
                    VStack(alignment: .leading, spacing: 6) {
                        row("Name", asset.label)
                        row("Duration", "\(formatTime(asset.duration)) (\(asset.duration) ms)")
                        if let info = loaded.info {
                            row("Picture", info.video ?? "none"); row("Sound", info.audio ?? "none")
                            row("Size", ByteCountFormatter.string(fromByteCount: info.fileSize, countStyle: .file))
                            if let created = info.created { row("Created", created.formatted(date: .abbreviated, time: .shortened)) }
                        } else { ProgressView().controlSize(.small) }
                        row("Used", "\(model.project.tracks.flatMap(\.clips).filter { $0.assetID == asset.id }.count) times in this movie")
                        row("Location", asset.url.path)
                    }
                }
            }
            if let clip {
                Divider()
                SectionTitle(text: "On the timeline")
                VStack(alignment: .leading, spacing: 6) {
                    row("Position", "\(timecode(clip.start, fps: model.project.fps)) – \(timecode(clip.end, fps: model.project.fps))")
                    row("Length", "\(formatTime(clip.duration)) (\(clip.duration) ms)")
                    if clip.assetID != nil {
                        row("Source part", "\(formatTime(clip.sourceIn)) – \(formatTime(clip.sourceIn + clip.sourceLength))")
                        row("Speed", String(format: "%.2f×", clip.speed)); row("Volume", String(format: "%.0f %%", clip.volume * 100) + (clip.muted ? " (picture only)" : ""))
                    }
                    if !clip.effects.isEmpty { row("Effects", clip.effects.map(\.type.title).joined(separator: ", ")) }
                    if let kind = clip.generator { row("Overlay", kind.title) }
                    if let text = clip.text { row("Text", text) }
                    if clip.groupID != nil { row("Group", "linked with other clips") }
                }
            }
            if let asset { HStack { Button("Show in Finder") { model.reveal(asset) }; Spacer() } }
        }
        .padding(20).frame(width: 560)
        .task { if let asset { loaded.info = await AssetInfo.load(asset) } }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12.5))
    }
}

// MARK: Rename

struct RenameSheet: View {
    @EnvironmentObject var model: AppModel
    let asset: Asset
    @StateObject private var text = TextBox()
    final class TextBox: ObservableObject { @Published var value = "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename").font(.title3.bold())
            TextField("Name", text: $text.value).textFieldStyle(.roundedBorder).onSubmit { model.rename(asset, to: text.value) }
            Text("Only the name shown in Eclipse changes, not the file on disk.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { model.renameTarget = nil }; Button("Rename") { model.rename(asset, to: text.value) }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 380).onAppear { text.value = asset.label }
    }
}

// MARK: Apply a template

struct ApplyTemplateSheet: View {
    @EnvironmentObject var model: AppModel
    let template: EditTemplate
    @StateObject private var options = Options()
    final class Options: ObservableObject {
        @Published var selectedOnly = false
        @Published var transitions = true
        @Published var titles = true
        @Published var overlay = true
        @Published var music = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                if let image = model.templateThumbs[template.id] { Image(decorative: image, scale: 1).resizable().scaledToFit().frame(width: 220).cornerRadius(10) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.name).font(.title2.bold())
                    Text(template.category).font(.caption).padding(.horizontal, 8).padding(.vertical, 2).background(Theme.accentSoft, in: Capsule())
                    Text(template.summary).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Pace: \(template.pace)").font(.system(size: 12))
                }
            }
            GroupBox("What it changes") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Apply to", selection: $options.selectedOnly) { Text("All video clips").tag(false); Text("Only the selected clip").tag(true) }.pickerStyle(.segmented)
                    if let t = template.transition { Toggle("Joins between clips: \(t.title) (\(template.transitionMs) ms)", isOn: $options.transitions) }
                    if let title = template.titleStyle { Toggle("Restyle titles like “\(title.rawValue)”", isOn: $options.titles) }
                    if let overlay = template.overlay { Toggle("Add the \(overlay.title.lowercased()) overlay over the movie", isOn: $options.overlay) }
                    if let music = template.music { Toggle("Also add the suggested music “\(music)”", isOn: $options.music) }
                    Text("The look and effects of the clips are replaced. You can undo this with ⌘Z.").font(.caption).foregroundStyle(.secondary)
                }.padding(6)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.templateToApply = nil }
                Button("Apply") {
                    var o = Editor.TemplateOptions(); o.transitions = options.transitions; o.titles = options.titles; o.overlay = options.overlay
                    model.applyTemplate(template, selectedOnly: options.selectedOnly, options: o, addMusic: options.music)
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 520)
    }
}

// MARK: Speed ramp studio

struct SpeedRampSheet: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var curve = Curve()

    final class Curve: ObservableObject {
        @Published var points = SpeedRamp.presets[0].points
        @Published var segments = 20.0
        @Published var preset = SpeedRamp.presets[0].name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Speed ramp studio").font(.title3.bold())
                Spacer()
                Button("Close") { model.rampSheet = false }
            }
            Text("Choose how the speed changes along the clip. 1× is normal, below 1× is slow motion, above is fast. The clip is cut into small pieces at changing speeds; undo returns the original.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SpeedRamp.presets, id: \.name) { p in Chip(title: p.name, selected: curve.preset == p.name) { curve.preset = p.name; curve.points = p.points } }
                }
            }
            CurveView(points: curve.points).frame(height: 130).card(Theme.panel, radius: 10)
            GroupBox("Points on the curve") {
                VStack(spacing: 6) {
                    ForEach(curve.points.indices, id: \.self) { i in
                        HStack(spacing: 10) {
                            Text("at").foregroundStyle(.secondary)
                            Text("\(Int(curve.points[i].position * 100)) %").frame(width: 44, alignment: .leading).monospacedDigit()
                            Slider(value: Binding(get: { log2(curve.points[i].speed) }, set: { curve.points[i].speed = min(8, max(0.1, pow(2, $0))); curve.preset = "Custom" }), in: log2(0.1)...log2(8))
                            Text(String(format: "%.2f×", curve.points[i].speed)).frame(width: 52, alignment: .trailing).monospacedDigit()
                        }
                    }
                }.padding(6)
            }
            HStack {
                Text("Smoothness").foregroundStyle(.secondary)
                Slider(value: $curve.segments, in: 8...40, step: 1)
                Text("\(Int(curve.segments)) pieces").monospacedDigit().frame(width: 70)
            }
            if let c = model.selectedClip, model.project.transitions.contains(where: { $0.fromClip == c.id || $0.toClip == c.id }) {
                Label("This clip has transitions. Remove them first; add them again after the ramp.", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            HStack { Spacer(); Button("Apply to the selected clip") { model.rampSelection(curve.points, segments: Int(curve.segments)) }.buttonStyle(.borderedProminent) }
        }.padding(20).frame(width: 560)
    }
}

struct CurveView: View {
    let points: [RampPoint]
    var body: some View {
        Canvas { ctx, size in
            let lo = log2(0.1), hi = log2(8.0)
            func y(_ speed: Double) -> CGFloat { size.height - CGFloat((log2(speed) - lo) / (hi - lo)) * (size.height - 16) - 8 }
            var one = Path(); one.move(to: CGPoint(x: 0, y: y(1))); one.addLine(to: CGPoint(x: size.width, y: y(1)))
            ctx.stroke(one, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            var path = Path()
            for i in 0...120 {
                let u = Double(i) / 120, p = CGPoint(x: CGFloat(u) * size.width, y: y(SpeedRamp.speed(at: u, points)))
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            ctx.stroke(path, with: .color(Theme.accent), lineWidth: 2.5)
            for p in points { ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(p.position) * size.width - 4, y: y(p.speed) - 4, width: 8, height: 8)), with: .color(.white)) }
            ctx.draw(Text("1×").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: 14, y: y(1) - 8))
        }
    }
}

// MARK: Offline mode: mark the parts that matter

final class RangePlayer: ObservableObject {
    let player = AVPlayer()
    @Published var currentMs: Ms = 0
    @Published var playing = false
    private var observer: Any?

    init() {
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            guard let self else { return }
            self.currentMs = Ms(max(0, t.seconds) * 1000)
            self.playing = self.player.rate != 0
        }
    }

    deinit { if let observer { player.removeTimeObserver(observer) }; player.pause() }

    func load(_ url: URL) { player.replaceCurrentItem(with: AVPlayerItem(url: url)); currentMs = 0; playing = false }
    func seek(_ ms: Ms) { player.seek(to: CMTime(value: ms, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero); currentMs = ms }
    /// While dragging the slider: loose tolerance so the picture follows the thumb instead of waiting for the release.
    func scrub(_ ms: Ms) {
        player.pause()
        let t = CMTime(value: ms, timescale: 1000), tol = CMTime(value: 300, timescale: 1000)
        player.seek(to: t, toleranceBefore: tol, toleranceAfter: tol); currentMs = ms
    }
    func toggle() { player.rate == 0 ? player.play() : player.pause() }
}

struct RawPlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView { let v = AVPlayerView(); v.controlsStyle = .none; v.player = player; return v }
    func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}

/// Offline mode: the user watches their files one by one and marks "start here" / "end here"; only the ranges go to Claude.
struct SelectionSheet: View {
    @EnvironmentObject var model: AppModel
    let request: SelectionRequest
    @StateObject private var player = RangePlayer()
    final class Picks: ObservableObject {
        @Published var current: UUID?
        @Published var included = Set<UUID>()
        @Published var ranges: [UUID: [Range<Ms>]] = [:]
        @Published var start: Ms?
        @Published var message = ""
    }
    @StateObject private var picks = Picks()
    private var current: UUID? { get { picks.current } nonmutating set { picks.current = newValue } }
    private var included: Set<UUID> { get { picks.included } nonmutating set { picks.included = newValue } }
    private var ranges: [UUID: [Range<Ms>]] { get { picks.ranges } nonmutating set { picks.ranges = newValue } }
    private var start: Ms? { get { picks.start } nonmutating set { picks.start = newValue } }
    private var markedParts: Int { ranges.values.map(\.count).reduce(0, +) }

    private var assets: [Asset] {
        model.project.assets.filter { $0.hasVideo && !$0.isStill && (request.assetIDs.isEmpty || request.assetIDs.contains($0.id)) }
    }
    private var asset: Asset? { assets.first { $0.id == current } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "lock.fill").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.reason).font(.system(size: 14, weight: .semibold))
                    Text("Offline mode: Claude never sees these videos. It only receives the start and end times you mark here.").font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                }
                Spacer()
            }.padding(14)
            Divider()
            HStack(spacing: 0) {
                List(assets, id: \.id, selection: $picks.current) { a in
                    HStack {
                        Toggle("", isOn: Binding(get: { included.contains(a.id) }, set: { if $0 { included.insert(a.id) } else { included.remove(a.id) } })).labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.label).lineLimit(1)
                            Text("\(formatTime(a.duration)) · \((ranges[a.id] ?? []).count) part\((ranges[a.id] ?? []).count == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.dim)
                        }
                    }.tag(a.id)
                }.frame(width: 240)
                Divider()
                VStack(spacing: 10) {
                    if let asset {
                        RawPlayerView(player: player.player).frame(minHeight: 260).clipShape(RoundedRectangle(cornerRadius: 10)).background(Color.black, in: RoundedRectangle(cornerRadius: 10))
                        HStack(spacing: 10) {
                            Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill") }.keyboardShortcut(.space, modifiers: [])
                            Button { player.seek(max(0, player.currentMs - Ms(model.frameMs.rounded()))) } label: { Image(systemName: "backward.frame.fill") }
                            Button { player.seek(min(asset.duration, player.currentMs + Ms(model.frameMs.rounded()))) } label: { Image(systemName: "forward.frame.fill") }
                            Slider(value: Binding(get: { Double(player.currentMs) }, set: { player.scrub(Ms($0)) }), in: 0...Double(max(1, asset.duration)), onEditingChanged: { editing in if !editing { player.seek(player.currentMs) } })
                            Text("\(formatTime(player.currentMs)) / \(formatTime(asset.duration))").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.dim)
                        }
                        HStack(spacing: 8) {
                            Button { start = player.currentMs } label: { Label("Start here", systemImage: "arrow.right.to.line") }
                            Button { addRange(to: player.currentMs, of: asset) } label: { Label("End here", systemImage: "arrow.left.to.line") }.disabled(start == nil)
                            Button("Whole clip") { ranges[asset.id, default: []].append(0..<asset.duration); included.insert(asset.id) }
                            Spacer()
                            if let start { Text("Start \(formatTime(start)): press End here").font(.system(size: 11.5)).foregroundStyle(Theme.accent) }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array((ranges[asset.id] ?? []).enumerated()), id: \.offset) { i, r in
                                HStack {
                                    Text("\(formatTime(r.lowerBound)) – \(formatTime(r.upperBound))").font(.system(size: 12, design: .monospaced))
                                    Button { player.seek(r.lowerBound) } label: { Image(systemName: "play.circle") }.buttonStyle(.plain)
                                    Spacer()
                                    Button { ranges[asset.id]?.remove(at: i) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(Theme.dim)
                                }.padding(.horizontal, 8).padding(.vertical, 4).card(radius: 6)
                            }
                            if (ranges[asset.id] ?? []).isEmpty { Text("No parts marked in this file yet.").font(.system(size: 11.5)).foregroundStyle(Theme.dim) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Choose a file on the left.").foregroundStyle(Theme.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.padding(14)
            }
            Divider()
            HStack {
                Text(picks.message.isEmpty ? (markedParts == 0 ? "Play a file, press Start here and End here to mark a part. Files with no marked part are left out unless you tick them (whole file)." : "\(markedParts) part\(markedParts == 1 ? "" : "s") marked in \(included.count) file\(included.count == 1 ? "" : "s").") : picks.message)
                    .font(.system(size: 11.5)).foregroundStyle(picks.message.isEmpty ? Theme.dim : .orange).lineLimit(2)
                Spacer()
                Button("Cancel") { model.finishSelection(nil) }.keyboardShortcut(.cancelAction)
                Button("Done") { model.finishSelection(summary()) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(included.isEmpty)
            }.padding(14)
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear { current = assets.first?.id }
        .onChange(of: current) { _, id in start = nil; if let a = assets.first(where: { $0.id == id }) { player.load(a.url) } }
    }

    private func addRange(to end: Ms, of asset: Asset) {
        guard let s = start else { return }
        let lo = min(s, end), hi = max(s, end)
        if hi - lo >= 200 { ranges[asset.id, default: []].append(lo..<hi); included.insert(asset.id); picks.message = "" }
        else { picks.message = "That part is too short: move the playhead further before pressing End here." }
        start = nil
    }

    private func summary() -> String {
        let lines = assets.filter { included.contains($0.id) }.map { a -> String in
            let r = (ranges[a.id] ?? []).sorted { $0.lowerBound < $1.lowerBound }
            let parts = r.isEmpty ? "no parts marked: use the whole file if you need it" : r.map { "\($0.lowerBound)-\($0.upperBound)" }.joined(separator: ", ")
            return "- \(a.label) (asset_id=\(a.id.uuidString), length \(a.duration) ms): \(parts)"
        }
        return "The user marked these parts in their videos (start_ms-end_ms in each source file). Use these ranges; files that are not listed are not to be used:\n" + lines.joined(separator: "\n")
    }
}

// MARK: Script review (medium, advanced and director modes)

struct ScriptSheet: View {
    @EnvironmentObject var model: AppModel
    final class Edit: ObservableObject {
        @Published var draft = ScriptDraft(title: "", logline: "", beats: [])
        @Published var feedback = ""
        var loaded = false
    }
    @StateObject private var edit = Edit()

    private func name(_ id: UUID?) -> String { id.flatMap { id in model.project.assets.first { $0.id == id }?.label } ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: "text.book.closed").foregroundStyle(Theme.accent).font(.system(size: 18))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Title", text: $edit.draft.title).textFieldStyle(.plain).font(.system(size: 17, weight: .semibold))
                    TextField("The idea in a sentence", text: $edit.draft.logline, axis: .vertical).textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Theme.dim)
                }
                Spacer()
                Text("\(model.scriptLevel.rawValue) mode · about \(Int(edit.draft.beats.map(\.seconds).reduce(0, +))) s").font(.system(size: 11.5)).foregroundStyle(Theme.dim)
            }.padding(14)
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(edit.draft.beats.enumerated()), id: \.offset) { i, beat in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("\(i + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22).background(Theme.accent, in: Circle())
                                TextField("Beat", text: $edit.draft.beats[i].title).textFieldStyle(.plain).font(.system(size: 13.5, weight: .semibold))
                                Stepper(value: $edit.draft.beats[i].seconds, in: 0.5...60, step: 0.5) { Text("\(String(format: "%.1f", beat.seconds)) s").font(.system(size: 12, design: .monospaced)) }.fixedSize()
                                Button { if i > 0 { edit.draft.beats.swapAt(i, i - 1) } } label: { Image(systemName: "arrow.up") }.buttonStyle(.plain).disabled(i == 0)
                                Button { if i < edit.draft.beats.count - 1 { edit.draft.beats.swapAt(i, i + 1) } } label: { Image(systemName: "arrow.down") }.buttonStyle(.plain).disabled(i == edit.draft.beats.count - 1)
                                Button { edit.draft.beats.remove(at: i) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(Theme.dim)
                            }
                            TextField("What this beat shows", text: $edit.draft.beats[i].detail, axis: .vertical).textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.text)
                            HStack(spacing: 10) {
                                if beat.assetID != nil {
                                    Label("\(name(beat.assetID))\(beat.startMs.map { s in beat.endMs.map { e in " \(formatTime(Ms(s)))–\(formatTime(Ms(e)))" } ?? "" } ?? "")", systemImage: "film").font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                                }
                                ComboField(label: "join", placeholder: "cut", text: $edit.draft.beats[i].join, presets: ["cut"] + TransitionType.allCases.map(\.rawValue)).frame(minWidth: 130)
                                ComboField(label: "sound", placeholder: "keep", text: $edit.draft.beats[i].sound, presets: ["keep", "mute", "keep 0.6, music lower", "music only", "keep, fade out", "keep, fade in"]).frame(minWidth: 130)
                                HStack(spacing: 3) { Text("text").font(.system(size: 11)).foregroundStyle(Theme.dim); TextField("none", text: $edit.draft.beats[i].text).textFieldStyle(.roundedBorder) }
                            }
                        }.padding(10).card(radius: 10)
                    }
                    Button { edit.draft.beats.append(ScriptBeat(title: "New beat")) } label: { Label("Add a beat", systemImage: "plus") }.controlSize(.small)
                    if !edit.draft.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 3) { Text("Notes").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim); Text(edit.draft.notes).font(.system(size: 12)).textSelection(.enabled) }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10).card(radius: 10)
                    }
                }.padding(14)
            }
            Divider()
            HStack(spacing: 10) {
                TextField("Or tell the Assistant what to change…", text: $edit.feedback).textFieldStyle(.roundedBorder)
                Button("Request changes") { model.finishScript(edit.draft, feedback: edit.feedback.isEmpty ? "Please revise the script." : edit.feedback) }.disabled(edit.feedback.isEmpty)
                Button("Close") { model.finishScript(nil, feedback: nil) }.keyboardShortcut(.cancelAction)
                Button("Approve and build") { model.finishScript(edit.draft, feedback: nil) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(edit.draft.beats.isEmpty)
            }.padding(14)
        }
        .frame(minWidth: 780, minHeight: 560)
        .onAppear { if !edit.loaded, let d = model.pendingScript { edit.draft = d; edit.loaded = true } }
    }
}

/// A text field with a dropdown of ready-made choices: pick one or type your own.
struct ComboField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let presets: [String]

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.dim)
            HStack(spacing: 0) {
                TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 12)).padding(.leading, 7).lineLimit(1)
                Menu {
                    ForEach(presets, id: \.self) { p in Button(p) { text = p } }
                } label: { Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.dim).frame(width: 22, height: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }.frame(height: 24).background(Theme.raised, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.stroke))
        }
    }
}
