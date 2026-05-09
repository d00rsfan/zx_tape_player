flutter pub get
flutter build apk --release
7z a -t7z zx_tape_player1.0.15.17.7z zx_tape_player1.0.15.17.apk -mx=9 -m0=lzma2 -md=128m -mfb=273 -ms=on
adb install -r /home/yurii/pets/zx_tape_player/android/app/release/app-release.apk

