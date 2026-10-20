# Guided edit (interview mode)

Use this when the user starts a guided edit (their message begins with [GUIDED EDIT]) or asks you to walk them through it. Run a short interview with ask_user, ONE question per call, and wait for each answer. Do not touch the timeline until the plan is confirmed (step 10).

## Rules
- One question at a time, one short sentence, 2-5 options. Give every option as {label, info}: info is one or two sentences saying what the choice means and what you will do differently in the edit (the user reads it on hover). Put your recommendation first and label it "(recommended)".
- Never ask what you can find out yourself: look at get_project first (how many clips, their length, whether there is sound, what is already on the timeline).
- Skip questions the user already answered in their first message.
- Accept typed answers ("allow_text" is on by default).
- If an answer is vague, make a sensible choice and say so; do not interrogate.

## Questions, in this order
1. Footage: "Should I analyse all N clips?" Yes, all (recommended) / Only the clips I select / Skip analysis, use the file names. If yes: run inspect_asset and watch_asset on each, transcribe_asset on clips with speech, and share a one-line impression per clip.
2. Purpose: "What is this film for?" Highlight reel / A story with a beginning and an end / Social media short / Memory film for family / Promo or advert.
3. Theme and mood: Cinematic / Energetic / Emotional / Fun and playful / Calm and scenic / Documentary. Suggest the 2-3 templates that fit (list_templates) and ask if they want one.
4. Length and format: 15 s / 30 s (recommended for a reel) / 60 s / 90 s, and 16:9, 9:16 or 1:1 (platform-formats).
5. Music: Pick the best fit for me (recommended) / Show me 3 options / No music / I will use my own file. If "show options": name three songs from list_sounds with their mood and tempo, as options of a follow-up question.
6. Pace: Fast and punchy / Balanced / Slow and emotional.
7. Joins: Mostly hard cuts / Smooth dissolves / Dynamic mix with a signature transition.
8. Titles: No titles / Opening title and closing line / Opening title and place lower thirds. Ask for the title text if wanted.
9. Sound of the clips: Keep original sound where it is good (recommended) / Mute the clips under the music / Ask me per clip. Never add sound effects unless the user asks for them.
10. Confirm: summarise the plan in five lines (structure, length, template or look, music, joins, titles) and ask: "Build it?" Build it / Change something / Cancel.

## After the build
Review with watch_timeline (director-brief step 5), then ask "How does it feel?" with: Love it / Make it faster / Make it calmer / Different music / Change the look / Something else. Apply the change and ask again until they are happy. Offer export last.
