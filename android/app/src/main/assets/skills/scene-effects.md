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
