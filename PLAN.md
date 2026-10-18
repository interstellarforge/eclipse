# Movie Maker — Plan (native macOS)

Free, local video editor, macOS only. Claude controls it via MCP. Includes GoPro-style auto-movie.

## Decisions
- Native Swift + SwiftUI/AppKit, AVFoundation + Metal. No webview, no FFmpeg (Tauri/Rust plan dropped: macOS-only makes it pointless).
- Claude link: MCP server embedded in the app.
- MVP: import, multi-track timeline, transitions, text/titles, audio (SFX, volume, fades), MP4 export, auto-movie.
- Build: SwiftPM (`swift build`). Only Command Line Tools installed (no Xcode) → no XCTest/Swift Testing; core checks run as `swift run CoreChecks`. Install Xcode before packaging a signed `.app`/`.dmg` and for Metal shader precompile (until then compile shaders at runtime from source).

## Architecture

```
SwiftUI/AppKit UI ──┐
                    ▼
        MovieCore: Project model + Command layer + undo  ◄── MCP server (same commands)
                    │
     ┌──────────────┼───────────────────┐
     ▼              ▼                   ▼
  Import/analysis  Composition builder   Export
  (AVAsset, thumbs, (AVMutableComposition (AVAssetExportSession /
  waveform, scene)  + AVVideoCompositing   AVAssetWriter, H.264/HEVC)
                    w/ Metal transitions)
```

**Core rule:** `Project` is a Codable value type owned by `Editor`. Every edit is a `Command` (add/move/trim/split/remove clip, transitions, volume/fades, …) applied atomically with undo/redo. UI and MCP both call `Editor.apply`.

**Preview = export:** one `AVMutableComposition` + custom `AVVideoCompositing` (Metal: crossfade/wipe/slide, text) feeds both `AVPlayer` preview and export. Audio via `AVAudioMix` (volume ramps = fades).

## Phases
0. **Scaffold** ✅ — SwiftPM package, `MovieCore` (model, commands, undo), `CoreChecks`, empty SwiftUI window.
1. **Import + timeline** ✅ (built, UI untested by hand; waveforms deferred) — import via AVAsset, thumbs/waveforms, asset bin, timeline view (drag, trim, split, snap, zoom), AVPlayer preview from composition.
2. **Export v1** ✅ (AVAssetExportSession; no progress bar yet) — cuts only → MP4.
3. **Transitions + text** ✅ (Core Image compositor, not Metal; UI untested by hand) — custom compositor, Metal shaders, title overlays.
4. **Audio** ✅ (volume, fades, synthesized SFX; ducking NOT done; UI untested by hand) — audio tracks, SFX library (CC0), volume/fades/ducking.
5. **MCP server** ✅ (hand-rolled streamable-HTTP, no SDK; localhost:39127 + token; 17 tools; not yet tried with real Claude) — Swift MCP SDK (or minimal JSON-RPC over localhost HTTP); tools = commands + read tools (`get_project`, `get_frame` so Claude can see clips). Token-protected, localhost only.
6. **Auto-movie** ✅ (motion+loudness scoring, beat-synced cuts, music; GoPro HiLight tags NOT read; UI untested by hand) — per-clip scene/motion/audio-energy scoring (AVAssetReader, Accelerate), GoPro HiLight tags (MP4 metadata), target length, optional beat-synced music; emits normal commands so it stays editable.
7. **Polish** ✅ — .moviemaker save/open, recovery autosave, `scripts/bundle.sh [dmg]` (ad-hoc signed; notarization still needs Xcode + Apple Developer account).

## Risks
- Custom `AVVideoCompositing` + multi-layer perf/correctness — spike in phase 1/3.
- Timeline UI is the biggest chunk; keep features tight (≤6 transitions).
- AVFoundation formats: MP4/MOV/HEVC/H.264 only (covers GoPro/iPhone); MKV etc. out of scope.
- No Xcode: no unit-test framework, no Metal offline compile, no signing yet.

## Not in MVP
Keyframes, color grading, speed ramps, Windows/Linux, in-app Claude chat.

## Later additions
- UI: sidebar tabs (Files/Transitions/Titles/Audio), inspector, waveforms, layers, detach audio, 23 transitions, speed, looks, text styling, track mute/hide, library delete.
- Claude chat panel (right column, "Claude" tab): runs the installed `claude -p` per message (stream-json, `--resume` for follow-ups), only the `movie-maker` MCP tools allowed (`--tools ""`), user's own Claude login. Live test: `CLAUDE_E2E="prompt" swift run CoreChecks` with the app running.
- Director skills (own text, `Sources/MovieCore/SkillContent.swift`, 11 guides) served over MCP (`list_skills`/`get_skill`), listed in the chat's system prompt; user skills in `~/Library/Application Support/MovieMaker/skills/*.md`.
- Perception for Claude: `inspect_asset`, `watch_asset` / `watch_timeline` (labelled contact sheets), `transcribe_asset` (Apple Speech, needs the .app + permission; untested).
- Free library: 12 synthesized SFX, 6 synthesized music beds (known BPM), online search via Openverse (CC0/PDM, optional CC BY) with credits tracking.
- Chat history (JSON per chat in Application Support/MovieMaker/chats), canvas format (16:9, 9:16, 1:1, 4:5; 24/30/60 fps).
- Director mode: `build_edit` (edit decision list, one undo step), skills rewritten so Claude must look (inspect/watch/transcribe), plan and build; `auto_movie` is labelled a quick mechanical pass. Live-tested: Claude read the skills, inspected and watched every clip, built the edit, reviewed it with `watch_timeline`.
- Scene effects (22 incl. green screen; remove-background is experimental), 23 transitions, keyframes, crop, photos (as still videos), stickers, animated titles, groups, track lock/duck, auto ducking, normalize, silence removal, noise reduction (simple), auto captions + SRT, voice-over, export profiles/presets/batch with progress and cancel, templates, relink, stock photos.
- Not done: motion tracking. Untested by me: UI by hand, voice-over (mic permission), auto captions (speech permission), in-app online downloads (sandbox blocked network), remove-background on a real person.

## Phase 3 (UI overhaul + features)
- UI: top bar, SF-symbol nav rail (compact/expanded), media grid, right tabs (Assistant/Adjust/Effects/Inspector), resizable/hideable panels, timeline follows playhead, click/drag seek, scroll-scrub on preview, waveform scales with volume, context menus + info sheet, Edit/Clip menus.
- Core: ducking, 37 transitions, 16 titles, 10 overlays, 40 songs, 34 templates, speed ramps, match cuts, smart reframe, ask_user (guided edits), Ghost Edit.
- Verified by NewChecks + CoreChecks; UI only via snapshots (`MovieMaker --snapshot <dir>`).
- Unverified: live UI by hand, voice-over/mic, auto captions permission, in-app online downloads, remove-background on people, ask_user long waits.
