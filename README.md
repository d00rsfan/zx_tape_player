# ZX Tape Player [![License GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-green.svg)](https://github.com/d00rsfan/zx_tape_player/blob/master/LICENSE.md)

ZX Tape Player turns your device into a virtual cassette player for the Sinclair ZX Spectrum, ZX81, and ZX80 home computers. It converts tape images to audio and can turn supported ZX Spectrum snapshots into a restoration stream for real hardware through your device's jack/headphone output.

## Supported Models and Formats

| Model | Input formats |
| --- | --- |
| ZX Spectrum | tapes: `.tap`, `.tzx`; snapshots: `.z80`, `.sna` |
| ZX81 | `.p`, `.81`, `.p81`, `.tzx` |
| ZX80 | `.o`, `.80`, `.tzx` |

Files can be selected directly or from a `.zip` archive. The app tries to identify local tapes and show metadata such as publisher and screenshots from the open [ZXInfo](https://zxinfo.dk) catalogue. You can also search that catalogue and download compatible tapes; choose the target model in Settings on the home screen. ZX Spectrum is selected by default.

**PLEASE NOTE:** This is NOT an emulator. Tape images are played as loading audio; snapshots are restored as saved machine state and are not reconstructed into their original tape. To run a program, you need a real ZX Spectrum, ZX81, or ZX80 connected to your device with an appropriate audio lead.

### ZX Spectrum snapshot restoration

The snapshot converter supports Z80 v1 48K files; Z80 v2 base 48K, unpaged 48K + Interface 1 (hardware mode 1), and base 128K files; base-model Z80 v3 48K and 128K files; and structurally valid 48K/128K SNA files. Compressed and raw supported Z80 memory forms are accepted, including the valid 128K SNA layouts where the current bank is 2 or 5. Z80 v2 mode 1 uses the ordinary 48K restore path when its separate Interface 1 ROM-paged byte is zero; a snapshot saved with that ROM paged remains unsupported.

Snapshot audio is a deterministic unsigned 8-bit mono restoration protocol for the bundled ZQLoader receiver. Choose a compatible generated-signal speed from `10x`, `7x`, `5x`, `4x`, `3x`, `2.5x`, `2x`, or `1x`, select 48 kHz or 44.1 kHz WAV generation, and invert polarity when an audio path requires it; first use defaults to 5x/standard/48 kHz, then the last successfully applied settings triple is remembered across app sessions. The resulting audio itself must always be played at media-player speed 1x. Tape filters remain selectable as your preference for ordinary tapes but are ignored for snapshots. Restore stages are shown for progress only: skipping or seeking into an internal stage is disabled because later stages depend on receiver state established by earlier ones. Restart begins again at the ROM bootstrap.

Supported restoration includes Spectrum RAM, Z80 CPU registers, interrupt state, border, PC/SP, and 128K `0x7ffd` paging. It does not restore AY registers, elapsed frame timing, Interface/MGT/Multiface peripheral state, nonzero `0x1ffd` state, or paged TR-DOS ROM state. A snapshot that saved paged TR-DOS state is still converted with a visible warning. Other extended and modified hardware modes are rejected rather than partially restored.

The in-RAM receiver needs a small documented scratch footprint until it jumps to the restored PC. The converter places it in an all-zero fixed-RAM run while protecting the saved PC instruction, stack word, and IM2 vector page; otherwise it uses a screen fallback. If even that fallback intersects critical execution state, conversion is rejected instead of producing a known-unsafe load. Z80 files with unequal IFF1/IFF2 or v1 SamRom state, and 128K SNA files with conflicting duplicate bank 2/5 data, are likewise rejected because those states cannot be restored unambiguously.

The snapshot host implementation has semantic and waveform test coverage, but real-hardware acceptance is recorded separately for repeated Android-to-48K and Android-to-128K loads before the feature is considered hardware-validated.

## In Memory of Andriy S'omak

This project was created by [Andriy S'omak](https://github.com/semack), a talented developer and a passionate ZX Spectrum enthusiast. Andriy passed away on October 23, 2023, leaving behind this project and a community of people who shared his love for retro computing.

Andriy poured his heart into ZX Tape Player -- it was more than just software to him. It was a bridge between the past and the present, a way to keep the spirit of the ZX Spectrum alive for those who still cherish these machines. His work connected thousands of retro computing fans with the games and programs of their childhood.

We are continuing the development and maintenance of this project in his memory. Our goal is to keep ZX Tape Player alive, fix issues, and add improvements based on community feedback -- just as Andriy would have wanted. If you find this app useful, take a moment to appreciate the person who made it possible.

Rest in peace, Andriy. Your code lives on.

## Availability

The app is no longer available on app stores. I plan to publish it on Google Play once the project is in good shape. In the meantime, you can build it yourself from source or download a pre-built APK from [Releases](https://github.com/d00rsfan/zx_tape_player/releases).

## Building from Source

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/install) (tested with Flutter 3.44.8 stable, which includes Dart 3.12.2; the project requires Dart `>=3.11.0 <4.0.0`)
- Java 21+

### Generate a Signing Key

Android requires all APKs to be signed. Generate your own keystore:

```bash
keytool -genkey -v -keystore ~/zx-tape-player-key.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias zxtapeplayer
```

Then create the file `android/key.properties`:

```properties
storePassword=<password you chose>
keyPassword=<password you chose>
keyAlias=zxtapeplayer
storeFile=/home/<your-username>/zx-tape-player-key.jks
```

### Build

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

The `--split-per-abi` flag produces smaller APKs by building a separate one for each CPU architecture. The output files will be at:

```
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk    # most modern phones
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk  # older 32-bit phones
build/app/outputs/flutter-apk/app-x86_64-release.apk       # emulators / x86 devices
```

For most devices, use the `arm64-v8a` variant.

### Building on macOS (iOS and Android)

Building for iOS requires macOS with Xcode installed. If you need to maintain multiple Xcode versions, use [`xcodes`](https://github.com/XcodesOrg/xcodes):

```bash
brew install xcodes
xcodes install --latest
xcodes select --latest
xcodes runtimes install --latest
```

Otherwise just install Xcode from the App Store.

Install Flutter and CocoaPods:

```bash
brew install --cask flutter
brew install cocoapods
flutter --disable-analytics
```

Flutter will be installed at `/opt/homebrew/share/flutter`.

Install the Android command-line tools (needed even when building only for iOS, since `flutter doctor` checks for them):

```bash
brew install --cask android-commandlinetools
export ANDROID_HOME=$HOMEBREW_PREFIX/share/android-commandlinetools
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools
```

Add the two `export` lines to your `~/.zshrc` to make them persistent.

Accept the Android SDK and Flutter licenses, then install the required Android SDK packages:

```bash
yes | sdkmanager --licenses
flutter doctor --android-licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
```

Fetch project dependencies and install iOS pods:

```bash
flutter pub get
cd ios && pod install && cd ..
```

Start an iOS Simulator (or Android emulator), then run the app:

```bash
flutter run
```

On the first run you may be prompted to download additional components — accept the dialog. If something fails, re-run `flutter run`.

If you hit stale build issues, do a clean rebuild:

```bash
flutter clean
flutter pub get
cd ios && pod install --repo-update && cd ..
flutter run
```

To produce a release build for iOS:

```bash
flutter build ios --release
```

## Contribute

Contributions are welcome! Please open an [Issue](https://github.com/d00rsfan/zx_tape_player/issues) or submit a Pull Request.

For questions, bug reports, or feature requests, reach out through [GitHub Issues](https://github.com/d00rsfan/zx_tape_player/issues).

## Thanks to

- [Thomas Kolbeck Kjaer Heckmann](mailto:zxinfo_dev@kolbeck.dk) for providing his [API v5](https://api.zxinfo.dk/v5) to the [ZXInfo](https://zxinfo.dk) database and involvement in the project;
- [Pavlo Hladkov](https://www.behance.net/hladkovpavlo) for the UI/UX of the application;
- [Sergey Kireev](https://github.com/psk7) for help in stabilizing the sound converter with custom loaders;
- [Daan Scherft (Oxidaan)](https://github.com/oxidaan) for the MIT-licensed ZQLoader receiver assets used for snapshot restoration; see [`assets/snapshots/LICENSE.txt`](assets/snapshots/LICENSE.txt);
- [Mikie](https://www.alessandrogrussu.it/tapir/index.html) for his Tapir audio post-processing implementation;
- To everyone who contributes to keeping this project alive.
