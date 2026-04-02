# ZX Tape Player

Virtual cassette player that converts TAP/TZX files to audio for loading software onto real ZX Spectrum computers. Integrates with ZXInfo API (32,000+ titles) for tape identification and metadata.

## Build & Run

```bash
flutter pub get
flutter run                    # debug
flutter build apk --release    # Android release
flutter build ios --release    # iOS release
flutter analyze                # static analysis
```

## Tech Stack

- **Flutter 3.41+** / **Dart 3.11+**
- **Android**: compileSdk 36, targetSdk 35, minSdk 24, Java 21, Gradle 8.13, AGP 8.12.1, Kotlin 2.2.0
- **iOS**: minimum deployment target 13.0

## Architecture

- **DI**: `GetIt` service locator — services registered in `main.dart`, accessed via `getIt<T>()`
- **State**: Stream-based with `StreamController` + `StreamBuilder`, `RxDart` for combining streams
- **API layer**: `BackendService` (abstract) → `ZxApiService` (implementation) using ZXInfo REST API v3
- **Audio**: `just_audio` for WAV playback, `zx_tape_to_wav` for TAP/TZX→WAV conversion (runs in isolate via `compute()`)
- **Localization**: `easy_localization` with 12 languages in `assets/translations/`

## Project Structure

```
lib/
  main.dart                          # Entry point, DI setup, routing
  exceptions/                        # Custom HTTP exceptions
  models/                            # Domain models (SoftwareModel, HitModel, etc.)
  services/
    backend_service.dart             # Abstract API interface
    silence_control_service.dart     # Abstract ringer mode control
    volume_control_service.dart      # Abstract volume control
    wake_lock_service.dart           # Abstract wake lock control
    zx_api/                          # ZXInfo API implementation + DTO models
    zx_control/                      # Platform service implementations
  ui/
    splash_screen.dart               # 3-second animated splash
    home_screen.dart                 # Search input + file picker
    search_screen.dart               # TypeAheadField + paginated results
    player_screen.dart               # Software info + tape player
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

- **ZXInfo API**: `https://api.zxinfo.dk/v3` — search, game details, file identification (SHA512)
- **ZXInfo Media**: `https://zxinfo.dk/media` — screenshots
- **Archive.org**: TOSEC tape downloads
- User-Agent: `ZX Tape Player/1.0`

## Signing

Android release signing configured via `android/key.properties` (not in repo). The `key.properties` file maps `keyAlias`, `keyPassword`, `storeFile`, `storePassword`.
