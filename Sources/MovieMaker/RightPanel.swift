import AppKit
import SwiftUI
import MovieCore

private let fontChoices = ["Helvetica Neue", "Avenir Next", "Georgia", "Menlo", "Impact", "Marker Felt", "Futura", "Bradley Hand", "Georgia-Italic"]

private func color(hex: String) -> Color {
    let v = UInt32(hex, radix: 16) ?? 0xFFFFFF
    return Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
}

private func hex(_ color: Color) -> String {
    let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
    return String(format: "%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format = "%.2f"
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack { Text(title).foregroundStyle(Theme.text); Spacer(); Text(String(format: format, value)).foregroundStyle(Theme.dim).monospacedDigit() }.font(.system(size: 12))
            Slider(value: $value, in: range) { editing in if !editing { onCommit() } }.controlSize(.small)
        }
    }
}

/// A titled card that groups a set of controls.
struct Block<Content: View>: View {
    let title: String
    var trailing: AnyView?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { SectionTitle(text: title); Spacer(); trailing }
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).card()
    }
}

struct RightPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(RightTab.allCases, id: \.self) { tab in
                    let selected = model.rightTab == tab
                    Button { model.rightTab = tab } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.symbol).font(.system(size: 12))
                            Text(tab.rawValue).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        }
                        .foregroundStyle(selected ? Color.white : Theme.dim).frame(maxWidth: .infinity).frame(height: 30)
                        .background(selected ? Theme.accent.opacity(0.9) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }.padding(8)
            Divider().overlay(Theme.stroke)
            switch model.rightTab {
            case .assistant: ChatView()
            case .adjust: AdjustPanel()
            case .effects: EffectsPanel()
            case .inspector: InspectorPanel()
            }
        }
        .background(Theme.panel)
    }
}

struct NothingSelected: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cursorarrow.click.2").font(.system(size: 26)).foregroundStyle(Theme.dim)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
}

// MARK: Adjust

struct AdjustPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let clip = model.selectedClip {
            ScrollView { ClipAdjustments(clip: clip).padding(12) }
        } else if let transition = model.selectedTransitionValue {
            ScrollView { TransitionInspector(transition: transition).padding(12) }
        } else {
            NothingSelected(text: "Select a clip on the timeline to adjust its picture, look, speed, sound or text. Select the orange band between two clips to change the transition.")
        }
    }
}

struct ClipAdjustments: View {
    @EnvironmentObject var model: AppModel
    let clip: Clip

    private var track: Track? { model.project.tracks.first { $0.clips.contains { $0.id == clip.id } } }
    private var asset: Asset? { model.project.assets.first { $0.id == clip.assetID } }
    private var isVideo: Bool { track?.kind == .video && clip.text == nil && clip.generator == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.generator?.title ?? asset?.label ?? "Title").font(.system(size: 14, weight: .semibold)).lineLimit(1).foregroundStyle(Theme.text)
                    Text("\(timecode(clip.start, fps: model.project.fps)) · \(formatTime(clip.duration))").font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
                Spacer()
                Button { model.resetSelection() } label: { Label("Reset clip", systemImage: "arrow.counterclockwise") }.controlSize(.small)
                    .help("Put everything on this clip back to plain: look, framing, effects, speed, volume")
            }
            if clip.text != nil { textBlock }
            if let kind = clip.generator { overlayBlock(kind) }
            if isVideo { pictureBlock; lookBlock }
            if clip.text == nil && clip.generator == nil { speedBlock }
            if asset?.hasAudio == true || isVideo { audioBlock }
            if let track, track.kind == .audio { duckBlock(track) }
        }
    }

    private var pictureBlock: some View {
        Block(title: "Picture", trailing: AnyView(Button("Reset") {
            model.draft.opacity = 1; model.draft.scale = 1; model.draft.offsetX = 0; model.draft.offsetY = 0; model.commitTransform()
        }.controlSize(.mini))) {
            LabeledSlider(title: "Opacity", value: $model.draft.opacity, range: 0...1) { model.commitTransform() }
            LabeledSlider(title: "Size", value: $model.draft.scale, range: 0.1...3) { model.commitTransform() }
            LabeledSlider(title: "Horizontal", value: $model.draft.offsetX, range: -1...1) { model.commitTransform() }
            LabeledSlider(title: "Vertical", value: $model.draft.offsetY, range: -1...1) { model.commitTransform() }
            Text("Shrink a clip and move it on a layer above another clip for picture-in-picture.").font(.system(size: 11)).foregroundStyle(Theme.dim)
            Divider().overlay(Theme.stroke)
            SectionTitle(text: "Animation (keyframes)")
            Text("Move the playhead, set the values above, then press Set keyframe. Values glide between keyframes.").font(.system(size: 11)).foregroundStyle(Theme.dim)
            LabeledSlider(title: "Spin (animated)", value: $model.draft.keyRotation, range: -180...180, format: "%.0f°") { model.setKeyframeAtPlayhead() }
            HStack {
                Button("Set keyframe here") { model.setKeyframeAtPlayhead() }.controlSize(.small)
                Button("Clear all") { model.perform(.setKeyframes(clip.id, []), quiet: true) }.controlSize(.small).disabled(clip.keyframes.isEmpty)
            }
            ForEach(clip.keyframes, id: \.time) { k in
                HStack(spacing: 6) {
                    Button(formatTime(k.time)) { model.jumpToKeyframe(k) }.buttonStyle(.link).help("Go to this keyframe")
                    Text("size \(String(format: "%.2f", k.scale)) · opacity \(String(format: "%.1f", k.opacity))").font(.system(size: 11)).foregroundStyle(Theme.dim)
                    Spacer()
                    Button { model.toggleKeyframeSmooth(at: k.time) } label: { Image(systemName: k.smooth ? "waveform.path" : "line.diagonal") }.buttonStyle(.borderless).help(k.smooth ? "Eased: tap for a straight line" : "Straight line: tap to ease")
                    Button { model.removeKeyframe(at: k.time) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).help("Delete this keyframe")
                }
            }
        }
    }

    private var lookBlock: some View {
        Block(title: "Look & colour", trailing: AnyView(Button("Reset look") { model.resetLook() }.controlSize(.mini).help("Remove every colour and framing change of this clip"))) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(Look.presetNames, id: \.self) { name in Chip(title: name) { model.applyLookPreset(name) } }
            }
            LabeledSlider(title: "Brightness", value: $model.draft.look.brightness, range: -1...1) { model.commitLook() }
            LabeledSlider(title: "Contrast", value: $model.draft.look.contrast, range: 0...3) { model.commitLook() }
            LabeledSlider(title: "Saturation", value: $model.draft.look.saturation, range: 0...3) { model.commitLook() }
            LabeledSlider(title: "Warmth", value: $model.draft.look.warmth, range: -1...1) { model.commitLook() }
            LabeledSlider(title: "Faded blacks", value: $model.draft.look.fade, range: 0...1) { model.commitLook() }
            LabeledSlider(title: "Sharpen", value: $model.draft.look.sharpen, range: 0...1) { model.commitLook() }
            LabeledSlider(title: "Sepia", value: $model.draft.look.sepia, range: 0...1) { model.commitLook() }
            LabeledSlider(title: "Blur", value: $model.draft.look.blur, range: 0...1) { model.commitLook() }
            LabeledSlider(title: "Vignette", value: $model.draft.look.vignette, range: 0...1) { model.commitLook() }
            Divider().overlay(Theme.stroke)
            SectionTitle(text: "Split toning")
            HStack {
                ColorPicker("Shadows", selection: Binding(get: { color(hex: model.draft.look.splitShadows ?? "808080") }, set: { model.draft.look.splitShadows = hex($0); if model.draft.look.splitAmount == 0 { model.draft.look.splitAmount = 0.5 }; model.commitLook() }))
                ColorPicker("Highlights", selection: Binding(get: { color(hex: model.draft.look.splitHighlights ?? "808080") }, set: { model.draft.look.splitHighlights = hex($0); if model.draft.look.splitAmount == 0 { model.draft.look.splitAmount = 0.5 }; model.commitLook() }))
            }.font(.system(size: 12))
            LabeledSlider(title: "Strength", value: $model.draft.look.splitAmount, range: 0...1) { model.commitLook() }
            Divider().overlay(Theme.stroke)
            SectionTitle(text: "Framing")
            HStack {
                Toggle("Flip ↔", isOn: Binding(get: { model.draft.look.flipX }, set: { model.draft.look.flipX = $0; model.commitLook() }))
                Toggle("Flip ↕", isOn: Binding(get: { model.draft.look.flipY }, set: { model.draft.look.flipY = $0; model.commitLook() }))
            }.toggleStyle(.button).controlSize(.small)
            LabeledSlider(title: "Rotate", value: $model.draft.look.rotation, range: -180...180, format: "%.0f°") { model.commitLook() }
            HStack {
                Button("⟲ 90°") { model.draft.look.rotation = (model.draft.look.rotation + 90).truncatingRemainder(dividingBy: 360); model.commitLook() }
                Button("⟳ 90°") { model.draft.look.rotation = (model.draft.look.rotation - 90).truncatingRemainder(dividingBy: 360); model.commitLook() }
            }.controlSize(.small)
            LabeledSlider(title: "Crop left", value: $model.draft.look.cropLeft, range: 0...0.9) { model.commitLook() }
            LabeledSlider(title: "Crop right", value: $model.draft.look.cropRight, range: 0...0.9) { model.commitLook() }
            LabeledSlider(title: "Crop top", value: $model.draft.look.cropTop, range: 0...0.9) { model.commitLook() }
            LabeledSlider(title: "Crop bottom", value: $model.draft.look.cropBottom, range: 0...0.9) { model.commitLook() }
        }
    }

    private var speedBlock: some View {
        Block(title: "Speed", trailing: AnyView(Button("Normal") { model.draft.speed = 1; model.commitSpeed() }.controlSize(.mini))) {
            LabeledSlider(title: "Playback speed", value: $model.draft.speed, range: 0.25...4, format: "%.2f×") { model.commitSpeed() }
            HStack {
                ForEach([0.5, 1.0, 2.0], id: \.self) { v in Button(v == 1 ? "Normal" : "\(v == 0.5 ? "½" : "2")×") { model.draft.speed = v; model.commitSpeed() }.controlSize(.small) }
                Spacer()
                Button { model.rampSheet = true } label: { Label("Ramp…", systemImage: "speedometer") }.controlSize(.small).help("Smooth slow motion into fast: the speed ramp studio")
            }
            Text("Changing the speed changes the clip's length; later clips on the track move with it.").font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
    }

    private var audioBlock: some View {
        Block(title: "Audio", trailing: AnyView(Button("Reset") { model.resetAudio() }.controlSize(.mini).help("Volume 100 %, no fades"))) {
            if track?.kind == .video && clip.muted {
                Label("Audio detached (see the audio track)", systemImage: "speaker.slash").font(.system(size: 12)).foregroundStyle(Theme.dim)
            } else {
                LabeledSlider(title: "Volume", value: $model.draft.volume, range: 0...2) { model.commitAudio() }
                LabeledSlider(title: track?.kind == .video ? "Fade in (picture + sound)" : "Fade in", value: $model.draft.fadeIn, range: 0...3, format: "%.1f s") { model.commitAudio() }
                LabeledSlider(title: track?.kind == .video ? "Fade out (picture + sound)" : "Fade out", value: $model.draft.fadeOut, range: 0...3, format: "%.1f s") { model.commitAudio() }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    Button("Normalize volume") { model.normalizeSelection() }.help("Bring this clip's sound to a standard level")
                    Button("Remove silences") { model.removeSilenceOfSelection() }.help("Cut out the quiet parts and close the gaps")
                    Button("Reduce noise") { model.reduceNoiseOfSelection() }.help("Remove rumble and hiss; the sound moves to its own cleaned audio clip")
                    Button("Auto captions") { model.autoCaptionsOfSelection() }.help("Write subtitles from the speech (asks for permission the first time)")
                }.controlSize(.small)
                if track?.kind == .video { Button { model.detachAudioOfSelection() } label: { Label("Detach audio", systemImage: "speaker.slash") }.controlSize(.small).help("Move the sound to its own audio clip") }
            }
        }
    }

    private func duckBlock(_ track: Track) -> some View {
        Block(title: "Ducking") {
            Toggle("Lower this track under speech and clip sound", isOn: Binding(get: { track.duck }, set: { model.setDuck(track, $0) })).font(.system(size: 12.5))
            if track.duck {
                LabeledSlider(title: "Lowers to", value: Binding(get: { model.duckDraft ?? track.duckLevel }, set: { model.duckDraft = $0 }), range: 0.05...0.95, format: "%.0f%%") {
                    model.setDuckLevel(track, model.duckDraft ?? track.duckLevel); model.duckDraft = nil
                }
            }
            Text("Good for music: it dips whenever a voice-over or a clip with sound plays, then comes back.").font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
    }

    private func overlayBlock(_ kind: GeneratorKind) -> some View {
        Block(title: "Overlay") {
            Picker("Type", selection: Binding(get: { kind }, set: { model.perform(.setGenerator(clip.id, kind: $0, amount: clip.generatorAmount), quiet: true) })) {
                ForEach(GeneratorKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            LabeledSlider(title: "Amount", value: Binding(get: { model.effectDrafts[clip.id] ?? clip.generatorAmount }, set: { model.effectDrafts[clip.id] = $0 }), range: 0...1) {
                model.perform(.setGenerator(clip.id, kind: kind, amount: model.effectDrafts[clip.id] ?? clip.generatorAmount), quiet: true); model.effectDrafts[clip.id] = nil
            }
            LabeledSlider(title: "Fade in", value: $model.draft.fadeIn, range: 0...3, format: "%.1f s") { model.commitAudio() }
            LabeledSlider(title: "Fade out", value: $model.draft.fadeOut, range: 0...3, format: "%.1f s") { model.commitAudio() }
            Text(kind.summary).font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
    }

    private var textBlock: some View {
        Block(title: "Text") {
            TextField("Text", text: Binding(get: { clip.text ?? "" }, set: { model.perform(.setText(clip.id, $0), quiet: true) }), axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                ForEach(TitlePreset.allCases, id: \.self) { preset in
                    Chip(title: preset.rawValue) { var s = preset.style; s.x = model.draft.style.x; s.y = model.draft.style.y; model.draft.style = s; model.commitStyle() }
                }
            }
            LabeledSlider(title: "Size", value: $model.draft.style.size, range: 0.02...0.4) { model.commitStyle() }
            LabeledSlider(title: "Horizontal position", value: $model.draft.style.x, range: 0...1) { model.commitStyle() }
            LabeledSlider(title: "Vertical position", value: $model.draft.style.y, range: 0...1) { model.commitStyle() }
            LabeledSlider(title: "Letter spacing", value: $model.draft.style.tracking, range: 0...0.8) { model.commitStyle() }
            ColorPicker("Colour", selection: Binding(get: { color(hex: model.draft.style.colorHex) }, set: { model.draft.style.colorHex = hex($0); model.commitStyle() })).font(.system(size: 12))
            Picker("Align", selection: Binding(get: { model.draft.style.align }, set: { model.draft.style.align = $0; model.commitStyle() })) { Text("Left").tag(0); Text("Center").tag(1); Text("Right").tag(2) }.pickerStyle(.segmented)
            Picker("Appears", selection: Binding(get: { model.draft.style.animation }, set: { model.draft.style.animation = $0; model.commitStyle() })) { ForEach(TextAnimation.allCases, id: \.self) { Text($0.title).tag($0) } }
            if model.draft.style.animation != .none {
                LabeledSlider(title: "Entrance length", value: Binding(get: { Double(model.draft.style.animationMs) / 1000 }, set: { model.draft.style.animationMs = Ms($0 * 1000) }), range: 0.1...2, format: "%.1f s") { model.commitStyle() }
            }
            LabeledSlider(title: "Fade in", value: $model.draft.fadeIn, range: 0...3, format: "%.1f s") { model.commitAudio() }
            LabeledSlider(title: "Fade out", value: $model.draft.fadeOut, range: 0...3, format: "%.1f s") { model.commitAudio() }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                Toggle("Bold", isOn: Binding(get: { model.draft.style.bold }, set: { model.draft.style.bold = $0; model.commitStyle() }))
                Toggle("Shadow", isOn: Binding(get: { model.draft.style.shadow }, set: { model.draft.style.shadow = $0; model.commitStyle() }))
                Toggle("Outline", isOn: Binding(get: { model.draft.style.outline }, set: { model.draft.style.outline = $0; model.commitStyle() }))
                Toggle("Box", isOn: Binding(get: { model.draft.style.box }, set: { model.draft.style.box = $0; model.commitStyle() }))
                Toggle("ALL CAPS", isOn: Binding(get: { model.draft.style.uppercase }, set: { model.draft.style.uppercase = $0; model.commitStyle() }))
                Toggle("Glow", isOn: Binding(get: { model.draft.style.glow }, set: { model.draft.style.glow = $0; model.commitStyle() }))
            }.font(.system(size: 12))
            Picker("Font", selection: Binding(get: { model.draft.style.fontName ?? "" }, set: { model.draft.style.fontName = $0.isEmpty ? nil : $0; model.commitStyle() })) {
                Text("System").tag(""); ForEach(fontChoices, id: \.self) { Text($0).tag($0) }
            }
        }
    }
}

struct TransitionInspector: View {
    @EnvironmentObject var model: AppModel
    let transition: MovieCore.Transition

    var body: some View {
        Block(title: "Transition") {
            Picker("Style", selection: Binding(get: { model.draft.transitionType }, set: { model.draft.transitionType = $0; model.commitTransition() })) {
                ForEach(TransitionType.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            LabeledSlider(title: "Overlap", value: $model.draft.transitionSeconds, range: 0.1...max(0.2, model.maxTransitionSeconds), format: "%.1f s") { model.commitTransition() }
            Text("The two clips play together for this long. A longer overlap makes the movie shorter by the same amount.").font(.system(size: 11)).foregroundStyle(Theme.dim)
            Button(role: .destructive) { model.deleteSelection() } label: { Label("Remove transition", systemImage: "trash") }.controlSize(.small)
        }
    }
}

// MARK: Effects

struct EffectsPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let clip = model.selectedClip, clip.text == nil, clip.generator == nil {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Block(title: "Effects on this clip", trailing: AnyView(Menu {
                        ForEach(EffectType.allCases, id: \.self) { type in Button(type.title) { model.addEffect(type, to: clip.id) } }
                    } label: { Label("Add", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize())) {
                        if clip.effects.isEmpty { Text("None yet. Add one with the button, or drag one from the Effects tab on the left.").font(.system(size: 11.5)).foregroundStyle(Theme.dim) }
                        ForEach(clip.effects) { effect in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(effect.type.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                                    Spacer()
                                    Button { model.removeEffect(effect, from: clip.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }.buttonStyle(.plain).help("Remove this effect")
                                }
                                LabeledSlider(title: "Strength", value: Binding(get: { model.effectDrafts[effect.id] ?? effect.amount }, set: { model.effectDrafts[effect.id] = $0 }), range: 0...1) {
                                    model.setEffectAmount(effect, on: clip.id, amount: model.effectDrafts[effect.id] ?? effect.amount)
                                }
                                Text(effect.type.summary).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                            }.padding(.vertical, 4)
                        }
                    }
                }.padding(12)
            }
        } else { NothingSelected(text: "Select a video clip to add effects and set their strength. Overlays and titles have their own settings in Adjust.") }
    }
}

// MARK: Inspector

struct InspectorPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let clip = model.selectedClip { ClipFacts(clip: clip) }
                else if let transition = model.selectedTransitionValue { TransitionInspector(transition: transition) }
                else { ProjectFacts() }
            }.padding(12)
        }
    }
}

struct ClipFacts: View {
    @EnvironmentObject var model: AppModel
    let clip: Clip

    private var asset: Asset? { model.project.assets.first { $0.id == clip.assetID } }
    private var track: Track? { model.project.tracks.first { $0.clips.contains { $0.id == clip.id } } }

    var body: some View {
        Block(title: "Clip") {
            fact("Name", clip.generator?.title ?? asset?.label ?? (clip.text.map { "Title: \($0)" } ?? "Clip"))
            fact("Track", track?.name ?? track.map { "\($0.kind.rawValue.capitalized) track" } ?? "")
            fact("Starts", timecode(clip.start, fps: model.project.fps)); fact("Ends", timecode(clip.end, fps: model.project.fps))
            fact("Length", "\(formatTime(clip.duration)) (\(clip.duration) ms)")
            if clip.assetID != nil {
                fact("Source part", "\(formatTime(clip.sourceIn)) – \(formatTime(clip.sourceIn + clip.sourceLength))")
                fact("Speed", String(format: "%.2f×", clip.speed)); fact("Volume", String(format: "%.0f %%", clip.volume * 100) + (clip.muted ? " (sound detached)" : ""))
            }
            if !clip.effects.isEmpty { fact("Effects", clip.effects.map(\.type.title).joined(separator: ", ")) }
            if !clip.keyframes.isEmpty { fact("Keyframes", "\(clip.keyframes.count)") }
            if clip.groupID != nil {
                HStack { Label("Grouped with other clips", systemImage: "link").font(.system(size: 12)); Spacer(); Button("Ungroup") { model.ungroupSelection() }.controlSize(.small) }
            }
        }
        Block(title: "Actions") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                Button("Split at playhead") { model.splitAtPlayhead() }
                Button("Duplicate") { model.duplicateSelection() }
                Button("Delete") { model.deleteSelection() }
                Button("Delete & close gap") { model.rippleDeleteSelection() }
                Button("Group (shift-click)") { model.groupSelection() }
                Button("Reset clip") { model.resetSelection() }
                Button("Get info…") { model.infoTarget = .clip(clip.id) }
                if let asset { Button("Show in Finder") { model.reveal(asset) } }
            }.controlSize(.small)
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(Theme.dim).frame(width: 82, alignment: .leading)
            Text(value).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.font(.system(size: 12))
    }
}

struct ProjectFacts: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Block(title: "Project") {
            row("Name", model.title)
            row("Size", "\(model.project.width)×\(model.project.height) at \(model.project.fps) fps")
            row("Length", "\(timecode(model.project.duration, fps: model.project.fps))")
            row("Clips", "\(model.project.tracks.flatMap(\.clips).count) on \(model.project.tracks.count) tracks")
            row("Media", "\(model.project.assets.count) files")
            row("Transitions", "\(model.project.transitions.count)")
        }
        Text("Select a clip on the timeline to see its details and actions here.").font(.system(size: 12)).foregroundStyle(Theme.dim)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(Theme.dim).frame(width: 82, alignment: .leading); Text(value).foregroundStyle(Theme.text); Spacer() }.font(.system(size: 12))
    }
}
