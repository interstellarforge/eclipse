import CoreImage
import Foundation

/// A complete film style: colour grade, effects, joins, title look, overlay and a music suggestion.
public struct EditTemplate: Identifiable, Equatable {
    public let id: String
    public var name: String
    public var category: String
    public var summary: String
    public var look: Look
    public var effects: [Effect]
    public var transition: TransitionType?
    public var transitionMs: Ms
    public var titleStyle: TitlePreset?
    public var overlay: GeneratorKind?
    public var overlayAmount: Double
    public var music: String?
    public var pace: String
}

public enum Templates {
    private static func look(_ name: String, _ tweak: (inout Look) -> Void = { _ in }) -> Look {
        var l = Look.preset(name) ?? Look(); tweak(&l); return l
    }

    private static func t(_ name: String, _ category: String, _ summary: String, look: Look, effects: [Effect] = [], transition: TransitionType? = nil, ms: Ms = 500,
                          title: TitlePreset? = nil, overlay: GeneratorKind? = nil, overlayAmount: Double = 0.4, music: String? = nil, pace: String) -> EditTemplate {
        EditTemplate(id: name.lowercased().filter { $0.isLetter || $0.isNumber }, name: name, category: category, summary: summary, look: look, effects: effects,
                     transition: transition, transitionMs: ms, titleStyle: title, overlay: overlay, overlayAmount: overlayAmount, music: music, pace: pace)
    }

    public static let all: [EditTemplate] = [
        // Cinematic
        t("Blockbuster", "Cinematic", "Teal and orange grade, widescreen bars, slow crossfades and grain: the big-screen look.", look: look("Teal & orange"),
          effects: [Effect(.cinemaBars), Effect(.grain, amount: 0.3), Effect(.glow, amount: 0.25)], transition: .crossfade, ms: 800, title: .movie, music: "Epic Rise", pace: "Slow to medium: 3-6 s shots, let moments breathe"),
        t("Noir", "Cinematic", "Black and white, deep contrast, heavy vignette and film grain. Dips to black between scenes.", look: look("Noir"),
          effects: [Effect(.grain, amount: 0.45)], transition: .fadeBlack, ms: 700, title: .wide, music: "Shadow Play", pace: "Slow: 4-7 s shots, long silences"),
        t("Indie Film", "Cinematic", "Warm faded colours, soft grain and gentle dissolves. Intimate, handheld, real.", look: look("Vintage film") { $0.sepia = 0; $0.warmth = 0.3 },
          effects: [Effect(.grain, amount: 0.35)], transition: .crossfade, ms: 600, title: .minimal, music: "Last Light", pace: "Medium: 3-5 s shots"),
        t("Sci-Fi", "Cinematic", "Cold steel colour, glow and a little colour split. Clean wipes.", look: look("Cold steel"),
          effects: [Effect(.glow, amount: 0.4), Effect(.chromatic, amount: 0.2)], transition: .wipe, ms: 450, title: .wide, music: "Cyber City", pace: "Medium: 2-4 s shots"),
        t("Western", "Cinematic", "Dusty golden tones, film dust and slow zooms.", look: look("Golden hour") { $0.sepia = 0.3; $0.contrast = 1.2 },
          effects: [Effect(.grain, amount: 0.4), Effect(.kenBurnsIn, amount: 0.4)], transition: .crossfade, ms: 700, title: .retro, overlay: .dust, music: "Wanderlust", pace: "Slow: 4-6 s shots"),
        t("Horror", "Cinematic", "Drained green-grey colour, vignette, glitches and flash cuts.", look: look("Moody") { $0.saturation = 0.45; $0.splitShadows = "0B3D2E"; $0.splitAmount = 0.35 },
          effects: [Effect(.grain, amount: 0.5), Effect(.glitch, amount: 0.3)], transition: .glitchCut, ms: 350, title: .impact, music: "Tension", pace: "Uneven: long holds, sudden short cuts"),
        t("Epic Trailer", "Cinematic", "Dramatic contrast, camera shake, flashes and widescreen. Built for peaks.", look: look("Dramatic") { $0.saturation = 0.9 },
          effects: [Effect(.cinemaBars), Effect(.shake, amount: 0.25), Effect(.flash, amount: 0.5)], transition: .flashCut, ms: 300, title: .impact, music: "Titan Pulse", pace: "Accelerating: 3 s down to 0.6 s"),
        t("Fantasy", "Cinematic", "Soft glow, golden light leaks and floating sparkles.", look: look("Dreamy") { $0.warmth = 0.2 },
          effects: [Effect(.glow, amount: 0.55), Effect(.lightLeak, amount: 0.4)], transition: .blurFade, ms: 800, title: .movie, overlay: .sparkles, music: "Aurora", pace: "Slow: 4-6 s shots"),
        t("Documentary", "Cinematic", "Natural, clean grade with a touch of sharpening. Simple dissolves.", look: look("Clean bright") { $0.saturation = 0.95 },
          transition: .crossfade, ms: 500, title: .lowerThird, music: "New Horizons", pace: "Medium: 3-6 s shots"),
        // Energetic
        t("Hype Montage", "Energetic", "Punchy colour, shake, glitch and whip pans. Cuts land hard.", look: look("Vivid"),
          effects: [Effect(.shake, amount: 0.2), Effect(.chromatic, amount: 0.2)], transition: .whipLeft, ms: 250, title: .impact, music: "Hype Machine", pace: "Fast: 0.8-1.8 s shots"),
        t("Sports Highlights", "Energetic", "High contrast, pulse on the beat, whip pans between plays.", look: look("Vivid") { $0.contrast = 1.25; $0.sharpen = 0.3 },
          effects: [Effect(.pulse, amount: 0.3)], transition: .whipRight, ms: 250, title: .impact, music: "Turbo Run", pace: "Fast: 1-2.5 s shots"),
        t("Party Night", "Energetic", "Saturated colour, bokeh and confetti. Zoom blur between clips.", look: look("Vivid") { $0.saturation = 1.7 },
          effects: [Effect(.glow, amount: 0.4), Effect(.lightLeak, amount: 0.3)], transition: .zoomBlur, ms: 350, title: .neon, overlay: .confetti, music: "Disco Fever", pace: "Fast: 1-2 s shots"),
        t("Street Style", "Energetic", "Gritty grain, VHS touches and slides. Urban and raw.", look: look("Bleach bypass"),
          effects: [Effect(.grain, amount: 0.5), Effect(.vhs, amount: 0.25)], transition: .slide, ms: 300, title: .tag, music: "Street Fire", pace: "Fast: 1-2.5 s shots"),
        t("Fitness Drive", "Energetic", "Hard contrast, sharp detail and a pulsing beat.", look: look("Dramatic") { $0.saturation = 1.1; $0.sharpen = 0.4; $0.vignette = 0.3 },
          effects: [Effect(.pulse, amount: 0.25)], transition: .flashCut, ms: 250, title: .impact, music: "Pump It", pace: "Fast: 1-2 s shots"),
        // Emotional
        t("Nostalgia", "Emotional", "Warm faded film, grain and a light leak. Slow dissolves.", look: look("Vintage film"),
          effects: [Effect(.grain, amount: 0.4), Effect(.lightLeak, amount: 0.35)], transition: .crossfade, ms: 1_000, title: .quote, overlay: .dust, music: "Remember Me", pace: "Slow: 4-7 s shots"),
        t("Wedding Romance", "Emotional", "Soft glow, warm pastel skin tones, hearts and gentle fades.", look: look("Pastel") { $0.warmth = 0.2 },
          effects: [Effect(.glow, amount: 0.5)], transition: .crossfade, ms: 900, title: .handwritten, overlay: .hearts, overlayAmount: 0.25, music: "Heartstrings", pace: "Slow: 4-6 s shots"),
        t("Memories", "Emotional", "Faded colour, vignette and a white photo frame.", look: look("Faded") { $0.vignette = 0.35; $0.warmth = 0.2 },
          effects: [Effect(.grain, amount: 0.25)], transition: .pageCurl, ms: 800, title: .dateStamp, overlay: .frame, overlayAmount: 0.4, music: "Tender Moment", pace: "Slow: 4-5 s shots"),
        t("Heartfelt", "Emotional", "Gentle warm look with slow push-ins. Intimate and quiet.", look: look("Golden hour") { $0.contrast = 1.0; $0.saturation = 1.0 },
          effects: [Effect(.kenBurnsIn, amount: 0.35), Effect(.glow, amount: 0.25)], transition: .crossfade, ms: 900, title: .quote, music: "First Light", pace: "Slow: 4-6 s shots"),
        t("Tribute", "Emotional", "Black and white with soft glow and dips to black.", look: look("Noir") { $0.contrast = 1.2; $0.vignette = 0.4 },
          effects: [Effect(.glow, amount: 0.3), Effect(.grain, amount: 0.25)], transition: .fadeBlack, ms: 900, title: .movie, music: "Letting Go", pace: "Slow: 5-7 s shots"),
        // Travel & lifestyle
        t("Travel Vlog", "Travel", "Warm, vivid colour and quick slides. Fresh and bright.", look: look("Golden hour") { $0.saturation = 1.3 },
          effects: [Effect(.pulse, amount: 0.15)], transition: .slide, ms: 350, title: .lowerThird, music: "Coastal Drive", pace: "Medium-fast: 2-3.5 s shots"),
        t("Summer Vibes", "Travel", "Sunny colours, light leaks and sun rays.", look: look("Golden hour") { $0.warmth = 0.45; $0.saturation = 1.35 },
          effects: [Effect(.lightLeak, amount: 0.4), Effect(.glow, amount: 0.3)], transition: .crossfade, ms: 500, title: .minimal, overlay: .sunbeams, music: "Island Time", pace: "Medium: 2.5-4 s shots"),
        t("Winter Chill", "Travel", "Cool blue grade with falling snow.", look: look("Cold steel") { $0.saturation = 0.85 },
          effects: [Effect(.glow, amount: 0.25)], transition: .crossfade, ms: 700, title: .wide, overlay: .snow, overlayAmount: 0.5, music: "Silent Valley", pace: "Slow-medium: 3-5 s shots"),
        t("Road Trip", "Travel", "Warm grain, whip pans and handheld energy.", look: look("Vintage film") { $0.sepia = 0.1; $0.saturation = 1.1 },
          effects: [Effect(.grain, amount: 0.35)], transition: .whipLeft, ms: 300, title: .dateStamp, music: "Road Trip", pace: "Medium-fast: 2-3 s shots"),
        t("Real Estate", "Travel", "Bright, clean and sharp. Smooth, quiet dissolves.", look: look("Clean bright") { $0.brightness = 0.08 },
          transition: .crossfade, ms: 600, title: .lowerThird, music: "Clean Slate", pace: "Slow: 4-6 s shots"),
        // Style
        t("Retro VHS", "Style", "Tape colour bleed, scanlines and glitches. Camcorder date stamp.", look: look("Vivid") { $0.saturation = 1.2; $0.warmth = 0.1 },
          effects: [Effect(.vhs, amount: 0.7), Effect(.chromatic, amount: 0.2)], transition: .glitchCut, ms: 300, title: .dateStamp, music: "Pixel Quest", pace: "Medium: 2-4 s shots"),
        t("Synthwave 80s", "Style", "Neon purple and cyan, glow and colour split. Pure 80s.", look: look("Cyberpunk"),
          effects: [Effect(.glow, amount: 0.5), Effect(.chromatic, amount: 0.25)], transition: .diagonalWipe, ms: 450, title: .neon, music: "Neon Nights", pace: "Medium: 2-3.5 s shots"),
        t("Cyberpunk City", "Style", "Dark neon night look with grain and glitches.", look: look("Cyberpunk") { $0.brightness = -0.06 },
          effects: [Effect(.glow, amount: 0.45), Effect(.glitch, amount: 0.25)], transition: .glitchCut, ms: 300, title: .neon, overlay: .rain, overlayAmount: 0.35, music: "Midnight Chase", pace: "Medium-fast: 1.5-3 s shots"),
        t("Lo-fi Chill", "Style", "Matte faded colour, soft grain, floating bokeh.", look: look("Matte") { $0.warmth = 0.15 },
          effects: [Effect(.grain, amount: 0.35)], transition: .crossfade, ms: 700, title: .handwritten, overlay: .bokeh, overlayAmount: 0.35, music: "Lo-fi Chill", pace: "Slow-medium: 3-5 s shots"),
        t("Dreamy Pastel", "Style", "Pastel colour, glow and sparkles.", look: look("Pastel"),
          effects: [Effect(.glow, amount: 0.5)], transition: .blurFade, ms: 800, title: .minimal, overlay: .sparkles, music: "Cloud Walk", pace: "Slow: 4-5 s shots"),
        t("Vintage 16mm", "Style", "Old film stock: warm fade, grain, dust and scratches.", look: look("Vintage film") { $0.vignette = 0.45 },
          effects: [Effect(.grain, amount: 0.55)], transition: .crossfade, ms: 500, title: .retro, overlay: .dust, overlayAmount: 0.6, music: "Market Day", pace: "Medium: 2-4 s shots"),
        t("Fashion Editorial", "Style", "Crisp black and white with hard flash cuts.", look: look("Noir") { $0.contrast = 1.4; $0.vignette = 0.2 },
          effects: [Effect(.grain, amount: 0.2)], transition: .flashCut, ms: 250, title: .wide, music: "Smooth Flow", pace: "Fast-medium: 1.5-3 s shots"),
        // Everyday
        t("Clean Corporate", "Everyday", "Neutral, bright and tidy. Soft dissolves, simple titles.", look: look("Clean bright"),
          transition: .crossfade, ms: 400, title: .lowerThird, music: "Bright Ideas", pace: "Medium: 3-5 s shots"),
        t("Product Ad", "Everyday", "Bright punchy colour with zoom accents.", look: look("Clean bright") { $0.saturation = 1.2; $0.contrast = 1.15 },
          effects: [Effect(.pulse, amount: 0.15)], transition: .zoom, ms: 350, title: .center, music: "Bright Ideas", pace: "Fast-medium: 1.5-3 s shots"),
        t("Kids Fun", "Everyday", "Saturated, bouncy and playful with confetti.", look: look("Vivid") { $0.saturation = 1.5; $0.brightness = 0.05 },
          transition: .spin, ms: 400, title: .retro, overlay: .confetti, overlayAmount: 0.35, music: "Playground", pace: "Fast: 1.5-3 s shots"),
        t("Family Album", "Everyday", "Warm, soft and friendly with a photo frame.", look: look("Golden hour") { $0.contrast = 1.0; $0.saturation = 1.05 },
          transition: .crossfade, ms: 700, title: .handwritten, overlay: .frame, overlayAmount: 0.3, music: "Sunday Morning", pace: "Medium: 3-5 s shots"),
    ]

    public static var categories: [String] {
        var seen: [String] = []
        for template in all where !seen.contains(template.category) { seen.append(template.category) }
        return seen
    }

    public static func named(_ name: String) -> EditTemplate? {
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return all.first { $0.id == key }
    }
}

extension Editor {
    public struct TemplateOptions {
        public var transitions = true      // add or restyle the joins between clips
        public var titles = true           // restyle existing titles
        public var overlay = true          // add the template's overlay over the whole movie
        public init() {}
    }

    /// Applies a template to the given clips (all video clips when nil) in one undo step. Returns what changed in plain words.
    @discardableResult
    public func applyTemplate(_ template: EditTemplate, to clipIDs: [UUID]? = nil, options: TemplateOptions = TemplateOptions()) throws -> String {
        var notes: [String] = []
        try transaction {
            let videoClips = project.tracks.filter { $0.kind == .video }.flatMap(\.clips).filter { $0.assetID != nil && (clipIDs?.contains($0.id) ?? true) }
            guard !videoClips.isEmpty else { throw EditError.invalid("There are no video clips to style.") }
            for clip in videoClips {
                var look = template.look
                look.flipX = clip.look.flipX; look.flipY = clip.look.flipY; look.rotation = clip.look.rotation   // framing stays
                look.cropLeft = clip.look.cropLeft; look.cropRight = clip.look.cropRight; look.cropTop = clip.look.cropTop; look.cropBottom = clip.look.cropBottom
                try apply(.setLook(clip.id, look))
                for old in clip.effects { try apply(.removeEffect(clip.id, effect: old.id)) }
                for effect in template.effects { try apply(.addEffect(clip.id, Effect(effect.type, amount: effect.amount, colorHex: effect.colorHex))) }
            }
            notes.append("styled \(videoClips.count) clips with the \(template.name) look" + (template.effects.isEmpty ? "" : " and effects"))
            if options.transitions, let type = template.transition {
                var changed = 0
                let ids = Set(videoClips.map(\.id))
                for track in project.tracks where track.kind == .video {
                    let sorted = track.clips.filter { $0.assetID != nil }.sorted { $0.start < $1.start }
                    for pair in zip(sorted, sorted.dropFirst()) where ids.contains(pair.0.id) && ids.contains(pair.1.id) {
                        if let existing = project.transitions.first(where: { $0.fromClip == pair.0.id && $0.toClip == pair.1.id }) {
                            let overlap = pair.0.end - pair.1.start
                            try apply(.setTransition(existing.id, type: type, duration: max(1, overlap))); changed += 1   // keeps the overlap, changes the style
                        } else if pair.0.end == pair.1.start {
                            try addTransition(after: pair.0.id, type: type, duration: template.transitionMs); changed += 1
                        }
                    }
                }
                if changed > 0 { notes.append("\(changed) joins now use \(type.title.lowercased())") }
            }
            if options.titles, let style = template.titleStyle {
                var count = 0
                for track in project.tracks where track.kind == .text && track.name != "Captions" {
                    for clip in track.clips where clip.text != nil {
                        var s = style.style; s.x = clip.style.x; s.y = clip.style.y   // the title stays where you put it
                        try apply(.setTextStyle(clip.id, s)); count += 1
                    }
                }
                if count > 0 { notes.append("\(count) titles restyled") }
            }
            if options.overlay, let kind = template.overlay, project.duration > 0 {
                let overlay = try addOverlay(kind, start: 0, duration: project.duration, amount: template.overlayAmount)
                try apply(.setVolume(overlay.id, volume: 1, fadeIn: min(800, overlay.duration / 3), fadeOut: min(800, overlay.duration / 3)))
                notes.append("\(kind.title.lowercased()) overlay added")
            }
        }
        return notes.joined(separator: "; ")
    }
}

/// Still pictures of templates for the Templates tab: your own first clip (or the demo scene) with the style applied.
public enum TemplateRenderer {
    public static func thumbnail(_ template: EditTemplate, source: CGImage?, size: CGSize = CGSize(width: 240, height: 135)) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        var image: CIImage
        if let source {
            let img = CIImage(cgImage: source), s = max(size.width / img.extent.width, size.height / img.extent.height)
            let scaled = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
            image = scaled.transformed(by: CGAffineTransform(translationX: (size.width - scaled.extent.width) / 2 - scaled.extent.minX, y: (size.height - scaled.extent.height) / 2 - scaled.extent.minY)).cropped(to: rect)
        } else { image = EffectRenderer.demoScene(size, greenScreen: false) }
        image = LookRenderer.apply(template.look, to: image, size: size)
        for effect in template.effects { image = EffectRenderer.apply(effect, to: image, size: size, progress: 0.5, seconds: 1.5, duration: 3) }
        if let kind = template.overlay, let overlay = GeneratorRenderer.image(kind, amount: template.overlayAmount + 0.2, size: size, seconds: 2) { image = overlay.composited(over: image) }
        return CIContext().createCGImage(image.cropped(to: rect), from: rect)
    }
}
