import Foundation

public struct OnlineSound: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var creator: String
    public var license: String          // cc0, pdm, by
    public var licenseVersion: String?
    public var licenseURL: String?
    public var durationMs: Ms
    public var fileURL: String
    public var pageURL: String?
    public var provider: String
    public var fileType: String?        // jpg, png ... for pictures

    /// One line to credit the author, e.g. in the video description.
    public var credit: String {
        license == "cc0" || license == "pdm"
            ? "\"\(title)\" by \(creator) (\(license == "cc0" ? "CC0" : "public domain"))\(pageURL.map { ", \($0)" } ?? "")"
            : "\"\(title)\" by \(creator), CC BY \(licenseVersion ?? "")\(licenseURL.map { " (\($0))" } ?? "")\(pageURL.map { ", \($0)" } ?? "")"
    }
    public var needsCredit: Bool { license != "cc0" && license != "pdm" }
    public var isImage: Bool { ["jpg", "jpeg", "png"].contains((fileType ?? "").lowercased()) }
}

/// Free sounds from Openverse (openverse.org): CC0 / public domain, optionally CC BY (credit required, tracked here).
/// Nothing is downloaded until you import a result.
public enum OnlineLibrary {
    public enum Kind: String { case music, effects, images }

    public static func parse(_ data: Data) -> [OnlineSound] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let id = r["id"] as? String, let url = r["url"] as? String, url.hasPrefix("https://"),
                  let license = r["license"] as? String, ["cc0", "pdm", "by"].contains(license) else { return nil }
            return OnlineSound(id: id, title: r["title"] as? String ?? "Untitled", creator: r["creator"] as? String ?? "unknown",
                               license: license, licenseVersion: r["license_version"] as? String, licenseURL: r["license_url"] as? String,
                               durationMs: Ms((r["duration"] as? NSNumber)?.int64Value ?? 0), fileURL: url,
                               pageURL: r["foreign_landing_url"] as? String, provider: r["provider"] as? String ?? "",
                               fileType: (r["filetype"] as? String) ?? URL(string: url)?.pathExtension)
        }
    }

    public static func searchURL(_ query: String, kind: Kind, allowAttribution: Bool) -> URL? {
        var c = URLComponents(string: kind == .images ? "https://api.openverse.org/v1/images/" : "https://api.openverse.org/v1/audio/")
        var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "page_size", value: "20"),
                     URLQueryItem(name: "license", value: allowAttribution ? "cc0,pdm,by" : "cc0,pdm")]
        if kind == .music { items.append(URLQueryItem(name: "category", value: "music")) }
        c?.queryItems = items
        return c?.url
    }

    public static func search(_ query: String, kind: Kind, allowAttribution: Bool) async throws -> [OnlineSound] {
        guard let url = searchURL(query, kind: kind, allowAttribution: allowAttribution) else { throw EditError.invalid("bad search") }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("MovieMaker/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw EditError.invalid("The sound search service is not reachable right now.") }
        return parse(data).filter {
            switch kind {
            case .music: return $0.durationMs >= 20_000
            case .effects: return $0.durationMs <= 60_000
            case .images: return $0.isImage
            }
        }
    }

    private static var folder: URL? {
        let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MovieMaker/Library", isDirectory: true)
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    /// Downloads the file (max 60 MB, https only), records its credit and returns the local file.
    public static func download(_ sound: OnlineSound, into directory: URL? = nil) async throws -> URL {
        guard let dir = directory ?? folder, let source = URL(string: sound.fileURL), source.scheme == "https" else {
            throw EditError.invalid("cannot download this sound")
        }
        let target = dir.appendingPathComponent(OnlineLibrary.localFileName(for: sound))
        if !FileManager.default.fileExists(atPath: target.path) {
            var request = URLRequest(url: source, timeoutInterval: 60)
            request.setValue("MovieMaker/0.1", forHTTPHeaderField: "User-Agent")
            let (temp, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw EditError.invalid("download failed") }
            let size = (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int) ?? 0
            guard size > 0, size <= 60_000_000 else { try? FileManager.default.removeItem(at: temp); throw EditError.invalid("file is empty or too large") }
            try FileManager.default.moveItem(at: temp, to: target)
        }
        try record(sound, in: dir)
        return target
    }

    /// Name of the downloaded file; also how credits are matched to the clips that use them.
    public static func localFileName(for sound: OnlineSound) -> String {
        "\(sound.provider)-\(sound.id.filter { $0.isLetter || $0.isNumber || $0 == "-" }).\(sound.isImage ? (sound.fileType ?? "jpg").lowercased() : "mp3")"
    }

    // MARK: Credits

    private static func creditsFile(_ dir: URL) -> URL { dir.appendingPathComponent("credits.json") }

    public static func record(_ sound: OnlineSound, in dir: URL) throws {
        var all = credits(in: dir)
        guard !all.contains(where: { $0.id == sound.id }) else { return }
        all.append(sound)
        try JSONEncoder().encode(all).write(to: creditsFile(dir), options: .atomic)
    }

    public static func credits(in directory: URL? = nil) -> [OnlineSound] {
        guard let dir = directory ?? folder, let data = try? Data(contentsOf: creditsFile(dir)) else { return [] }
        return (try? JSONDecoder().decode([OnlineSound].self, from: data)) ?? []
    }

    /// Credits for sounds that need them, ready to paste in a video description.
    public static func creditsText(for sounds: [OnlineSound]) -> String {
        let lines = sounds.filter(\.needsCredit).map { "Music/sound: " + $0.credit }
        return lines.isEmpty ? "No credits needed." : lines.joined(separator: "\n")
    }
}
