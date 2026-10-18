import AVFoundation

/// Output size of an export. The movie keeps its look; clips are fitted into this frame.
public struct ExportSettings: Equatable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }

    /// The project's aspect ratio with `shortSide` pixels on its short edge (720, 1080, 2160).
    public static func profile(_ p: Project, shortSide: Int) -> ExportSettings {
        let aspect = Double(p.width) / Double(p.height)
        let (w, h) = aspect >= 1 ? (Double(shortSide) * aspect, Double(shortSide)) : (Double(shortSide), Double(shortSide) / aspect)
        return ExportSettings(width: Int(w.rounded()) & ~1, height: Int(h.rounded()) & ~1)
    }
}

/// Ready-made sizes for where the video will be watched.
public enum ExportPreset: String, CaseIterable {
    case youtube720, youtube1080, youtube4K, tiktok, instagramFeed, square

    public var title: String {
        switch self {
        case .youtube720: return "YouTube 720p"
        case .youtube1080: return "YouTube 1080p"
        case .youtube4K: return "YouTube 4K"
        case .tiktok: return "TikTok / Reels / Shorts (9:16)"
        case .instagramFeed: return "Instagram feed (4:5)"
        case .square: return "Square (1:1)"
        }
    }

    public var settings: ExportSettings {
        switch self {
        case .youtube720: return ExportSettings(width: 1280, height: 720)
        case .youtube1080: return ExportSettings(width: 1920, height: 1080)
        case .youtube4K: return ExportSettings(width: 3840, height: 2160)
        case .tiktok: return ExportSettings(width: 1080, height: 1920)
        case .instagramFeed: return ExportSettings(width: 1080, height: 1350)
        case .square: return ExportSettings(width: 1080, height: 1080)
        }
    }

    public var fileSuffix: String { rawValue }
}

public enum Exporter {
    /// Renders the project to an H.264 + AAC MP4. Replaces an existing file at `url`. Cancelling the task cancels the export.
    /// `progress` gets 0...1 about five times a second.
    public static func export(_ p: Project, to url: URL, settings: ExportSettings? = nil, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard p.duration > 0 else { throw EditError.invalid("nothing to export") }
        let size = settings.map { CGSize(width: $0.width, height: $0.height) }
        let built = try await CompositionBuilder.build(p, renderSize: size)
        let longSide = max(settings?.width ?? p.width, settings?.height ?? p.height)
        let preset = longSide >= 3_000 ? AVAssetExportPreset3840x2160 : longSide >= 1_700 ? AVAssetExportPreset1920x1080 : AVAssetExportPreset1280x720   // all H.264
        guard let session = AVAssetExportSession(asset: built.composition, presetName: preset) else {
            throw EditError.invalid("This movie can't be exported at that size.")
        }
        session.videoComposition = built.videoComposition
        session.audioMix = built.audioMix
        session.audioTimePitchAlgorithm = .spectral
        try? FileManager.default.removeItem(at: url)
        do {
            try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    if let progress {
                        group.addTask {
                            for await state in session.states(updateInterval: 0.2) {
                                if case .exporting(let p) = state { progress(p.fractionCompleted) }
                            }
                        }
                    }
                    try await session.export(to: url, as: .mp4)
                    group.cancelAll()
                }
            } onCancel: { session.cancelExport() }
            progress?(1)
        } catch {
            try? FileManager.default.removeItem(at: url)   // never leave a half-written file behind
            if Task.isCancelled || (error as? AVError)?.code == .exportFailed && (error as NSError).localizedDescription.localizedCaseInsensitiveContains("cancel") {
                throw CancellationError()
            }
            throw error
        }
    }

    /// One file per preset in `folder`: "<name>-<preset>.mp4". Returns the files written.
    public static func exportBatch(_ p: Project, presets: [ExportPreset], into folder: URL, name: String,
                                   progress: (@Sendable (ExportPreset, Double) -> Void)? = nil) async throws -> [URL] {
        var written: [URL] = []
        for preset in presets {
            let url = folder.appendingPathComponent("\(name)-\(preset.fileSuffix).mp4")
            try await export(p, to: url, settings: preset.settings) { progress?(preset, $0) }
            written.append(url)
        }
        return written
    }
}
