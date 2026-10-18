import AVFoundation
import Foundation

/// Folders the user opened in the Files tab. Claude may look inside them (names, sizes, lengths) and import files from them,
/// but browse_folder refuses any path outside these folders.
public enum Workspace {
    public static let videoExt: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "mts", "m2ts", "webm", "mpg", "mpeg"]
    public static let audioExt: Set<String> = ["mp3", "m4a", "wav", "aac", "aiff", "aif", "flac", "caf"]
    public static let imageExt: Set<String> = ["jpg", "jpeg", "png", "heic", "gif", "tiff", "tif", "webp", "bmp"]

    public static func kind(_ url: URL) -> String? {
        let e = url.pathExtension.lowercased()
        if videoExt.contains(e) { return "video" }
        if audioExt.contains(e) { return "audio" }
        if imageExt.contains(e) { return "image" }
        return nil
    }

    public static func isInside(_ url: URL, roots: [URL]) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return roots.contains { root in
            let r = root.resolvingSymlinksInPath().standardizedFileURL.path
            return path == r || path.hasPrefix(r.hasSuffix("/") ? r : r + "/")
        }
    }

    /// Sorted children, folders first, hidden files skipped.
    public static func children(of url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        func isDir(_ u: URL) -> Bool { (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        return items.sorted { a, b in
            let da = isDir(a), db = isDir(b)
            return da != db ? da : a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
    }

    public static func isFolder(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }

    /// Every media file below a folder (recursive).
    public static func mediaFiles(in url: URL, limit: Int = 500) -> [URL] {
        var out: [URL] = []
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        for case let u as URL in walker { if kind(u) != nil { out.append(u); if out.count >= limit { break } } }
        return out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func size(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// A text listing for the assistant: names, kinds, sizes, and for media the length and resolution (read from the file's headers only;
    /// nothing is decoded or looked at).
    public static func describe(_ folder: URL, depth: Int, maxLines: Int = 150) async -> String {
        var lines: [String] = [], counts = ["video": 0, "audio": 0, "image": 0, "other": 0]
        var videoSeconds = 0.0, bytes = 0, truncated = false

        func entry(_ url: URL, indent: String) async {
            let name = url.lastPathComponent
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let n = (attrs?[.size] as? Int) ?? 0
            guard let kind = kind(url) else { counts["other", default: 0] += 1; bytes += n; return }
            counts[kind, default: 0] += 1; bytes += n
            var detail = size(n)
            if kind == "video" || kind == "audio" {
                let asset = AVURLAsset(url: url)
                if let d = try? await asset.load(.duration), d.seconds.isFinite { detail = clock(d.seconds) + " · " + detail; if kind == "video" { videoSeconds += d.seconds } }
                if kind == "video", let t = try? await asset.loadTracks(withMediaType: .video).first, let s = try? await t.load(.naturalSize) { detail += " · \(Int(abs(s.width)))x\(Int(abs(s.height)))" }
            }
            if lines.count < maxLines { lines.append("\(indent)[\(kind)] \(name)  \(detail)") } else { truncated = true }
        }

        func walk(_ dir: URL, level: Int) async {
            let indent = String(repeating: "  ", count: level + 1)
            for url in children(of: dir) {
                if isFolder(url) {
                    let media = mediaFiles(in: url, limit: 2_000)
                    if lines.count < maxLines { lines.append("\(indent)[folder] \(url.lastPathComponent)/  (\(media.count) media file\(media.count == 1 ? "" : "s"))") } else { truncated = true }
                    if level + 1 < depth { await walk(url, level: level + 1) }
                } else { await entry(url, indent: indent) }
            }
        }
        await walk(folder, level: 0)
        let head = "Folder \(folder.path)"
        let tail = "Summary (shown levels): \(counts["video"]!) video (\(clock(videoSeconds)) total), \(counts["audio"]!) audio, \(counts["image"]!) images, \(counts["other"]!) other files, \(size(bytes))." + (truncated ? " Listing cut at \(maxLines) lines: browse a subfolder for more." : "")
        return ([head] + lines + [tail]).joined(separator: "\n")
    }
}
