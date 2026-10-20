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
