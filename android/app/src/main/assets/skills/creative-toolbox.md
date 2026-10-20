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
