# Changelog

All notable changes to this project are documented in this file.
The format loosely follows [Keep a Changelog](https://keepachangelog.com/),
and the project adheres to [Semantic Versioning](https://semver.org/).

## v1.5.0 - My Eyes Have Seen You

### New Features
- **ZX81 support** — the app now plays ZX81 `.p` tape images and their identical `.81` variant, plus `.p81` images whose embedded tape name precedes the memory image. Files can be selected directly or from inside a `.zip` archive. They are converted to the authentic ZX81 tape signal: no pilot tone, each bit a burst of pulses closed by a silence gap, with 2 s of lead-in silence. For `.p`/`.81`, the program name is derived from the host filename; `.p81` preserves its embedded name. The tape is shown as a single `Program` block, and all four audio filters apply.
- **ZX80 support** — `.o` images and their identical `.80` variant now play locally and from `.zip` archives. The memory image is trimmed at its E_LINE pointer and emitted with the authentic ZX80 pulse encoding, without adding a ZX81-style filename.
- **Model-specific catalogue** — Settings now lets you choose ZX Spectrum (the default), ZX81, or ZX80. ZXInfo searches and remote downloads request `.tap`/`.tzx` files for Spectrum, `.p`/`.81`/`.p81` files for ZX81, and `.o`/`.80` files for ZX80.

### Improvements
- Settings is now available from the home/search screen, before a catalogue search starts. Its home-screen menu shows only Settings and Tips; tape-specific share and export actions remain in the player. Changing the model opens a fresh search with its query cleared, so results from the previous machine cannot linger.
- Catalogue searches now ignore malformed screenshot entries from ZXInfo instead of discarding an otherwise valid result page. This handling is shared by all supported models.
- Generic `.zip` downloads inside ZX81 or ZX80 catalogue directories are now offered even when the archive filename does not include `.p` or `.o`; the downloaded archive contents remain validated before playback.

### Bug Fixes
- Direct `.tap` files convert and play again. Conversion workers now receive an isolate-safe request instead of live service and stream-controller objects, while progress updates are relayed through a send port.

### Maintenance
- Updated `audio_session` to 0.2.4 for Android Gradle Plugin 9 compatibility and Built-in Kotlin migration support.

## v1.4.3 - People Are Strange

### New Features
- **Search by publisher** — start a search with a SPACE to look up tapes by publisher instead of title: the suggestion list completes publisher names from the ZXInfo database, and picking one (or just submitting the query) lists every compatible tape from that publisher, sorted by title. Hints on the home screen and on the not-yet-searched search screen explain the trick, and a new first entry in Tips documents it too. Translated across all 12 supported languages.

### Improvements
- Search results now show each tape's publisher after the year and genre.

### Maintenance
- Dependencies refreshed; the discontinued `sound_mode` package was replaced by its maintained successor `sound_mode_advanced`.
- Android edge-to-edge compliance for the Play Console deprecation warnings (proper `enableEdgeToEdge()` styling and display-cutout handling on Android 11+).
- Toolchain: Flutter 3.44 / Dart 3.12, Gradle 8.14.3, AGP 8.13.0, Kotlin 2.3.20, Java 21; Gradle-9-ready build scripts.
- CI/packaging: signed APKs are now attached to GitHub releases, and the Linux AppImage bundles libmpv with a self-containment check.

## v1.4.2 - Moonlight Drive

### New Features
- **Export** — new item in the player's overflow menu opens a bottom sheet with export options: *Tape image* (the raw `.tap` / `.tzx` file, extracted from the archive if the source is a `.zip`), *Original archive (.zip)* (shown only when the source is a `.zip` — saves the archive as-is), and *Audio (WAV)* (the converted WAV file with the current audio filter applied; available once conversion is complete). On Android/iOS/macOS the system share sheet is used; on Linux/Windows a native Save As dialog appears instead.
- **Settings** — new item in the player's overflow menu opens a dedicated settings screen with two choices on launch:
  - **Audio filter** — pick how the TAP/TZX signal is shaped before output: *Bass boost* (default, the previous behaviour: peak around 250 Hz to thicken low frequencies — recommended for loading into a real ZX Spectrum), *None* (pure square wave, no post-processing — alternative for loading into a real ZX Spectrum if Bass boost fails), *Sine* (smooth sinusoidal pulses with minimal harmonic content — recommended for re-recording to magnetic tape) or *Tapir* (analog microphone-circuit simulation; mostly legacy — useful for tapes with non-standard data formats such as generalized data blocks, and the slowest to convert). The currently playing tape rewinds to the start and switches over immediately; the converted WAV is cached per filter so flipping back is instant.
  - **Reset settings to default** — restores the audio filter to *Bass boost* and the system playback volume to maximum.

### Improvements
- WAV cache filenames now include the audio filter, so changing the filter never replays stale audio from a previously cached conversion.
- Bumped `zx_tape_to_wav_x` to 1.2.0, which adds the *Sine* filter and fixes block-time offsets and an off-by-one sample at the start of every WAV produced with a buffered filter (*Tapir*, *Sine*).

### Bug Fixes
- Switching the audio filter mid-playback no longer leaves the player in a half-active state where the seek bar advances but no audio is heard. just_audio 0.10.5 has a known race between `stop()`'s audio-session deactivation and the next `play()`'s reactivation that simultaneously chases a fresh `setFilePath()` load (still tagged with a `TODO: rewrite this to more cleanly handle simultaneous load/play requests` in upstream's source). The filter listener now uses `pause()` instead of `stop()`, keeping the audio session active and decoders alive for the rebound WAV. If playback was active before the switch, the new filter resumes automatically once conversion completes — no second tap on Play required. An explicit user-pressed Stop or Pause during the conversion cancels that auto-resume.
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
