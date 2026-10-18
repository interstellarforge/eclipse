import AVFoundation
import AppKit
import Speech

/// Eyes and ears for Claude: it can look at footage (contact sheets), read an activity summary, and read a transcript.
public enum Vision {
    private static func stamp(_ ms: Ms) -> String { String(format: "%d:%02d.%d", ms / 60_000, (ms / 1000) % 60, (ms % 1000) / 100) }

    /// One PNG with evenly spaced frames, each labelled with its time. `videoComposition` shows the edited result instead of raw footage.
    public static func contactSheet(of asset: AVAsset, videoComposition: AVVideoComposition? = nil, times: [Ms],
                                    cellSize: Int = 320, columns: Int? = nil) async throws -> Data {
        guard !times.isEmpty else { throw EditError.invalid("no frames requested") }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.videoComposition = videoComposition
        gen.maximumSize = CGSize(width: cellSize, height: cellSize)
        gen.requestedTimeToleranceBefore = CMTime(value: 250, timescale: 1000)
        gen.requestedTimeToleranceAfter = CMTime(value: 250, timescale: 1000)
        var frames: [Ms: CGImage] = [:]
        for await result in gen.images(for: times.map { cm($0) }) {
            if let image = try? result.image { frames[Ms((result.requestedTime.seconds * 1000).rounded())] = image }
        }
        guard let first = times.compactMap({ frames[$0] }).first else { throw EditError.invalid("could not read any frame") }
        let cw = first.width, ch = first.height
        let cols = columns ?? (cw >= ch ? min(times.count, 4) : min(times.count, 6))
        let rows = (times.count + cols - 1) / cols
        let gap = 4
        let width = cols * cw + (cols + 1) * gap, height = rows * ch + (rows + 1) * gap
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw EditError.invalid("could not draw the contact sheet")
        }
        ctx.setFillColor(gray: 0.08, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for (i, t) in times.enumerated() {
            let col = i % cols, row = i / cols
            let x = CGFloat(gap + col * (cw + gap))
            let y = CGFloat(height - gap - (row + 1) * ch - row * gap)   // rows run top to bottom
            let cell = CGRect(x: x, y: y, width: CGFloat(cw), height: CGFloat(ch))
            if let image = frames[t] { ctx.draw(image, in: cell) }
            else { ctx.setFillColor(gray: 0.25, alpha: 1); ctx.fill(cell) }
            let label = " \(stamp(t)) " as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
            let size = label.size(withAttributes: attrs)
            NSColor.black.withAlphaComponent(0.7).setFill()
            let top = y + CGFloat(ch) - size.height
            NSBezierPath(rect: CGRect(x: x, y: top - 2, width: size.width + 2, height: size.height + 2)).fill()
            label.draw(at: CGPoint(x: x + 1, y: top - 1), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { throw EditError.invalid("could not draw the contact sheet") }
        return try pngData(image)
    }

    /// `count` times spread evenly over [start, end), each at the middle of its slice.
    public static func evenTimes(start: Ms, end: Ms, count: Int) -> [Ms] {
        let n = max(1, count), span = max(1, end - start)
        return (0..<n).map { start + span * Int64(2 * $0 + 1) / Int64(2 * n) }
    }

    /// Facts and an activity summary of one clip, as plain text.
    public static func inspect(_ asset: Asset) async throws -> String {
        let av = AVURLAsset(url: asset.url)
        var lines = ["file: \(asset.url.lastPathComponent)", "duration: \(asset.duration) ms (\(stamp(asset.duration)))"]
        if let track = try await av.loadTracks(withMediaType: .video).first {
            let size = try await track.load(.naturalSize).applying(try await track.load(.preferredTransform))
            let fps = try await track.load(.nominalFrameRate)
            lines.append("picture: \(Int(abs(size.width)))x\(Int(abs(size.height))) at \(String(format: "%.0f", fps)) fps"
                         + (abs(size.height) > abs(size.width) ? " (vertical)" : ""))
        } else { lines.append("picture: none (audio only)") }
        lines.append("sound: \(asset.hasAudio ? "yes" : "no")")
        let a = await ClipAnalyzer.analyze(asset)
        func digits(_ v: [Double]) -> String { String(v.map { Character(String(min(9, Int(($0 * 9).rounded())))) }) }
        lines.append("analysis: one character per \(a.binMs) ms, 0 = calm/quiet, 9 = busiest/loudest")
        if asset.hasVideo { lines.append("activity: \(digits(a.motion))") }
        if !a.loudness.isEmpty { lines.append("loudness: \(digits(a.loudness))") }
        let cuts = a.rawMotion.enumerated().filter { $0.element > 0.3 }.prefix(12).map { stamp(Ms($0.offset + 1) * a.binMs) }
        if !cuts.isEmpty { lines.append("big picture changes (cuts or fast motion) near: \(cuts.joined(separator: ", "))") }
        let best = a.bestWindows(length: 3_000, count: 3, duration: asset.duration)
        lines.append("best 3 s moments by activity and sound: " + best.enumerated().map {
            "\($0.offset + 1)) \($0.element.start)-\($0.element.end) ms (score \(String(format: "%.2f", $0.element.score)))" }.joined(separator: "; "))
        lines.append("tip: look at these with watch_asset (start_ms, end_ms) before using them.")
        return lines.joined(separator: "\n")
    }
}

/// Speech to text with Apple's recognizer (on-device when the language supports it). Needs the bundled app: macOS asks permission once.
public enum Transcriber {
    public static func transcribe(url: URL, language: String? = nil) async throws -> String {
        format(try await phrases(url: url, language: language))
    }

    /// Phrases (ms in the file) split at pauses.
    public static func phrases(url: URL, language: String? = nil) async throws -> [Phrase] {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else {
            throw EditError.invalid("Transcription needs the Lumacut app (it asks macOS for speech recognition permission).")
        }
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else { throw EditError.invalid("Speech recognition is not allowed. Enable it for Lumacut in System Settings > Privacy & Security > Speech Recognition.") }
        let locale = language.map { Locale(identifier: $0) } ?? Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw EditError.invalid("Speech recognition is not available for \(locale.identifier).")
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { cont in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal { finished = true; cont.resume(returning: result) }
                else if let error { finished = true; cont.resume(throwing: error) }
            }
        }
        return split(result.bestTranscription.segments.map { ($0.timestamp, $0.duration, $0.substring) })
    }

    static func format(_ phrases: [Phrase]) -> String {
        phrases.isEmpty ? "(no speech found)" : phrases.map { "\($0.start)-\($0.end) ms: \($0.text)" }.joined(separator: "\n")
    }

    /// Words (seconds) grouped into phrases at pauses longer than 0.7 s.
    public static func split(_ words: [(start: Double, duration: Double, text: String)]) -> [Phrase] {
        var phrases: [Phrase] = []
        var current: [String] = []
        var start = 0.0, end = 0.0
        func flush() { if !current.isEmpty { phrases.append(Phrase(start: Ms(start * 1000), end: Ms(end * 1000), text: current.joined(separator: " "))); current = [] } }
        for w in words {
            if !current.isEmpty && w.start - end > 0.7 { flush() }
            if current.isEmpty { start = w.start }
            current.append(w.text); end = w.start + w.duration
        }
        flush()
        return phrases
    }

    public static func group(_ words: [(start: Double, duration: Double, text: String)]) -> String { format(split(words)) }
}
