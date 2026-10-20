# Extracter

Offline speech-to-text for (almost) any audio or video file. Flutter app for Android, iOS,
macOS, Windows and Linux. Files are decoded with a decode-only LGPL FFmpeg build and
transcribed on-device with whisper.cpp — nothing is uploaded.

- Queue many files (pick or drag-and-drop on desktop), live segments, cancel.
- Export TXT / SRT / VTT, copy, share; local History with full-text search.
- Whisper models (tiny → large-v3-turbo) download on demand, SHA-256 verified.
- English and Russian UI.

Design decisions and review history: [PLAN.md](PLAN.md), [PLAN-REVIEW-LOG.md](PLAN-REVIEW-LOG.md).
Third-party components and licences: [THIRD_PARTY.md](THIRD_PARTY.md).

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

## Platform support status

| Platform | Status |
|---|---|
| macOS | Built; unit, native smoke (27 checks) and integration tests pass |
| iOS Simulator | Built; integration tests pass (CPU — Metal is disabled on the Simulator) |
| Android emulator (arm64) | Built; integration tests pass; 16 KB alignment check passes |
| Physical iPhone / Android device | Not tried yet |
| Windows, Linux | CMake + scripts written, **not yet built** (need those hosts) |
