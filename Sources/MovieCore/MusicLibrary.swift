import Foundation

/// Royalty-free music beds made by the app itself: no licences, and the tempo is known, so cuts can sit on the beat.
/// Forty songs across moods; each is built from chords, bass, drums and a melody and is rendered the first time you use it.
public enum MusicLibrary {
    public struct Track: Equatable {
        public let name: String
        public let bpm: Double
        public let mood: String
        public let category: String
    }

    private enum Voice { case pluck, piano, bell, square, saw }
    private enum Bass { case saw, sine, sub808 }

    private struct Song {
        var name: String, category: String, mood: String
        var bpm: Double
        var key = 48                 // MIDI note of the tonic (48 = C3)
        var minor = false
        var degrees = [1, 5, 6, 4]   // chord per bar (scale degrees), cycling
        var sevenths = false
        var kick: [Int] = [], snare: [Int] = [], clap: [Int] = [], hat: [Int] = [], openHat: [Int] = []
        var bassSteps: [Int] = [], pluckSteps: [Int] = []
        var voice = Voice.pluck, bassVoice = Bass.saw
        var melody = false           // a tune on top
        var swing = 0.0
        var padLevel = 0.18, pluckLevel = 0.12, drumsFromBar = 4
        var riser = false, drone = false
        var track: Track { Track(name: name, bpm: bpm, mood: mood, category: category) }
    }

    // Step patterns (16 steps per bar) shared by many songs.
    private static let eighths = [0, 2, 4, 6, 8, 10, 12, 14]
    private static let sixteenths = Array(0..<16)
    private static let fourFloor = [0, 4, 8, 12]

    private static let songs: [Song] = [
        // --- Energetic
        Song(name: "Sunny Day", category: "Energetic", mood: "bright, happy, travel and vlog", bpm: 120, degrees: [1, 5, 6, 4], kick: [0, 8], snare: [4, 12], hat: eighths, bassSteps: [0, 3, 6, 8, 11, 14], pluckSteps: eighths, melody: true),
        Song(name: "Turbo Run", category: "Energetic", mood: "fast, driving, sports and action", bpm: 140, key: 55, degrees: [1, 5, 6, 4], kick: fourFloor, snare: [4, 12], clap: [4, 12], hat: eighths, bassSteps: eighths, pluckSteps: sixteenths, voice: .square, pluckLevel: 0.09, drumsFromBar: 2),
        Song(name: "Street Fire", category: "Energetic", mood: "aggressive, urban, hype montage", bpm: 128, key: 50, minor: true, degrees: [1, 1, 6, 7], kick: fourFloor, snare: [4, 12], hat: [2, 6, 10, 14], bassSteps: [0, 3, 6, 10, 12], pluckSteps: [0, 3, 6, 10], voice: .saw, drumsFromBar: 2),
        Song(name: "Victory Lap", category: "Energetic", mood: "triumphant, celebration, wins", bpm: 132, key: 53, degrees: [1, 4, 5, 1], kick: fourFloor, snare: [4, 12], clap: [4, 12], hat: eighths, bassSteps: eighths, pluckSteps: [0, 4, 8, 12], melody: true, padLevel: 0.22, riser: true),
        Song(name: "Hype Machine", category: "Energetic", mood: "intense, drop-heavy, trailers and reels", bpm: 150, key: 52, minor: true, degrees: [1, 6, 7, 1], kick: [0, 3, 6, 10], snare: [4, 12], hat: sixteenths, bassSteps: [0, 3, 6, 10], pluckSteps: [], bassVoice: .sub808, drumsFromBar: 4),
        Song(name: "Pump It", category: "Energetic", mood: "gym, training, motivation", bpm: 138, key: 48, minor: true, degrees: [1, 3, 7, 6], kick: fourFloor, snare: [4, 12], clap: [4, 12], hat: [2, 6, 10, 14], bassSteps: [0, 2, 4, 6, 8, 10, 12, 14], pluckSteps: [0, 6, 10], voice: .saw, drumsFromBar: 2),
        // --- Cinematic
        Song(name: "Epic Rise", category: "Cinematic", mood: "building, cinematic, big reveals", bpm: 100, key: 57, minor: true, degrees: [1, 6, 3, 7], kick: [0, 6, 8, 14], snare: [4, 12], hat: [0, 4, 8, 12], bassSteps: [0, 4, 8, 12], pluckSteps: [0, 3, 6, 9, 12], padLevel: 0.26, pluckLevel: 0.1, drumsFromBar: 8, riser: true),
        Song(name: "Kingdom", category: "Cinematic", mood: "heroic, orchestral feel, fantasy", bpm: 90, key: 50, minor: true, degrees: [1, 7, 6, 7], kick: [0, 8], snare: [8], hat: [], bassSteps: [0], pluckSteps: [0, 8], voice: .bell, padLevel: 0.3, pluckLevel: 0.1, drumsFromBar: 8, riser: true),
        Song(name: "Silent Valley", category: "Cinematic", mood: "vast, quiet, nature documentary", bpm: 70, degrees: [1, 5, 6, 4], bassSteps: [0], pluckSteps: [0, 4, 8, 12], voice: .piano, melody: true, padLevel: 0.28, pluckLevel: 0.09, drumsFromBar: 99),
        Song(name: "Last Light", category: "Cinematic", mood: "bittersweet, sunset, farewell", bpm: 80, key: 52, minor: true, degrees: [1, 6, 4, 5], kick: [0, 10], snare: [8], hat: [], bassSteps: [0, 8], pluckSteps: [0, 6, 10], voice: .piano, melody: true, padLevel: 0.24, drumsFromBar: 8),
        Song(name: "Titan Pulse", category: "Cinematic", mood: "heavy, tense, action trailer", bpm: 110, key: 53, minor: true, degrees: [1, 1, 6, 7], kick: [0, 6, 8, 14], snare: [4, 12], hat: [0, 4, 8, 12], bassSteps: eighths, pluckSteps: [], bassVoice: .sub808, padLevel: 0.26, drumsFromBar: 4, riser: true, drone: true),
        Song(name: "Aurora", category: "Cinematic", mood: "magical, glowing, wonder", bpm: 64, key: 50, degrees: [1, 3, 4, 5], bassSteps: [0], pluckSteps: [0, 8], voice: .bell, melody: true, padLevel: 0.3, pluckLevel: 0.09, drumsFromBar: 99),
        // --- Emotional
        Song(name: "Heartstrings", category: "Emotional", mood: "tender piano, love, weddings", bpm: 72, degrees: [1, 5, 6, 4], bassSteps: [0], pluckSteps: [0, 4, 8, 12], voice: .piano, melody: true, padLevel: 0.2, drumsFromBar: 99),
        Song(name: "Tender Moment", category: "Emotional", mood: "soft, family, gratitude", bpm: 66, key: 53, degrees: [1, 4, 1, 5], bassSteps: [0], pluckSteps: [0, 6, 10], voice: .piano, melody: true, padLevel: 0.22, drumsFromBar: 99),
        Song(name: "Remember Me", category: "Emotional", mood: "nostalgic, memories, tribute", bpm: 76, key: 57, minor: true, degrees: [1, 6, 3, 7], kick: [0, 10], snare: [8], bassSteps: [0, 8], pluckSteps: [0, 4, 8, 12], voice: .piano, melody: true, drumsFromBar: 8),
        Song(name: "Letting Go", category: "Emotional", mood: "sad, reflective, slow", bpm: 68, key: 50, minor: true, degrees: [1, 4, 6, 5], bassSteps: [0], pluckSteps: [0, 8], voice: .piano, melody: true, padLevel: 0.26, drumsFromBar: 99),
        Song(name: "First Light", category: "Emotional", mood: "hopeful, new beginnings, uplifting", bpm: 84, key: 55, degrees: [1, 5, 6, 4], kick: [0, 8], snare: [4, 12], hat: [0, 4, 8, 12], bassSteps: [0, 8], pluckSteps: [0, 4, 8, 12], voice: .piano, melody: true, padLevel: 0.22, drumsFromBar: 8, riser: true),
        // --- Chill
        Song(name: "Lo-fi Chill", category: "Chill", mood: "relaxed, warm, everyday moments", bpm: 78, key: 50, degrees: [1, 5, 4, 6], sevenths: true, kick: [0, 7, 10], snare: [4, 12], hat: eighths, bassSteps: [0, 6, 10], pluckSteps: [3, 7, 11, 14], swing: 0.3, padLevel: 0.2, pluckLevel: 0.1, drumsFromBar: 2),
        Song(name: "Sunday Morning", category: "Chill", mood: "easy, coffee, slow start", bpm: 82, key: 53, degrees: [1, 6, 4, 5], sevenths: true, kick: [0, 7, 10], snare: [4, 12], hat: eighths, bassSteps: [0, 6, 10], pluckSteps: [0, 6, 10, 14], voice: .piano, melody: true, swing: 0.25, drumsFromBar: 2),
        Song(name: "Late Night Coffee", category: "Chill", mood: "cosy, city lights, studying", bpm: 74, key: 57, minor: true, degrees: [1, 4, 7, 3], sevenths: true, kick: [0, 7], snare: [4, 12], hat: [2, 6, 10, 14], bassSteps: [0, 10], pluckSteps: [3, 7, 11], voice: .piano, swing: 0.3, drumsFromBar: 2),
        Song(name: "Cloud Walk", category: "Chill", mood: "floating, dreamy, easy", bpm: 70, key: 50, degrees: [1, 3, 4, 5], sevenths: true, bassSteps: [0], pluckSteps: [0, 8], voice: .bell, melody: true, padLevel: 0.28, drumsFromBar: 99),
        Song(name: "Sea Breeze", category: "Chill", mood: "beach, summer, relaxed groove", bpm: 88, key: 48, degrees: [1, 5, 6, 4], kick: [0, 8], snare: [12], hat: [2, 6, 10, 14], bassSteps: [0, 6, 8], pluckSteps: [0, 3, 6, 10], melody: true, swing: 0.1, drumsFromBar: 4),
        // --- Travel & upbeat
        Song(name: "Coastal Drive", category: "Travel", mood: "open road, sunshine, freedom", bpm: 118, key: 57, degrees: [1, 5, 6, 4], kick: fourFloor, snare: [4, 12], hat: eighths, bassSteps: eighths, pluckSteps: [0, 3, 6, 8, 11, 14], melody: true, drumsFromBar: 4),
        Song(name: "Road Trip", category: "Travel", mood: "singalong, friends, car windows down", bpm: 112, key: 50, degrees: [1, 4, 5, 4], kick: [0, 8], snare: [4, 12], clap: [4, 12], hat: eighths, bassSteps: [0, 4, 8, 12], pluckSteps: [0, 4, 8, 12], melody: true, drumsFromBar: 2),
        Song(name: "Wanderlust", category: "Travel", mood: "adventure, discovery, mountains", bpm: 104, key: 55, degrees: [1, 6, 4, 5], kick: [0, 8], snare: [4, 12], hat: [0, 4, 8, 12], bassSteps: [0, 8], pluckSteps: eighths, melody: true, padLevel: 0.22, drumsFromBar: 4),
        Song(name: "Market Day", category: "Travel", mood: "lively, street food, bustling", bpm: 108, key: 48, degrees: [1, 4, 1, 5], kick: [0, 8], snare: [4, 12], hat: eighths, bassSteps: [0, 3, 8, 11], pluckSteps: [2, 6, 10, 14], melody: true, swing: 0.15, drumsFromBar: 2),
        Song(name: "Island Time", category: "Travel", mood: "tropical, laid back, holiday", bpm: 96, key: 52, degrees: [1, 5, 6, 4], kick: [0, 7, 10], snare: [12], clap: [4], hat: [2, 6, 10, 14], bassSteps: [0, 6, 10], pluckSteps: [0, 3, 6, 10, 14], melody: true, swing: 0.12, drumsFromBar: 2),
        // --- Dark
        Song(name: "Tension", category: "Dark", mood: "suspense, mystery, something is about to happen", bpm: 90, key: 57, minor: true, degrees: [1, 1, 7, 1], kick: [0, 10], hat: [4, 12], bassSteps: [0, 4, 8, 12], pluckSteps: [0, 6, 11], padLevel: 0.22, pluckLevel: 0.08, drumsFromBar: 4, drone: true),
        Song(name: "Shadow Play", category: "Dark", mood: "brooding, noir, slow menace", bpm: 84, key: 50, minor: true, degrees: [1, 4, 5, 1], kick: [0, 10], snare: [8], hat: [4, 12], bassSteps: [0, 10], pluckSteps: [0, 8], voice: .bell, bassVoice: .sub808, padLevel: 0.24, drumsFromBar: 4, drone: true),
        Song(name: "Midnight Chase", category: "Dark", mood: "pursuit, thriller, night driving", bpm: 124, key: 52, minor: true, degrees: [1, 1, 6, 7], kick: fourFloor, snare: [4, 12], hat: [2, 6, 10, 14], bassSteps: sixteenths.filter { $0 % 2 == 0 }, pluckSteps: [0, 3, 6, 10], voice: .saw, drumsFromBar: 2),
        Song(name: "Cold Case", category: "Dark", mood: "investigation, sparse, uneasy", bpm: 78, key: 55, minor: true, degrees: [1, 6, 1, 7], kick: [0], hat: [4, 12], bassSteps: [0], pluckSteps: [0, 10], voice: .piano, padLevel: 0.26, drumsFromBar: 8, drone: true),
        // --- Retro & electronic
        Song(name: "Neon Nights", category: "Retro", mood: "80s synthwave, night city, neon", bpm: 108, key: 57, minor: true, degrees: [1, 6, 3, 7], kick: fourFloor, snare: [4, 12], clap: [4, 12], hat: eighths, bassSteps: eighths, pluckSteps: sixteenths, voice: .saw, padLevel: 0.2, pluckLevel: 0.1, drumsFromBar: 2),
        Song(name: "Pixel Quest", category: "Retro", mood: "8-bit game, playful chiptune", bpm: 150, key: 48, degrees: [1, 5, 6, 4], kick: [0, 8], snare: [4, 12], hat: eighths, bassSteps: eighths, pluckSteps: sixteenths, voice: .square, melody: true, padLevel: 0.05, pluckLevel: 0.12, drumsFromBar: 2),
        Song(name: "Disco Fever", category: "Retro", mood: "70s disco, dancing, party", bpm: 118, key: 55, degrees: [1, 4, 5, 4], sevenths: true, kick: fourFloor, snare: [4, 12], clap: [4, 12], hat: [2, 6, 10, 14], openHat: [2, 6, 10, 14], bassSteps: [2, 3, 6, 7, 10, 11, 14, 15], pluckSteps: [0, 3, 6, 10], voice: .pluck, drumsFromBar: 2),
        Song(name: "Deep House", category: "Electronic", mood: "club, smooth, driving groove", bpm: 122, key: 50, minor: true, degrees: [1, 4, 6, 7], sevenths: true, kick: fourFloor, clap: [4, 12], hat: [2, 6, 10, 14], openHat: [2, 6, 10, 14], bassSteps: [2, 6, 10, 14], pluckSteps: [0, 3, 8, 11], voice: .piano, drumsFromBar: 2),
        Song(name: "Cyber City", category: "Electronic", mood: "futuristic, tech, sci-fi", bpm: 128, key: 53, minor: true, degrees: [1, 3, 6, 7], kick: fourFloor, snare: [12], hat: sixteenths, bassSteps: [0, 3, 6, 10, 12], pluckSteps: [0, 2, 3, 6, 8, 10], voice: .square, bassVoice: .sub808, drumsFromBar: 2),
        // --- Hip-hop
        Song(name: "Boom Bap Classic", category: "Hip-hop", mood: "dusty drums, street, 90s", bpm: 90, key: 57, minor: true, degrees: [1, 4, 1, 5], sevenths: true, kick: [0, 7, 10], snare: [4, 12], hat: eighths, bassSteps: [0, 7, 10], pluckSteps: [0, 6, 10], voice: .piano, swing: 0.2, drumsFromBar: 2),
        Song(name: "Trap Nation", category: "Hip-hop", mood: "heavy 808s, rolling hats, modern", bpm: 140, key: 50, minor: true, degrees: [1, 6, 4, 5], kick: [0, 6, 10], snare: [8], clap: [8], hat: sixteenths, bassSteps: [0, 6, 10], pluckSteps: [0, 3, 6, 10], voice: .bell, bassVoice: .sub808, drumsFromBar: 2),
        Song(name: "Smooth Flow", category: "Hip-hop", mood: "laid-back, confident, vlog", bpm: 85, key: 53, degrees: [1, 6, 4, 5], sevenths: true, kick: [0, 10], snare: [4, 12], hat: eighths, bassSteps: [0, 10], pluckSteps: [3, 7, 11], voice: .piano, bassVoice: .sub808, swing: 0.2, drumsFromBar: 2),
        // --- Corporate & documentary
        Song(name: "Bright Ideas", category: "Corporate", mood: "clean, optimistic, tech and startup", bpm: 110, key: 55, degrees: [1, 5, 6, 4], kick: [0, 8], snare: [4, 12], hat: eighths, bassSteps: [0, 8], pluckSteps: eighths, melody: true, drumsFromBar: 4),
        Song(name: "New Horizons", category: "Corporate", mood: "inspiring, progress, presentations", bpm: 100, key: 50, degrees: [1, 4, 6, 5], kick: [0, 8], snare: [12], hat: [0, 4, 8, 12], bassSteps: [0], pluckSteps: [0, 4, 8, 12], voice: .piano, melody: true, padLevel: 0.22, drumsFromBar: 8),
        Song(name: "Clean Slate", category: "Corporate", mood: "light, neutral, explainer videos", bpm: 96, key: 48, degrees: [1, 6, 4, 5], kick: [0, 8], snare: [4, 12], hat: [2, 6, 10, 14], bassSteps: [0, 8], pluckSteps: [0, 3, 6, 10, 14], melody: true, drumsFromBar: 4),
        // --- Fun
        Song(name: "Funky Groove", category: "Fun", mood: "playful, street, cooking, party", bpm: 108, key: 52, minor: true, degrees: [1, 1, 7, 7], sevenths: true, kick: [0, 3, 8, 11], snare: [4, 12, 15], hat: sixteenths, bassSteps: [0, 2, 3, 6, 8, 10, 11, 14], pluckSteps: [2, 6, 10, 14], swing: 0.15, padLevel: 0.1, pluckLevel: 0.16, drumsFromBar: 2),
        Song(name: "Playground", category: "Fun", mood: "kids, cartoons, silly and bouncy", bpm: 120, key: 55, degrees: [1, 5, 1, 4], kick: [0, 8], snare: [4, 12], clap: [4, 12], hat: eighths, bassSteps: [0, 4, 8, 12], pluckSteps: eighths, voice: .bell, melody: true, drumsFromBar: 2),
        Song(name: "Jazz Cafe", category: "Fun", mood: "swing, sophisticated, brunch", bpm: 96, key: 53, degrees: [2, 5, 1, 6], sevenths: true, kick: [0], snare: [4, 12], hat: [0, 3, 4, 7, 8, 11, 12, 15], bassSteps: [0, 4, 8, 12], pluckSteps: [2, 6, 10], voice: .piano, melody: true, swing: 0.33, drumsFromBar: 2),
        Song(name: "Calm Ambient", category: "Ambient", mood: "peaceful, nature, slow scenic shots", bpm: 60, degrees: [1, 4, 6, 5], sevenths: true, bassSteps: [0], pluckSteps: [0, 8], voice: .bell, padLevel: 0.3, pluckLevel: 0.09, drumsFromBar: 99),
        Song(name: "Deep Space", category: "Ambient", mood: "weightless, mysterious, sci-fi calm", bpm: 56, key: 50, minor: true, degrees: [1, 6, 4, 5], sevenths: true, bassSteps: [0], pluckSteps: [0], voice: .bell, padLevel: 0.32, pluckLevel: 0.08, drumsFromBar: 99, drone: true),
    ]

    public static let tracks: [Track] = songs.map(\.track)
    public static var categories: [String] { Array(Set(tracks.map(\.category))).sorted() }
    private static let sampleRate = 44_100
    private static let bars = 24

    public static func url(for name: String) throws -> URL {
        guard let song = songs.first(where: { $0.name == name }) else { throw EditError.notFound }
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MovieMaker/Music/v2", isDirectory: true)   // v2: songs were re-composed; older cached renders stay unused
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).wav")
        if !FileManager.default.fileExists(atPath: url.path) { try SoundEffects.writeWAV(render(song), to: url) }
        return url
    }

    // MARK: Harmony

    private static let majorScale = [0, 2, 4, 5, 7, 9, 11], minorScale = [0, 2, 3, 5, 7, 8, 10]

    private static func scaleNote(_ s: Song, _ degree: Int) -> Int {
        let scale = s.minor ? minorScale : majorScale
        let index = degree - 1
        let octave = Int((Double(index) / 7).rounded(.down))
        return s.key + scale[((index % 7) + 7) % 7] + 12 * octave
    }

    private static func chord(_ s: Song, _ degree: Int) -> [Int] {
        ([degree, degree + 2, degree + 4] + (s.sevenths ? [degree + 6] : [])).map { scaleNote(s, $0) }
    }

    // MARK: Synthesis

    private static func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    private static func render(_ s: Song) -> [Float] {
        let sr = Double(sampleRate)
        let beat = 60 / s.bpm, step = beat / 4, barLength = beat * 4
        var buffer = [Double](repeating: 0, count: Int((Double(bars) * barLength + 3) * sr))
        var seed: UInt32 = 987_654 &+ UInt32(truncatingIfNeeded: s.name.hashValueStable)
        func noise() -> Double { seed = seed &* 1_664_525 &+ 1_013_904_223; return Double(seed >> 8) / Double(1 << 24) * 2 - 1 }
        func rnd(_ a: Int, _ b: Int) -> Double {
            var x = UInt64(truncatingIfNeeded: a &* 73_856_093 &+ b &* 19_349_663 &+ s.name.hashValueStable)
            x ^= x << 13; x ^= x >> 7; x ^= x << 17
            return Double((x &* 0x2545F4914F6CDD1D) >> 11) / Double(1 << 53)
        }

        func add(_ start: Double, _ count: Int, _ body: (Double) -> Double) {
            let first = Int(start * sr)
            guard first >= 0, first + count < buffer.count else { return }
            for i in 0..<count { buffer[first + i] += body(Double(i) / sr) }
        }
        func tone(at start: Double, length: Double, freq: Double, amp: Double, attack: Double, release: Double, saw: Double = 0) {
            add(start, Int((length + release) * sr)) { t in
                let env = min(1, t / max(attack, 0.002)) * (t < length ? 1 : max(0, 1 - (t - length) / release))
                let p = freq * t
                return (sin(2 * .pi * p) + saw * (sin(4 * .pi * p) * 0.5 + sin(6 * .pi * p) * 0.33)) * env * amp
            }
        }
        func lead(at start: Double, freq: Double, amp: Double, length: Double) {
            switch s.voice {
            case .pluck: add(start, Int(0.6 * sr)) { t in (sin(2 * .pi * freq * t) + 0.4 * sin(4 * .pi * freq * t)) * exp(-7 * t) * amp }
            case .piano: add(start, Int(1.4 * sr)) { t in
                let env = min(1, t / 0.004)
                return (sin(2 * .pi * freq * t) * exp(-2.2 * t) + 0.5 * sin(4 * .pi * freq * t) * exp(-3.5 * t) + 0.25 * sin(6 * .pi * freq * t) * exp(-5 * t) + 0.1 * sin(8 * .pi * freq * t) * exp(-7 * t)) * env * amp * 1.4
            }
            case .bell: add(start, Int(2.6 * sr)) { t in
                (sin(2 * .pi * freq * t) * exp(-1.6 * t) + 0.5 * sin(2 * .pi * freq * 2.76 * t) * exp(-2.4 * t) + 0.3 * sin(2 * .pi * freq * 5.4 * t) * exp(-3.4 * t)) * amp * 1.2
            }
            case .square: add(start, Int(max(0.12, length) * sr)) { t in
                let p = freq * t, env = exp(-6 * t) * 0.6 + 0.4 * (t < length ? 1 : 0)
                return (sin(2 * .pi * p) + sin(6 * .pi * p) / 3 + sin(10 * .pi * p) / 5) * env * amp * 0.8
            }
            case .saw: add(start, Int(max(0.2, length) * sr)) { t in
                let p = freq * t, env = min(1, t / 0.01) * exp(-4 * t)
                return (sin(2 * .pi * p) + 0.5 * sin(4 * .pi * p) + 0.33 * sin(6 * .pi * p) + 0.25 * sin(8 * .pi * p)) * env * amp * 0.55
            }
            }
        }
        func bass(at start: Double, midi: Int, length: Double, amp: Double) {
            switch s.bassVoice {
            case .saw: tone(at: start, length: length, freq: hz(midi), amp: amp, attack: 0.01, release: 0.06, saw: 0.4)
            case .sine: tone(at: start, length: length, freq: hz(midi), amp: amp, attack: 0.01, release: 0.08)
            case .sub808: add(start, Int(0.9 * sr)) { t in sin(2 * .pi * (hz(midi) * (1 + 1.2 * exp(-18 * t)) * t)) * exp(-3 * t) * amp * 1.2 }
            }
        }
        func kick(at start: Double, amp: Double) { add(start, Int(0.35 * sr)) { t in sin(2 * .pi * (45 * t + 105 * (1 - exp(-28 * t)) / 28)) * exp(-9 * t) * amp } }
        func snare(at start: Double, amp: Double) { add(start, Int(0.25 * sr)) { t in (noise() * 0.7 + sin(2 * .pi * 190 * t) * 0.4) * exp(-22 * t) * amp } }
        func clap(at start: Double, amp: Double) { add(start, Int(0.2 * sr)) { t in noise() * (exp(-60 * t) + 0.8 * exp(-60 * max(0, t - 0.012)) * (t > 0.012 ? 1 : 0) + 0.7 * exp(-30 * max(0, t - 0.024)) * (t > 0.024 ? 1 : 0)) * amp * 0.45 } }
        func hat(at start: Double, amp: Double, open: Bool = false) {
            var previous = 0.0
            add(start, Int((open ? 0.3 : 0.08) * sr)) { t in let n = noise(); defer { previous = n }; return (n - previous) * exp((open ? -14 : -70) * t) * amp }
        }

        let pentatonic = s.minor ? [0, 3, 5, 7, 10] : [0, 2, 4, 7, 9]
        func penta(_ index: Int) -> Int { s.key + 24 + pentatonic[((index % 5) + 5) % 5] + 12 * Int((Double(index) / 5).rounded(.down)) }
        var tune = 5   // position in the pentatonic ladder, a random walk

        for bar in 0..<bars {
            let t0 = Double(bar) * barLength
            let degree = s.degrees[bar % s.degrees.count]
            let notes = chord(s, degree)
            let intro = Double(min(bar + 1, 2)) / 2
            for note in notes { tone(at: t0, length: barLength, freq: hz(note + 12), amp: s.padLevel * intro / Double(notes.count) * 2, attack: 0.6, release: 0.5, saw: 0.35) }
            let root = scaleNote(s, degree) - 12
            if s.drone { tone(at: t0, length: barLength, freq: hz(root - 12), amp: 0.22, attack: 1, release: 0.8, saw: 0.5) }
            for st in s.pluckSteps where bar >= 1 {
                lead(at: t0 + Double(st) * step + (st % 2 == 1 ? s.swing * step : 0), freq: hz(notes[st % notes.count] + (st > 7 ? 24 : 12)), amp: s.pluckLevel, length: step * 1.5)
            }
            if s.melody && bar >= 3 && bar % 4 != 3 {   // a short tune, resting every fourth bar
                let rhythm = [[0, 4, 6, 8, 12], [0, 3, 6, 8, 11, 14], [0, 2, 4, 8, 10, 12], [0, 6, 8, 14]][Int(rnd(bar / 4, 11) * 4) % 4]
                for st in rhythm {
                    let move = [-2, -1, -1, 0, 1, 1, 2][Int(rnd(bar, st + 100) * 7) % 7]
                    tune = max(0, min(9, tune + move))
                    lead(at: t0 + Double(st) * step, freq: hz(penta(tune)), amp: s.pluckLevel * 1.5, length: step * 2)
                }
            }
            guard bar >= s.drumsFromBar else { continue }
            let lift = s.riser ? min(1, 0.6 + Double(bar - s.drumsFromBar) / 16) : 1
            for st in s.bassSteps { bass(at: t0 + Double(st) * step, midi: root, length: step * 1.6, amp: 0.3 * lift) }
            for st in s.kick { kick(at: t0 + Double(st) * step, amp: 0.8 * lift) }
            for st in s.snare { snare(at: t0 + Double(st) * step, amp: 0.45 * lift) }
            for st in s.clap { clap(at: t0 + Double(st) * step, amp: 0.5 * lift) }
            for st in s.hat { hat(at: t0 + Double(st) * step + (st % 2 == 1 ? s.swing * step : 0), amp: 0.12 * lift) }
            for st in s.openHat { hat(at: t0 + Double(st) * step, amp: 0.1 * lift, open: true) }
        }
        if s.riser {
            let start = Int((Double(bars - 2) * barLength) * sr), count = Int(barLength * sr)
            var lp = 0.0
            for i in 0..<count where start + i < buffer.count {
                let p = Double(i) / Double(count); lp += (0.02 + 0.5 * p) * (noise() - lp)
                buffer[start + i] += lp * p * p * 0.5
            }
        }
        let total = Double(bars) * barLength
        let peak = max(0.001, buffer.prefix(Int(total * sr)).map(abs).max() ?? 1)
        return (0..<Int(total * sr)).map { i in
            let fade = min(1, (total - Double(i) / sr) / 2.5)
            return Float(buffer[i] / peak * 0.8 * fade)
        }
    }
}

private extension String {
    /// A number that is the same on every run (Swift's own hashing is randomised per launch).
    var hashValueStable: Int { unicodeScalars.reduce(5_381) { ($0 &* 33) &+ Int($1.value) } }
}
