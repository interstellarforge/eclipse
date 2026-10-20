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
