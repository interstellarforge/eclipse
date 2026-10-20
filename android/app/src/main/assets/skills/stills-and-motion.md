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
