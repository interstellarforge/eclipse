import Foundation
import MovieCore

func runMusicChecks() async throws {
    let tracks = MusicLibrary.tracks
    check(tracks.count >= 40, "40 songs: \(tracks.count)")
    check(Set(tracks.map(\.name)).count == tracks.count, "song names are unique")
    check(MusicLibrary.categories.count >= 10, "categories: \(MusicLibrary.categories)")
    for old in ["Sunny Day", "Lo-fi Chill", "Epic Rise", "Calm Ambient", "Funky Groove", "Tension"] { check(tracks.contains { $0.name == old }, "\(old) is still there") }
    check(tracks.allSatisfy { (50...160).contains($0.bpm) && !$0.mood.isEmpty }, "tempos and moods are filled in")
    for name in ["Sunny Day", "Neon Nights", "Pixel Quest"] {
        let started = Date()
        let url = try MusicLibrary.url(for: name)
        let asset = try await Asset.load(url: url)
        let bpm = tracks.first { $0.name == name }!.bpm
        let expected = 24 * 4 * 60 / bpm * 1000
        check(abs(Double(asset.duration) - expected) < 400, "\(name) length \(asset.duration) vs \(expected)")
        let grid = try await BeatTracker.analyze(url: url)
        check([1.0, 0.5, 2.0, 1.5, 2.0 / 3].contains { abs(grid.bpm - bpm * $0) < 4 }, "\(name) beat found: \(grid.bpm) for \(bpm)")
        let levels = try await Waveform.levels(url: url)
        check(levels.count > 100 && levels.filter { $0 > 0.2 }.count > levels.count / 4, "\(name) has sound throughout")
        print("  \(name) rendered in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
    }
    let rich = try MusicLibrary.url(for: "Heartstrings")
    check(abs(Double(try await Asset.load(url: rich).duration) - 80_000) < 400, "a slow piano song renders too")
}
