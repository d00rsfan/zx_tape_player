# ZX Tape Player [![License GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-green.svg)](https://github.com/semack/zx_tape_player/blob/master/LICENSE.md)

ZX Tape Player is a utility that converts your device into a virtual cassette player for the British home computer ZX Spectrum that was quite popular in many countries from 1982 and forward. This player lets you playback virtual tapes in the TZX or TAP format used by many emulators and lets you play them back via the jack/headphone plug into your ZX Spectrum.

The app lets you select TAP or TZX files on your local device to playback, and tries to identify your file and show additional information such as publisher and screenshots - provided by the online Open Source API ZXInfo that contains information for more than 32,000 software titles from 1982 and up to date.

**PLEASE NOTE:** This is NOT an emulator and can not run the programs on TAP/TZX files. In order to run the program, you need a real physical ZX Spectrum connected to your device using the mini-jack lead that came with the machine.

## In Memory of Andriy S'omak

This project was created by [Andriy S'omak](https://github.com/semack), a talented developer and a passionate ZX Spectrum enthusiast. Andriy passed away on October 23, 2023, leaving behind this project and a community of people who shared his love for retro computing.

Andriy poured his heart into ZX Tape Player -- it was more than just software to him. It was a bridge between the past and the present, a way to keep the spirit of the ZX Spectrum alive for those who still cherish these machines. His work connected thousands of retro computing fans with the games and programs of their childhood.

We are continuing the development and maintenance of this project in his memory. Our goal is to keep ZX Tape Player alive, fix issues, and add improvements based on community feedback -- just as Andriy would have wanted. If you find this app useful, take a moment to appreciate the person who made it possible.

Rest in peace, Andriy. Your code lives on.

## Availability

The app is no longer available on app stores. I plan to publish it on Google Play once the project is in good shape. In the meantime, you can build it yourself from source or download a pre-built APK from [Releases](https://github.com/d00rsfan/zx_tape_player/releases).

## Building from Source

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/install) 3.41+
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

## Contribute

Contributions are welcome! Please open an [Issue](https://github.com/d00rsfan/zx_tape_player/issues) or submit a Pull Request.

For questions, bug reports, or feature requests, reach out through [GitHub Issues](https://github.com/d00rsfan/zx_tape_player/issues).

## Thanks to

- [Thomas Kolbeck Kjaer Heckmann](mailto:zxinfo_dev@kolbeck.dk) for providing his [API](https://api.zxinfo.dk/v3/#/) to the [ZXInfo](https://zxinfo.dk) database and involvement in the project;
- [Pavlo Hladkov](https://www.behance.net/hladkovpavlo) for the UI/UX of the application;
- [Sergey Kireev](https://github.com/psk7) for help in stabilizing the sound converter with custom loaders;
- [Mikie](https://www.alessandrogrussu.it/tapir/index.html) for his Tapir audio post-processing implementation;
- To everyone who contributes to keeping this project alive.

## Screenshots

<img src="https://github.com/semack/zx_tape_player/blob/master/android/fastlane/metadata/android/en-US/images/phoneScreenshots/1_en-US.jpeg?raw=true" width="33%"></img> <img src="https://github.com/semack/zx_tape_player/blob/master/android/fastlane/metadata/android/en-US/images/phoneScreenshots/2_en-US.jpeg?raw=true" width="33%"></img> <img src="https://github.com/semack/zx_tape_player/blob/master/android/fastlane/metadata/android/en-US/images/phoneScreenshots/3_en-US.jpeg?raw=true" width="33%"></img> <img src="https://github.com/semack/zx_tape_player/blob/master/android/fastlane/metadata/android/en-US/images/phoneScreenshots/4_en-US.jpeg?raw=true" width="33%"></img> <img src="https://github.com/semack/zx_tape_player/blob/master/android/fastlane/metadata/android/en-US/images/phoneScreenshots/5_en-US.jpeg?raw=true" width="33%"></img> <img src="https://github.com/semack/zx_tape_player/blob/master/android/fastlane/metadata/android/en-US/images/phoneScreenshots/6_en-US.jpeg?raw=true" width="33%"></img>
