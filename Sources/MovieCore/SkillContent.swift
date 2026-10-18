// Our own director skills for editing real footage in Lumacut. Written for this editor's tools; the ideas
// (emotion first, quality gates, perception before judgement) are general film-editing craft.

enum SkillContent {
    static let all: [(name: String, summary: String, body: String)] = [
        ("director-brief",
         "START HERE for any creative request: intake, routing, workflow, principles and the working rules of this editor.",
         #"""
         # Director brief

         You are directing an edit, not just running commands. Decide what the viewer should FEEL, then pick the mechanics.

         ## 1. Intake
         Find out (ask at most two short questions, otherwise assume and say what you assumed):
         purpose and audience, the feeling to leave them with (one word), target length, where it will be watched (platform-formats).

         ## 2. Routing: read these skills when the task matches
         | Task | Skills |
         |---|---|
         | Understand what the footage contains | perceiving-footage |
         | A highlight reel, recap, aftermovie, "best of" | highlight-reel, then edit-decision-list |
         | Writing the cuts in one go (the main tool) | edit-decision-list |
         | Choose and order clips, set pace | story-and-pacing, shot-grammar |
         | Finding a FRESH idea, escaping the usual look | creative-thinking, then creative-toolbox |
         | CHOOSING a creative direction; what to add and what to leave out | creative-toolbox (read it before planning ANY creative film) |
         | Cuts, joins, transitions | transitions, shot-grammar |
         | Visual effects, zooms, glitch, glow, green screen | scene-effects |
         | Music, beat, sound effects, levels | rhythm-and-music, sound-design |
         | Titles, captions, lower thirds | titles-and-text |
         | Make clips look consistent or stylised | color-and-look |
         | Vertical / square / length targets | platform-formats |
         | The user wants to be asked step by step | guided-edit |
         | Before saying "done" | review-checklist |

         ## 3. Workflow (do all of it; the quality is in steps 1, 2 and 5)
         1. LOOK at every clip. get_project, then inspect_asset AND watch_asset on each video; transcribe_asset on clips with people talking. This takes several tool calls and that is the job. Never edit footage you have not seen.
         2. NOTE what you saw: per clip the best moment (start_ms-end_ms), what is in it, a score 1-5, whether its sound is worth keeping.
         3. TREATMENT first: read creative-thinking and creative-toolbox, call suggest_treatments, choose a direction, then PLAN the film like a director: hook, build, peak, breath, ending; the length of EVERY cut (they differ on purpose); where each transition and effect goes and why; the music; the sound per clip; titles. Tell the user the plan in a few lines.
         4. BUILD with build_edit (one undoable step). Do NOT use auto_movie for creative requests: it chains the busiest moments at equal lengths with one transition and never looks at the pictures. Use it only if the user explicitly wants a quick automatic cut.
         5. REVIEW with watch_timeline (4-6 frames per 10 seconds is plenty, or several sheets), and run review-checklist. Fix problems with the single-purpose tools (trim_clip, set_audio, update_transition ...), then report in two or three sentences.

                  ## 4. Principles
         - Every shot earns its place: it changes the emotion, moves the story or raises the pressure. Otherwise cut it.
         - Start late, leave early. Cut the slow beginning and the long goodbye of every clip.
         - A hard cut is the default. Every other transition needs a reason.
         - Contrast makes energy: alternate wide and close, still and moving, loud and quiet.
         - Restraint reads as quality: at most two transition styles, two fonts, one look per film.
         - Specific beats generic: choose the clip with the clear action or face, not the pretty empty landscape.

         ## 5. Working rules of this editor
         - All times are milliseconds. Clips on one track cannot overlap, except through a transition (the overlap makes the movie shorter by that amount).
         - The first track in get_project is the top layer. Titles are always drawn over video.
         - Work in small steps the user can undo. Do not delete or replace the user's clips unless asked.
         - After each phase look at the result with get_frame (2-3 key times) before continuing.
         - Say briefly what you changed and why. Mention any assumption.
         - Equal clip lengths and the same transition everywhere are the mark of a lazy edit. Vary them with purpose.
         """#),

        ("perceiving-footage",
         "How to actually look at clips: inspect, contact sheets, transcript, choosing moments.",
         #"""
         # Perceiving footage

         You can only edit well what you have seen. The tools give you eyes and ears; you do the judging.

         ## Order of looking
         1. inspect_asset(asset_id): duration, size, fps, audio, plus an activity curve, loudness, probable cuts and suggested best moments. Use it to decide where to look.
         2. watch_asset(asset_id): a contact sheet of evenly spaced frames with timestamps. Start with 12-16 frames for a whole clip.
         3. Drill down: watch_asset with start_ms / end_ms and more frames around moments that matter (a face, a jump, the end of an action).
         4. transcribe_asset(asset_id) when people speak. Speech decides cut points: cut between sentences, never mid-word, and keep the strongest line.

         ## What to note per clip
         - Subject and action in one line. Shot size (wide, medium, close). Camera: static, handheld, moving.
         - Best 2-6 second window (start_ms, end_ms) and why. Anything unusable (blur, shake, lens covered, someone else's face).
         - Sound: speech, laughter, wind noise, music, silence.
         - Mood and where it could sit in the story.

         ## Budget
         Contact sheets cost context. Do one sheet per clip first; only drill into the clips that will actually be used. For very long clips use the suggested moments from inspect_asset instead of scanning everything.

         ## Report back
         Keep a short shot list in your reply: clip name, best window, one-line description. It becomes the plan for story-and-pacing.
         """#),

        ("story-and-pacing",
         "Structure, clip selection, shot length and pacing for short videos.",
         #"""
         # Story and pacing

         ## Shape of a short film
         - HOOK (first 1-3 s): the most intriguing or beautiful moment, or a question. Never start on a slow establishing shot unless the mood is calm by design.
         - BUILD: show the situation, then escalate. Each beat should add something new.
         - PEAK: the strongest moment. Give it room: a pause just before it, and let it play a little longer than the others.
         - RESOLVE: one calm closing shot, a title or a payoff line. End while interest is still high.

         ## What to keep, what to cut
         Priority when choosing between clips (a classic order): emotion first, then story, then rhythm, then where the eye is looking, then the screen geometry. If a pretty shot hurts the emotion, drop it.
         Keep: faces reacting, hands doing something, clear cause and effect, moments of change. Cut: waiting, walking in, camera settling, repeats of the same information.

         ## Shot length (starting points, then trust the footage)
         | Mood | Typical shot length |
         |---|---|
         | Calm, scenic, emotional | 4-8 s |
         | Everyday storytelling, vlog | 2.5-4 s |
         | Energetic, sports, travel montage | 1-2.5 s |
         | Hype, trailer peak | 0.4-1 s |
         Vary on purpose. A montage often builds: shots get shorter toward the peak, then one long shot breathes after it.

         ## Pacing with this editor
         - trim_clip to the chosen window; split_clip to remove the dull middle; remove_clip with ripple to close gaps.
         - Total length = sum of clips minus transition overlaps. Check get_project duration against the target.
         - Move the funniest, most surprising or most moving clip to the peak, not the start (unless it is the hook).
         - If the whole thing feels slow, shorten every clip by ~15 % before changing anything else.
         """#),

        ("creative-thinking",
         "How to find a fresh idea for a film instead of the usual one: list the defaults, move away from them, test concepts, filter. Read before choosing a direction.",
         #"""
         # Creative thinking

         Language models drift to the most likely answer. For films that means the same look every time. This skill is a short procedure to leave the default on purpose. Method adapted from common ideation practice (diverge, then filter; rotate the frame; add a random constraint).

         ## 1. Name the default first (30 seconds)
         Write down, for this exact request, the film you would make without thinking: structure, joins, effects, title, music feel. Include the usual suspects (widescreen bars, grain, glow, crossfades, slow-motion hero shot, big title). That list is the thing to avoid, not the answer. Never use grain, cinema bars or glow because "it looks filmic".

         ## 2. Separate the need from the packaging
         The need: what must the viewer feel or understand, who is watching, how long. The packaging: every technique. Keep the need, throw away the packaging, then rebuild it from the footage you actually have.

         ## 3. Rotate the frame (pick two axes, answer each in one line)
         - WHO: whose point of view? A child, the dog, the host, a stranger, the camera operator.
         - WHEN: where does it start? At the end, at the quietest moment, mid-action, the day before.
         - SCALE: details and textures, or one wide patient shot, or only faces.
         - METHOD: sound-led, silent, graphic, rhythm from the footage's own motion, chaptered, split into two threads.
         - ORDER: chronological, by theme, by colour, by energy, backwards, a loop that ends where it began.

         ## 4. Diverge, then filter
         Write five different one-line concepts (not five variations of one). Use the treatments from suggest_treatments and the constraint cards as raw material. Then filter hard: drop any concept that looks like the default list from step 1; drop any the footage cannot support (check clip names, lengths, what the user told you or marked); score the rest on surprise, fit to the feeling, and doability with few tools. Keep ONE. Say it to the user in one sentence.

         ## 5. Obey the constraint cards
         suggest_treatments returns random constraint cards. Follow at least one. Constraints are how you reach ideas ordinary generation skips.

         ## 6. Light reasoning, not templates
         Do not fill the same plan template every time. Decide the shape from the idea: some films want few long shots, some a burst of short ones, some almost no graphics. Ask 'what would make a viewer lean in at second three, second fifteen, and the last shot?' and answer with the footage.

         ## 7. Stay restrained
         Creative is not busy. After choosing, apply the addition test from creative-toolbox: each effect, join, overlay or title must add something the plain cut cannot. Often the most creative move is the order and rhythm of the clips.
         """#),

        ("creative-toolbox",
         "The whole toolbox in one place (joins, effects, overlays, titles, looks, speed, templates) with when each ADDS something, a spice budget, and how to avoid making the same film twice.",
         #"""
         # Creative toolbox

         Imagination is not more effects. It is choosing a specific idea for THIS footage, then using few tools with intent. Two failures to avoid: sameness (every film gets the same arc, the same crossfades, the same title) and decoration (effects nobody asked for).

         ## 1. Pick a treatment BEFORE planning
         First read creative-thinking: name the default film for this request and move away from it. Then call suggest_treatments with a few mood words from the user's request and what you saw in the footage. You get three different directions. Choose one (or blend two), say which and why in one line. If the project already has a look, effects or a template (get_project), do not repeat it for a new film unless asked: take a different direction. Ignore a suggestion that does not fit the footage; invent your own if the footage asks for it.

         ## 2. Vary the shape, not only the style
         Different films need different structures. Choose one on purpose: cold open (best shot first, silence, title), cumulative build (cuts get shorter), rhythm montage (cuts on beats), parallel cutting (two threads alternating), match-cut chain (shape or motion rhymes), slow burn (few long shots), chaptered (a day, a place, a person at a time), question and payoff (tease, reveal at the end). The 30 s example in highlight-reel is a skeleton, never a template: change the lengths, the order of beats and the ending.

         ## 3. The catalog, with the test for each
         - JOINS (47, see transitions): the default is a hard cut. A join earns its place only when something changes (time, place, mood) or the camera already moves that way. At most two styles per film and a join on at most one cut in three.
         - SCENE EFFECTS (34, see scene-effects): camera moves (kenBurns, pan) for stills and static shots; texture (grain, vhs, lightLeak, cinemaBars) as ONE film-wide signature; impact (flash, shake, pulse, glitch, chromatic) on a real hit or beat only; blurIn/Out for focus pulls; stylise (posterize, duotone, comic, mirror) only when the concept is graphic; chromaKey/removeBackground when asked or the footage needs it.
         - OVERLAYS (19): confetti (a win, 3-4 s), snow, rain, sparkles, bokeh, dust, sunbeams, frame, hearts, fireflies, stars (night, endings), embers (fire, drama), petals (spring, weddings), bubbles (kids, summer), leaves (autumn), fireworks (finales, new year), smoke (mystery), streaks (cinematic polish), digitalRain (tech). Zero or one per film, 2-6 s, supporting the mood at one moment.
         - TITLES (27 styles; chapter and whisper for quiet films, statement and comic for loud ones, typewriter and news for documentary text, gold and signoff for endings, stamp and postcard for playful ones): the opening title names it (3 words), a lower third names a person or place the first time, a closing line ends it. One or two title styles per film. Match the style to the treatment (movie/wide for cinematic, handwritten for personal, neon for night, dateStamp for retro, impact for sport).
         - LOOKS (18 presets, set_look): one grade across the film so it feels like one piece; match shots to each other first. A look is a decision about mood: warm golden hour for memories, teal & orange for adventure, noir for tension, matte or clean for documentary.
         - TEMPLATES (list_templates): a whole style in one call. Use when the user asks for a style or wants a fast base; then adjust. Do not stack a template on top of manual effects.
         - SPEED (ramp_speed, set_speed): slow motion for the one moment that deserves it, a ramp into a beat drop, 2x for dull travel. Not on every clip.
         - SMART TOOLS: find_match_cuts when two shots rhyme; smart_reframe for vertical delivery.
         - SOUND EFFECTS: only when the user asks. Never by default.

         ## 4. Spice budget (per 30 seconds of film; more length allows proportionally more, never double)
         - Join styles: 2 maximum, on at most a third of the cuts.
         - Signature effect: 1 (film-wide) plus at most 2 impact moments.
         - Overlay: 0 or 1.
         - Speed changes: 0 to 2.
         - Titles: opening, optional lower thirds, closing; 3 to 4 total.
         - Anything beyond this needs a reason you can say in one sentence.

         ## 5. The addition test (ask for every effect, join, overlay, title)
         1. What does it add that the plain cut does not? (emotion, clarity, rhythm, a change of place)
         2. Would the film be worse without it? If not, leave it out.
         3. Does it match the treatment you chose? If not, it is decoration.
         Plain, well-timed cuts on strong shots beat decoration. When unsure, subtract.

         ## 6. Say what you did
         End with the treatment name, the structure, and the two or three choices that define it, in plain words. Offer one alternative direction the user can ask for next ("want it as a Noir cut instead?").
         """#),

        ("shot-grammar",
         "Continuity, shot sizes, jump cuts, reframing and speed for editing real footage.",
         #"""
         # Shot grammar for editors

         ## Shot sizes
         Wide = where, medium = who and what, close = how it feels, detail = what matters. A good sequence moves between sizes. Two neighbouring shots of the same size and angle of the same subject feel like a glitch (a jump cut).

         ## Cutting rules that save you
         - Change the size or angle noticeably (about 30 degrees or a size step) between shots of the same subject, or cover the join with a cutaway, a transition or a title.
         - Cut on action: end a shot in the middle of a movement and start the next one in the same movement. It hides the cut.
         - Keep screen direction. If someone moves left to right, the next shot should keep that direction unless you want to signal a turn.
         - Look direction: a person looking right wants an answer shot looking left, and what they look at should appear next.
         - Reaction after information: show the thing, then the face.
         - Match energy across a cut. Moving into still needs a reason.

         ## Tools you have to fix problems
         - Punch-in: set_transform scale 1.15-1.4 on part of a long shot makes a new shot size from one clip. Keep it modest or it looks soft.
         - Reframe: set_transform offset_x / offset_y after scaling to fix headroom or hide a distraction.
         - Slow motion: set_speed 0.4-0.6 on a short action (a jump, a splash, a smile) to stress it. Fast: 2-4x for boring travel or waiting. Slow speeds suit clips shot at 50-60 fps; at 25-30 fps keep it at 0.7 or above.
         - Sound bridge: detach_audio, then let the audio start before the picture (J cut) or continue after it (L cut) by moving the audio clip.
         - Cutaway: place a related detail on a higher layer (add_track kind video on_top) for a moment, with the main audio running underneath.

         ## Layers
         The first video track is the top layer. Use layers for picture-in-picture (set_transform scale 0.3, offsets toward a corner) and for cutaways.
         """#),

        ("transitions",
         "When to use each of the 47 transitions and how long they should be.",
         #"""
         # Transitions

         47 styles are available (list them with the Transitions tab, or see the table). Default is the hard cut (no transition). A transition is a statement; use it for a reason.

         ## Meaning
         | Transition | Use for |
         |---|---|
         | crossfade | passing time, gentle mood, joining two similar shots |
         | fadeBlack | end of a chapter or of the film, a heavy ending |
         | fadeWhite | memory, dream, bright flash, start of something new |
         | blurFade | dreamy, soft change of place |
         | pixelate, pixelDissolve | digital, glitchy, tech topics, playful |
         | wipe, wipeLeft, wipeUp, wipeDown, diagonalWipe | graphic, informative, travelling, "meanwhile" |
         | slide, slideRight, slideUp, slideDown | energetic montage, direction of travel matches the move |
         | whipLeft, whipRight | fast whip pan with motion blur: sports, travel, hype; hides a cut well |
         | cover, uncover, splitSlide | layered, modern; reveal a new scene |
         | zoom, zoomBlur | energy, going "into" something, pairs well with a beat |
         | spin, rotateZoom | playful or retro, use rarely |
         | irisOpen, irisClose, diamond | cartoon or old-film feel, a story opening or closing |
         | barnDoorH, barnDoorV, blinds, clock, barsSwipe | stylised, retro or playful; keep for fun projects |
         | glitchCut | digital shock cut for hype, tech, horror |
         | flashCut | a fast white flash on an impact or a beat drop |
         | modTransition, ripple | ring burst and water ripple: dreamy, magical, dream sequences |
         | pageCurl | memory book, album, wedding |
         | swirl | dreamy twist between two places, magical, time slip |
         | filmBurn | warm orange film-burn dissolve: nostalgia, memories, travel |
         | shutter | camera-shutter close and open: a chapter break with a beat of black |
         | cornerIris | circle growing from a corner: playful reveal, kids, comedy |
         | tvStatic | noise and jitter: retro tech, channel-flip, found footage |
         | squeeze | picture squeezes away sideways: graphic, modern cut-away |
         | cubeSpin | cube-like turn to the next scene: travel, slideshow with energy |
         | blindsV | vertical blinds: stylish reveal, interview breaks |
         | copyMachine | scanner light sweeps across: tech, documents, sci-fi |
         | flare | bright lens flare burst: celebration, sun, big reveals |

         ## Rules of thumb
         - Pick one main transition style for the film, at most one accent. Do not use a different one on every cut.
         - Length: fast edits 0.2-0.4 s, normal 0.5-0.8 s, slow or emotional 1-2 s. Never longer than half of the shorter clip.
         - Match the direction: a slide or wipe should travel the way the subject or camera moves.
         - Put dips (fadeBlack / fadeWhite) at structural points only, not between every pair.
         - Remember the overlap: add_transition makes the clips overlap, shortening the movie by the duration. For beat-synced edits keep durations equal.
         - update_transition changes style or length later; remove_transition restores the original timing.
         """#),

        ("rhythm-and-music",
         "Choosing music, cutting to the beat, levels and endings.",
         #"""
         # Rhythm and music

         ## Choosing music
         - Match the feeling first, tempo second. Calm travel: 70-95 BPM. Everyday upbeat: 100-125. Sports and hype: 125-150.
         - The built-in library (list_sounds) and the online search (search_online_sounds) offer free music. Check the licence note for online results and keep the credits.
         - Instrumental under speech; a track with a clear groove under montage.

         ## Cutting to the beat
         - In build_edit put music at start_ms 0 and choose cut lengths in beats (beat = 60000 / BPM ms); list_sounds shows the tempo of built-in beds. For imported music estimate the tempo by listening to the loudness curve from inspect_asset, or use a built-in bed.
         - By hand: beat length = 60000 / BPM ms. Cut on beat 1 of a bar when the picture changes scene, on beats 2-4 for smaller changes. A bar of 4 beats at 120 BPM is 2000 ms.
         - Long, calm shots can span 2 or 4 bars; energetic shots 1 bar or one beat.
         - Put the biggest change (peak, title reveal, drop) on a downbeat after a short pause.

         ## Levels and structure
         - Music alone: volume about 0.8-1.0. Under speech or video sound: about 0.15-0.3, and lower the original sound only when the music must lead.
         - Fade the music in over 0.5-1 s unless it starts on the first frame on purpose; fade out over 1.5-3 s at the end. set_audio handles volume and fades.
         - If the picture is longer than the music, trim the picture, do not loop badly. If shorter, fade out early.
         - Silence is a tool: drop the music for one beat before an emotional line or impact.

         ## Ending
         End with a clean cut on a beat, or with fadeBlack and the music tail. Never let music cut off mid-note.
         """#),

        ("sound-design",
         "Layers, levels, sound effects with picture, and sound bridges.",
         #"""
         # Sound design

         Good sound makes a cheap picture feel expensive.

         ## Layers
         1. Dialogue or key natural sound: always clear. 2. Ambience: continuous bed under cuts so they do not jump. 3. Effects: whooshes, hits, clicks that mark action. 4. Music.

         ## Levels (volume values in set_audio, 1 = original)
         | Layer | Level |
         |---|---|
         | Dialogue | 1.0 (lift quiet voices up to 1.5-2) |
         | Ambience | 0.2-0.4 |
         | Effects | 0.4-0.8, never louder than speech |
         | Music under speech | 0.15-0.3 |
         | Music alone | 0.8-1.0 |

         ## Techniques
         - Sound effects: ONLY when the user asks for them (a film or highlight reel does not get automatic whooshes or hits). If asked: a whoosh centred on a slide or wipe, a short hit on an impact, with add_sound_effect at the transition start.
         - Give every sound a fade of 20-100 ms at the ends to avoid clicks; ambience gets longer fades (0.5-1 s) when it changes.
         - Detach audio (detach_audio) from video clips to edit sound separately: lengthen it for a J/L cut, lower wind noise, or replace it with music.
         - When joining two clips with different background noise, crossfade their audio with a transition or hide the join under a sound effect.
         - Mute a whole track with set_track muted when a layer should be picture only.
         - Music under speech: set_track duck true on the music track (or music duck true in build_edit). The music dips to about a third while clip sound or a voice-over plays and returns after.
         - Quiet or loud clips: normalize_audio sets a standard level. Talking clips with long pauses: remove_silence cuts the quiet parts (it cuts the picture too, so cover jumps with a cutaway or a short crossfade).
         - Voice-over is recorded in the app (microphone button); you can place and level it like any audio clip.
         - Do not stack many effects: two well placed beat more than ten, and none beats two when nobody asked.
         """#),

        ("titles-and-text",
         "Typography, placement, timing and style for titles, lower thirds and captions.",
         #"""
         # Titles and text

         ## Timing
         - Reading time is about 0.3 s per word plus 1 s. A 3-word title: 2 s. A 10-word caption: 4 s. Titles under 1.5 s feel like mistakes.
         - Put titles on calm, simple parts of the picture. Start a title 0.3 s after a cut, not exactly on it.

         ## Placement (set_text_style: x from the left 0-1, y from the bottom 0-1, size as fraction of frame height)
         | Kind | size | x, y | align |
         |---|---|---|---|
         | Opening or centre title | 0.10-0.14 | 0.5, 0.5 | center |
         | Lower third (name, place) | 0.05-0.06 | 0.08-0.30, 0.12-0.16 | left |
         | Subtitle / caption | 0.04-0.05 | 0.5, 0.07-0.1 | center |
         | Corner tag | 0.035 | 0.9, 0.93 | right |
         Keep text out of the outer 5 % of the frame. For vertical video avoid the bottom 20 % where the app puts its interface.

         ## Readability
         - Contrast beats beauty: white text with shadow or outline, or turn on box on busy backgrounds.
         - One font family; bold for titles, regular for captions. Do not use more than two sizes in one scene.
         - Maximum two lines of about 32 characters each for captions.

         ## Ready-made styles (add_title preset)
         center, lowerThird, subtitle, impact (huge uppercase), neon (glowing cyan), minimal (airy uppercase), wide (cinematic wide tracking), movie (serif title), quote (italic), tag (corner tag), boxed, retro (yellow Impact), handwritten (typewriter), credits, dateStamp (bottom right), countdown (huge number). Override any detail with size, color, x, y, align, tracking, uppercase, glow, outline, box.

         ## Animation
         set_text_style animation: fade, slideUp, slideDown, slideLeft, pop or typewriter, with animation_ms (0.3-0.6 s is natural; typewriter 0.8-1.5 s). Titles also fade at the ends with fade_in_ms / fade_out_ms. One animation style per film.

         ## Subtitles
         auto_captions writes subtitles from speech onto a Captions track; export_srt saves them as .srt. Edit wrong words with set_title_text.

         ## Fades and layers
         Titles live on text tracks and sit above video. To fade a title use set_audio fade_in_ms / fade_out_ms on the title clip (fades apply to its opacity too), typically 0.3-0.5 s.
         """#),

        ("color-and-look",
         "Matching clips and choosing a look with set_look.",
         #"""
         # Color and look

         ## First: make clips belong together
         Compare the clips with watch_asset or get_frame. Brightness (-1..1), contrast (1 = normal) and saturation (1 = normal) in set_look. Pull the odd one out toward the group in small steps: brightness within +-0.15, contrast 0.9-1.2, saturation 0.8-1.3.

         ## Then choose one look for the film
         | Mood | Settings |
         |---|---|
         | Natural, honest | leave alone, only match |
         | Warm, nostalgic | sepia 0.2-0.4, contrast 0.95, saturation 0.9 |
         | Punchy travel | contrast 1.15, saturation 1.3 |
         | Dramatic | contrast 1.4-1.5, saturation 0.8, vignette 0.4-0.6 |
         | Soft, dreamy | blur 0.1-0.2, brightness +0.08 |
         | Memory or flashback | saturation 0-0.4 or sepia 0.8 |
         | Documentary, cool | saturation 0.8, contrast 1.1 |

         ## Rules
         - Apply the same settings to every clip of the same scene; vary between scenes only with a reason.
         - Subtle beats loud: stop when you first notice the effect.
         - A vignette of 0.2-0.4 focuses the eye without looking like a filter.
         - Black and white needs strong contrast (1.2-1.4).
         - Always look at the result with get_frame before and after.
         """#),

        ("platform-formats",
         "Aspect ratios, lengths and hooks per destination; set_format.",
         #"""
         # Platform formats

         Use set_format to choose the canvas before placing clips.

         | Destination | Canvas | Length | Notes |
         |---|---|---|---|
         | YouTube, web, TV | 16:9 (1920x1080) | any | titles anywhere in the safe 90 % |
         | Reels, TikTok, Shorts | 9:16 (1080x1920) | 15-60 s | hook in the first 1 s, text mid-upper, avoid the bottom 20 % |
         | Instagram feed | 4:5 (1080x1350) or 1:1 (1080x1080) | 15-60 s | keep key action centred |
         | Presentation, memory film | 16:9 | 1-5 min | slower pace, music-led |

         ## Reframing for another aspect
         Clips are fitted inside the canvas (with black bars). To fill a vertical canvas with landscape footage use set_transform scale about 2.2-3.2 and an offset to pick the subject. Check with get_frame; if the picture turns soft, choose shots with the subject centred.

         ## Export
         export takes a preset: youtube720, youtube1080, youtube4K, tiktok (9:16), instagramFeed (4:5), square. Clips are fitted inside the preset's frame, so set the canvas with set_format first when the film is not 16:9.

         ## Pace
         Vertical short-form: first shot under 2 s, cuts every 1-2.5 s, text early, loop-friendly ending. Long-form: let moments breathe, vary pace.
         """#),


        ("edit-decision-list",
         "The build_edit format: how to write all cuts, joins, sound, effects, titles and music in one go.",
         #"""
         # Edit decision list (build_edit)

         build_edit takes a list of cuts and builds the whole film in ONE undo step. Check everything first: nothing is applied if a field is invalid, and the error says what to fix.

         ## Shape
         ```
         {
           "replace": true,                      // needed when the timeline already has clips
           "canvas": "16:9",                     // optional: 16:9, 9:16, 1:1, 4:5
           "cuts": [
             {"asset_id": "...", "start_ms": 12000, "end_ms": 13400,   // the part of the SOURCE clip to use
              "sound": "mute",                                          // keep | mute | number 0..2
              "effects": [{"type": "kenBurnsIn", "amount": 0.5}]},
             {"asset_id": "...", "start_ms": 3000, "end_ms": 6200,
              "transition": "crossfade", "transition_ms": 600,          // the join with the PREVIOUS cut; default none = hard cut
              "speed": 0.5, "look": "Dramatic", "scale": 1.2, "offset_y": -0.05, "fade_in_ms": 200}
           ],
           "titles": [{"text": "Summer 2024", "start_ms": 300, "duration_ms": 2400, "preset": "center"}],
           "music": {"name": "Sunny Day", "volume": 0.7},
           "overlays": [{"kind": "sparkles", "start_ms": 5000, "duration_ms": 3000, "amount": 0.5}]
         }
         ```

         ## Timing rules
         - A cut's length on the timeline = (end_ms - start_ms) / speed. Cuts follow each other with no gaps.
         - A transition of d ms overlaps the previous cut's last d ms with this cut's first d ms, so the film gets d ms shorter. If you want the previous cut to keep its full visible length, add d to its range.
         - Titles, overlays and sfx at_ms use TIMELINE time. sfx at_cut uses the timeline start of that cut index (counting from 0) plus offset_ms.
         - sfx (sound effects) are only for when the user asks for them. A highlight reel, recap or film does NOT get automatic whooshes or hits: it gets music and the original sound, nothing invented.
         - The answer lists every cut with its timeline start and end, and the total. Use it to place titles and to check the length.

         ## Defaults
         - Sound: "keep" at volume 1 when there is no music; with music the clips default to 0.3 (music leads). Say "sound": 0.8 to keep a clip loud, or "mute".
         - Music: 0.6 volume, fades in and out, trimmed to the film length. Built-in beds are about 48 seconds.
         - Titles: preset center, 2.5 s, fades 0.3 s. Style fields (size, color, x, y, align, bold, shadow, outline, box) override the preset.
         - look: a preset name (Normal, Black & white, Sepia, Vivid, Faded, Dramatic, Dreamy) or an object {brightness, contrast, saturation, sepia, blur, vignette}.
         - effects: see scene-effects. transition names: see transitions.

         ## Habits of a good list
         - 6-16 cuts for a 30 s film. Lengths differ (hook short, peak cluster shortest, one long breath).
         - Every cut has a reason you could say in one line. Write the list only after step 2 of the director-brief.
         - Re-run build_edit with replace: true to try another version; the user can undo back to the first.
         """#),

        ("highlight-reel",
         "Recipe for a highlight reel / recap / best-of: how to pick moments and build the arc.",
         #"""
         # Highlight reel

         Goal: the feeling of the whole event in 20-60 seconds. A story with rhythm, not a slideshow.

         ## 1. Look
         inspect_asset and watch_asset every clip (perceiving-footage). Transcribe clips with talking. Use 12-16 frames per clip, then drill into candidates.

         ## 2. Rate moments (write a quick list)
         For each candidate moment (start-end ms): energy or emotion 1-5, clarity (subject visible, steady, well lit) 1-5, uniqueness 1-5, sound worth keeping yes/no. Keep roughly 1.3 times as many as you need and drop the weakest at the end.

         ## 3. Choose for variety
         Different subjects, places, shot sizes and movement. Never two near-identical shots in a row. One clip may supply several moments, but spread them.

         ## 4. Arc and lengths (a 30 s example: a skeleton, not a template. Take the structure of the treatment you chose from creative-toolbox and vary the lengths and order)
         - Hook, 1-2 s: the single most striking moment.
         - Build, 8-12 s: 2-3.5 s cuts, setting and people.
         - Peak cluster, 6-8 s: shortest cuts (0.8-1.6 s), strongest actions, effects, a speed change.
         - Breath, 3-5 s: one long calm or emotional shot (slow zoom).
         - Ending, 3-4 s: a quiet closing shot, closing title, fade to black.
         With music cut on beats: lengths in whole beats or half bars.

         ## 5. Joins
         Mostly hard cuts. A crossfade (0.5-0.8 s) for a change of time or place. A push, zoom or whip pan on the peak cluster. A flash effect on an impact. fadeBlack before the end. No more than two transition styles. No sound effects unless the user asks.

         ## 6. Sound
         Decide per clip: keep (speech worth hearing, laughter, a real impact or splash, crowd) or mute (wind, handling noise, mumbling). Under music keep wanted clips at 0.5-0.8 and lower the music (duck) or mute the clip. Silence for one beat before the peak is powerful.

         ## 7. Spice, with restraint
         Slow motion (speed 0.5) for the best action if the clip is smooth. 2x for boring travel. slow zoom on static shots and photos. A signature touch only if the chosen treatment has one (see creative-toolbox): none is a valid choice, and grain, glow and cinema bars together are NOT a default.

         ## 8. Titles
         One short opening title (3 words max), optional place or date lower third, a closing line.

         ## 9. Build and review
         build_edit, then watch_timeline. Fix the weakest moment first. Offer to export.
         """#),

        ("scene-effects",
         "Which scene effect to use when, strengths, and combinations (add_effect / effects in build_edit).",
         #"""
         # Scene effects

         Effects belong to a clip and animate over the clip's length. Use add_effect or the effects list in build_edit. amount is 0..1.

         ## Camera
         | Effect | Use | Amount |
         |---|---|---|
         | kenBurnsIn | slow push on static shots, photos, emotional close-ups | 0.4-0.7 |
         | kenBurnsOut | pull back for a reveal or ending | 0.4-0.7 |
         | panLeft, panRight | drift across wide scenery or a photo | 0.4-0.6 |
         | shake | impacts, explosions, rough action; short clips only | 0.3-0.6 |
         | pulse | hype montage on the beat, 1-3 s | 0.3-0.5 |

         ## Light and punctuation
         | Effect | Use |
         |---|---|
         | flash | the first frames of a cut that lands on a hit or drop (0.5-0.8) |
         | glow | warm, dreamy, sun, celebration (0.3-0.6) |
         | lightLeak | transitions between sunny scenes, nostalgia (0.4-0.6) |
         | cinemaBars | widescreen film feel, only for cinematic treatments (1.0); never on vertical video, never as a default |

         ## Texture and style
         | Effect | Use |
         |---|---|
         | grain | organic film feel under any look (0.25-0.5) |
         | vhs | retro, home-video, 90s (0.5) |
         | chromatic | tension, tech, dizzy moments (0.3-0.5) |
         | glitch | digital, sudden change, hype (0.4-0.7), briefly |
         | blurIn, blurOut | start or end a scene out of focus (0.5-0.8) |
         | posterize, duotone, comic | stylised sections or title backgrounds; one per film at most |
         | mirror | psychedelic or symmetric shots |
         | vignette | quiet polish: darker edges draw the eye (0.3-0.6); pairs with any look |
         | tiltShift | miniature look for aerial or city shots (0.5-0.8) |
         | punchIn | emphasis zoom at the start of a clip, on a beat or a spoken word |
         | dreamBlur | romantic haze, memories, soft endings (0.3-0.6) |
         | halftone, pixelate | graphic or playful moments, censoring (pixelate) |
         | neonEdges | glowing outlines, music visuals, sci-fi night |
         | invert | one-beat shock or dream-state flash; never for a whole clip |
         | kaleidoscope | psychedelic transition-like moment, 1-2 s |
         | fisheye | action-cam, skate, comedy |
         | strobe | club or concert burst; keep under 2 s |
         | dutchTilt | tension and unease; one or two shots at most |

         ## Overlays (drawn layers, add_overlay)
         confetti (parties, wins), snow (winter, calm), rain (moody), sparkles (magic, glamour), bokeh (dreamy night), dust (film dust and scratches, vintage), sunbeams (golden hour, hope), frame (white photo border, memories), hearts (love, weddings), fireflies (evening, fairy-tale). An overlay is a clip on a video layer above the picture: start_ms, duration_ms (2-6 s feels right), amount = density 0-1. Fade it with set_audio fade_in_ms / fade_out_ms. One overlay at a time; use them to support a mood, not to decorate.

         ## Green screen
         chromaKey removes a background colour (default 00FF00; pass color for blue or other). Put the keyed clip on a HIGHER video track than the background clip (add_track kind video on_top, then add_clip with track_id). Raise amount for stubborn edges, lower it if the subject turns transparent.

         ## Taste
         - One signature effect across the film; extras only on the peak.
         - Camera effects for rhythm, texture for mood, never everything at once.
         - Effects stack in the order added. Grain goes last.
         - After adding, look with watch_timeline or get_frame at the middle and end of the clip: effects animate.
         """#),


        ("stills-and-motion",
         "Photos, stickers, keyframe animation, crop and picture-in-picture: bringing still material to life.",
         #"""
         # Stills and motion

         ## Photos
         Photos import like clips (import_media works on JPG/PNG/HEIC). A photo clip is 4 s by default, can be stretched to a minute, and takes effects, looks and transitions like video.
         In build_edit a photo cut needs no start/end: give duration_ms (default 3000). Never leave a photo static for more than 2 s: add a slow zoom (effect kenBurnsIn or kenBurnsOut, amount 0.4-0.6) or pans.
         Mix photos and video with rhythm: photo 2-3 s, then a video cut. Vary kenBurns direction between consecutive photos (in, then out).

         ## Keyframes (set_keyframes, or keyframes inside a build_edit cut)
         Keyframes animate opacity, scale, offset_x, offset_y and rotation. time_ms counts from the start of the clip. Values glide between keyframes (smooth = eased) and hold after the last one.
         Recipes:
         - Punch-in on a beat: [{time_ms:0, scale:1}, {time_ms:300, scale:1.25}] on a longer clip.
         - Picture-in-picture entrance: scale 0.35 at the corner (offset_x 0.3, offset_y 0.28), keyframes from offset_x 0.6 to 0.3 over 400 ms.
         - Fade a layer in: opacity 0 to 1 over 500 ms.
         - Gentle drift: offset_x 0 to 0.03 over the whole clip.
         A clip with keyframes ignores its plain opacity/scale/offset values.

         ## Crop and reframe
         set_look crop_left / crop_right / crop_top / crop_bottom (0 to 0.9) trims the edges of a picture; the trimmed area shows the layer below. To fill a vertical canvas from landscape footage use set_transform scale 2-3 and an offset, not crop alone.

         ## Picture in picture and overlays
         Put the overlay on a HIGHER video track (add_track kind video on_top true), scale 0.25-0.4, offset toward a corner, with a slight inset from the edge (offsets up to 0.3). A reaction cam, a logo or a photo overlay all work this way.

         ## Stickers
         add_sticker puts an emoji on screen with a pop-in. Use 1-2 per film, on the peak or a joke. Move with set_text_style x / y, size 0.12-0.3.

         ## Green screen
         See scene-effects: chromaKey on the upper track.
         """#),


        ("guided-edit",
         "Interview mode: ask the user step by step (analyse clips? theme? length? music? pace?) before building.",
         #"""
         # Guided edit (interview mode)

         Use this when the user starts a guided edit (their message begins with [GUIDED EDIT]) or asks you to walk them through it. Run a short interview with ask_user, ONE question per call, and wait for each answer. Do not touch the timeline until the plan is confirmed (step 10).

         ## Rules
         - One question at a time, one short sentence, 2-5 options. Give every option as {label, info}: info is one or two sentences saying what the choice means and what you will do differently in the edit (the user reads it on hover). Put your recommendation first and label it "(recommended)".
         - Never ask what you can find out yourself: look at get_project first (how many clips, their length, whether there is sound, what is already on the timeline).
         - Skip questions the user already answered in their first message.
         - Accept typed answers ("allow_text" is on by default).
         - If an answer is vague, make a sensible choice and say so; do not interrogate.

         ## Questions, in this order
         1. Footage: "Should I analyse all N clips?" Yes, all (recommended) / Only the clips I select / Skip analysis, use the file names. If yes: run inspect_asset and watch_asset on each, transcribe_asset on clips with speech, and share a one-line impression per clip.
         2. Purpose: "What is this film for?" Highlight reel / A story with a beginning and an end / Social media short / Memory film for family / Promo or advert.
         3. Theme and mood: Cinematic / Energetic / Emotional / Fun and playful / Calm and scenic / Documentary. Suggest the 2-3 templates that fit (list_templates) and ask if they want one.
         4. Length and format: 15 s / 30 s (recommended for a reel) / 60 s / 90 s, and 16:9, 9:16 or 1:1 (platform-formats).
         5. Music: Pick the best fit for me (recommended) / Show me 3 options / No music / I will use my own file. If "show options": name three songs from list_sounds with their mood and tempo, as options of a follow-up question.
         6. Pace: Fast and punchy / Balanced / Slow and emotional.
         7. Joins: Mostly hard cuts / Smooth dissolves / Dynamic mix with a signature transition.
         8. Titles: No titles / Opening title and closing line / Opening title and place lower thirds. Ask for the title text if wanted.
         9. Sound of the clips: Keep original sound where it is good (recommended) / Mute the clips under the music / Ask me per clip. Never add sound effects unless the user asks for them.
         10. Confirm: summarise the plan in five lines (structure, length, template or look, music, joins, titles) and ask: "Build it?" Build it / Change something / Cancel.

         ## After the build
         Review with watch_timeline (director-brief step 5), then ask "How does it feel?" with: Love it / Make it faster / Make it calmer / Different music / Change the look / Something else. Apply the change and ask again until they are happy. Offer export last.
         """#),

        ("review-checklist",
         "Quality gate to run before saying a cut is finished.",
         #"""
         # Review checklist (quality gate)

         Run this before reporting done. Fix what fails, then report in 2-3 sentences.

         ## Look (get_frame at the start, ~25 %, 50 %, 75 % and the last second)
         - [ ] First frame is interesting (hook) and not black unless intended.
         - [ ] No unintended black frames or gaps between clips (get_project: each clip starts where the previous one ends, minus transition overlaps).
         - [ ] Titles are readable, inside the safe area, long enough to read.
         - [ ] Looks are consistent: no clip clearly brighter, darker or more colourful than its neighbours.
         - [ ] Transitions follow the style rule: one main style, a reason for any accent.

         ## Listen (check volumes in get_project / set_audio values)
         - [ ] Speech is the loudest layer; music is ducked under it.
         - [ ] Music starts and ends cleanly (fades), no hard cut-offs.
         - [ ] No two sound effects fighting; no overlapping speech by accident.

         ## Story
         - [ ] Hook, build, peak, resolve are all there; the peak is not at the start.
         - [ ] Every clip earns its place; the weakest clip is cut or shortened.
         - [ ] Length matches the target within ~10 %.

         ## Housekeeping
         - [ ] Nothing selected-by-accident deleted; the user's originals are untouched (clips only reference files).
         - [ ] save_project if the user asked, export only when asked or when the checklist passes and the user wants a file.
         - [ ] Mention assumptions and one suggestion for improvement.
         """#),
    ]
}
