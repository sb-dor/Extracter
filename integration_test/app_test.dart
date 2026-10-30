// End-to-end tests on a real device/desktop with the real native engine.
//
// Fixtures: copy speech.wav and speech_video.mp4 from
// packages/extracter_native/test_fixtures/ into
// `<application support>/test_fixtures/` (the macOS sandbox cannot read the
// repo), or pass --dart-define=FIXTURES_DIR=<dir> on the iOS Simulator.
// The model test downloads the real `tiny` model from Hugging Face.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:cross_file/cross_file.dart';
import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:extracter/src/common/utils/cancel_token.dart';
import 'package:extracter/src/common/widget/app.dart';
import 'package:extracter/src/feature/transcript_deletion/data/transcript_deletion_repository.dart';
import 'package:extracter/src/feature/transcript_detail/data/transcript_detail_repository.dart';
import 'package:extracter/src/feature/transcription_queue/controller/transcription_queue_controller.dart';
import 'package:extracter/src/feature/transcription_queue/data/transcription_queue_repository.dart';
import 'package:extracter/src/feature/transcription_queue/models/picked_media.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcripts/data/transcripts_repository.dart';
import 'package:extracter/src/feature/whisper_model_download/data/whisper_model_download_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Dependencies dependencies;
  late Directory support;

  setUpAll(() async {
    dependencies = await Dependencies.initialize();
    support = await getApplicationSupportDirectory();
  });

  testWidgets('download tiny, transcribe, history, search, delete', (tester) async {
    // --dart-define=FIXTURES_DIR=... works where the sandbox allows host paths
    // (iOS Simulator); otherwise stage them in the app's support directory.
    const fixturesDir = String.fromEnvironment('FIXTURES_DIR');
    final fixtures = Directory(fixturesDir.isNotEmpty ? fixturesDir : p.join(support.path, 'test_fixtures'));
    if (!File(p.join(fixtures.path, 'speech.wav')).existsSync()) {
      markTestSkipped('fixtures not staged in ${fixtures.path}');
      return;
    }
    await tester.runAsync(() async {
      final store = dependencies.modelStore;
      final tiny = WhisperModelSpec.byId('tiny')!;
      if (!store.isInstalled(tiny.id)) {
        final download = WhisperModelDownloadRepositoryImpl(
          modelStore: store,
          freeDiskBytes: dependencies.native.freeDiskBytes,
        );
        await download.download(tiny, CancelToken()).drain<void>();
      }
      expect(store.isInstalled(tiny.id), isTrue, reason: 'tiny model installed after verified download');

      final queue = TranscriptionQueueController(
        transcriptionQueueRepository: TranscriptionQueueRepositoryImpl(
          native: dependencies.native,
          modelStore: store,
          database: dependencies.database,
          inboxDirectory: dependencies.inboxDirectory,
        ),
      );
      const settings = TranscriptionSettings(modelId: 'tiny', language: 'en');
      final media = [
        for (final name in ['speech.wav', 'speech_video.mp4'])
          PickedMedia(name: name, path: p.join(fixtures.path, name), file: XFile(p.join(fixtures.path, name))),
      ];
      final rejected = await queue.enqueue(media, settings);
      expect(rejected, isEmpty);
      expect(store.reservationsOf('tiny'), 2, reason: 'each queued job reserves its model');
      await expectLater(() => store.delete('tiny'), throwsA(isA<ModelInUseException>()));

      final done = Completer<void>();
      void check() {
        if (queue.state.jobs.every((j) => j.status.isTerminal) && !done.isCompleted) done.complete();
      }

      queue.addListener(check);
      check();
      await done.future.timeout(const Duration(minutes: 3));
      queue.removeListener(check);

      for (final job in queue.state.jobs) {
        expect(job.status, QueueJobStatus.done, reason: '${job.sourceName}: ${job.failure}');
        expect(job.transcriptId, isNotNull);
        expect(job.segments.map((s) => s.text).join(' ').toLowerCase(), contains('fox'));
      }
      expect(store.reservationsOf('tiny'), 0, reason: 'reservations released exactly once');

      final transcripts = TranscriptsRepositoryImpl(database: dependencies.database);
      final found = await transcripts.transcripts(query: 'brown fox', after: null, limit: 30);
      final ids = queue.state.jobs.map((j) => j.transcriptId).toSet();
      expect(found.where((t) => ids.contains(t.id)), hasLength(2), reason: 'FTS finds both by text');
      expect(await transcripts.transcripts(query: '"   ', after: null, limit: 30), isNotEmpty);

      final detail = await TranscriptDetailRepositoryImpl(database: dependencies.database)
          .transcript(queue.state.jobs.first.transcriptId!);
      expect(detail.segments, isNotEmpty);
      expect(detail.summary.language, 'en');

      final deletion = TranscriptDeletionRepositoryImpl(database: dependencies.database);
      for (final id in ids) {
        await deletion.delete(id!);
      }
      final after = await transcripts.transcripts(query: 'brown fox', after: null, limit: 30);
      expect(after.where((t) => ids.contains(t.id)), isEmpty, reason: 'deleted rows leave the FTS index');
      final orphanSegments = await dependencies.database
          .customSelect('SELECT COUNT(*) AS c FROM segments WHERE transcript_id IN (${ids.join(',')})')
          .getSingle();
      expect(orphanSegments.read<int>('c'), 0, reason: 'segments cascade-deleted');
      queue.dispose();
    });
  });

  testWidgets('screens render (desktop + phone), saved as PNG', (tester) async {
    final out = Directory(p.join(support.path, 'screenshots'));
    await out.create(recursive: true);

    Future<void> shot(String name) async {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await tester.runAsync(() async {
        final view = tester.binding.renderViews.first;
        final layer = view.debugLayer! as OffsetLayer;
        // The root layer is already in physical pixels (it carries the DPR transform).
        final image = await layer.toImage(Offset.zero & tester.view.physicalSize);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(p.join(out.path, '$name.png')).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    Future<void> tapTab(IconData icon) async {
      await tester.tap(find.byIcon(icon).last);
      await tester.pump(const Duration(milliseconds: 300));
    }

    for (final (label, size) in [('desktop', const Size(1440, 960)), ('phone', const Size(390, 844))]) {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = size * 2;
      await tester.pumpWidget(dependencies.inject(child: const App()));
      await tester.pump(const Duration(seconds: 1));
      await shot('$label-transcribe');
      await tapTab(Icons.history);
      await shot('$label-history');
      await tapTab(Icons.memory);
      await tester.pump(const Duration(milliseconds: 500));
      await shot('$label-models');
      expect(find.text('Large v3 Turbo'), findsWidgets);
      await tapTab(Icons.graphic_eq);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    tester.view.reset();
    expect(out.listSync().whereType<File>().map((f) => p.basename(f.path)).sorted(), hasLength(6));
  });
}
