# Changelog

## v1.6.1 - Hello, I Love You

### New Features
- A first-launch warning explains the loud loading signal and the 100% default volume. Resetting Settings shows the warning and release notes again.
- Release notes appear on first install and after updates. To turn them back on, open **What's new** from the Home or player menu and clear **Never show again**.

### Improvements
- More reliable high-speed loading of Z80 and SNA snapshots. The receiver better distinguishes short pulses, and the audio holds its final level long enough for the Spectrum to detect the last bit.
- Snapshot speeds now show the transfer rate relative to standard ROM loading, rounded to one decimal place for the selected sample rate. The default is 48 kHz.
- Choose the sample rate (48 or 44.1 kHz) and snapshot polarity in **Settings**. The sample rate applies to tapes and snapshots. Resetting audio settings keeps your snapshot speed.
- Changing audio settings while a tape is loading now uses the selected settings for playback.

### Bug Fixes
- Android navigation buttons stay visible against the bottom bar, including after switching themes or returning to the app.

## v1.6.0 - When the Music's Over

### New Features
- Restore supported 48K and 128K ZX Spectrum snapshots on real hardware. Open a `.z80` or `.sna` file from your device, a ZIP archive or ZXInfo results. You can also export the audio as a WAV.
- Choose a snapshot loading speed from 1× to 10×. Start with the default 5× at 48 kHz, or try a slower speed or inverted polarity if loading fails. The player remembers your settings. Snapshots play from the start and ignore tape filters.
- **Tips** explains which parts of the machine state can be restored. Snapshot loading is based on [ZQLoader](https://github.com/oxidaan/zqloader) by Daan Scherft (Oxidaan).

### Improvements
- ZXInfo lists tapes before snapshots when both are available.
- On Android, the Tape Block Browser controls stay above the navigation bar.

### Bug Fixes
- Improved restore reliability and error messages for unsupported snapshots. 48K Interface 1 snapshots in Z80 v2 format can load if the Interface 1 ROM was inactive. The player warns before loading a 128K SNA saved with TR-DOS active.
- When a snapshot finishes, you can swipe to another file immediately.

## v1.5.0 - My Eyes Have Seen You

### New Features
- Play ZX81 files (`.p`, `.81`, `.p81`) and ZX80 files (`.o`, `.80`) from your device or a ZIP archive. Both models also support compatible TZX recordings.
- Choose **ZX Spectrum**, **ZX81** or **ZX80** in **Settings** on the home screen. The catalogue shows tapes for that computer. Switching models starts a fresh search.

### Bug Fixes
- Unzipped TAP files convert and play again. Search results still appear when a catalogue entry has invalid screenshot data.
- More ZX81 and ZX80 ZIP downloads now appear in the catalogue.

## v1.4.3 - People Are Strange

### New Features
- To search by publisher, start with a space and type the publisher’s name. Select a suggestion or submit the search to see compatible tapes in title order.
- Search results now show the publisher alongside the year and genre.

### Downloads
- Signed Android APKs are available on GitHub. The Linux AppImage now includes its audio playback library.

## v1.4.2 - Moonlight Drive

### New Features
- Choose **Export** in the player menu to save the tape image, the original ZIP (if you opened an archive), or a WAV with your selected filter once conversion finishes.
- Choose an audio filter in **Settings**. Start with **Bass boost** for a real Spectrum, or try **None** if loading fails. Use **Sine** for recording to cassette or try **Tapir** for non-standard tapes.
- Resetting settings restores **Bass boost** and sets playback volume to maximum.

### Bug Fixes
- Switching filters during playback now rewinds the tape and resumes with sound after conversion. Press Pause or Stop during conversion to prevent playback from restarting.
- On Android 7–10, long-pressing the filename saves the tape to **Downloads/ZX Tape Player/** again. The player confirms saves when a duplicate is renamed and reports failed downloads.

## v1.4.1 - Horse Latitudes

### New Features
- Open **Tips** in the player menu for help with alternate tape versions, saving downloads, skipping blocks, rewinding and adjusting speed. The guide is available in all 12 supported languages. You can open it even for tapes the catalogue doesn’t recognise.

## v1.4.0 - Unhappy Girl

### New Features
- Desktop downloads are available for Linux (`.deb`, `.rpm`), Windows (`.zip`) and macOS (`.dmg`).

### Downloads
- On Android, new downloads go to **Downloads/ZX Tape Player/**. Tapes saved by earlier versions remain in `Android/data/io.github.d00rsfan.zx_tape_player/files/`.

## v1.3.3 - Love Me Two Times

### Bug Fixes
- Improved edge-to-edge display on Android 15 and earlier versions.
- Pressing Enter on an external keyboard now submits your search.

## v1.3.2 - You're Lost Little Girl

### Improvements
- **Adjust speed** has more presets and **+** and **−** buttons for fine adjustments in steps of 0.01×.
- The Play button is now centred, and the player remembers your volume for the next session.

### Installation note
Android treats v1.3.2 as a separate app. You may need to uninstall the previous version before installing it.

## v1.3.1 - Strange Days

### New Features
- See how much time is left in the current tape block.
- Damaged TAP and TZX files now show a warning. You can still try to play them.

### Improvements
- The 1.10× speed preset replaces 0.25× for slightly faster loading.

### Bug Fixes
- Fixed TOSEC downloads with spaces, brackets or ampersands in the filename. Thanks to Thomas Heckmann for identifying the cause.

## v1.3.0 - The Doors

### New Features
- See the current block number, type and name. Use the block controls to restart it or jump to the previous or next block.
- Adjust playback from 0.25× to 4× in steps of 0.05×. Pitch changes with speed, as on a tape recorder.

### Bug Fixes
- Fixed detection of tapes from TOSEC and display of long filenames on iOS.

## v1.2.1 - Can

### Improvements
- Updated the TOSEC tape archive to the September 2023 collection.

### Bug Fixes
- Search, suggestions and browsing by letter now show only ZX Spectrum software. Thanks to Thomas Heckmann for suggesting the fix.

## v1.2.0 - Black Sabbath

This release is dedicated to the memory of:

- Cozy Powell
- Ronnie James Dio
- Geoff Nicholls
- Ozzy Osbourne

### New Features
- Open the **Tape Block Browser** to see each block and its start time. Tap a block to jump there.

### Improvements
- Controls stay clear of the system bars on Android 15 and later.
- Local tapes recognised by ZXInfo now show their catalogue details and screenshots. You can also share them or open their catalogue page.

### Installation note
Android treats v1.2.0 as a separate app. You may need to uninstall the previous version before installing it.

## v1.1.1 - Anathema

### New Features
- Open TAP and TZX files inside local or downloaded ZIP archives. ZXInfo now offers downloads from Spectrum Computing as well as TOSEC.

### Bug Fixes
- Files selected from your device play again. If conversion fails, you can still swipe to another tape.

### Downloads
- The Android APK is available on the GitHub release page. On iOS, build the app locally.

## v1.1.0 - Add support for zip files

### New Features
- Automatically extract and play tapes from `.tap.zip` and `.tzx.zip` files returned by the API.
- Accept local ZIP archives and play the first TAP or TZX file found inside.

### Bug Fixes
- Restore carousel swiping after a tape-conversion error.

## v1.0.15

### Bug Fixes
- Fix errors when attempting to play a local file.

### Maintenance
- Update dependencies.

See the [GitHub release history](https://github.com/d00rsfan/zx_tape_player/releases) for historical release details and dedications.
