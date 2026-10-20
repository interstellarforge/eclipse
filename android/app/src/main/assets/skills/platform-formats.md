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
