import AppKit
import SwiftUI
import MovieCore

/// Draws the whole interface with a sample project, so layout can be checked without clicking through the app.
@MainActor
enum Snapshot {
    static func run(to folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = AppModel(restoreRecovery: false, startServer: false), chat = ChatModel(), search = SoundSearchModel()
        await populate(model, folder: folder)

        // ImageRenderer cannot draw AppKit-backed controls (scroll views, fields, menus), so the view is hosted in a real,
        // off-screen window and captured with cacheDisplay.
        let size = NSSize(width: 1500, height: 940)
        let host = NSHostingView(rootView: AnyView(ContentView().environmentObject(model).environmentObject(chat).environmentObject(search)))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -3000, y: -3000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFrontRegardless()

        func render(_ name: String, _ configure: () -> Void = {}) async {
            configure()
            try? await Task.sleep(nanoseconds: 900_000_000)   // let SwiftUI lay out and draw
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: folder.appendingPathComponent("\(name).png")) }
        }
        model.rightTab = .assistant; model.leftTab = .media
        await render("1-edit-assistant")
        await render("2-media") { model.leftTab = .media }
        await render("3-templates") { model.leftTab = .templates; model.ensureTemplateThumbs() }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        await render("3-templates")
        await render("4-adjust") { model.leftTab = .transitions; model.rightTab = .adjust; model.selection = model.project.tracks.flatMap(\.clips).first { $0.assetID != nil }?.id }
        await render("5-audio-effects") { model.leftTab = .audio; model.rightTab = .effects }
        await render("7-files") { model.workspaceRoots = [folder]; model.leftTab = .files }
        await render("6-expanded") { model.leftTab = .titles; model.navExpanded = true; model.rightTab = .inspector }
    }

    private static func populate(_ model: AppModel, folder: URL) async {
        let size = CGSize(width: 960, height: 540), rect = CGRect(origin: .zero, size: size)
        let looks: [(String, String?)] = [("sunrise", nil), ("harbour", "Teal & orange"), ("market", "Golden hour"), ("night", "Cyberpunk")]
        for (name, look) in looks {
            var image = EffectRenderer.demoScene(size, greenScreen: false)
            if let look, let l = Look.preset(look) { image = LookRenderer.apply(l, to: image, size: size).cropped(to: rect) }
            guard let cg = CIContext().createCGImage(image, from: rect) else { continue }
            let url = folder.appendingPathComponent("\(name).png")
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) { CGImageDestinationAddImage(dest, cg, nil); CGImageDestinationFinalize(dest) }
            _ = try? await model.importAsset(url)
        }
        if let music = try? await model.importAsset(MusicLibrary.url(for: "Neon Nights")) {
            let editor = model.editor
            let photos = model.project.assets.filter(\.isStill)
            var clips: [Clip] = []
            for asset in photos { if let c = try? editor.addClip(asset: asset, duration: 3_500) { clips.append(c) } }
            for c in clips.dropLast() { try? editor.addTransition(after: c.id, type: .crossfade, duration: 600) }
            if let first = clips.first { try? editor.apply(.addEffect(first.id, Effect(.kenBurnsIn))) }
            if clips.count > 1 { try? editor.apply(.addEffect(clips[1].id, Effect(.glow))); try? editor.apply(.setSpeed(clips[1].id, 0.5)) }
            _ = try? editor.addTitle("Summer in Lisbon", start: 300, duration: 2_600)
            _ = try? editor.addOverlay(.sparkles, start: 2_000, duration: 4_000)
            _ = try? editor.addMusicBed(music, start: 0)
            if let track = editor.project.tracks.last(where: { $0.kind == .audio }) { try? editor.apply(.setTrackDuck(track.id, true)) }
        }
        model.seek(4_200)
    }
}
