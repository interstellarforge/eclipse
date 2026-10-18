import AVFoundation
import CoreImage
import Foundation
import ImageIO
import MovieCore

func check(_ ok: Bool, _ msg: String, line: Int = #line) {
    guard ok else { print("FAIL line \(line): \(msg)"); exit(1) }
}

func makeTestVideo(at url: URL, seconds: Int, bgra: (UInt8, UInt8, UInt8) = (0, 0, 0), flickerFrom: Int? = nil) async throws {
    let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 128])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 128])
    w.add(input); w.startWriting(); w.startSession(atSourceTime: .zero)
    for i in 0..<(seconds * 30) {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 128, 128, kCVPixelFormatType_32BGRA, nil, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let base = CVPixelBufferGetBaseAddress(pb!)!.assumingMemoryBound(to: UInt8.self)
        let invert = flickerFrom.map { i >= $0 && i % 2 == 0 } ?? false   // alternate frames = high motion
        for px in 0..<(CVPixelBufferGetBytesPerRow(pb!) * 128 / 4) {
            base[px * 4] = invert ? 255 - bgra.0 : bgra.0; base[px * 4 + 1] = invert ? 255 - bgra.1 : bgra.1
            base[px * 4 + 2] = invert ? 255 - bgra.2 : bgra.2; base[px * 4 + 3] = 255
        }
        CVPixelBufferUnlockBaseAddress(pb!, [])
        adaptor.append(pb!, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
    }
    input.markAsFinished()
    await w.finishWriting()
    if w.status != .completed { throw w.error ?? EditError.invalid("video write failed") }
}

/// RMS level of the mixed audio (volume ramps applied) in each [start, end) ms window.
func rms(_ built: BuiltComposition, windows: [(Ms, Ms)]) async throws -> [Double] {
    let tracks = try await built.composition.loadTracks(withMediaType: .audio)
    let reader = try AVAssetReader(asset: built.composition)
    let out = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1])
    out.audioMix = built.audioMix
    reader.add(out)
    reader.startReading()
    var samples: [Float] = []
    while let sb = out.copyNextSampleBuffer() {
        guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
        var length = 0; var ptr: UnsafeMutablePointer<CChar>?
        CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr)
        samples += Array(UnsafeBufferPointer(start: UnsafeRawPointer(ptr!).assumingMemoryBound(to: Float.self), count: length / 4))
    }
    return windows.map { w in
        let slice = samples[min(Int(w.0 * 44), samples.count)..<min(Int(w.1 * 44), samples.count)]
        return (slice.reduce(0) { $0 + Double($1 * $1) } / Double(max(slice.count, 1))).squareRoot()
    }
}


/// An MCP server around an editor, with a small client, for tool-level checks.
@MainActor
final class McpHarness {
    let editor: Editor
    private let server: MCPServer
    private let url: URL
    private var nextID = 0

    init(editor: Editor) async throws {
        self.editor = editor
        server = MCPServer(editor: editor, host: MCPHost(importMedia: { url in
            if let existing = editor.project.assets.first(where: { $0.url == url }) { return existing }
            let asset = try await Asset.load(url: url)
            try editor.apply(.addAsset(asset))
            return asset
        }, playhead: { 0 }), token: "harness")
        try await server.start()
        url = URL(string: "http://127.0.0.1:\(server.port)/mcp")!
    }

    func stop() { server.stop() }

    @discardableResult
    func call(_ tool: String, _ args: [String: Any] = [:]) async throws -> (isError: Bool, text: String, content: [[String: Any]]) {
        nextID += 1
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("Bearer harness", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": nextID, "method": "tools/call", "params": ["name": tool, "arguments": args]])
        let (data, _) = try await URLSession.shared.data(for: req)
        let r = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["result"] as? [String: Any]
        let content = r?["content"] as? [[String: Any]] ?? []
        return (r?["isError"] as? Bool ?? true, (content.first?["text"] as? String) ?? "", content)
    }

    /// Value after `key=` in a tool answer such as "asset_id=… duration_ms=…".
    static func field(_ text: String, _ key: String) -> String {
        text.components(separatedBy: CharacterSet.whitespacesAndNewlines).first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) } ?? ""
    }
}

/// A constant tone as a WAV file.
func writeTone(_ seconds: Double, amplitude: Float, freq: Double = 440) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID()).wav")
    try SoundEffects.writeWAV((0..<Int(44_100 * seconds)).map { Float(amplitude) * Float(sin(2 * .pi * freq * Double($0) / 44_100)) }, to: url)
    return url
}
