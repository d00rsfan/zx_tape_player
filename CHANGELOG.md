# Changelog

All notable changes to this project are documented in this file.
The format loosely follows [Keep a Changelog](https://keepachangelog.com/),
and the project adheres to [Semantic Versioning](https://semver.org/).

## v1.4.2 - Moonlight Drive

### New Features
- **Settings** — new item in the player's overflow menu opens a dedicated settings screen with two choices on launch:
  - **Audio filter** — pick how the TAP/TZX signal is shaped before output: *Bass boost* (default, the previous behaviour: peak around 250 Hz to thicken low frequencies — recommended for loading into a real ZX Spectrum), *None* (pure square wave, no post-processing — alternative for loading into a real ZX Spectrum if Bass boost fails), *Sine* (smooth sinusoidal pulses with minimal harmonic content — recommended for re-recording to magnetic tape) or *Tapir* (analog microphone-circuit simulation; mostly legacy — useful for tapes with non-standard data formats such as generalized data blocks, and the slowest to convert). The currently playing tape rewinds to the start and switches over immediately; the converted WAV is cached per filter so flipping back is instant.
  - **Reset settings to default** — restores the audio filter to *Bass boost* and the system playback volume to maximum.

### Improvements
- WAV cache filenames now include the audio filter, so changing the filter never replays stale audio from a previously cached conversion.
- Bumped `zx_tape_to_wav_x` to 1.2.0, which adds the *Sine* filter and fixes block-time offsets and an off-by-one sample at the start of every WAV produced with a buffered filter (*Tapir*, *Sine*).

### Bug Fixes
- Long-pressing the file name to save a tape to **Downloads/ZX Tape Player/** now works on every supported Android version. The v1.4.0 MediaStore migration silently broke the feature on Android 7–10 — `media_store_plus` falls back to legacy file I/O on API ≤ 29, but the `WRITE_EXTERNAL_STORAGE` permission and `requestLegacyExternalStorage` manifest flag had been removed along with the old storage path. Both are restored, scoped to `maxSdkVersion="29"` so Android 11+ never sees a runtime permission prompt and keeps using scoped `MediaStore.Downloads`. The success toast also failed to fire on Android 11+ when a same-named tape already existed and got auto-suffixed (e.g. `Game (1).tap`) — that auto-rename is now correctly treated as a successful save. Real failures (no network, permission denied) now surface a red error snackbar instead of vibrating into silence. Removed the bogus `READ_INTERNAL_STORAGE` entry from the Android manifest.

## v1.4.1 - Horse Latitudes

### New Features
- **Tips** — new item in the player's overflow menu opens a built-in guide to features that are easy to miss: swiping between alternative tape versions, long-pressing the file name to save a tape to Downloads, the tape-block list and skip controls, Stop's auto-rewind, and the speed slider's tape-recorder pitch. Translated across all 12 supported languages.

### Improvements
- The player's overflow menu is now always available — including for tapes not recognised by the ZXInfo database (e.g. save states or custom dumps), so the new Tips entry is reachable from any tape. Share and Open-in-browser still appear only when the tape is identified, since both need a ZXInfo entry.

## v1.4.0 - Unhappy Girl

### New Features
- **Cross-platform desktop releases** — first-time Linux (`.deb` / `.rpm`) and Windows (`.zip`) builds, with macOS (`.dmg`) joining the lineup. Audio on Linux/Windows is powered by libmpv via `media_kit`; macOS keeps its native AVAudio path.

### Improvements
- Android: downloaded tapes now save to the phone's public **Downloads/ZX Tape Player/** folder so any file manager can find them — previously they were tucked away under the app-private `Android/data/io.github.d00rsfan.zx_tape_player/files/` path.
- Android: storage-permission prompt removed — the app uses the modern scoped MediaStore API instead of the legacy `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` permissions, which are no longer requested at install or runtime.
- Updated download success message ("Tape saved to your Downloads folder.") translated across all 12 supported languages.

### Note
Tapes saved by previous versions still live in the old per-app folder; only new downloads land in the public Downloads folder.

## v1.3.3 - Love Me Two Times

### Bug Fixes
- Edge-to-edge display modernised for Android 15 — switched to `enableEdgeToEdge()` in the host activity and removed the deprecated `Window.setNavigationBarColor()` code path, fixing the Play Console warnings about deprecated edge-to-edge APIs and inconsistent edge-to-edge rendering on older Android versions.
- Pressing Enter on an external keyboard now submits the search query, matching the search-icon tap (previously the keystroke was swallowed by the suggestions overlay when no suggestion was highlighted).

## v1.3.2 - You're Lost Little Girl

### Improvements
- **Adjust speed** redesigned as a bottom sheet — finer 0.01 step, ± nudge buttons flanking the slider, uniform track on both sides of the thumb (no more "progress-bar fill-to-here" look), and an expanded preset list (0.33, 0.5, 0.9, 1.0, 1.05, 1.1, 1.15, 2.0, 3.0).
- Transport controls laid out symmetrically — the stop icon now matches the other transport icons in size, so the play button sits naturally centered.
- Volume level is now remembered across sessions and restored on the next playback.
- Updated dependencies.

### Note
Android application id was renamed to `io.github.d00rsfan.zx_tape_player` to satisfy Play Market package-uniqueness requirements. Android will therefore treat this as a new app rather than an update — you may need to uninstall the previous version before installing v1.3.2.

## v1.2.0

This release is dedicated to the memory of:
Cozy Powell
Ronnie James Dio
Geoff Nicholls
Ozzy Osbourne

### New Features
- **Tape Block Browser** — new bottom sheet listing all tape blocks (headers, data, tones, pauses) with their time offsets; tap any block to seek playback directly to that position.

### Improvements
- Edge-to-edge display support — all screens now respect safe areas on Android 15+.
- Switch to `zx_tape_to_wav_x` fork for tape-to-WAV conversion.
- Updated copyright information across all 12 languages.
- Updated dependencies.

### Bug Fixes
- Show full metadata (year, genre, scores, authors, screenshots) and context menu (open in web, share) for local files recognized by the ZXInfo API.
- Rename package to `io.github.d00rsfan.zxtapeplayer`.

### Note
Due to the package rename, Android will treat this as a new app rather than an update. You may need to uninstall the previous version before installing v1.2.0.
