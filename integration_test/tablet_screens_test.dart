// Renders every screen at common tablet sizes, for checking the tablet layouts:
// a live transcription, History, an open transcript and Models.
//
//   flutter drive --driver test_driver/store_screenshots.dart \
//     --target integration_test/tablet_screens_test.dart -d <android> \
//     --dart-define=FIXTURES_DIR=/data/local/tmp/fx
// The driver writes the PNGs to build/tablet_screens/. Replaces History with
// sample transcripts, so run it on an emulator, not on a device you use.
import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:extracter/src/common/widget/app.dart';
import 'package:extracter/src/feature/transcription_queue/models/picked_media.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'store_capture.dart';

/// Logical sizes: a 10" tablet both ways, a 7" tablet sideways, an iPad both ways.
const tabletSizes = <String, Size>{
  'tablet_portrait': Size(800, 1280),
  'tablet_landscape': Size(1280, 800),
  'small_landscape': Size(960, 600),
  'ipad_portrait': Size(820, 1180),
  'ipad_landscape': Size(1180, 820),
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tablet screens', (tester) async {
    const fixturesDir = String.fromEnvironment('FIXTURES_DIR');
    final dependencies = await initCaptureDependencies(tester);
    final shots = <String, String>{};

    Future<void> resize(Size size) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = size * 2;
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> shot(String name) async => shots[name] = await captureFrame(tester, pixelRatio: 0.5);

    Future<void> tap(Finder finder) async {
      await tester.tap(finder.last);
      await tester.pump(const Duration(milliseconds: 600));
    }

    final (fixture, podcastName, detailEntry) = storePodcasts['en']!;
    await seedSamples(tester, dependencies, 'en');
    await resize(tabletSizes.values.first);
    await tester.pumpWidget(dependencies.inject(child: const App()));
    await tester.pump(const Duration(seconds: 2));

    // 1. A live transcription, shown at every size while it runs.
    final state = tester.state<TranscriptionQueueConfigWidgetState>(find.byType(TranscriptionQueueConfigWidget));
    final path = p.join(fixturesDir, fixture);
    unawaited(state.addFiles([PickedMedia(name: podcastName, path: path, file: XFile(path))]));
    for (var i = 0; i < 180; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      if (state.queueController.state.jobs.any((job) => job.segments.length >= 2)) break;
    }
    for (final MapEntry(key: name, value: size) in tabletSizes.entries) {
      await resize(size);
      await shot('${name}_1_transcribe');
    }
    for (final job in state.queueController.state.jobs) {
      state.cancel(job.id);
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));

    // 2. History, 3. a transcript, 4. Models.
    for (final MapEntry(key: name, value: size) in tabletSizes.entries) {
      await resize(size);
      await tap(find.byIcon(Icons.history));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await shot('${name}_2_history');
      await tap(find.textContaining(detailEntry));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await shot('${name}_3_transcript');
      // A pushed transcript screen closes with back; a side pane stays. Back
      // with nothing to pop would send the app to the background.
      await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      // Android's page transition runs 800 ms of real time; pump does not wait
      // it out, and the settled layout needs a few frames after it ends.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      await tap(find.byIcon(Icons.memory));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await shot('${name}_4_models');
      await tap(find.byIcon(Icons.graphic_eq));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
    binding.reportData = {'screenshots': shots, 'outDir': 'build/tablet_screens'};
    expect(shots, hasLength(tabletSizes.length * 4));
  });
}
