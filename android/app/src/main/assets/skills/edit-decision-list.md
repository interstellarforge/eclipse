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
