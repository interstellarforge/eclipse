import Foundation

extension Project {
    public static let fileExtension = "moviemaker"

    public func write(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> Project {
        try JSONDecoder().decode(Project.self, from: Data(contentsOf: url))
    }

    /// Assets whose media file has moved or been deleted (the project stores absolute paths).
    public var missingAssets: [Asset] { assets.filter { !FileManager.default.fileExists(atPath: $0.url.path) } }
}
