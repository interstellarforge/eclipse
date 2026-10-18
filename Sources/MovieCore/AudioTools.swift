import AVFoundation
import CryptoKit
import Foundation

public struct Phrase: Equatable {
    public var start: Ms          // in the source file
    public var end: Ms
    public var text: String
    public init(start: Ms, end: Ms, text: String) { self.start = start; self.end = end; self.text = text }
}

public enum AudioTools {
    /// Quiet stretches (source time, ms) inside the part of the file a clip uses. Quiet = below 8 % of the loud parts' level.
    /// `padding` of each silence is kept, so words are not clipped.
    public static func silences(of asset: Asset, sourceIn: Ms, length: Ms, minSilence: Ms = 700, padding: Ms = 150) async throws -> [(start: Ms, end: Ms)] {
        let hop: Ms = 50
        let levels = try await AudioEnvelope.read(url: asset.url, hopMs: Int(hop))
        let first = Int(sourceIn / hop), last = min(levels.count, Int((sourceIn + length) / hop))
        guard first < last else { return [] }
        let slice = Array(levels[first..<last])
        let loud = slice.sorted()[Int(Double(slice.count - 1) * 0.9)]
        guard loud > 0.003 else { return [] }   // nothing but silence: leave it alone
        let threshold = max(0.002, Double(loud) * 0.08)
        var result: [(Ms, Ms)] = []
        var runStart: Int?
        for (i, level) in (slice + [Float.greatestFiniteMagnitude]).enumerated() {
            if Double(level) < threshold { if runStart == nil { runStart = i } }
            else if let s = runStart {
                let from = sourceIn + Ms(s) * hop, to = sourceIn + Ms(i) * hop
                if to - from >= minSilence, to - from - 2 * padding > 100 { result.append((from + padding, to - padding)) }
                runStart = nil
            }
        }
        return result
    }

    /// Volume that brings the clip's speech/music level to about -20 dBFS (RMS 0.1), clamped to 0.1...3.
    public static func normalizedVolume(of asset: Asset, sourceIn: Ms, length: Ms, target: Double = 0.1) async throws -> Double? {
        let hop: Ms = 100
        let levels = try await AudioEnvelope.read(url: asset.url, hopMs: Int(hop))
        let first = Int(sourceIn / hop), last = min(levels.count, Int((sourceIn + length) / hop))
        guard first < last else { return nil }
        let slice = Array(levels[first..<last]).map(Double.init)
        let peak = slice.max() ?? 0
        let active = slice.filter { $0 > peak * 0.15 }       // ignore the quiet gaps
        guard peak > 0.001, !active.isEmpty else { return nil }
        let rms = (active.reduce(0) { $0 + $1 * $1 } / Double(active.count)).squareRoot()
        return min(3, max(0.1, target / rms))
    }
}

extension AudioTools {
    /// Rumble removal (high-pass 90 Hz) plus a soft noise gate that closes in the pauses. Returns a mono WAV (cached) that lines up
    /// with the original file, so a clip can switch to it without moving. This is simple noise reduction, not studio restoration.
    public static func reduceNoise(of asset: Asset) async throws -> URL {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MovieMaker/Cleaned", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = "\(asset.url.path)|\((try? FileManager.default.attributesOfItem(atPath: asset.url.path)[.size] as? Int) ?? 0)"
        let output = dir.appendingPathComponent(SHA256.hash(data: Data(key.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined() + ".wav")
        if FileManager.default.fileExists(atPath: output.path) { return output }
        let rate = 44_100
        let input = try await AudioEnvelope.readSamples(url: asset.url, rate: rate)
        guard !input.isEmpty else { throw EditError.invalid("no sound to clean") }
        try SoundEffects.writeWAV(denoise(input, rate: rate), to: output)
        return output
    }

    public static func denoise(_ input: [Float], rate: Int) -> [Float] {
        // 2nd-order Butterworth high-pass at 90 Hz
        let w0 = 2 * Double.pi * 90 / Double(rate), alpha = sin(w0) / (2 * 0.7071)
        let b0 = (1 + cos(w0)) / 2, b1 = -(1 + cos(w0)), b2 = b0
        let a0 = 1 + alpha, a1 = -2 * cos(w0), a2 = 1 - alpha
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var filtered = [Float](repeating: 0, count: input.count)
        for i in input.indices {
            let x = Double(input[i])
            let y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
            x2 = x1; x1 = x; y2 = y1; y1 = y
            filtered[i] = Float(y)
        }
        // Noise floor = quiet 15 % of 10 ms frames; the gate opens above ~1.5x that and closes slowly.
        let frame = rate / 100
        let frames = max(1, filtered.count / frame)
        var levels = [Double](repeating: 0, count: frames)
        for f in 0..<frames {
            let slice = filtered[(f * frame)..<min(filtered.count, (f + 1) * frame)]
            levels[f] = (slice.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, slice.count))).squareRoot()
        }
        let floorLevel = max(1e-5, levels.sorted()[Int(Double(frames - 1) * 0.15)])
        var gate = [Double](repeating: 1, count: frames)
        for f in 0..<frames { gate[f] = min(1, max(0.1, (levels[f] - 1.3 * floorLevel) / (2.5 * floorLevel))) }
        var smoothed = 1.0
        var out = [Float](repeating: 0, count: filtered.count)
        let attack = 1 - exp(-1 / (0.006 * Double(rate))), release = 1 - exp(-1 / (0.12 * Double(rate)))
        for i in filtered.indices {
            let target = gate[min(frames - 1, i / frame)]
            smoothed += (target - smoothed) * (target > smoothed ? attack : release)
            out[i] = filtered[i] * Float(smoothed)
        }
        return out
    }
}

extension Editor {
    /// Swaps a clip's sound for a cleaned version. A video clip's own sound is detached (muted picture, grouped audio clip) first.
    public func useCleanedAudio(of clipID: UUID, cleaned: Asset) throws {
        guard let track = project.tracks.first(where: { $0.clips.contains { $0.id == clipID } }),
              let clip = track.clips.first(where: { $0.id == clipID }) else { throw EditError.notFound }
        try transaction {
            if track.kind == .audio {
                try apply(.replaceClipAsset(clipID, cleaned.id))
            } else {
                guard !clip.muted else { throw EditError.invalid("This clip's sound is already detached: select the audio clip instead.") }
                let audio = try addClip(asset: cleaned, start: clip.start, sourceIn: clip.sourceIn, duration: clip.sourceLength, kind: .audio)
                if clip.speed != 1 { try apply(.setSpeed(audio.id, clip.speed)) }
                try apply(.setVolume(audio.id, volume: clip.volume, fadeIn: clip.fadeIn, fadeOut: clip.fadeOut))
                try apply(.setMuted(clipID, true))
                try apply(.group([clipID, audio.id]))
            }
        }
    }
}

extension Editor {
    /// Cuts the quiet parts out of a clip and closes the gaps (ripple, grouped sound follows). Returns how many ms were removed.
    @discardableResult
    public func removeSilences(of clipID: UUID, ranges: [(start: Ms, end: Ms)]) throws -> Ms {
        func find(_ id: UUID) -> Clip? { project.tracks.flatMap(\.clips).first { $0.id == id } }
        guard let clip = find(clipID) else { throw EditError.notFound }
        var removed: Ms = 0
        try transaction {
            // Latest first, so the earlier ranges keep their positions. Source ms become timeline ms through the speed.
            for r in ranges.sorted(by: { $0.start > $1.start }) {
                let from = clip.start + Ms((Double(r.start - clip.sourceIn) / clip.speed).rounded())
                let to = clip.start + Ms((Double(r.end - clip.sourceIn) / clip.speed).rounded())
                guard from >= clip.start, to <= clip.end, to > from, let current = find(clipID) else { continue }
                if to < current.end { try apply(.splitClip(clipID, at: to)) }
                if from > clip.start {
                    try apply(.splitClip(clipID, at: from))
                    guard let track = project.tracks.first(where: { $0.clips.contains { $0.id == clipID } }),
                          let silence = track.clips.first(where: { $0.start == from && $0.id != clipID }) else { continue }
                    try apply(.rippleRemove(silence.id))
                } else {
                    try apply(.rippleRemove(clipID))   // the silence is the very start of the clip
                }
                removed += to - from
            }
        }
        return removed
    }

    /// Subtitles from speech: one title per phrase on the "Captions" track, placed through the clip's source offset and speed.
    @discardableResult
    public func addCaptions(for clipID: UUID, phrases: [Phrase], maxCharacters: Int = 42) throws -> Int {
        guard let clip = project.tracks.flatMap(\.clips).first(where: { $0.id == clipID }) else { throw EditError.notFound }
        let sourceStart = clip.sourceIn, sourceEnd = clip.sourceIn + clip.sourceLength
        var cues: [(start: Ms, end: Ms, text: String)] = []
        for p in phrases where p.end > sourceStart && p.start < sourceEnd && !p.text.isEmpty {
            let s = max(p.start, sourceStart), e = min(p.end, sourceEnd)
            let words = p.text.split(separator: " ").map(String.init)
            var chunks: [String] = [], line = ""
            for w in words {   // short lines that read in one glance
                if !line.isEmpty && line.count + 1 + w.count > maxCharacters { chunks.append(line); line = w } else { line += (line.isEmpty ? "" : " ") + w }
            }
            if !line.isEmpty { chunks.append(line) }
            let total = max(1, chunks.reduce(0) { $0 + $1.count })
            var cursor = s
            for (i, text) in chunks.enumerated() {
                let share = Ms(Double(e - s) * Double(text.count) / Double(total))
                let to = i == chunks.count - 1 ? e : cursor + share
                cues.append((cursor, to, text)); cursor = to
            }
        }
        guard !cues.isEmpty else { return 0 }
        try transaction {
            var track = project.tracks.first { $0.kind == .text && $0.name == "Captions" }?.id
            if track == nil {
                let id = UUID()
                try apply(.addTrack(id: id, kind: .text)); try apply(.setTrackName(id, "Captions")); track = id
            }
            var style = TitlePreset.subtitle.style
            style.box = true; style.size = 0.045; style.y = 0.1
            var lastEnd: Ms = 0
            for cue in cues {
                let start = max(clip.start + Ms((Double(cue.start - sourceStart) / clip.speed).rounded()), lastEnd)
                let end = min(clip.start + Ms((Double(cue.end - sourceStart) / clip.speed).rounded()), clip.end)
                guard end - start >= 200 else { continue }
                let caption = Clip(assetID: nil, text: cue.text, duration: end - start, start: start)
                try apply(.addClip(track: track!, clip: caption))
                try apply(.setTextStyle(caption.id, style))
                lastEnd = end
            }
        }
        return cues.count
    }
}

public enum Subtitles {
    /// SubRip (.srt) from the Captions track, or from all title tracks when there is none.
    public static func srt(_ p: Project) -> String {
        let captions = p.tracks.filter { $0.kind == .text && $0.name == "Captions" }
        let tracks = captions.isEmpty ? p.tracks.filter { $0.kind == .text } : captions
        let cues = tracks.flatMap(\.clips).filter { !($0.text ?? "").isEmpty }.sorted { $0.start < $1.start }
        func time(_ ms: Ms) -> String { String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000) }
        return cues.enumerated().map { "\($0.offset + 1)\n\(time($0.element.start)) --> \(time($0.element.end))\n\($0.element.text ?? "")\n" }.joined(separator: "\n")
    }
}
