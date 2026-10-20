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
