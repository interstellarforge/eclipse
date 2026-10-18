import Foundation

/// Ready-made requests for the Assistant: specific, with taste. Click one to put it in the box and edit it, or send it right away.
struct PromptIdea: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let subtitle: String
    let prompt: String
}

enum PromptLibrary {
    static let categories = ["Make a film", "Improve", "Style & sound"]

    static func ideas(in category: String) -> [PromptIdea] { all.filter { $0.category == category }.map(\.idea) }

    private static let all: [(category: String, idea: PromptIdea)] = [
        // MARK: Make a film
        ("Make a film", PromptIdea(emoji: "🎬", title: "Cinematic highlight reel", subtitle: "Hook, build, peak, quiet ending, big-screen grade",
            prompt: "Make a 30 second cinematic highlight reel from my clips. Look at every clip first and pick only the strongest moments. Give it a hook in the first two seconds, a build, a peak with shorter cuts, and a quiet closing shot that fades to black. Vary the shot lengths on purpose, use mostly hard cuts with a few slow dissolves, apply the Blockbuster look, and pick music that fits the mood. No sound effects.")),
        ("Make a film", PromptIdea(emoji: "⚡️", title: "Hype sports montage", subtitle: "Fast cuts on the beat, slow-mo on the best action",
            prompt: "Make a 20 second hype montage from my clips. Choose the most energetic moments, cut them to the beat of a driving song (check list_sounds for a fitting tempo), use whip pans and flashes only on the peak, slow down the single best action with a speed ramp, and end on a freeze-like slow shot. Keep the colours punchy.")),
        ("Make a film", PromptIdea(emoji: "🥹", title: "Emotional memory film", subtitle: "Slow, warm, piano, soft dissolves",
            prompt: "Make a warm, emotional memory film of about 45 seconds. Favour faces, hands and quiet moments, hold shots 4 to 6 seconds, use slow crossfades, a warm faded grade with gentle grain, soft piano music, an opening title and a simple closing line. Let the best moment breathe a little longer than the others.")),
        ("Make a film", PromptIdea(emoji: "🧳", title: "Travel vlog recap", subtitle: "Places, movement, bright colour, lower thirds",
            prompt: "Turn my clips into a travel recap of about 45 seconds. Show a variety of places and shot sizes, keep the energy medium with slides between locations, bright warm colours, upbeat music, and a lower-third title for each new place if you can tell where they are. Open with the most beautiful shot and end with a calm sunset-style moment.")),
        ("Make a film", PromptIdea(emoji: "📱", title: "Vertical short for Reels/TikTok", subtitle: "9:16, hook in one second, subject kept in frame",
            prompt: "Make a 15 second vertical short (9:16) from my clips for Reels and TikTok. Hook in the first second, cuts every 1 to 2 seconds, smart-reframe the clips so the main subject stays in the frame, big readable captions, and a loopable ending. Use energetic music.")),
        ("Make a film", PromptIdea(emoji: "💍", title: "Wedding or family tribute", subtitle: "Romantic grade, hearts, handwritten titles",
            prompt: "Make a tender tribute film of about 60 seconds. Soft glow and pastel colours, slow dissolves, a handwritten opening title, the Wedding Romance style, gentle music that rises toward the middle and settles at the end. Keep the original sound for any laughter or speech and lower the music under it.")),
        ("Make a film", PromptIdea(emoji: "🛍️", title: "Product promo", subtitle: "Clean, bright, zoom accents, clear message",
            prompt: "Make a 20 second product promo from my clips. Bright, clean colours, sharp detail, quick zoom accents on the beat, a bold opening title, a call-to-action title at the end, and upbeat corporate music. Show the product benefit in the first five seconds.")),
        ("Make a film", PromptIdea(emoji: "🎞️", title: "Movie trailer", subtitle: "Dramatic grade, accelerating cuts, title cards",
            prompt: "Make a 30 second movie trailer from my clips. Start quiet and mysterious, accelerate the cuts toward a loud peak, add title cards between beats in a cinematic wide style, a dark dramatic grade with grain and widescreen bars, dips to black, and a big final title.")),
        ("Make a film", PromptIdea(emoji: "🎵", title: "Beat-synced music video", subtitle: "Every cut lands on the beat",
            prompt: "Make a 30 second music video from my clips. Pick one of the built-in songs and cut exactly on its beats: calm shots across 2 bars, faster shots on the chorus feel, use the tempo to compute the cut times. Add a glow and a light pulse on the strongest beats, but nothing else flashy.")),
        ("Make a film", PromptIdea(emoji: "🎯", title: "10 second teaser", subtitle: "Only the very best moments",
            prompt: "Make a 10 second teaser: the three most striking moments of my clips, tight cuts, one bold title, music that starts on the first frame. Tell me which moments you chose and why.")),
        // MARK: Improve
        ("Improve", PromptIdea(emoji: "✂️", title: "Tighten the pacing", subtitle: "Cut dead time, keep energy rising",
            prompt: "Look at my timeline and tighten the pacing. Trim the slow beginnings and long endings of the clips, shorten the weakest clips by about 15 percent, and keep the energy rising toward the end. Tell me what you removed.")),
        ("Improve", PromptIdea(emoji: "🔍", title: "Find the best moments", subtitle: "Analyse the clips, list timecodes, no edits",
            prompt: "Analyse all my clips (inspect and look at each one) and list the best 3 moments of each with start and end times and why they are good. Do not change the timeline.")),
        ("Improve", PromptIdea(emoji: "🩺", title: "Review my edit", subtitle: "Honest feedback, three improvements",
            prompt: "Review my current edit like a film editor: look at it with watch_timeline, tell me what works, what drags, and give me exactly three concrete improvements. Do not change anything yet.")),
        ("Improve", PromptIdea(emoji: "🐢", title: "Slow motion on the best action", subtitle: "A speed ramp where it matters",
            prompt: "Find the single best action moment in my clips (a jump, a splash, a smile) and give it a speed ramp: normal speed, a smooth dip into slow motion on the peak, then back to normal. Only do it if the footage is smooth enough, and say which clip you used.")),
        ("Improve", PromptIdea(emoji: "🔗", title: "Find match cuts", subtitle: "Clips that flow into each other",
            prompt: "Find match cuts between my clips (similar colours, shapes or movement) and rebuild my edit so the best two or three matches become hard cuts between clips. Tell me which clips flow into each other.")),
        ("Improve", PromptIdea(emoji: "🎨", title: "Match all the colours", subtitle: "One consistent look across clips",
            prompt: "Compare my clips and make them look like they belong together: match brightness, contrast and saturation across clips, then apply one subtle consistent grade. Show me a before and after frame description.")),
        // MARK: Style & sound
        ("Style & sound", PromptIdea(emoji: "📽️", title: "Make it more cinematic", subtitle: "Blockbuster grade, bars, grain, slow dissolves",
            prompt: "Make my edit feel more cinematic: apply the Blockbuster template, keep my cuts as they are, add subtle film grain and widescreen bars, and use slow dissolves only where time passes.")),
        ("Style & sound", PromptIdea(emoji: "📼", title: "Retro VHS look", subtitle: "Tape bleed, scanlines, date stamp",
            prompt: "Give my film a retro VHS home-video look: tape colour bleed, scanlines and a little glitch on the cuts, a camcorder-style date stamp in the corner, and music from the Retro category.")),
        ("Style & sound", PromptIdea(emoji: "🌅", title: "Golden hour warmth", subtitle: "Warm light leaks and sun rays",
            prompt: "Give my film a golden hour feel: warm grade with soft glow, subtle light leaks on a couple of dissolves, and a gentle sun-rays overlay in the quiet parts. Keep it subtle.")),
        ("Style & sound", PromptIdea(emoji: "🔤", title: "Add a title sequence", subtitle: "Opening title, places, closing line",
            prompt: "Add a tasteful title sequence: an opening title in the cinematic wide style on the first calm shot, lower-third place names where it makes sense, and a short closing line over the last shot. Ask me for the title text if you can't tell what it should say.")),
        ("Style & sound", PromptIdea(emoji: "🔊", title: "Clean up the sound", subtitle: "Levels, silences, noise, music ducking",
            prompt: "Clean up the sound of my film: normalise the clips that have speech, remove long silences in talking clips, reduce noise where it is noisy, and make the music duck under speech and clip sound. Tell me what you changed.")),
        ("Style & sound", PromptIdea(emoji: "💬", title: "Add subtitles", subtitle: "Captions from the speech",
            prompt: "Add subtitles: transcribe the clips with speech, create captions in a clean readable style, and tell me if any part could not be transcribed.")),
        ("Style & sound", PromptIdea(emoji: "✨", title: "Surprise me", subtitle: "Creative freedom, short brief",
            prompt: "Surprise me. Look at my clips, decide what kind of film they want to be, tell me your idea in two sentences, then make it. Use whatever combination of look, music, titles and effects serves that idea, with restraint.")),
    ].map { ($0.0, $0.1) }
}
