import AVKit
import SwiftUI
import UniformTypeIdentifiers
import MovieCore

func formatTime(_ ms: Ms) -> String {
    String(format: "%d:%02d.%d", ms / 60_000, (ms / 1000) % 60, (ms % 1000) / 100)
}

/// hh:mm:ss:ff, like a video editor shows it.
func timecode(_ ms: Ms, fps: Int) -> String {
    let frames = Int(Double(ms % 1000) / 1000 * Double(fps))
    return String(format: "%02d:%02d:%02d:%02d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, frames)
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView(); v.player = player; v.controlsStyle = .none; v.videoGravity = .resizeAspect; return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {}
}

/// Lets the scroll wheel / trackpad scrub through the movie, and a click play or pause.
struct ScrubOverlay: NSViewRepresentable {
    let onScroll: (Double) -> Void
    let onClick: () -> Void

    final class Catcher: NSView {
        var onScroll: ((Double) -> Void)?
        var onClick: (() -> Void)?
        override func scrollWheel(with event: NSEvent) {
            let scale = event.hasPreciseScrollingDeltas ? 1.0 : 8.0   // a mouse wheel notch is worth several trackpad points
            onScroll?(-Double(event.scrollingDeltaX + event.scrollingDeltaY) * scale)
        }
        override func mouseDown(with event: NSEvent) { onClick?() }
    }

    func makeNSView(context: Context) -> Catcher { let v = Catcher(); v.onScroll = onScroll; v.onClick = onClick; return v }
    func updateNSView(_ v: Catcher, context: Context) { v.onScroll = onScroll; v.onClick = onClick }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            HStack(spacing: 0) {
                if model.showLeft {
                    LeftArea()
                    PanelHandle(edge: .rightOfLeft, value: $model.leftWidth, range: 240...560)
                }
                PreviewArea().frame(minWidth: 380)
                if model.showRight {
                    PanelHandle(edge: .leftOfRight, value: $model.rightWidth, range: 300...600)
                    RightPanel().frame(width: model.rightWidth)
                }
            }
            if model.showTimeline {
                PanelHandle(edge: .aboveBottom, value: $model.timelineHeight, range: 200...620)
                EditorTimeline().frame(height: model.timelineHeight)
            }
            StatusBar()
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .frame(minWidth: 1180, minHeight: 720)
        .fileImporter(isPresented: $model.importing, allowedContentTypes: [.movie, .audio, .image], allowsMultipleSelection: true) {
            if case .success(let urls) = $0 { model.importFiles(urls) }
        }
        .sheet(isPresented: $model.showExport) { ExportSheet().environmentObject(model) }
        .sheet(item: $model.infoTarget) { InfoSheet(target: $0).environmentObject(model) }
        .sheet(item: $model.pendingScript) { _ in ScriptSheet().environmentObject(model) }
        .sheet(item: $model.pendingSelection) { SelectionSheet(request: $0).environmentObject(model) }
        .sheet(item: $model.renameTarget) { RenameSheet(asset: $0).environmentObject(model) }
        .sheet(item: $model.templateToApply) { ApplyTemplateSheet(template: $0).environmentObject(model) }
        .sheet(isPresented: $model.rampSheet) { SpeedRampSheet().environmentObject(model) }
        .alert("Remove from library?", isPresented: Binding(get: { model.assetToRemove != nil }, set: { if !$0 { model.assetToRemove = nil } })) {
            Button("Remove", role: .destructive) { if let a = model.assetToRemove { model.removeAsset(a) } }
            Button("Cancel", role: .cancel) { model.assetToRemove = nil }
        } message: {
            Text("\(model.assetToRemove?.label ?? "This file") is used in the timeline. Its clips will be removed too (you can undo).")
        }
        .alert("Eclipse", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

// MARK: Top bar

struct TopBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 72)   // room for the window buttons
            EclipseLogo(size: 26)
            Menu {
                Button("New") { model.newProject() }
                Button("Open…") { model.open() }
                Button("Save") { model.save() }
                Button("Save As…") { model.saveAs() }
                Button("Duplicate (save a copy)…") { model.duplicateProject() }
                Divider()
                Menu("New from Template") {
                    ForEach(AppModel.builtInTemplates, id: \.name) { t in Button(t.name) { model.newProject(width: t.width, height: t.height) } }
                    if !model.userTemplates.isEmpty {
                        Divider()
                        ForEach(model.userTemplates, id: \.self) { url in Button(url.deletingPathExtension().lastPathComponent) { model.newProject(fromTemplate: url) } }
                    }
                }
                Button("Save as Template") { model.saveAsTemplate() }
                Divider()
                Menu("Movie size") {
                    Button("16:9 landscape (1920×1080)") { model.setFormat(width: 1920, height: 1080) }
                    Button("9:16 vertical (1080×1920)") { model.setFormat(width: 1080, height: 1920) }
                    Button("1:1 square (1080×1080)") { model.setFormat(width: 1080, height: 1080) }
                    Button("4:5 portrait (1080×1350)") { model.setFormat(width: 1080, height: 1350) }
                    Divider()
                    Button("720p") { model.setResolution(shortSide: 720) }
                    Button("1080p (Full HD)") { model.setResolution(shortSide: 1080) }
                    Button("4K") { model.setResolution(shortSide: 2160) }
                    Divider()
                    ForEach([24, 30, 60], id: \.self) { fps in Button("\(fps) fps") { model.setFormat(width: model.project.width, height: model.project.height, fps: fps) } }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(model.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.dim)
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            TimelineView(.periodic(from: .now, by: 20)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(model.lastEdit)))
                Text(seconds < 45 ? "Edited just now" : "Edited \(seconds / 60 + 1) min ago").font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            Text("\(model.project.width)×\(model.project.height) · \(model.project.fps) fps").font(.system(size: 11)).foregroundStyle(Theme.dim)
                .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.raised, in: Capsule())
            Spacer()
            IconButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { model.editor.undo() }.opacity(model.editor.canUndo ? 1 : 0.35)
            IconButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { model.editor.redo() }.opacity(model.editor.canRedo ? 1 : 0.35)
            Divider().frame(height: 18)
            IconButton(symbol: "sidebar.left", help: "Show or hide the media panel", active: model.showLeft) { model.showLeft.toggle() }
            IconButton(symbol: "rectangle.bottomthird.inset.filled", help: "Show or hide the timeline", active: model.showTimeline) { model.showTimeline.toggle() }
            IconButton(symbol: "sidebar.right", help: "Show or hide the assistant and adjustments", active: model.showRight) { model.showRight.toggle() }
            Divider().frame(height: 18)
            IconButton(symbol: model.recording ? "stop.circle.fill" : "mic", help: "Record a voice-over at the playhead (use headphones)", active: model.recording) { model.toggleVoiceOver() }
            IconButton(symbol: "link", help: "Copy the command that connects Claude Code to this editor") { model.copyClaudeCommand() }.opacity(model.mcpCommand == nil ? 0.35 : 1)
            Button { model.showExport = true } label: {
                Label(model.exporting ? "Exporting…" : "Export", systemImage: "square.and.arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7).background(Theme.accent, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).disabled(model.project.duration == 0).opacity(model.project.duration == 0 ? 0.45 : 1)
            .help("Render to MP4, subtitles and sharing formats")
        }
        .padding(.horizontal, 14).frame(height: 50)
        .background(Theme.panel)
        .background(WindowDragArea())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }
}

// MARK: Preview and transport

struct PreviewArea: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if model.hasVideo || model.ghostPreview { PlayerView(player: model.player) } else { EmptyPreview() }
                ScrubOverlay(onScroll: { model.scrub(by: $0 * model.frameMs * 0.35) }, onClick: { model.togglePlay() })
                if model.ghost != nil { GhostBanner().frame(maxHeight: .infinity, alignment: .top) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
            .padding(.horizontal, 16).padding(.top, 14)
            TransportBar()
        }
        .background(Theme.background)
    }
}

struct GhostBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            Text(model.ghostDiffers ? "Ghost edit ready" : "Ghost edit: Claude is working on a copy").font(.system(size: 12, weight: .semibold))
            Toggle("Preview", isOn: $model.ghostPreview).toggleStyle(.button).controlSize(.small).disabled(!model.ghostDiffers)
            Button("Accept") { model.acceptGhost() }.controlSize(.small).disabled(!model.ghostDiffers)
            Button("Discard") { model.endGhost() }.controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 7).background(.ultraThinMaterial, in: Capsule()).padding(10)
    }
}

struct EmptyPreview: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack").font(.system(size: 42)).foregroundStyle(Theme.dim)
            Text(model.project.assets.isEmpty ? "Import your clips to begin" : "Drag a clip onto the timeline")
                .font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.text)
            Text("or ask the Assistant to build a film for you").font(.system(size: 13)).foregroundStyle(Theme.dim)
            if model.project.assets.isEmpty { Button("Import media…") { model.importing = true }.buttonStyle(.borderedProminent).padding(.top, 4) }
        }
        .allowsHitTesting(model.project.assets.isEmpty)
    }
}

struct TransportBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text(timecode(model.playhead, fps: model.project.fps)).foregroundStyle(Theme.text)
                Text("/ " + timecode(model.playbackProject.duration, fps: model.project.fps)).foregroundStyle(Theme.dim)
            }.font(.system(size: 12.5, weight: .medium, design: .monospaced)).frame(width: 230, alignment: .leading)
            Spacer()
            HStack(spacing: 6) {
                IconButton(symbol: "backward.end.fill", help: "Previous cut (↑)") { model.jumpToEdit(forward: false) }
                IconButton(symbol: "backward.frame.fill", help: "One frame back (←)") { model.step(by: -model.frameMs) }
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Theme.accent, in: Circle())
                }.buttonStyle(.plain).disabled(model.playbackProject.duration == 0).help("Play or pause (space)")
                IconButton(symbol: "forward.frame.fill", help: "One frame forward (→)") { model.step(by: model.frameMs) }
                IconButton(symbol: "forward.end.fill", help: "Next cut (↓)") { model.jumpToEdit(forward: true) }
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: model.previewVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundStyle(Theme.dim).font(.system(size: 12))
                Slider(value: $model.previewVolume, in: 0...1).frame(width: 90).controlSize(.small)
                IconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Full screen") { NSApp.keyWindow?.toggleFullScreen(nil) }
            }.frame(width: 230, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }
}

struct StatusBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack {
            Text(model.statusMessage ?? "Ready").font(.system(size: 11.5)).foregroundStyle(model.statusMessage == nil ? Theme.dim.opacity(0.6) : Theme.text)
            Spacer()
            Text("\(model.project.tracks.flatMap(\.clips).count) clips · \(timecode(model.project.duration, fps: model.project.fps))")
                .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 14).frame(height: 24).background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }
}

/// Lets an empty strip of the top bar move the window (AppKit; SwiftUI's WindowDragGesture crashed the display cycle).
struct WindowDragArea: NSViewRepresentable {
    final class V: NSView { override var mouseDownCanMoveWindow: Bool { true } }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ v: NSView, context: Context) {}
}

/// The Eclipse mark: aperture ring around a dark eclipse disc on a deep-space tile (matches the app icon).
struct EclipseLogo: View {
    let size: CGFloat
    var body: some View {
        let s = size
        if let url = Bundle.main.url(forResource: "AppLogo", withExtension: "png"), let img = NSImage(contentsOf: url) {
            return AnyView(Image(nsImage: img).resizable().interpolation(.high).frame(width: s, height: s))
        }
        return AnyView(ZStack {
            RoundedRectangle(cornerRadius: s * 0.24).fill(LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.44), Color(red: 0.02, green: 0.03, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(LinearGradient(colors: [Color(red: 0.48, green: 0.24, blue: 1), Color(red: 0.76, green: 0.36, blue: 1), Color(red: 1, green: 0.37, blue: 0.78), Color(red: 1, green: 0.61, blue: 0.41)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: s * 0.62, height: s * 0.62)
            Circle().fill(Color(red: 0.02, green: 0.03, blue: 0.08)).frame(width: s * 0.32, height: s * 0.32)
            Circle().trim(from: 0.0, to: 0.25).stroke(Color(red: 1, green: 0.61, blue: 0.41), lineWidth: max(1, s * 0.03)).frame(width: s * 0.32, height: s * 0.32).rotationEffect(.degrees(-20))
        }.frame(width: s, height: s))
    }
}
