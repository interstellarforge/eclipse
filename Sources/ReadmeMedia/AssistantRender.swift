import AVFoundation
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Replays a recorded assistant session (assistant-session.json) as a video: chat on the left, the movie it is building on the right.
private let bg = NSColor(red: 0.031, green: 0.039, blue: 0.094, alpha: 1), panel = NSColor(red: 0.051, green: 0.063, blue: 0.141, alpha: 1)
private let accent = NSColor(red: 0.482, green: 0.239, blue: 1, alpha: 1), dim = NSColor(white: 0.62, alpha: 1), light = NSColor(white: 0.93, alpha: 1)

private func nice(_ t: String) -> String { t.replacingOccurrences(of: "_", with: " ").prefix(1).uppercased() + t.replacingOccurrences(of: "_", with: " ").dropFirst() }

private struct Item { var step: Step; var appear: Double; var typing: Double }

private func attr(_ s: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}

@MainActor
func renderAssistant(out: URL) async throws {
    let steps = try JSONDecoder().decode([Step].self, from: Data(contentsOf: out.appendingPathComponent("assistant-session.json")))
    let frames = out.appendingPathComponent("assistant-frames")
    // timeline
    var items: [Item] = [], t = 0.6
    for s in steps {
        var typing = 0.0
        switch s.kind {
        case "user": typing = 1.6; items.append(Item(step: s, appear: t, typing: typing)); t += 2.4
        case "text": typing = min(5, Double(s.text.count) / 60); items.append(Item(step: s, appear: t, typing: typing)); t += typing + 0.7
        default: items.append(Item(step: s, appear: t, typing: 0)); t += 0.45
        }
    }
    let chatEnd = t + 1.0
    let final = AVURLAsset(url: out.appendingPathComponent("assistant-result.mp4"))
    let finalLen = try await final.load(.duration).seconds
    let total = chatEnd + finalLen + 1.2
    let gen = AVAssetImageGenerator(asset: final); gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero; gen.maximumSize = CGSize(width: 1300, height: 732)
    var frameCache: [String: CGImage] = [:]
    func previewFor(_ time: Double) -> (CGImage?, String) {
        if time >= chatEnd { return ((try? gen.copyCGImage(at: CMTime(seconds: min(time - chatEnd, finalLen - 0.05), preferredTimescale: 600), actualTime: nil)), "Result") }
        var name: String?, clips = 0, ms = 0
        for it in items where it.appear + 0.5 <= time { if let f = it.step.frame { name = f; clips = it.step.clips ?? 0; ms = it.step.ms ?? 0 } }
        guard let name else { return (nil, "") }
        if frameCache[name] == nil, let src = CGImageSourceCreateWithURL(frames.appendingPathComponent(name) as CFURL, nil) { frameCache[name] = CGImageSourceCreateImageAtIndex(src, 0, nil) }
        return (frameCache[name], "\(clips) clips · \(String(format: "%.1f", Double(ms) / 1000)) s")
    }

    let W = 1280, H = 720, chatW: CGFloat = 540
    func draw(_ time: Double) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let g = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
        let cg = g.cgContext; cg.translateBy(x: 0, y: CGFloat(H)); cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        bg.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
        // chat panel
        panel.setFill(); NSBezierPath(roundedRect: NSRect(x: 16, y: 16, width: chatW, height: CGFloat(H) - 32), xRadius: 14, yRadius: 14).fill()
        attr("✦ AI Assistant", size: 17, color: light, weight: .semibold).draw(at: NSPoint(x: 38, y: 32))
        attr("BETA", size: 10, color: NSColor(red: 0.76, green: 0.36, blue: 1, alpha: 1), weight: .bold).draw(at: NSPoint(x: 168, y: 37))
        // lay out items that have appeared
        let inner = chatW - 56
        var blocks: [(rect: NSRect, draw: () -> Void)] = [], y: CGFloat = 0
        for it in items where it.appear <= time {
            let s = it.step
            switch s.kind {
            case "user":
                let shown = String(s.text.prefix(Int(Double(s.text.count) * min(1, (time - it.appear) / max(it.typing, 0.1)))))
                let a = attr(shown, size: 13, color: .white)
                let r = a.boundingRect(with: NSSize(width: inner - 60, height: 2000), options: [.usesLineFragmentOrigin])
                let h = ceil(r.height) + 22, w = min(inner, ceil(r.width) + 28), yy = y
                blocks.append((NSRect(x: 0, y: yy, width: inner, height: h), { let b = NSRect(x: 38 + inner - w, y: 0, width: w, height: h)
                    accent.setFill(); NSBezierPath(roundedRect: b, xRadius: 12, yRadius: 12).fill()
                    a.draw(with: NSRect(x: b.minX + 14, y: 11, width: w - 28, height: h), options: [.usesLineFragmentOrigin]) }))
                y += h + 12
            case "text":
                let shown = String(s.text.prefix(Int(Double(s.text.count) * min(1, (time - it.appear) / max(it.typing, 0.1)))))
                let a = attr(shown.replacingOccurrences(of: "**", with: ""), size: 13, color: light)
                let h = ceil(a.boundingRect(with: NSSize(width: inner, height: 4000), options: [.usesLineFragmentOrigin]).height) + 4
                blocks.append((NSRect(x: 0, y: y, width: inner, height: h), { a.draw(with: NSRect(x: 38, y: 0, width: inner, height: h), options: [.usesLineFragmentOrigin]) }))
                y += h + 12
            default:
                let done = time - it.appear > 0.4
                blocks.append((NSRect(x: 0, y: y, width: inner, height: 20), {
                    (s.error == true ? NSColor.systemRed : done ? NSColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1) : accent).setFill()
                    NSBezierPath(ovalIn: NSRect(x: 38, y: 5, width: 9, height: 9)).fill()
                    attr(nice(s.tool ?? "tool"), size: 12, color: dim).draw(at: NSPoint(x: 56, y: 1)) }))
                y += 22
            }
        }
        // bottom-anchored scroll inside the panel
        let top: CGFloat = 70, bottom = CGFloat(H) - 40, avail = bottom - top
        let offset = max(0, y - avail)
        cg.saveGState(); cg.clip(to: CGRect(x: 20, y: top, width: chatW - 8, height: avail))
        for b in blocks { let yy = top + b.rect.minY - offset; if yy > top - 400, yy < bottom + 20 { cg.saveGState(); cg.translateBy(x: 0, y: yy); b.draw(); cg.restoreGState() } }
        cg.restoreGState()
        // preview
        let (img, caption) = previewFor(time)
        let pr = NSRect(x: 580, y: 120, width: 676, height: 380)
        NSColor.black.setFill(); NSBezierPath(roundedRect: pr, xRadius: 12, yRadius: 12).fill()
        if let img { cg.saveGState(); NSBezierPath(roundedRect: pr, xRadius: 12, yRadius: 12).addClip()
            cg.translateBy(x: pr.minX, y: pr.maxY); cg.scaleBy(x: 1, y: -1); cg.draw(img, in: CGRect(x: 0, y: 0, width: pr.width, height: pr.height)); cg.restoreGState()
        } else { attr("Your clips are ready. Ask for a film.", size: 15, color: dim).draw(at: NSPoint(x: pr.minX + 190, y: pr.midY - 10)) }
        attr(caption, size: 13, color: dim).draw(at: NSPoint(x: pr.minX + 4, y: pr.maxY + 10))
        attr("Eclipse · real session: the assistant edits the project through the editor's own tools", size: 12, color: NSColor(white: 0.45, alpha: 1)).draw(at: NSPoint(x: 580, y: 40))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    // encode
    let mp4 = out.appendingPathComponent("assistant-demo.mp4"); try? FileManager.default.removeItem(at: mp4)
    let w = try AVAssetWriter(outputURL: mp4, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000]])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
    w.add(input); w.startWriting(); w.startSession(atSourceTime: .zero)
    let gifURL = out.appendingPathComponent("assistant-demo.gif"), gifFPS = 8
    let n = Int(total * 30), gifN = Int(total * Double(gifFPS))
    let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, gifN, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    var nextGif = 0
    for i in 0..<n {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        let time = Double(i) / 30, img = draw(time)
        var pb: CVPixelBuffer?; CVPixelBufferCreate(nil, W, H, kCVPixelFormatType_32BGRA, nil, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let c = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: W, height: H, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        c.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H)); CVPixelBufferUnlockBaseAddress(pb!, [])
        adaptor.append(pb!, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
        if time >= Double(nextGif) / Double(gifFPS), nextGif < gifN {
            let sc = CGContext(data: nil, width: 800, height: 450, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            sc.interpolationQuality = .high; sc.draw(img, in: CGRect(x: 0, y: 0, width: 800, height: 450))
            CGImageDestinationAddImage(dest, sc.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(gifFPS)]] as CFDictionary); nextGif += 1
        }
        // stills for the README at chosen moments
        let marks: [(String, Double)] = [("ask", 2.6), ("working", chatEnd * 0.55), ("done", chatEnd - 0.2), ("result", chatEnd + finalLen * 0.5)]
        for (name, mark) in marks where i == Int(mark * 30) {
            try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: out.deletingLastPathComponent().appendingPathComponent("screenshots/assistant-\(name).png"))
        }
    }
    input.markAsFinished(); await w.finishWriting(); CGImageDestinationFinalize(dest)
    print("rendered \(total) s")
}
