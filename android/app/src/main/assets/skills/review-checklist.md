# Review checklist (quality gate)

Run this before reporting done. Fix what fails, then report in 2-3 sentences.

## Look (get_frame at the start, ~25 %, 50 %, 75 % and the last second)
- [ ] First frame is interesting (hook) and not black unless intended.
- [ ] No unintended black frames or gaps between clips (get_project: each clip starts where the previous one ends, minus transition overlaps).
- [ ] Titles are readable, inside the safe area, long enough to read.
- [ ] Looks are consistent: no clip clearly brighter, darker or more colourful than its neighbours.
- [ ] Transitions follow the style rule: one main style, a reason for any accent.

## Listen (check volumes in get_project / set_audio values)
- [ ] Speech is the loudest layer; music is ducked under it.
- [ ] Music starts and ends cleanly (fades), no hard cut-offs.
- [ ] No two sound effects fighting; no overlapping speech by accident.

## Story
- [ ] Hook, build, peak, resolve are all there; the peak is not at the start.
- [ ] Every clip earns its place; the weakest clip is cut or shortened.
- [ ] Length matches the target within ~10 %.

## Housekeeping
- [ ] Nothing selected-by-accident deleted; the user's originals are untouched (clips only reference files).
- [ ] save_project if the user asked, export only when asked or when the checklist passes and the user wants a file.
- [ ] Mention assumptions and one suggestion for improvement.
