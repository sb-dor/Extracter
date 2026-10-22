# Developing Extracter

How to build the native engine, run the app and run the tests. For what the app does, see the
[README](../README.md); for the design and its review history, [PLAN.md](../PLAN.md) and
[PLAN-REVIEW-LOG.md](../PLAN-REVIEW-LOG.md).

## Prerequisites

- Flutter 3.38+ (developed on 3.47.1), Xcode 26, Android NDK r28+.
- `brew install cmake pkg-config nasm` (macOS host). `ffmpeg` CLI only for test fixtures.
- Windows host: Visual Studio 2022, MSYS2 + MinGW-w64 (for FFmpeg), NASM.
- Linux host: build-essential, cmake, nasm, zlib1g-dev.

```bash
git submodule update --init
```

## Build the native libraries (once per machine / after a version bump)

All outputs are git-ignored and reproducible.

```bash
packages/extracter_native/scripts/build_apple.sh
```

```bash
packages/extracter_native/scripts/build_ffmpeg.sh android-arm64-v8a
```

```bash
packages/extracter_native/scripts/build_ffmpeg.sh android-x86_64
```

On a Linux host: `scripts/build_ffmpeg.sh linux-x86_64`. On Windows (MSYS2 MinGW64 shell,
with a VS developer prompt's `lib.exe` on PATH): `scripts/build_ffmpeg.sh windows-x86_64`.
whisper.cpp for Android/Linux/Windows is compiled by the plugin's CMake build.

## Run

```bash
flutter pub get
```

```bash
dart run intl_utils:generate && dart run build_runner build --delete-conflicting-outputs && dart format lib/
```

```bash
flutter run -d macos
```

## Tests

```bash
flutter test
```

```bash
packages/extracter_native/scripts/make_fixtures.sh && packages/extracter_native/scripts/run_native_smoke.sh
```

Integration tests run the real engine (they download the `tiny` model) and need the
speech fixtures from `scripts/make_fixtures.sh`:

- **macOS** (sandboxed): copy `speech.wav` and `speech_video.mp4` from
  `packages/extracter_native/test_fixtures/` into
  `~/Library/Containers/<bundle id>/Data/Library/Application Support/<bundle id>/test_fixtures/`, then
  `flutter test integration_test/app_test.dart -d macos`.
- **iOS Simulator**: add `--dart-define=FIXTURES_DIR=$PWD/packages/extracter_native/test_fixtures`.
- **Android emulator**: `adb push` both files to `/data/local/tmp/fx/` and add
  `--dart-define=FIXTURES_DIR=/data/local/tmp/fx`.

Android release builds: check 16 KB page alignment with
`packages/extracter_native/scripts/check_16kb.sh <apk-or-aab>`.

## Platform status

| Platform | Status |
|---|---|
| macOS | Debug + **release** built; unit, native smoke (27 checks) and integration tests pass; live UI test (⌘O → song) extracts text |
| iOS Simulator | Debug built; integration tests pass; live UI test (Files picker → song) extracts text (CPU — Metal is off on the Simulator) |
| Android emulator (arm64) | Debug + **release** built; integration tests pass; live UI test (system picker → song) extracts text; 16 KB alignment passes |
| Physical iPhone / Android device | Not tried yet |
| Windows, Linux | CMake + scripts written, **not yet built** (need those hosts) |

## Android release builds

Release signing reads `android/key.properties` (git-ignored), which points at the upload
keystore. Without it, release builds fall back to the debug key so `flutter run --release`
still works.

```properties
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=upload-keystore.jks
```

Build the Play bundle for the 64-bit ABIs the native engine supports:

```bash
flutter build appbundle --release --target-platform android-arm64,android-x64
```

## Store assets

Everything on the Google Play page is generated from the real app:

1. `integration_test/store_screenshots_test.dart` renders the screens in English and Russian
   with sample data and a live transcription:

   ```bash
   flutter drive --driver test_driver/store_screenshots.dart --target integration_test/store_screenshots_test.dart -d <android-device> --dart-define=FIXTURES_DIR=/data/local/tmp/fx
   ```

2. `tool/store/compose_store_assets.py` turns those captures into the store screenshots and
   feature graphics in `store/google_play/{en,ru}/`.
3. `tool/store/compose_readme_images.py` builds the README banner and screenshot strip in
   `docs/images/`.
4. `tool/icon/render_icons.py --final b_wave_to_text` renders the launcher and Play icons.

Listing texts and console answers live in `store/google_play/`; the privacy policy page is
`store/privacy/index.html`.
