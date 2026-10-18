import Foundation

/// Procedurally synthesized sound effects: no third-party audio, so no licences to track.
public enum SoundEffects {
    public static let names = ["Whoosh", "Impact", "Riser", "Ding", "Sparkle", "Pop", "Click", "Shutter", "Heartbeat", "Rain", "Wind", "Beep"]
    static let sampleRate = 44_100

    /// Returns a WAV file for the effect, writing it to Application Support on first use.
    public static func url(for name: String) throws -> URL {
        guard let samples = synthesize(name) else { throw EditError.notFound }
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
            .appendingPathComponent("MovieMaker/SFX", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).wav")
        if !FileManager.default.fileExists(atPath: url.path) { try writeWAV(samples, to: url) }
        return url
    }

    /// 16-bit mono PCM at 44.1 kHz.
    public static func writeWAV(_ samples: [Float], to url: URL) throws {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_767))) }
        try d.write(to: url)
    }

    static func synthesize(_ name: String) -> [Float]? {
        let sr = Double(sampleRate)
        var seed: UInt32 = 12_345   // fixed seed: the same effect every run
        func noise() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed >> 8) / Double(1 << 24) * 2 - 1
        }
        func make(_ seconds: Double, _ f: (Double, Double) -> Double) -> [Float] {   // (t, progress 0...1)
            (0..<Int(seconds * sr)).map { Float(f(Double($0) / sr, Double($0) / (seconds * sr))) }
        }
        switch name {
        case "Whoosh":
            var lp = 0.0
            return make(1.2) { _, p in
                let cutoff = 0.02 + 0.5 * sin(.pi * p)          // filter opens then closes
                lp += cutoff * (noise() - lp)
                return lp * 2.5 * pow(sin(.pi * p), 2) * 0.7
            }
        case "Ding":
            return make(1.5) { t, _ in
                (sin(2 * .pi * 1318.5 * t) + 0.3 * sin(2 * .pi * 2637 * t)) * exp(-4 * t) * 0.5
            }
        case "Pop":
            return make(0.15) { t, p in sin(2 * .pi * (400 - 300 * p) * t) * exp(-30 * t) * 0.8 }
        case "Riser":
            var phase = 0.0
            return make(2.0) { _, p in
                phase += 2 * .pi * (200 + 1800 * p * p) / sr
                return (sin(phase) * 0.6 + noise() * 0.2) * p * 0.6
            }
        case "Beep":
            return make(0.4) { t, p in sin(2 * .pi * 880 * t) * min(1, t * 100, (1 - p) * 40) * 0.5 }
        case "Impact":
            var lp = 0.0
            return make(1.4) { t, _ in
                lp += 0.08 * (noise() - lp)
                return (sin(2 * .pi * (35 + 90 * exp(-12 * t)) * t) * exp(-3.2 * t) + lp * 3 * exp(-14 * t)) * 0.9
            }
        case "Click":
            return make(0.06) { t, _ in (sin(2 * .pi * 2_400 * t) * 0.6 + noise() * 0.3) * exp(-90 * t) * 0.8 }
        case "Sparkle":
            var blips: [(at: Double, freq: Double)] = []
            var cursor = 0.0
            while cursor < 1.0 { blips.append((cursor, 2_500 + (noise() + 1) * 1_800)); cursor += 0.05 + (noise() + 1) * 0.05 }
            return make(1.4) { t, _ in
                blips.reduce(0.0) { acc, b in t >= b.at ? acc + sin(2 * .pi * b.freq * (t - b.at)) * exp(-14 * (t - b.at)) * 0.25 : acc }
            }
        case "Shutter":
            return make(0.3) { t, _ in
                let a = (noise() * 0.6 + sin(2 * .pi * 1_800 * t) * 0.3) * exp(-70 * t)
                let b = t > 0.11 ? (noise() * 0.6 + sin(2 * .pi * 1_300 * (t - 0.11)) * 0.3) * exp(-60 * (t - 0.11)) : 0
                return (a + b) * 0.8
            }
        case "Heartbeat":
            return make(1.8) { t, _ in
                [0.0, 0.28, 0.9, 1.18].reduce(0.0) { acc, at in
                    t >= at ? acc + sin(2 * .pi * 58 * (t - at)) * exp(-16 * (t - at)) * (at.truncatingRemainder(dividingBy: 0.9) == 0 ? 0.9 : 0.6) : acc
                }
            }
        case "Rain":
            var lp = 0.0, drops = 0.0
            return make(8.0) { t, p in
                lp += 0.35 * (noise() - lp)
                if noise() > 0.995 { drops = 0.6 }
                drops *= 0.9
                return (noise() - lp) * 0.22 + drops * noise() * 0.3 * min(1, t * 4, (1 - p) * 20)
            }
        case "Wind":
            var lp = 0.0
            return make(8.0) { t, p in
                lp += (0.01 + 0.03 * (0.5 + 0.5 * sin(2 * .pi * 0.25 * t))) * (noise() - lp)
                return lp * 4 * min(1, t * 2, (1 - p) * 10) * 0.8
            }
        default:
            return nil
        }
    }
}
