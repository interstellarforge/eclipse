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
