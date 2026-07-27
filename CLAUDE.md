# ZX Tape Player

Virtual cassette player that converts `.tap`/`.tzx` (ZX Spectrum), `.p`/`.81`/`.p81` (ZX81), and `.o`/`.80` (ZX80) tape images to audio for loading software onto real Sinclair computers. Local files and `.zip` archives are supported. ZXInfo API v5 provides tape identification, metadata, model-specific catalogue search, and remote downloads. ZX Spectrum is the default model.

## Build & Run

```bash
flutter pub get
flutter run                    # debug
flutter build apk --release    # Android release
flutter build ios --release    # iOS release
flutter test                   # unit and widget tests
flutter analyze                # static analysis
```

## Tech Stack

- **Flutter 3.44.8 stable** / **Dart 3.12.2** (tested toolchain; `pubspec.yaml` allows Dart `>=3.11.0 <4.0.0`)
- **Android**: compileSdk 36, targetSdk 36, minSdk 24, Java 21 (via jvmToolchain), Gradle 9.1.0, AGP 9.0.1, Kotlin 2.3.20
- **iOS**: minimum deployment target 13.0

## Architecture

- **DI**: `GetIt` service locator — services registered in `main.dart`, accessed via `getIt<T>()`
- **State**: Stream-based with `StreamController` + `StreamBuilder`, `RxDart` for combining streams
- **API layer**: `BackendService` (abstract) → `ZxApiService` (implementation) using ZXInfo REST API v5
- **Audio**: `just_audio` for WAV playback, `zx_tape_to_wav` plus the app's raw Sinclair-image adapter for tape→WAV conversion (runs in an isolate via `compute()`)
- **Localization**: `easy_localization` with 12 languages in `assets/translations/`

## Project Structure

```
lib/
  main.dart                          # Entry point, DI setup, routing
  exceptions/                        # Custom HTTP exceptions
  models/                            # Domain models (SoftwareModel, HitModel, etc.)
    zx_model.dart                    # Model-specific API machine and tape filters
  services/
    backend_service.dart             # Abstract API interface
    settings_service.dart            # Persisted audio-filter and machine settings
    tape_conversion_service.dart     # Isolate-safe tape-to-WAV conversion
    tape_image_service.dart          # Direct/archive tape extraction and export staging
    silence_control_service.dart     # Abstract ringer mode control
    volume_control_service.dart      # Abstract volume control
    wake_lock_service.dart           # Abstract wake lock control
    zx_api/                          # ZXInfo API implementation + DTO models
    zx_control/                      # Platform service implementations
  ui/
    splash_screen.dart               # 3-second animated splash
    home_screen.dart                 # Search input + file picker
    search_screen.dart               # TypeAheadField + paginated results
    settings_screen.dart             # Audio filter + target Sinclair model
    player_screen.dart               # Software info + tape player
    tips_screen.dart                 # In-app usage guide
    widgets/
      cassette.dart                  # Animated cassette visualization
      tape_player/                   # Audio player controls, seek bar, carousel
  utils/
    definitions.dart                 # App constants (page size, extensions, frequencies)
    extensions.dart                  # String.format(), HexColor, isNullOrEmpty()
    api_base_helper.dart             # HTTP client with custom User-Agent
    bar_helper.dart                  # SnackBar helper
```

## Key APIs & External Services

- **ZXInfo API**: `https://api.zxinfo.dk/v5` — title/letter/publisher search, entry details, and file identification
- **ZXInfo Media**: `https://zxinfo.dk/media` — screenshots and mirrored ZXDB tape downloads
- **Archive.org**: Spectrum TOSEC and legacy mirror downloads
- User-Agent: `ZX Tape Player/1.0`

Catalogue requests use the selected model's ZXInfo `machinetype` and `tosectype` filters: `ZXSPECTRUM` + `tap`/`tzx`, `ZX81` + `p`/`81`/`p81`, or `ZX80` + `o`/`80`. Changing the model returns to a fresh search screen and clears the old query.

## Signing

Android release signing configured via `android/key.properties` (not in repo). The `key.properties` file maps `keyAlias`, `keyPassword`, `storeFile`, `storePassword`.

## Dated Maintenance Follow-ups

- On the first project maintenance session after **2026-08-07**, remind the maintainer to recheck Built-in Kotlin support for both dependencies below:
  - `in_app_review`: currently `2.0.12`; check whether a release containing [PR #180](https://github.com/britannio/in_app_review/pull/180) is available.
  - `media_store_plus`: currently `0.1.3`; check [issue #34](https://github.com/SNNafi/media_store_plus/issues/34) and consider replacing or locally migrating the plugin if no compatible release exists.
- Remove this follow-up after both dependencies support Built-in Kotlin and `android.builtInKotlin=false` is no longer needed.
