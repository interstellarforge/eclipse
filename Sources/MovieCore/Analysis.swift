import AVFoundation
import CoreGraphics

enum AudioEnvelope {
    /// RMS level per `hopMs` of the first audio track (mono, 20 kHz so every hop is a whole number of samples). Empty if there is no audio.
    static func read(url: URL, hopMs: Int) async throws -> [Float] {
        let av = AVURLAsset(url: url)
        guard let track = try await av.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: av)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 20_000, AVNumberOfChannelsKey: 1])
        reader.add(out)
        guard reader.startReading() else { throw reader.error ?? EditError.invalid("cannot read audio") }
        let hop = 20_000 * hopMs / 1000
        var result: [Float] = []
        var sum = 0.0, count = 0
        while let sb = out.copyNextSampleBuffer() {
            guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
            var length = 0; var ptr: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr)
            let floats = UnsafeBufferPointer(start: UnsafeRawPointer(ptr!).assumingMemoryBound(to: Float.self), count: length / 4)
            for s in floats {
                sum += Double(s * s); count += 1
                if count == hop { result.append(Float((sum / Double(count)).squareRoot())); sum = 0; count = 0 }
            }
        }
        return result
    }
}

extension AudioEnvelope {
    /// All samples of the first audio track as mono floats at `rate` Hz.
    static func readSamples(url: URL, rate: Int = 44_100) async throws -> [Float] {
        let av = AVURLAsset(url: url)
        guard let track = try await av.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: av)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1])
        reader.add(out)
        guard reader.startReading() else { throw reader.error ?? EditError.invalid("cannot read audio") }
        var samples: [Float] = []
        while let sb = out.copyNextSampleBuffer() {
            guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
            var length = 0; var ptr: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr)
            samples += Array(UnsafeBufferPointer(start: UnsafeRawPointer(ptr!).assumingMemoryBound(to: Float.self), count: length / 4))
        }
        return samples
    }
}

struct ClipAnalysis {
    var binMs: Ms
    var scores: [Double]       // 0...1, higher = more interesting
    var motion: [Double] = []  // 0...1 relative to the clip's busiest moment
    var rawMotion: [Double] = []   // mean frame difference 0...1 between neighbouring samples
    var loudness: [Double] = []    // 0...1 relative to the loudest moment (empty without audio)

    /// Best non-overlapping windows, highest score first.
    func bestWindows(length: Ms, count: Int, duration: Ms) -> [(start: Ms, end: Ms, score: Double)] {
        let window = min(length, duration)
        var picked: [(start: Ms, end: Ms, score: Double)] = []
        let candidates = stride(from: Int64(0), through: max(0, duration - window), by: Int(binMs)).map { start in
            (start: start, end: start + window, score: score(from: start, length: window))
        }.sorted { $0.score > $1.score }
        for c in candidates where picked.count < count && !picked.contains(where: { c.start < $0.end && $0.start < c.end }) { picked.append(c) }
        return picked
    }

    func score(from start: Ms, length: Ms) -> Double {
        let a = Int(start / binMs), b = max(a + 1, Int((start + length) / binMs))
        let slice = scores[min(a, scores.count)..<min(b, scores.count)]
        return slice.isEmpty ? 0 : slice.reduce(0, +) / Double(slice.count)
    }
}

enum ClipAnalyzer {
    /// Interest per time bin: 60% frame-to-frame motion, 40% audio loudness (motion only if the clip is silent).
    static func analyze(_ asset: Asset) async -> ClipAnalysis {
        let bin = max(500, (asset.duration / 1_500 / 500) * 500)   // cap the number of sampled frames
        let bins = Int((asset.duration + bin - 1) / bin)
        var motion = [Double](repeating: 0, count: bins)
        if asset.hasVideo {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: asset.url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 64, height: 64)
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            let times = (0..<bins).map { cm(min(Ms($0) * bin, max(0, asset.duration - 1))) }
            var previous: [UInt8]?
            var index = 0
            for await result in gen.images(for: times) {
                defer { index += 1 }
                guard let image = try? result.image, let pixels = grayPixels(image) else { previous = nil; continue }
                if let prev = previous, prev.count == pixels.count, index > 0 {
                    let diff = zip(prev, pixels).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
                    motion[index - 1] = Double(diff) / Double(pixels.count) / 255
                }
                previous = pixels
            }
        }
        let loud = ((try? await AudioEnvelope.read(url: asset.url, hopMs: Int(bin))) ?? [])
        func normalized(_ v: [Double]) -> [Double] { let m = v.max() ?? 0; return m > 0 ? v.map { $0 / m } : v }
        let m = normalized(motion)
        guard let top = loud.max(), top > 0 else { return ClipAnalysis(binMs: bin, scores: m, motion: m, rawMotion: motion) }
        let l = loud.map { Double($0 / top) }
        return ClipAnalysis(binMs: bin, scores: (0..<bins).map { 0.6 * m[$0] + 0.4 * (l.indices.contains($0) ? l[$0] : 0) },
                            motion: m, rawMotion: motion, loudness: l)
    }

    private static func grayPixels(_ image: CGImage) -> [UInt8]? {
        let w = 32, h = 32
        var px = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return px
    }
}

public struct BeatGrid {
    public var bpm: Double
    public var firstBeatMs: Ms
    public var periodMs: Double
}

public enum BeatTracker {
    /// Finds tempo (70-180 BPM) and the first beat by comb-filtering the onset curve.
    /// Limitation: can lock onto half/double time on music with strong off-beats.
    public static func analyze(url: URL) async throws -> BeatGrid {
        let env = try await AudioEnvelope.read(url: url, hopMs: 10)
        guard env.count > 300 else { throw EditError.invalid("music too short to find a beat") }
        var onset = [Double](repeating: 0, count: env.count)
        for i in 1..<env.count { onset[i] = Double(max(0, env[i] - env[i - 1])) }
        var best = (score: -1.0, period: 50.0, phase: 0)
        var p = 33.0
        while p <= 86.0 {
            for phase in 0..<Int(p) {
                var sum = 0.0, n = 0
                var pos = Double(phase)
                while Int(pos.rounded()) < onset.count { sum += onset[Int(pos.rounded())]; n += 1; pos += p }
                let score = sum / Double(max(n, 1))
                if score > best.score { best = (score, p, phase) }
            }
            p += 0.1
        }
        return BeatGrid(bpm: 6_000 / best.period, firstBeatMs: Ms(best.phase) * 10, periodMs: best.period * 10)
    }
}

public enum Waveform {
    /// Loudness per `hopMs`, scaled so the loudest bin is 1. Empty if the file has no audio.
    public static func levels(url: URL, hopMs: Int = 50) async -> [Float] {
        let env = (try? await AudioEnvelope.read(url: url, hopMs: hopMs)) ?? []
        let top = env.max() ?? 0
        return top > 0 ? env.map { $0 / top } : env
    }
}
