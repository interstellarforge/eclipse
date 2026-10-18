import AVFoundation
import CoreGraphics
import CryptoKit
import ImageIO

/// Photos are turned into a 60 second one-frame-per-second H.264 video once (cached), so they work like any clip:
/// trim, effects, slow zoom, transitions, layers. The original photo is never touched.
enum StillVideo {
    static let seconds = 60

    static func make(from image: URL) throws -> URL {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MovieMaker/Stills", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let attributes = try FileManager.default.attributesOfItem(atPath: image.path)
        let key = "\(image.path)|\(attributes[.size] ?? 0)|\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        let name = SHA256.hash(data: Data(key.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
        let output = dir.appendingPathComponent("\(name).mp4")
        if FileManager.default.fileExists(atPath: output.path) { return output }

        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
              let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                                                            kCGImageSourceThumbnailMaxPixelSize: 3_840] as CFDictionary)
        else { throw EditError.invalid("Can't read this picture.") }
        let width = picture.width & ~1, height = picture.height & ~1
        guard width >= 16, height >= 16 else { throw EditError.invalid("This picture is too small.") }

        let temp = dir.appendingPathComponent("\(name)-writing.mp4")
        try? FileManager.default.removeItem(at: temp)
        let writer = try AVAssetWriter(outputURL: temp, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? EditError.invalid("Can't create the picture clip.") }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let pixels = buffer else { throw EditError.invalid("Out of memory.") }
        CVPixelBufferLockBaseAddress(pixels, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8,
                               bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        for second in 0..<seconds {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(second), timescale: 1))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: Int64(seconds), timescale: 1))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? EditError.invalid("Can't create the picture clip.") }
        try FileManager.default.moveItem(at: temp, to: output)
        return output
    }
}
