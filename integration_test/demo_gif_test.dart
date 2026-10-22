// Captures the frames of the README demo GIF from the real app (English): a
// podcast transcribing live, then History, the transcript and the copy menu.
//
//   flutter drive --driver test_driver/store_screenshots.dart \
//     --target integration_test/demo_gif_test.dart -d <android> \
//     --dart-define=FIXTURES_DIR=/data/local/tmp/fx
// Frames land in build/demo_frames/; tool/store/compose_demo_gif.py turns them into docs/images/demo.gif.
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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo gif frames', (tester) async {
    const fixturesDir = String.fromEnvironment('FIXTURES_DIR');
    final dependencies = await initCaptureDependencies(tester);
    final frames = <String, String>{};
    // Frame names carry how long the GIF holds them: <index>_<milliseconds>.
    Future<void> frame(int holdMs) async =>
        frames['${frames.length.toString().padLeft(3, '0')}_$holdMs'] = await captureFrame(tester, pixelRatio: 0.5);

    Future<void> tap(Finder finder) async {
      await tester.tap(finder.last);
      await tester.pump(const Duration(milliseconds: 600));
    }

    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = const Size(1080, 1920);
    tester.platformDispatcher.localesTestValue = [const Locale('en')];
    await seedSamples(tester, dependencies, 'en');
    await tester.pumpWidget(dependencies.inject(child: const App()));
    await tester.pump(const Duration(seconds: 2));
    await frame(1200);

    // Live transcription: one frame per new segment until the file is done.
    final state = tester.state<TranscriptionQueueConfigWidgetState>(find.byType(TranscriptionQueueConfigWidget));
    final (fixture, podcastName, _) = storePodcasts['en']!;
    final path = p.join(fixturesDir, fixture);
    unawaited(state.addFiles([PickedMedia(name: podcastName, path: path, file: XFile(path))]));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await frame(900);
    var seen = 0;
    var shownPermille = 0;
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      final jobs = state.queueController.state.jobs;
      final job = jobs.isEmpty ? null : jobs.first;
      if (job == null || job.status.isTerminal) break;
      final permille = job.permille ?? 0;
      if (job.segments.length != seen || permille - shownPermille >= 120) {
        seen = job.segments.length;
        shownPermille = permille;
        await frame(job.segments.isEmpty ? 450 : 700);
      }
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await frame(1400);

    // The finished transcript in History, opened, then copied with timestamps.
    await tap(find.byIcon(Icons.history));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await frame(1400);
    await tap(find.textContaining('Podcast'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump(const Duration(milliseconds: 600));
    await frame(1800);
    await tap(find.byIcon(Icons.copy_outlined));
    await frame(1100);
    await tap(find.text('Copy with timestamps'));
    await frame(2200);

    tester.view.reset();
    tester.platformDispatcher.clearLocalesTestValue();
    binding.reportData = {'outDir': 'build/demo_frames', 'screenshots': frames};
    expect(frames.length, greaterThan(6));
  });
}
