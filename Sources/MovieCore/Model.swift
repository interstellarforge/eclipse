import Foundation

/// All times are integer milliseconds.
public typealias Ms = Int64

public enum TrackKind: String, Codable { case video, audio, text }

public struct Asset: Codable, Identifiable, Equatable {
    public var id: UUID
    public var url: URL
    public var duration: Ms
    public var hasVideo: Bool
    public var hasAudio: Bool
    public var isStill = false      // a photo: `url` is a video made from it, so it behaves like any clip
    public var name: String?        // shown instead of the file name (photos, renamed files)
    public var favorite = false
    public init(id: UUID = UUID(), url: URL, duration: Ms, hasVideo: Bool, hasAudio: Bool, isStill: Bool = false, name: String? = nil, favorite: Bool = false) {
        self.id = id; self.url = url; self.duration = duration
        self.hasVideo = hasVideo; self.hasAudio = hasAudio; self.isStill = isStill; self.name = name; self.favorite = favorite
    }

    public var label: String { name ?? url.lastPathComponent }

    enum CodingKeys: String, CodingKey { case id, url, duration, hasVideo, hasAudio, isStill, name, favorite }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), url: try c.decode(URL.self, forKey: .url), duration: try c.decode(Ms.self, forKey: .duration),
                  hasVideo: try c.decode(Bool.self, forKey: .hasVideo), hasAudio: try c.decode(Bool.self, forKey: .hasAudio),
                  isStill: try c.decodeIfPresent(Bool.self, forKey: .isStill) ?? false, name: try c.decodeIfPresent(String.self, forKey: .name),
                  favorite: try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false)
    }
}

public enum TextAnimation: String, Codable, CaseIterable {
    case none, fade, slideUp, slideDown, slideLeft, pop, typewriter
    public var title: String {
        switch self {
        case .none: return "None"
        case .fade: return "Fade in"
        case .slideUp: return "Slide up"
        case .slideDown: return "Slide down"
        case .slideLeft: return "Slide in from right"
        case .pop: return "Pop"
        case .typewriter: return "Typewriter"
        }
    }
}

public struct TextStyle: Codable, Equatable {
    public var size = 0.08          // fraction of the video height
    public var colorHex = "FFFFFF"
    public var x = 0.5              // centre, fraction of width from the left
    public var y = 0.15             // centre, fraction of height from the bottom
    public var bold = true
    public var shadow = true
    public var fontName: String?
    public var align = 1            // 0 left, 1 centre, 2 right
    public var outline = false
    public var box = false          // dark box behind the text
    public var tracking = 0.0       // letter spacing as a fraction of the size
    public var uppercase = false
    public var glow = false         // soft halo in the text colour
    public var animation = TextAnimation.none   // how it appears at the start of the clip
    public var animationMs: Ms = 500
    public init() {}

    enum CodingKeys: String, CodingKey { case size, colorHex, x, y, bold, shadow, fontName, align, outline, box, tracking, uppercase, glow, animation, animationMs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? size
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? colorHex
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? x
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? y
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? bold
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? shadow
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName)
        align = try c.decodeIfPresent(Int.self, forKey: .align) ?? align
        outline = try c.decodeIfPresent(Bool.self, forKey: .outline) ?? outline
        box = try c.decodeIfPresent(Bool.self, forKey: .box) ?? box
        tracking = try c.decodeIfPresent(Double.self, forKey: .tracking) ?? tracking
        uppercase = try c.decodeIfPresent(Bool.self, forKey: .uppercase) ?? uppercase
        glow = try c.decodeIfPresent(Bool.self, forKey: .glow) ?? glow
        animation = try c.decodeIfPresent(TextAnimation.self, forKey: .animation) ?? animation
        animationMs = try c.decodeIfPresent(Ms.self, forKey: .animationMs) ?? animationMs
    }
}

public enum EffectType: String, Codable, CaseIterable {
    case kenBurnsIn, kenBurnsOut, panLeft, panRight, shake, pulse
    case glow, flash, lightLeak, cinemaBars
    case grain, vhs, chromatic, glitch
    case blurIn, blurOut, posterize, duotone, comic, mirror
    case chromaKey, removeBackground
    case vignette, tiltShift, punchIn, dreamBlur, halftone, pixelate, neonEdges, invert, kaleidoscope, fisheye, strobe, dutchTilt

    public var title: String {
        switch self {
        case .kenBurnsIn: return "Slow zoom in"
        case .kenBurnsOut: return "Slow zoom out"
        case .panLeft: return "Pan left"
        case .panRight: return "Pan right"
        case .shake: return "Camera shake"
        case .pulse: return "Beat pulse"
        case .glow: return "Glow"
        case .flash: return "Flash"
        case .lightLeak: return "Light leak"
        case .cinemaBars: return "Cinema bars"
        case .grain: return "Film grain"
        case .vhs: return "VHS tape"
        case .chromatic: return "Colour split"
        case .glitch: return "Glitch"
        case .blurIn: return "Focus in"
        case .blurOut: return "Focus out"
        case .posterize: return "Poster"
        case .duotone: return "Duotone"
        case .comic: return "Comic"
        case .mirror: return "Mirror"
        case .chromaKey: return "Green screen"
        case .removeBackground: return "Remove background (people)"
        case .vignette: return "Vignette"
        case .tiltShift: return "Tilt-shift"
        case .punchIn: return "Punch in"
        case .dreamBlur: return "Dream blur"
        case .halftone: return "Halftone print"
        case .pixelate: return "Pixelate"
        case .neonEdges: return "Neon edges"
        case .invert: return "Negative"
        case .kaleidoscope: return "Kaleidoscope"
        case .fisheye: return "Fisheye"
        case .strobe: return "Strobe"
        case .dutchTilt: return "Dutch tilt"
        }
    }

    public var summary: String {
        switch self {
        case .kenBurnsIn: return "Camera slowly pushes in over the clip. Brings stills and calm shots to life."
        case .kenBurnsOut: return "Camera slowly pulls back. Good for reveals and endings."
        case .panLeft: return "Slow sideways drift to the left (the picture moves left)."
        case .panRight: return "Slow sideways drift to the right."
        case .shake: return "Handheld or impact shake. Use on hits, explosions, hype moments."
        case .pulse: return "Gentle zoom pulse about twice a second. Pairs with music."
        case .glow: return "Soft bloom around bright areas. Dreamy, warm, sun-lit."
        case .flash: return "White flash at the start of the clip that fades out. Punctuates a cut."
        case .lightLeak: return "Warm film-style light sweeping across the frame."
        case .cinemaBars: return "Black bars top and bottom for a widescreen film look."
        case .grain: return "Film grain texture. Makes digital footage feel organic."
        case .vhs: return "Retro tape look: colour bleed, scanlines and noise."
        case .chromatic: return "Red and blue edges split apart. Energy, tech, dizziness."
        case .glitch: return "Digital glitch bursts with sliced, shifted picture."
        case .blurIn: return "Starts blurred and pulls into focus."
        case .blurOut: return "Starts sharp and drifts out of focus."
        case .posterize: return "Flat poster-like colours."
        case .duotone: return "Two-colour treatment (dark blue shadows, warm highlights)."
        case .comic: return "Comic-book outlines and flat colours."
        case .mirror: return "Mirrors the left half onto the right."
        case .removeBackground: return "EXPERIMENTAL: cuts out people with Apple Vision and removes everything else, so the layer below shows through. Needs a clearly visible person; put the clip on a higher video track."
        case .vignette: return "Darkens the edges to pull the eye to the centre. Subtle polish for portraits and cinematic looks."
        case .tiltShift: return "Blurs the top and bottom so the scene looks like a miniature. Aerial and city shots."
        case .punchIn: return "A quick zoom punch at the start of the clip that settles. Emphasis on a beat or a line."
        case .dreamBlur: return "Soft haze with glowing highlights. Dreams, romance, memories."
        case .halftone: return "Printed dot pattern, pop-art feel. Graphic, playful sequences."
        case .pixelate: return "Chunky pixels. Censoring, retro games, digital moments."
        case .neonEdges: return "Glowing outlines on a dark picture. Music visuals, sci-fi, night."
        case .invert: return "Photo-negative colours. A brief shock or a dream-state beat."
        case .kaleidoscope: return "Mirrored, rotating kaleidoscope. Psychedelic or transition-like moments."
        case .fisheye: return "Bulging wide-angle lens. Action cams, skate, comedy."
        case .strobe: return "Rapid white flashes. Club, concert, high-energy bursts. Use very briefly."
        case .dutchTilt: return "Tilts and crops the frame at an angle. Unease, tension, rebellion."
        case .chromaKey: return "Removes a background colour (green by default) so the layer below shows through. Put the clip on a higher video track."
        }
    }

    /// Strength a freshly added effect starts with.
    public var defaultAmount: Double {
        switch self {
        case .cinemaBars, .mirror, .chromaKey, .removeBackground, .invert: return 1
        case .kaleidoscope, .fisheye: return 0.8
        case .flash, .glitch, .kenBurnsIn, .kenBurnsOut: return 0.6
        default: return 0.5
        }
    }
}

/// A visual effect on a clip. `amount` is the strength 0...1; `colorHex` is used by the green screen.
public struct Effect: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var type: EffectType
    public var amount: Double
    public var colorHex: String?
    public init(_ type: EffectType, amount: Double? = nil, colorHex: String? = nil) {
        self.type = type; self.amount = amount ?? type.defaultAmount; self.colorHex = colorHex
    }
}

/// Colour and geometry adjustments of a video clip.
public struct Look: Codable, Equatable {
    public var brightness = 0.0     // -1...1
    public var contrast = 1.0       // 0...4, 1 = unchanged
    public var saturation = 1.0     // 0...3, 0 = black and white
    public var sepia = 0.0          // 0...1
    public var blur = 0.0           // 0...1
    public var vignette = 0.0       // 0...1
    public var flipX = false
    public var flipY = false
    public var rotation = 0.0       // degrees
    public var cropLeft = 0.0       // fractions of the picture trimmed from each edge, 0...0.9
    public var cropRight = 0.0
    public var cropTop = 0.0
    public var cropBottom = 0.0
    public var warmth = 0.0         // -1 cool ... +1 warm
    public var fade = 0.0           // lifts the blacks for a matte film look, 0...1
    public var sharpen = 0.0        // 0...1
    public var splitShadows: String?     // tint for dark areas, hex like 0B6E7F
    public var splitHighlights: String?  // tint for bright areas
    public var splitAmount = 0.0    // how strongly the two tints show, 0...1
    public init() {}

    enum CodingKeys: String, CodingKey {
        case brightness, contrast, saturation, sepia, blur, vignette, flipX, flipY, rotation, cropLeft, cropRight, cropTop, cropBottom
        case warmth, fade, sharpen, splitShadows, splitHighlights, splitAmount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? brightness
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? contrast
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? saturation
        sepia = try c.decodeIfPresent(Double.self, forKey: .sepia) ?? sepia
        blur = try c.decodeIfPresent(Double.self, forKey: .blur) ?? blur
        vignette = try c.decodeIfPresent(Double.self, forKey: .vignette) ?? vignette
        flipX = try c.decodeIfPresent(Bool.self, forKey: .flipX) ?? flipX
        flipY = try c.decodeIfPresent(Bool.self, forKey: .flipY) ?? flipY
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? rotation
        cropLeft = try c.decodeIfPresent(Double.self, forKey: .cropLeft) ?? cropLeft
        cropRight = try c.decodeIfPresent(Double.self, forKey: .cropRight) ?? cropRight
        cropTop = try c.decodeIfPresent(Double.self, forKey: .cropTop) ?? cropTop
        cropBottom = try c.decodeIfPresent(Double.self, forKey: .cropBottom) ?? cropBottom
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? warmth
        fade = try c.decodeIfPresent(Double.self, forKey: .fade) ?? fade
        sharpen = try c.decodeIfPresent(Double.self, forKey: .sharpen) ?? sharpen
        splitShadows = try c.decodeIfPresent(String.self, forKey: .splitShadows)
        splitHighlights = try c.decodeIfPresent(String.self, forKey: .splitHighlights)
        splitAmount = try c.decodeIfPresent(Double.self, forKey: .splitAmount) ?? splitAmount
    }

    public static let presetNames = ["Normal", "Black & white", "Sepia", "Vivid", "Faded", "Dramatic", "Dreamy",
                                     "Teal & orange", "Golden hour", "Cold steel", "Noir", "Bleach bypass", "Pastel", "Vintage film", "Cyberpunk", "Moody", "Clean bright", "Matte"]

    /// Colour looks by name (case-insensitive; "bw" and "none" work too). Geometry (flip, rotation, crop) is not touched.
    public static func preset(_ name: String) -> Look? {
        var l = Look()
        switch name.lowercased() {
        case "normal", "none": break
        case "black & white", "bw", "b&w", "black and white": l.saturation = 0; l.contrast = 1.15
        case "sepia": l.sepia = 0.9
        case "vivid": l.saturation = 1.6; l.contrast = 1.15
        case "faded": l.saturation = 0.6; l.contrast = 0.85; l.brightness = 0.08
        case "dramatic": l.contrast = 1.5; l.saturation = 0.8; l.vignette = 0.6; l.brightness = -0.05
        case "dreamy": l.blur = 0.15; l.brightness = 0.1; l.saturation = 1.2
        case "teal & orange", "teal and orange", "teal-orange": l.contrast = 1.15; l.saturation = 1.1; l.splitShadows = "0B6E7F"; l.splitHighlights = "FF9A3C"; l.splitAmount = 0.55; l.vignette = 0.2
        case "golden hour": l.warmth = 0.6; l.contrast = 1.1; l.saturation = 1.15; l.fade = 0.05; l.splitHighlights = "FFC070"; l.splitShadows = "7A3B14"; l.splitAmount = 0.3
        case "cold steel": l.warmth = -0.6; l.contrast = 1.2; l.saturation = 0.7; l.splitShadows = "2B4C7E"; l.splitHighlights = "BFD9FF"; l.splitAmount = 0.3
        case "noir": l.saturation = 0; l.contrast = 1.5; l.vignette = 0.6; l.brightness = -0.05
        case "bleach bypass": l.saturation = 0.45; l.contrast = 1.45; l.sharpen = 0.4
        case "pastel": l.brightness = 0.1; l.contrast = 0.85; l.saturation = 0.8; l.fade = 0.2; l.splitHighlights = "FFD1DC"; l.splitShadows = "A9C7FF"; l.splitAmount = 0.25
        case "vintage film": l.sepia = 0.35; l.fade = 0.25; l.contrast = 0.95; l.vignette = 0.35; l.warmth = 0.25
        case "cyberpunk": l.saturation = 1.4; l.contrast = 1.2; l.splitShadows = "3A0CA3"; l.splitHighlights = "00F5D4"; l.splitAmount = 0.6
        case "moody": l.brightness = -0.08; l.contrast = 1.3; l.saturation = 0.75; l.vignette = 0.5; l.warmth = -0.15
        case "clean bright": l.brightness = 0.06; l.contrast = 1.08; l.saturation = 1.1; l.sharpen = 0.3
        case "matte": l.fade = 0.3; l.contrast = 0.9; l.saturation = 0.9
        default: return nil
        }
        return l
    }
}

/// A picture state at a moment of the clip. Between keyframes the values glide; before the first and after the last they hold.
/// A drawn overlay layer (no file): falling confetti, snow, rain, sparkles, light, frames.
public enum GeneratorKind: String, Codable, CaseIterable {
    case confetti, snow, rain, sparkles, bokeh, dust, sunbeams, frame, hearts, fireflies
    case stars, embers, petals, bubbles, leaves, fireworks, smoke, streaks, digitalRain

    public var title: String {
        switch self {
        case .confetti: return "Confetti"
        case .snow: return "Snowfall"
        case .rain: return "Rain"
        case .sparkles: return "Sparkles"
        case .bokeh: return "Bokeh lights"
        case .dust: return "Film dust"
        case .sunbeams: return "Sun rays"
        case .frame: return "Photo frame"
        case .hearts: return "Floating hearts"
        case .fireflies: return "Fireflies"
        case .stars: return "Starfield"
        case .embers: return "Rising embers"
        case .petals: return "Falling petals"
        case .bubbles: return "Bubbles"
        case .leaves: return "Autumn leaves"
        case .fireworks: return "Fireworks"
        case .smoke: return "Drifting smoke"
        case .streaks: return "Light streaks"
        case .digitalRain: return "Digital rain"
        }
    }

    public var summary: String {
        switch self {
        case .confetti: return "Colourful confetti falling. Parties, celebrations, wins."
        case .snow: return "Gentle snowfall. Winter, calm, magical moments."
        case .rain: return "Rain streaks. Moody, dramatic, melancholic scenes."
        case .sparkles: return "Twinkling stars. Magic, glamour, special moments."
        case .bokeh: return "Soft glowing light discs. Dreamy, night, romantic."
        case .dust: return "Film dust and scratches. Vintage and nostalgic looks."
        case .sunbeams: return "Warm rays of sun from the corner. Golden hour, hope."
        case .frame: return "A white photo border. Memories, polaroid and album looks."
        case .hearts: return "Hearts rising. Love, weddings, thank-yous."
        case .fireflies: return "Glowing fireflies drifting. Evening, fairy-tale, calm."
        case .stars: return "A twinkling night sky. Night scenes, space, wishes, endings."
        case .embers: return "Glowing sparks rising. Campfires, drama, intensity, action."
        case .petals: return "Pink petals drifting down. Spring, weddings, gentle beauty."
        case .bubbles: return "Soap bubbles floating up. Kids, summer, playful and dreamy."
        case .leaves: return "Autumn leaves falling. Autumn, nostalgia, travel."
        case .fireworks: return "Bursting fireworks. New year, celebrations, finales."
        case .smoke: return "Soft smoke drifting across. Mystery, moody, cinematic atmosphere."
        case .streaks: return "Warm light streaks sweeping across. Cinematic polish, transitions, glamour."
        case .digitalRain: return "Falling green code. Tech, hacker, sci-fi topics."
        }
    }
}

/// One point of a speed curve: `position` is where in the clip (0 start ... 1 end), `speed` how fast it plays there (1 = normal).
public struct RampPoint: Codable, Equatable {
    public var position: Double
    public var speed: Double
    public init(position: Double, speed: Double) { self.position = position; self.speed = speed }
}

public enum SpeedRamp {
    public static let presets: [(name: String, points: [RampPoint])] = [
        ("Slow-mo dip", [RampPoint(position: 0, speed: 1), RampPoint(position: 0.35, speed: 1), RampPoint(position: 0.5, speed: 0.3), RampPoint(position: 0.65, speed: 1), RampPoint(position: 1, speed: 1)]),
        ("Hero pause", [RampPoint(position: 0, speed: 1), RampPoint(position: 0.4, speed: 0.2), RampPoint(position: 0.6, speed: 0.2), RampPoint(position: 1, speed: 1)]),
        ("Ramp up", [RampPoint(position: 0, speed: 0.5), RampPoint(position: 1, speed: 2.5)]),
        ("Ramp down", [RampPoint(position: 0, speed: 2.5), RampPoint(position: 1, speed: 0.5)]),
        ("Speed burst", [RampPoint(position: 0, speed: 1), RampPoint(position: 0.4, speed: 1), RampPoint(position: 0.5, speed: 3), RampPoint(position: 0.6, speed: 1), RampPoint(position: 1, speed: 1)]),
        ("Slow ending", [RampPoint(position: 0, speed: 1), RampPoint(position: 0.7, speed: 1), RampPoint(position: 1, speed: 0.4)]),
        ("Slow start", [RampPoint(position: 0, speed: 0.4), RampPoint(position: 0.3, speed: 1), RampPoint(position: 1, speed: 1)]),
        ("Pulse", [RampPoint(position: 0, speed: 1), RampPoint(position: 0.25, speed: 0.4), RampPoint(position: 0.5, speed: 1), RampPoint(position: 0.75, speed: 0.4), RampPoint(position: 1, speed: 1)]),
    ]

    public static func preset(_ name: String) -> [RampPoint]? {
        let key = name.lowercased().filter { $0.isLetter }
        return presets.first { $0.name.lowercased().filter(\.isLetter) == key }?.points
    }

    /// Speed at `u` (0...1): glides between the points (in the ratio of the speeds, so 0.5 to 2 feels even).
    public static func speed(at u: Double, _ points: [RampPoint]) -> Double {
        guard let first = points.first, let last = points.last else { return 1 }
        if u <= first.position { return first.speed }
        if u >= last.position { return last.speed }
        for i in 0..<(points.count - 1) where u <= points[i + 1].position {
            let a = points[i], b = points[i + 1]
            let f = (u - a.position) / max(1e-9, b.position - a.position), eased = f * f * (3 - 2 * f)
            return exp(log(a.speed) + (log(b.speed) - log(a.speed)) * eased)
        }
        return last.speed
    }
}

public struct Keyframe: Codable, Equatable {
    public var time: Ms             // from the start of the clip
    public var opacity = 1.0
    public var scale = 1.0
    public var offsetX = 0.0
    public var offsetY = 0.0
    public var rotation = 0.0       // degrees
    public var smooth = true        // ease in and out towards this keyframe instead of a straight line
    public init(time: Ms, opacity: Double = 1, scale: Double = 1, offsetX: Double = 0, offsetY: Double = 0, rotation: Double = 0, smooth: Bool = true) {
        self.time = time; self.opacity = opacity; self.scale = scale; self.offsetX = offsetX; self.offsetY = offsetY
        self.rotation = rotation; self.smooth = smooth
    }
}

extension Keyframe {
    /// The picture state at `time` (ms from the clip start): straight or eased glide between neighbours, holding at the ends.
    public static func interpolate(_ frames: [Keyframe], at time: Double) -> Keyframe? {
        guard let first = frames.first, let last = frames.last else { return nil }
        if time <= Double(first.time) { return first }
        if time >= Double(last.time) { return last }
        for i in 0..<(frames.count - 1) where time < Double(frames[i + 1].time) {
            let a = frames[i], b = frames[i + 1]
            var u = (time - Double(a.time)) / Double(max(1, b.time - a.time))
            if b.smooth { u = u * u * (3 - 2 * u) }
            func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * u }
            return Keyframe(time: Ms(time), opacity: mix(a.opacity, b.opacity), scale: mix(a.scale, b.scale),
                            offsetX: mix(a.offsetX, b.offsetX), offsetY: mix(a.offsetY, b.offsetY), rotation: mix(a.rotation, b.rotation))
        }
        return last
    }
}

public struct Clip: Codable, Identifiable, Equatable {
    public var id: UUID
    public var assetID: UUID?      // nil for text clips
    public var text: String?
    public var sourceIn: Ms        // offset into asset
    public var duration: Ms
    public var start: Ms           // position on timeline
    public var volume: Double
    public var fadeIn: Ms
    public var fadeOut: Ms
    public var muted = false       // video clip whose audio was detached or switched off
    public var opacity = 1.0
    public var scale = 1.0
    public var offsetX = 0.0       // fraction of width, + is right
    public var offsetY = 0.0       // fraction of height, + is up
    public var style = TextStyle() // text clips only
    public var speed = 1.0         // 2 = plays twice as fast; `duration` is the time on the timeline
    public var look = Look()
    public var effects: [Effect] = []
    public var groupID: UUID?      // clips sharing a group move, split and delete together
    public var keyframes: [Keyframe] = []   // when present they replace opacity, scale, offset and rotation
    public var generator: GeneratorKind?    // overlay clips have no file: they are drawn
    public var generatorAmount = 0.5        // how much of it (density), 0...1
    public var end: Ms { start + duration }
    /// Length of the source material the clip uses.
    public var sourceLength: Ms { Ms((Double(duration) * speed).rounded()) }
    public init(id: UUID = UUID(), assetID: UUID?, text: String? = nil, sourceIn: Ms = 0,
                duration: Ms, start: Ms, volume: Double = 1, fadeIn: Ms = 0, fadeOut: Ms = 0) {
        self.id = id; self.assetID = assetID; self.text = text; self.sourceIn = sourceIn
        self.duration = duration; self.start = start; self.volume = volume
        self.fadeIn = fadeIn; self.fadeOut = fadeOut
    }
}

extension Clip {
    enum CodingKeys: String, CodingKey {
        case id, assetID, text, sourceIn, duration, start, volume, fadeIn, fadeOut, muted, opacity, scale, offsetX, offsetY, style, speed, look, effects, groupID, keyframes, generator, generatorAmount
    }

    /// Files saved before a field existed still load: new fields fall back to their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), assetID: try c.decodeIfPresent(UUID.self, forKey: .assetID),
                  text: try c.decodeIfPresent(String.self, forKey: .text), sourceIn: try c.decode(Ms.self, forKey: .sourceIn),
                  duration: try c.decode(Ms.self, forKey: .duration), start: try c.decode(Ms.self, forKey: .start),
                  volume: try c.decode(Double.self, forKey: .volume), fadeIn: try c.decode(Ms.self, forKey: .fadeIn),
                  fadeOut: try c.decode(Ms.self, forKey: .fadeOut))
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        offsetX = try c.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try c.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
        style = try c.decodeIfPresent(TextStyle.self, forKey: .style) ?? TextStyle()
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        look = try c.decodeIfPresent(Look.self, forKey: .look) ?? Look()
        effects = try c.decodeIfPresent([Effect].self, forKey: .effects) ?? []
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        keyframes = try c.decodeIfPresent([Keyframe].self, forKey: .keyframes) ?? []
        generator = try c.decodeIfPresent(GeneratorKind.self, forKey: .generator)
        generatorAmount = try c.decodeIfPresent(Double.self, forKey: .generatorAmount) ?? 0.5
    }
}

public struct Track: Codable, Identifiable, Equatable {
    public var id: UUID
    public var kind: TrackKind
    public var clips: [Clip]
    public var muted = false     // audio of this track is silent
    public var hidden = false    // picture / titles of this track are not shown
    public var locked = false    // clips on this track cannot be changed
    public var duck = false      // audio track whose volume dips while other sound plays (music under speech)
    public var duckLevel = 0.3   // how far it dips, as a fraction of its volume
    public var name: String?     // e.g. "Captions"
    public init(id: UUID = UUID(), kind: TrackKind, clips: [Clip] = []) {
        self.id = id; self.kind = kind; self.clips = clips
    }

    enum CodingKeys: String, CodingKey { case id, kind, clips, muted, hidden, locked, duck, duckLevel, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), kind: try c.decode(TrackKind.self, forKey: .kind),
                  clips: try c.decode([Clip].self, forKey: .clips))
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        duck = try c.decodeIfPresent(Bool.self, forKey: .duck) ?? false
        duckLevel = try c.decodeIfPresent(Double.self, forKey: .duckLevel) ?? 0.3
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }
}

public enum TransitionType: String, Codable, CaseIterable {
    case crossfade, fadeBlack, fadeWhite, blurFade, pixelate
    case wipe, wipeLeft, wipeUp, wipeDown
    case slide, slideRight, slideUp, slideDown, cover, uncover
    case zoom, spin, irisOpen, irisClose, barnDoorH, barnDoorV, blinds, clock
    case whipLeft, whipRight, glitchCut, flashCut, zoomBlur, rotateZoom, pixelDissolve, diagonalWipe, diamond, splitSlide
    case barsSwipe, modTransition, ripple, pageCurl
    case swirl, filmBurn, shutter, cornerIris, tvStatic, squeeze, cubeSpin, blindsV, copyMachine, flare

    public var title: String {
        switch self {
        case .crossfade: return "Crossfade"
        case .fadeBlack: return "Dip to black"
        case .fadeWhite: return "Dip to white"
        case .blurFade: return "Blur dissolve"
        case .pixelate: return "Pixelate"
        case .wipe: return "Wipe right"
        case .wipeLeft: return "Wipe left"
        case .wipeUp: return "Wipe up"
        case .wipeDown: return "Wipe down"
        case .slide: return "Push left"
        case .slideRight: return "Push right"
        case .slideUp: return "Push up"
        case .slideDown: return "Push down"
        case .cover: return "Cover"
        case .uncover: return "Uncover"
        case .zoom: return "Zoom"
        case .spin: return "Spin away"
        case .irisOpen: return "Iris open"
        case .irisClose: return "Iris close"
        case .barnDoorH: return "Barn door (horizontal)"
        case .barnDoorV: return "Barn door (vertical)"
        case .blinds: return "Blinds"
        case .clock: return "Clock wipe"
        case .whipLeft: return "Whip pan left"
        case .whipRight: return "Whip pan right"
        case .glitchCut: return "Glitch cut"
        case .flashCut: return "Flash cut"
        case .zoomBlur: return "Zoom blur"
        case .rotateZoom: return "Spin in"
        case .pixelDissolve: return "Pixel dissolve"
        case .diagonalWipe: return "Diagonal wipe"
        case .diamond: return "Diamond"
        case .splitSlide: return "Split open"
        case .barsSwipe: return "Bars swipe"
        case .modTransition: return "Ring burst"
        case .ripple: return "Ripple"
        case .pageCurl: return "Page curl"
        case .swirl: return "Swirl"
        case .filmBurn: return "Film burn"
        case .shutter: return "Shutter"
        case .cornerIris: return "Corner iris"
        case .tvStatic: return "TV static"
        case .squeeze: return "Squeeze"
        case .cubeSpin: return "Cube"
        case .blindsV: return "Blinds (vertical)"
        case .copyMachine: return "Copy machine"
        case .flare: return "Lens flare"
        }
    }
}

/// Overlap transition between two adjacent clips on the same track.
public struct Transition: Codable, Identifiable, Equatable {
    public var id: UUID
    public var fromClip: UUID
    public var toClip: UUID
    public var type: TransitionType
    public var duration: Ms
    public init(id: UUID = UUID(), fromClip: UUID, toClip: UUID, type: TransitionType, duration: Ms) {
        self.id = id; self.fromClip = fromClip; self.toClip = toClip
        self.type = type; self.duration = duration
    }
}

public enum TitlePreset: String, CaseIterable {
    case center = "Center title", lowerThird = "Lower third", subtitle = "Subtitle", impact = "Big impact", neon = "Neon glow", minimal = "Minimal"
    case wide = "Cinematic wide", movie = "Movie title", quote = "Quote", tag = "Corner tag", boxed = "Boxed caption", retro = "Retro"
    case handwritten = "Handwritten", credits = "End credits", dateStamp = "Date stamp", countdown = "Big number"
    case chapter = "Chapter card", statement = "Big statement", whisper = "Whisper", postcard = "Postcard", typewriter = "Typewriter", gold = "Gold award"
    case comic = "Comic pop", news = "News bar", signoff = "Script sign-off", stamp = "Rubber stamp", bubblegum = "Bubblegum"

    public var text: String {
        switch self {
        case .center: return "Center title"
        case .lowerThird: return "Name · Place"
        case .subtitle: return "Subtitle goes here"
        case .impact: return "Let's go"
        case .neon: return "Night out"
        case .minimal: return "Summer"
        case .wide: return "A summer story"
        case .movie: return "The Journey"
        case .quote: return "Every day is a gift"
        case .tag: return "Day 3 · Lisbon"
        case .boxed: return "Caption in a box"
        case .retro: return "Good times"
        case .handwritten: return "Dear memories"
        case .credits: return "Directed by you"
        case .dateStamp: return "16 OCT 2026"
        case .countdown: return "3"
        case .chapter: return "Chapter one"
        case .statement: return "Never stop"
        case .whisper: return "and then it was quiet"
        case .postcard: return "Greetings from Lisbon"
        case .typewriter: return "It started on a Tuesday"
        case .gold: return "Best day ever"
        case .comic: return "Boom!"
        case .news: return "Breaking · Our trip"
        case .signoff: return "Thanks for watching"
        case .stamp: return "Approved"
        case .bubblegum: return "Hello summer"
        }
    }

    public var style: TextStyle {
        var s = TextStyle()
        switch self {
        case .center: s.size = 0.12; s.y = 0.5
        case .lowerThird: s.size = 0.06; s.x = 0.08; s.y = 0.15; s.align = 0
        case .subtitle: s.size = 0.05; s.y = 0.07; s.bold = false
        case .impact: s.size = 0.2; s.y = 0.5; s.uppercase = true; s.outline = true; s.animation = .pop
        case .neon: s.size = 0.12; s.y = 0.5; s.colorHex = "35F0FF"; s.glow = true; s.shadow = false; s.tracking = 0.05
        case .minimal: s.size = 0.05; s.y = 0.5; s.bold = false; s.uppercase = true; s.tracking = 0.35; s.fontName = "HelveticaNeue-Light"; s.shadow = false; s.animation = .fade
        case .wide: s.size = 0.045; s.y = 0.5; s.bold = false; s.uppercase = true; s.tracking = 0.5; s.fontName = "HelveticaNeue-Light"; s.animation = .fade; s.animationMs = 900
        case .movie: s.size = 0.13; s.y = 0.5; s.uppercase = true; s.tracking = 0.1; s.fontName = "Georgia-Bold"; s.animation = .fade; s.animationMs = 800
        case .quote: s.size = 0.06; s.y = 0.5; s.bold = false; s.fontName = "Georgia-Italic"; s.animation = .slideUp
        case .tag: s.size = 0.035; s.x = 0.05; s.y = 0.93; s.align = 0; s.box = true; s.bold = false
        case .boxed: s.size = 0.05; s.y = 0.12; s.box = true; s.bold = false
        case .retro: s.size = 0.13; s.y = 0.5; s.colorHex = "FFD60A"; s.fontName = "Impact"; s.outline = true; s.animation = .pop
        case .handwritten: s.size = 0.09; s.y = 0.5; s.fontName = "BradleyHandITCTT-Bold"; s.animation = .typewriter; s.animationMs = 1_400
        case .credits: s.size = 0.04; s.y = 0.5; s.bold = false; s.tracking = 0.15; s.animation = .slideUp
        case .dateStamp: s.size = 0.035; s.x = 0.95; s.y = 0.07; s.align = 2; s.colorHex = "FFB000"; s.fontName = "Menlo-Bold"; s.bold = true
        case .countdown: s.size = 0.4; s.y = 0.5; s.glow = true; s.colorHex = "FFFFFF"; s.animation = .pop
        case .chapter: s.size = 0.07; s.y = 0.5; s.uppercase = true; s.tracking = 0.3; s.bold = false; s.fontName = "HelveticaNeue-Light"; s.animation = .fade; s.animationMs = 900
        case .statement: s.size = 0.17; s.y = 0.5; s.uppercase = true; s.fontName = "HelveticaNeue-CondensedBlack"; s.animation = .slideUp; s.animationMs = 450
        case .whisper: s.size = 0.045; s.y = 0.32; s.bold = false; s.fontName = "Georgia-Italic"; s.shadow = false; s.animation = .fade; s.animationMs = 1_400
        case .postcard: s.size = 0.1; s.y = 0.5; s.colorHex = "FFE08A"; s.fontName = "MarkerFelt-Wide"; s.outline = true; s.animation = .pop
        case .typewriter: s.size = 0.05; s.x = 0.08; s.y = 0.5; s.align = 0; s.fontName = "Menlo-Regular"; s.bold = false; s.box = true; s.animation = .typewriter; s.animationMs = 1_800
        case .gold: s.size = 0.09; s.y = 0.5; s.colorHex = "D4AF37"; s.fontName = "Didot"; s.uppercase = true; s.tracking = 0.2; s.glow = true; s.animation = .fade; s.animationMs = 1_000
        case .comic: s.size = 0.18; s.y = 0.5; s.colorHex = "FFEA00"; s.fontName = "ChalkboardSE-Bold"; s.uppercase = true; s.outline = true; s.animation = .pop; s.animationMs = 300
        case .news: s.size = 0.045; s.x = 0.06; s.y = 0.1; s.align = 0; s.uppercase = true; s.box = true; s.tracking = 0.05; s.animation = .slideLeft
        case .signoff: s.size = 0.12; s.y = 0.5; s.fontName = "SnellRoundhand-Bold"; s.animation = .slideUp; s.animationMs = 800
        case .stamp: s.size = 0.11; s.y = 0.5; s.colorHex = "FF5A5F"; s.fontName = "AmericanTypewriter-Bold"; s.uppercase = true; s.outline = true; s.tracking = 0.1; s.animation = .pop; s.animationMs = 250
        case .bubblegum: s.size = 0.13; s.y = 0.5; s.colorHex = "FF4FA3"; s.fontName = "Chalkduster"; s.outline = true; s.glow = true; s.animation = .pop
        }
        return s
    }

    /// "center", "lowerThird", "lower third", "Cinematic wide" (case- and space-insensitive).
    public static func named(_ name: String) -> TitlePreset? {
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter } }
        let k = key(name)
        return allCases.first { key($0.rawValue) == k || key(String(describing: $0)) == k }
    }
}

public struct Project: Codable, Equatable {
    public var assets: [Asset] = []
    public var tracks: [Track] = []
    public var transitions: [Transition] = []
    public var width = 1920
    public var height = 1080
    public var fps = 30
    public init() {}

    public var duration: Ms { tracks.flatMap(\.clips).map(\.end).max() ?? 0 }
}
