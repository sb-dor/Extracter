// Renders Google Play phone screenshots (1080x1920, 9:16) of the real app in
// English and Russian: seeded History, a live transcription, detail, models.
//
//   flutter drive --driver test_driver/store_screenshots.dart \
//     --target integration_test/store_screenshots_test.dart -d <android> \
//     --dart-define=FIXTURES_DIR=/data/local/tmp/fx
// The driver writes the PNGs to store/google_play/raw/.
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

  testWidgets('store screenshots', (tester) async {
    const fixturesDir = String.fromEnvironment('FIXTURES_DIR');
    final dependencies = await initCaptureDependencies(tester);
    final shots = <String, String>{};

    Future<void> shot(String name) async => shots[name] = await captureFrame(tester);

    Future<void> tap(Finder finder) async {
      await tester.tap(finder.last);
      await tester.pump(const Duration(milliseconds: 600));
    }

    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = const Size(1080, 1920);
    for (final locale in const [Locale('en'), Locale('ru')]) {
      tester.platformDispatcher.localesTestValue = [locale];
      final tag = locale.languageCode;
      final (fixture, podcastName, detailEntry) = storePodcasts[tag]!;
      await seedSamples(tester, dependencies, tag);
      await tester.pumpWidget(dependencies.inject(child: const App()));
      await tester.pump(const Duration(seconds: 2));

      // 1. Live transcription of a real file.
      final state = tester.state<TranscriptionQueueConfigWidgetState>(find.byType(TranscriptionQueueConfigWidget));
      final path = p.join(fixturesDir, fixture);
      unawaited(state.addFiles([PickedMedia(name: podcastName, path: path, file: XFile(path))]));
      // Wait until the card shows live text (the latest two segments).
      for (var i = 0; i < 180; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        if (state.queueController.state.jobs.any((job) => job.segments.length >= 2)) break;
      }
      await shot('${tag}_1_transcribe');
      for (final job in state.queueController.state.jobs) {
        state.cancel(job.id);
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));

      // 2. History, 3. transcript, 4. copy menu, 5. models.
      await tap(find.byIcon(Icons.history));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await shot('${tag}_2_history');
      await tap(find.textContaining(detailEntry));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await tester.pump(const Duration(milliseconds: 600));
      await shot('${tag}_3_transcript');
      await tap(find.byIcon(Icons.copy_outlined));
      await shot('${tag}_4_copy');
      // One system back leaves the transcript (the menu is an overlay, not a
      // route); a second one would close the activity.
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 600));
      await tap(find.byIcon(Icons.memory));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await shot('${tag}_5_models');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    }
    tester.view.reset();
    tester.platformDispatcher.clearLocalesTestValue();
    binding.reportData = {'screenshots': shots};
    expect(shots, hasLength(10));
  });
}
