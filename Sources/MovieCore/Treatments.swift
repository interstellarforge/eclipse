import Foundation

/// A worked-out creative direction: structure, joins, look, one signature touch. Gives the assistant different, coherent starting points
/// so films stop looking alike. Every name is validated against the real catalogs by NewChecks.
public struct Treatment {
    public let name: String
    public let moods: [String]
    public let idea: String
    public let structure: String
    public let transitions: [TransitionType]   // at most two, and mostly hard cuts anyway
    public let look: String
    public let effects: [(EffectType, Double)] // the signature touch: one or two, never more
    public let overlay: GeneratorKind?
    public let title: TitlePreset
    public let speed: String
    public let restraint: String
}

public enum Treatments {
    public static let all: [Treatment] = [
        Treatment(name: "Cold open", moods: ["epic", "cinematic", "drama", "trailer"],
                  idea: "Start with the single best shot in silence, then smash to title and music.",
                  structure: "Hook shot (1-2 s, no music) -> black beat -> title -> escalating montage with cuts shortening -> one held final shot.",
                  transitions: [.fadeBlack, .flashCut], look: "Teal & orange", effects: [(.vignette, 0.4)], overlay: nil, title: .movie,
                  speed: "One slow-motion hero moment at the peak.", restraint: "Flash only on the biggest impact; no other effects."),
        Treatment(name: "Rhythm montage", moods: ["energetic", "sport", "party", "hype"],
                  idea: "Every cut lands on the beat; cut length follows the music, tight at the drop.",
                  structure: "4-beat intro -> 2-beat cuts -> 1-beat cuts at the drop -> half-beat burst -> last hit on the downbeat.",
                  transitions: [.whipLeft, .zoomBlur], look: "Vivid", effects: [(.pulse, 0.4)], overlay: nil, title: .impact,
                  speed: "A speed ramp into the drop, normal after.", restraint: "Hard cuts for most; a whip only where the camera really moves."),
        Treatment(name: "Slow burn", moods: ["emotional", "calm", "memory", "tribute", "wedding"],
                  idea: "Few long shots, slow pushes, breathing room. Let faces and light do the work.",
                  structure: "Quiet establishing shot -> 4-6 s shots with gentle pushes -> one longer emotional shot -> fade out.",
                  transitions: [.crossfade, .fadeBlack], look: "Golden hour", effects: [(.kenBurnsIn, 0.45)], overlay: .sunbeams, title: .handwritten,
                  speed: "Slow motion at 0.7x only on a gesture or glance.", restraint: "Crossfades only between different places or times; the rest are hard cuts."),
        Treatment(name: "Match-cut chain", moods: ["creative", "travel", "artistic", "story"],
                  idea: "Each shot hands over to the next through a shared shape, colour or motion.",
                  structure: "Order clips by visual rhyme (find_match_cuts) rather than chronology; cut on the matching movement.",
                  transitions: [], look: "Clean bright", effects: [], overlay: nil, title: .minimal,
                  speed: "None, keep the motion natural.", restraint: "No transitions at all: the match is the transition."),
        Treatment(name: "Retro tape", moods: ["fun", "nostalgic", "friends", "holiday", "90s"],
                  idea: "Home-video memory: grain, soft colour, date stamp, imperfect.",
                  structure: "Chronological, loose, 2-4 s shots, a date stamp on first shot of each day, a handwritten ending.",
                  transitions: [.crossfade], look: "Vintage film", effects: [(.vhs, 0.5)], overlay: .dust, title: .dateStamp,
                  speed: "None.", restraint: "VHS on the whole film at one strength, no extra effects."),
        Treatment(name: "Neon night", moods: ["night", "city", "club", "tech", "futuristic"],
                  idea: "Contrasty city night with glow and a little digital damage.",
                  structure: "Short punchy cuts, glitch on scene changes only, a held neon title at the end.",
                  transitions: [.glitchCut], look: "Cyberpunk", effects: [(.glow, 0.5), (.chromatic, 0.3)], overlay: nil, title: .neon,
                  speed: "Fast ramps on movement.", restraint: "Glitch cut at most 3 times in the film."),
        Treatment(name: "Documentary clean", moods: ["informative", "product", "business", "tutorial", "corporate"],
                  idea: "Clear, honest, readable: the footage speaks, graphics support it.",
                  structure: "Setting -> point -> evidence -> conclusion; lower thirds to name things; steady 3-5 s shots.",
                  transitions: [.crossfade], look: "Clean bright", effects: [], overlay: nil, title: .lowerThird,
                  speed: "None.", restraint: "No effects at all; one title style throughout."),
        Treatment(name: "Adventure journal", moods: ["travel", "outdoor", "adventure", "road trip", "nature"],
                  idea: "A day-by-day journey with a sense of place and movement.",
                  structure: "Map-like opening wide shot -> place by place with a short caption -> action cluster -> sunset ending.",
                  transitions: [.slide, .whipRight], look: "Teal & orange", effects: [(.kenBurnsIn, 0.4)], overlay: nil, title: .subtitle,
                  speed: "2x on boring travel, 0.5x on the best action.", restraint: "Slide only in the direction of travel."),
        Treatment(name: "Dream sequence", moods: ["dreamy", "magical", "romantic", "fantasy", "wedding"],
                  idea: "Soft, glowing, weightless: reality seen through a memory.",
                  structure: "Long dissolves, slow motion, light blooms, sparse text.",
                  transitions: [.blurFade, .ripple], look: "Dreamy", effects: [(.glow, 0.45)], overlay: .bokeh, title: .quote,
                  speed: "0.5x for most shots.", restraint: "Ripple once, at the moment of 'waking' or time shift."),
        Treatment(name: "Noir", moods: ["mystery", "serious", "dark", "drama", "crime"],
                  idea: "High contrast black and white, hard cuts, silence and shadow.",
                  structure: "Slow, tense, unbalanced framing; cut on sound; black between chapters.",
                  transitions: [.fadeBlack], look: "Noir", effects: [(.grain, 0.5)], overlay: nil, title: .wide,
                  speed: "None.", restraint: "Hard cuts everywhere except fadeBlack at chapter ends."),
        Treatment(name: "Sports hype", moods: ["sport", "action", "competition", "gym", "highlight"],
                  idea: "Power and speed: impact frames, replays, punchy titles.",
                  structure: "Name card -> best three plays -> replay of the best in slow motion -> final stat or score title.",
                  transitions: [.whipLeft, .flashCut], look: "Dramatic", effects: [(.shake, 0.4)], overlay: nil, title: .impact,
                  speed: "Replay at 0.3x with a ramp back to normal.", restraint: "Shake on impacts only, never on every clip."),
        Treatment(name: "Polaroid memories", moods: ["family", "kids", "birthday", "memories", "photos"],
                  idea: "Warm photo-album feel: stills with gentle motion, borders and handwriting.",
                  structure: "Group by person or theme, 3-4 s per photo with a slow push, captions in handwriting.",
                  transitions: [.pageCurl, .crossfade], look: "Faded", effects: [(.kenBurnsIn, 0.4)], overlay: .frame, title: .handwritten,
                  speed: "None.", restraint: "Page curl at most twice, as chapter turns."),
        Treatment(name: "Quiet and wide", moods: ["landscape", "calm", "relax", "nature", "ambient"],
                  idea: "Patience: wide beautiful shots held long, almost no graphics.",
                  structure: "6-10 s shots, minimal music, a single line of text, a long fade.",
                  transitions: [.crossfade], look: "Matte", effects: [], overlay: nil, title: .minimal,
                  speed: "Time-lapse feel with 4x on clouds or traffic only.", restraint: "No effects, no overlay."),
        Treatment(name: "Party pop", moods: ["party", "birthday", "celebration", "fun", "festival"],
                  idea: "Bright, bouncy, joyful: colour and confetti at the moment of cheer.",
                  structure: "Arrival -> food and faces -> dance cluster -> toast or cake moment -> confetti and a bold goodbye title.",
                  transitions: [.zoom, .slideUp], look: "Vivid", effects: [(.pulse, 0.35)], overlay: .confetti, title: .boxed,
                  speed: "0.5x at the cheer or blow-out.", restraint: "Confetti once, 3-4 seconds, at the peak."),
        Treatment(name: "Trailer", moods: ["trailer", "teaser", "epic", "story", "dramatic"],
                  idea: "Questions, not answers: tease, escalate, title drop, final sting.",
                  structure: "Calm ominous opening -> clips with growing pace -> silence one beat -> title drop -> last-second twist shot.",
                  transitions: [.fadeBlack, .flashCut], look: "Dramatic", effects: [(.cinemaBars, 0.6)], overlay: nil, title: .movie,
                  speed: "One slow-down before the title drop.", restraint: "Title cards short and few: 3 at most."),
        Treatment(name: "Vlog daily", moods: ["vlog", "daily", "lifestyle", "social", "reels"],
                  idea: "Personal and quick: jump cuts, captions, a friendly tone.",
                  structure: "Hook line first, quick sequence of moments, a payoff, a short sign-off.",
                  transitions: [.slide], look: "Clean bright", effects: [], overlay: nil, title: .subtitle,
                  speed: "None.", restraint: "Hard cuts; captions simple and readable."),
    ]

    /// Random constraints that push the film away from the usual: cards the assistant must obey at least one of.
    public static let constraints = [
        "Open on a detail (hands, feet, a sound source), never on the establishing shot.",
        "No music for the first five seconds: let the original sound carry the hook.",
        "Every cut happens on a movement inside the frame.",
        "Use no transitions at all; cut harder instead.",
        "Tell it backwards: start at the end of the day and rewind.",
        "Build the film around one repeated visual rhyme (a colour, a gesture, a shape) that returns three times.",
        "Make the longest shot the one you would normally cut first.",
        "Let the title arrive late, after the first third, and keep it to two words.",
        "Show the same moment twice from two different angles, once at normal speed and once slowed.",
        "Alternate two threads (two people, two places) and let them meet in the last shot.",
        "Cut to silence for one beat just before the biggest moment.",
        "No effects on the picture: the look comes only from clip choice, order and rhythm.",
        "Pick one person or object as the narrator: choose every shot as they would see it.",
        "End on the quietest shot, not the loudest.",
        "Make the cuts get shorter then suddenly long: break the rhythm once on purpose.",
        "Use one speed change only, at the moment that matters most.",
    ]

    public static func drawConstraints(_ count: Int = 2) -> [String] { Array(constraints.shuffled().prefix(count)) }

    private nonisolated(unsafe) static var recent: [String] = []
    private static let lock = NSLock()

    /// Several different treatments, matching the mood words when given, avoiding the ones suggested last time.
    public static func suggest(mood: String?, count: Int = 3) -> [Treatment] {
        lock.lock(); defer { lock.unlock() }
        let words = (mood ?? "").lowercased().split(whereSeparator: { !$0.isLetter && $0 != " " }).map(String.init)
        let scored = all.map { t -> (Treatment, Int) in
            let hits = t.moods.filter { m in words.contains { m.contains($0) || $0.contains(m) } }.count
            return (t, hits)
        }
        // Matches come first (fresh ones before repeats), then fresh others; a repeat only shows up when it is the best match.
        let fresh = scored.filter { !recent.contains($0.0.name) }, stale = scored.filter { recent.contains($0.0.name) }
        let ordered = fresh.filter { $0.1 > 0 }.shuffled() + stale.filter { $0.1 > 0 }.shuffled() + fresh.filter { $0.1 == 0 }.shuffled() + stale.filter { $0.1 == 0 }.shuffled()
        var picks: [Treatment] = [], looks = Set<String>()
        for (t, _) in ordered where picks.count < count && !looks.contains(t.look) { picks.append(t); looks.insert(t.look) }
        for (t, _) in ordered where picks.count < count && !picks.contains(where: { $0.name == t.name }) { picks.append(t) }
        recent = Array((recent + picks.map(\.name)).suffix(8))
        return picks
    }

    public static func describe(_ t: Treatment) -> String {
        let fx = t.effects.map { "\($0.0.rawValue) \($0.1)" }.joined(separator: ", ")
        return """
        \(t.name): \(t.idea)
          structure: \(t.structure)
          joins: \(t.transitions.isEmpty ? "hard cuts only" : t.transitions.map(\.rawValue).joined(separator: ", ") + " (mostly hard cuts)")
          look: \(t.look); signature effect: \(fx.isEmpty ? "none" : fx); overlay: \(t.overlay?.rawValue ?? "none"); title style: \(t.title.rawValue)
          speed: \(t.speed)
          restraint: \(t.restraint)
        """
    }
}
