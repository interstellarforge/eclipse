import Foundation
import MovieCore

/// State of the "Search online" section of the Audio tab.
@MainActor
final class SoundSearchModel: ObservableObject {
    @Published var query = ""
    @Published var kind = OnlineLibrary.Kind.music
    @Published var allowAttribution = true
    @Published var results: [OnlineSound] = []
    @Published var searching = false
    @Published var message: String?
    @Published var busy = Set<String>()

    func run() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !searching else { return }
        searching = true; message = nil
        let kind = kind, allow = allowAttribution
        Task {
            defer { searching = false }
            do {
                results = try await OnlineLibrary.search(text, kind: kind, allowAttribution: allow)
                if results.isEmpty { message = "Nothing found. Try other words" + (allow ? "." : ", or include CC BY.") }
            } catch { results = []; message = "\(error)" }
        }
    }

    func add(_ sound: OnlineSound, model: AppModel) {
        busy.insert(sound.id)
        let music = kind == .music
        Task {
            await model.addOnline(sound, music: music)
            busy.remove(sound.id)
        }
    }
}

