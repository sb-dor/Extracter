// Starts a native job on a long file, cancels it mid-transcription and waits
// for its DONE event; the process must survive the worker's final posts.
//
//   flutter test integration_test/cancel_test.dart -d <device> --dart-define=FIXTURES_DIR=<dir>

import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/feature/whisper_model_download/data/whisper_model_download_repository.dart';
import 'package:extracter/src/feature/whisper_model_download/models/model_download.dart';
import 'package:extracter_native/extracter_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cancel mid-transcription', (tester) async {
    const fixturesDir = String.fromEnvironment('FIXTURES_DIR');
    await tester.runAsync(() async {
      final dependencies = await Dependencies.initialize();
      final spec = WhisperModelSpec.byId('base')!;
      final native = dependencies.native;
      if (!dependencies.modelStore.isInstalled(spec.id)) {
        await WhisperModelDownloadRepositoryImpl(
          modelStore: dependencies.modelStore,
          freeDiskBytes: native.freeDiskBytes,
        ).download(spec, DownloadCancelToken()).drain<void>();
      }
      final events = <NativeJobEvent>[];
      final sub = native.events.listen(events.add);
      final id = native.startJob(
        mediaPath: p.join(fixturesDir, 'long_boundary.m4a'),
        modelPath: dependencies.modelStore.filePath(spec),
        language: 'auto',
        translate: false,
        threads: 4,
      );
      expect(id, greaterThan(0));
      await Future<void>.delayed(const Duration(seconds: 15));
      native.cancelJob(id);
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!events.any((e) => e is NativeDone) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await sub.cancel();
      final done = events.whereType<NativeDone>().single;
      // ignore: avoid_print
      print('events=${events.length} segments=${events.whereType<NativeSegment>().length} status=${done.status}');
      expect(done.status, NativeJobStatus.cancelled);
    });
  });
}
