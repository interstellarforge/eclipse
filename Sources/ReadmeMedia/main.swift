import AVFoundation
import AppKit
import Foundation
import ImageIO
import MovieCore
import UniformTypeIdentifiers

// swift run ReadmeMedia <output folder>   (default docs/media)
// Draws four short sample scenes, edits them with the real MovieCore editor (overlays, transitions, effects, looks, titles),
// exports each demo as MP4 and makes a small GIF of it for README.md.
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/media")
let footage = out.appendingPathComponent("footage")
try FileManager.default.createDirectory(at: footage, withIntermediateDirectories: true)

func gif(from video: URL, to url: URL, width: Int = 480, fps: Int = 10) async throws {
    let asset = AVURLAsset(url: video)
    let seconds = try await asset.load(.duration).seconds
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: width, height: width * 9 / 16)
    gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
    let n = Int(seconds * Double(fps))
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, n, nil) else { return }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for i in 0..<n {
        let image = try await gen.image(at: CMTime(seconds: Double(i) / Double(fps), preferredTimescale: 600)).image
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)]] as CFDictionary)
    }
    CGImageDestinationFinalize(dest)
}

@MainActor func render(_ name: String, _ e: Editor) async throws {
    let mp4 = out.appendingPathComponent("\(name).mp4")
    try await Exporter.export(e.project, to: mp4)
    try await gif(from: mp4, to: out.appendingPathComponent("\(name).gif"))
    let size = (try? FileManager.default.attributesOfItem(atPath: out.appendingPathComponent("\(name).gif").path)[.size] as? Int) ?? 0
    print("\(name): \(e.project.duration) ms, gif \(size / 1024) KB")
}

@MainActor func newEditor() throws -> Editor {
    let e = Editor(); try e.apply(.setFormat(width: 1280, height: 720, fps: 30)); return e
}

@MainActor func caption(_ e: Editor, _ text: String, start: Ms, duration: Ms) throws {
    let c = try e.addTitle(text, start: start, duration: duration)
    try e.apply(.setTextStyle(c.id, TitlePreset.lowerThird.style))
}

@MainActor func main() async throws {
    // 1. sample footage
    var assets: [Scene: Asset] = [:]
    for s in Scene.allCases {
        let url = footage.appendingPathComponent("\(s.rawValue).mp4")
        if !FileManager.default.fileExists(atPath: url.path) { try await writeScene(s, seconds: 6, to: url) }
        assets[s] = try await Asset.load(url: url)
    }
    let scenes = Scene.allCases
    func addAssets(_ e: Editor) throws { for s in scenes { try e.apply(.addAsset(assets[s]!)) } }

    // 2. overlays
    do {
        let e = try newEditor(); try addAssets(e)
        _ = try e.addClip(asset: assets[.sunset]!, duration: 6_000); _ = try e.addClip(asset: assets[.forest]!, duration: 6_000)
        let kinds: [GeneratorKind] = [.confetti, .snow, .rain, .sparkles, .fireflies, .fireworks, .bokeh, .sunbeams, .hearts, .embers]
        for (i, k) in kinds.enumerated() {
            let start = Ms(i) * 1_200
            _ = try e.addOverlay(k, start: start, duration: 1_200, amount: 0.8)
            try caption(e, k.title, start: start + 80, duration: 1_040)
        }
        try await render("overlays", e)
    }
    // 3. transitions
    do {
        let e = try newEditor(); try addAssets(e)
        let types: [TransitionType] = [.crossfade, .slide, .zoom, .spin, .irisOpen, .pixelate, .cubeSpin, .whipLeft, .fadeBlack]
        var clips: [Clip] = []
        for i in 0...types.count { clips.append(try e.addClip(asset: assets[scenes[i % scenes.count]]!, sourceIn: Ms((i / scenes.count) * 1_500), duration: 2_400)) }
        for (i, t) in types.enumerated() { try e.addTransition(after: clips[i].id, type: t, duration: 900) }
        func clipStart(_ id: UUID) -> Ms { e.project.tracks.flatMap { $0.clips }.first { $0.id == id }!.start }
        for (i, t) in types.enumerated() { try caption(e, t.title, start: clipStart(clips[i + 1].id) + 50, duration: 800) }
        try await render("transitions", e)
    }
    // 4. effects
    do {
        let e = try newEditor(); try addAssets(e)
        let fx: [EffectType] = [.kenBurnsIn, .panLeft, .shake, .pulse, .lightLeak, .vhs, .chromatic, .glitch, .kaleidoscope, .fisheye, .neonEdges, .tiltShift]
        for (i, k) in fx.enumerated() {
            let c = try e.addClip(asset: assets[scenes[i % scenes.count]]!, sourceIn: Ms(i / scenes.count) * 1_500, duration: 1_300)
            try e.apply(.addEffect(c.id, Effect(k)))
            try caption(e, k.title, start: c.start + 60, duration: 1_150)
        }
        try await render("effects", e)
    }
    // 5. colour looks
    do {
        let e = try newEditor(); try addAssets(e)
        let looks = ["Teal & orange", "Golden hour", "Noir", "Cyberpunk", "Vintage film", "Pastel", "Cold steel", "Vivid"]
        for (i, name) in looks.enumerated() {
            let c = try e.addClip(asset: assets[scenes[i % scenes.count]]!, sourceIn: Ms(i / scenes.count) * 1_500, duration: 1_300)
            try e.apply(.setLook(c.id, Look.preset(name)!))
            try caption(e, name, start: c.start + 60, duration: 1_150)
        }
        try await render("looks", e)
    }
    // 6. titles
    do {
        let e = try newEditor(); try addAssets(e)
        let presets: [TitlePreset] = [.movie, .neon, .impact, .typewriter, .gold, .quote, .retro, .chapter]
        for (i, p) in presets.enumerated() {
            let c = try e.addClip(asset: assets[scenes[i % scenes.count]]!, sourceIn: Ms(i / scenes.count) * 1_500, duration: 1_500)
            let t = try e.addTitle(p.text, start: c.start + 100, duration: 1_300)
            try e.apply(.setTextStyle(t.id, p.style))
        }
        try await render("titles", e)
    }
}

if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "assistant-render" { try await renderAssistant(out: out) } else if CommandLine.arguments.count > 3, CommandLine.arguments[2] == "assistant" { try await recordAssistant(out: out, prompt: CommandLine.arguments[3]) } else { try await main() }
