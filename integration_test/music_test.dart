// Transcribes one music file through the real queue on the device and prints a
// summary (timings, segment count, language) — never the lyrics themselves.
//
//   flutter test integration_test/music_test.dart -d <device> \
//     --dart-define=FIXTURES_DIR=<dir> --dart-define=MUSIC_FILE=MeekerBallGame.ogg
import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/feature/transcription_queue/controller/transcription_queue_controller.dart';
import 'package:extracter/src/feature/transcription_queue/data/transcription_queue_repository.dart';
import 'package:extracter/src/feature/transcription_queue/models/picked_media.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/whisper_model_download/data/whisper_model_download_repository.dart';
import 'package:extracter/src/feature/whisper_model_download/models/model_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('transcribes a music file', (tester) async {
    const fixturesDir = String.fromEnvironment('FIXTURES_DIR');
    const musicFile = String.fromEnvironment('MUSIC_FILE', defaultValue: 'MeekerBallGame.ogg');
    const modelId = String.fromEnvironment('MODEL', defaultValue: 'tiny');
    await tester.runAsync(() async {
      final dependencies = await Dependencies.initialize();
      final support = await getApplicationSupportDirectory();
      final dir = fixturesDir.isNotEmpty ? fixturesDir : p.join(support.path, 'test_fixtures');
      final path = p.join(dir, musicFile);
      expect(File(path).existsSync(), isTrue, reason: 'music file not found at $path');

      final spec = WhisperModelSpec.byId(modelId)!;
      if (!dependencies.modelStore.isInstalled(spec.id)) {
        await WhisperModelDownloadRepositoryImpl(
          modelStore: dependencies.modelStore,
          freeDiskBytes: dependencies.native.freeDiskBytes,
        ).download(spec, DownloadCancelToken()).drain<void>();
      }

      final queue = TranscriptionQueueController(
        transcriptionQueueRepository: TranscriptionQueueRepositoryImpl(
          native: dependencies.native,
          modelStore: dependencies.modelStore,
          database: dependencies.database,
          inboxDirectory: dependencies.inboxDirectory,
        ),
      );
      final started = DateTime.now();
      final rejected = await queue.enqueue([
        PickedMedia(name: musicFile, path: path, file: XFile(path)),
      ], TranscriptionSettings(modelId: spec.id));
      expect(rejected, isEmpty);

      final done = Completer<void>();
      void check() {
        if (queue.state.jobs.every((j) => j.status.isTerminal) && !done.isCompleted) done.complete();
      }

      queue.addListener(check);
      check();
      await done.future.timeout(const Duration(minutes: 10));
      final elapsed = DateTime.now().difference(started);
      final job = queue.state.jobs.single;
      final text = job.segments.map((s) => s.text.toLowerCase()).join(' ');
      final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      final unique = job.segments.map((s) => s.text).toSet().length;

      // ignore: avoid_print
      print(
        'MUSIC_RESULT platform=${Platform.operatingSystem} model=${spec.id} status=${job.status.name} '
        'language=${job.detectedLanguage} durationMs=${job.durationMs} elapsedMs=${elapsed.inMilliseconds} '
        'segments=${job.segments.length} unique=$unique words=$words '
        'firstMs=${job.segments.firstOrNull?.startMs} lastEndMs=${job.segments.lastOrNull?.endMs} '
        'titleHits=${'ball game'.allMatches(text).length}',
      );

      // Degenerate output (one repeated token) is safe to show and helps debugging.
      if (unique <= 2) {
        // ignore: avoid_print
        print('MUSIC_DEGENERATE ${job.segments.map((s) => s.text).toSet().toList()}');
      }
      expect(job.status, QueueJobStatus.done, reason: '${job.failure}');
      expect(job.detectedLanguage, 'en');
      expect(job.segments.length, greaterThanOrEqualTo(10));
      expect(job.segments.last.endMs, greaterThan(100000), reason: 'whole song covered');
      expect(unique, greaterThan(5), reason: 'not one repeated token');
      queue.dispose();
    });
  });
}
