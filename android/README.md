# Eclipse for Android

Native Kotlin + Jetpack Compose port of the macOS app. Media3 for preview/export. Assistant calls the Claude API directly (API key in assistant settings).

## Build

JDK 21, Android SDK 36 (`local.properties` → `sdk.dir`).

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
./gradlew assembleDebug          # app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest      # 24 JVM tests
```

minSdk 26. Exports go to Movies/Eclipse (MediaStore).

## Parity

| Area | Status |
|---|---|
| Project model, undo/redo, save/open/recovery | done (same JSON fields as macOS) |
| Timeline (zoom, drag, trim, split, menus, waveform) | done |
| Media import, view modes, Files (SAF folders) | done |
| Titles (27), overlays (19), effects (34), looks (18), templates (35), music library (47) | done |
| Transitions | 47 styles listed; rendered as 5 families (dissolve, dip, push, zoom, spin) |
| Export H.264/AAC | done |
| Assistant: ~50 tools, skills (18), treatments, offline mode, script modes, ask_user/request_selection/propose_script | done |
| Voice-over | implemented, untested |
| Sound-effects library, online sounds | not ported |
| auto_movie, auto captions/transcribe, remove silence, normalize, denoise | not ported |
| Match cuts, smart reframe | not ported (centre-crop "Make vertical" only) |
| Codex/OpenCode agents | n/a on phone |
| Animated effect previews, resizable panels | not ported |

## Known limits

- Emulator preview lags (software GL); not confirmed on device.
- Only vignette, Ken Burns, chromatic, look shaders visually checked; other effects/transitions unchecked.
- Claude API path tested against MockWebServer only.

Debug build only: `SpikeActivity` (headless export spike) and demo intent (`--ei demo N`).

## Updates (GitHub Releases)

Installed apps check `interstellarforge/eclipse` releases tagged `android-v<versionCode>` (daily on launch, or menu → Check for updates), download the `.apk` asset, verify its SHA-256 and open Android's installer. First time: allow "Install unknown apps" for Eclipse.

Publish: `scripts/publish-android.sh "what changed"` (bumps `android/version.properties`, builds a signed release, creates the release; commit the version file afterwards).

Signing key: `~/.eclipse/eclipse-release.jks` + `keystore.properties` (outside the repo). Back it up: a build signed with another key cannot update installed apps.
