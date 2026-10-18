import AVFoundation

/// Facts about a media file for the Get Info window.
public struct AssetInfo {
    public var fileName: String
    public var path: String
    public var fileSize: Int64
    public var created: Date?
    public var duration: Ms
    public var video: String?        // "1920x1080 · 30 fps · H.264 · 12.4 Mb/s"
    public var audio: String?        // "AAC · 48 kHz · stereo"
    public var isPhoto: Bool

    public static func load(_ asset: Asset) async -> AssetInfo {
        let url = asset.url
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        var info = AssetInfo(fileName: asset.label, path: url.path, fileSize: (attrs?[.size] as? NSNumber)?.int64Value ?? 0,
                             created: attrs?[.creationDate] as? Date, duration: asset.duration, video: nil, audio: nil, isPhoto: asset.isStill)
        let av = AVURLAsset(url: url)
        if let track = try? await av.loadTracks(withMediaType: .video).first {
            let size = ((try? await track.load(.naturalSize)) ?? .zero).applying((try? await track.load(.preferredTransform)) ?? .identity)
            let fps = (try? await track.load(.nominalFrameRate)) ?? 0
            let rate = (try? await track.load(.estimatedDataRate)) ?? 0
            let codec = ((try? await track.load(.formatDescriptions))?.first).map { fourCC(CMFormatDescriptionGetMediaSubType($0)) }
            var parts = ["\(Int(abs(size.width)))x\(Int(abs(size.height)))"]
            if !asset.isStill { parts.append("\(String(format: "%.0f", fps)) fps") }
            if let codec { parts.append(codecName(codec)) }
            if rate > 0, !asset.isStill { parts.append(String(format: "%.1f Mb/s", Double(rate) / 1_000_000)) }
            info.video = parts.joined(separator: " · ")
        }
        if let track = try? await av.loadTracks(withMediaType: .audio).first {
            var parts: [String] = []
            if let desc = (try? await track.load(.formatDescriptions))?.first {
                parts.append(codecName(fourCC(CMFormatDescriptionGetMediaSubType(desc))))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                    parts.append(String(format: "%.1f kHz", asbd.mSampleRate / 1000))
                    parts.append(asbd.mChannelsPerFrame == 1 ? "mono" : asbd.mChannelsPerFrame == 2 ? "stereo" : "\(asbd.mChannelsPerFrame) channels")
                }
            }
            info.audio = parts.joined(separator: " · ")
        }
        return info
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        String(bytes: [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255), UInt8((code >> 8) & 255), UInt8(code & 255)], encoding: .macOSRoman) ?? "?"
    }

    private static func codecName(_ code: String) -> String {
        ["avc1": "H.264", "hvc1": "HEVC", "hev1": "HEVC", "mp4a": "AAC", "lpcm": "PCM", "apcn": "ProRes 422", "ap4h": "ProRes 4444", "alac": "Apple Lossless"][code] ?? code
    }
}
