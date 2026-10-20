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
