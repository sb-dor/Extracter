# Contributing to Extracter

Thanks for helping! Extracter is a Flutter app with a native engine (FFmpeg + whisper.cpp),
so there's work for Dart, C++ and build-system people alike.

## Ways to help

- **Report a bug** or a file that won't transcribe. Open an issue with the format, its length,
  the model and the platform. Please don't attach private recordings.
- **Suggest a feature** in an issue first, so we can agree on the shape before code.
- **Pick an issue** labelled [`good first issue`](https://github.com/sb-dor/Extracter/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
  or [`help wanted`](https://github.com/sb-dor/Extracter/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22).
- **Translate** the app: strings live in `lib/src/common/localization/intl_*.arb`.

## Setting up

Follow [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) to build the native libraries and run the app.
On macOS the quickest loop is `flutter run -d macos`.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Keep changes focused: one fix or feature per pull request.
3. Follow the existing architecture (feature folders with controller, repository and config
   widget). The design is explained in [PLAN.md](PLAN.md).
4. Before you push, make sure these pass:

   ```bash
   dart format -l 120 --set-exit-if-changed lib test integration_test
   ```

   ```bash
   dart analyze
   ```

   ```bash
   flutter test
   ```

   If you touched `packages/extracter_native/src`, also run
   `packages/extracter_native/scripts/run_native_smoke.sh` (macOS).
5. Describe what changed and how you tested it, on which platform.

## Privacy is a feature

Extracter must keep working fully offline. Please don't add analytics, crash reporting, ads or
any network call beyond the model download. Changes that send user data anywhere won't be merged.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
