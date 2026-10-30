import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:extracter/src/common/database/database.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:extracter/src/common/utils/cancel_token.dart';
import 'package:extracter/src/feature/transcription_queue/data/transcription_queue_repository.dart';
import 'package:extracter/src/feature/transcription_queue/models/picked_media.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_event.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_failure.dart';
import 'package:extracter_native/extracter_native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Native engine stand-in: jobs start with increasing ids and the test posts their events.
final class FakeNative implements IExtracterNative {
  final StreamController<NativeJobEvent> _events = StreamController<NativeJobEvent>.broadcast();
  final List<String> startedModels = [];
  final List<int> cancelled = [];

  @override
  Stream<NativeJobEvent> get events => _events.stream;

  void post(NativeJobEvent event) => _events.add(event);

  void done(int jobId, NativeJobStatus status) =>
      post(NativeDone(jobId, status: status, nativeCode: 0, detectedLanguage: 'en', durationMs: 1000));

  @override
  int startJob({
    required String mediaPath,
    required String modelPath,
    required String language,
    required bool translate,
    required int threads,
  }) {
    startedModels.add(modelPath);
    return startedModels.length;
  }

  @override
  void cancelJob(int jobId) => cancelled.add(jobId);

  @override
  int? freeDiskBytes(String directory) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late ModelStore store;
  late FakeNative native;
  const settings = TranscriptionSettings(modelId: 'tiny');
  final tiny = WhisperModelSpec.byId('tiny')!;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('queue_repository_test');
    await Directory('${dir.path}/models').create();
    await File('${dir.path}/models/${tiny.fileName}').writeAsBytes(Uint8List(tiny.sizeBytes));
    store = ModelStore(directory: Directory('${dir.path}/models'));
    await store.initialize();
    native = FakeNative();
  });

  tearDown(() => dir.delete(recursive: true));

  TranscriptionQueueRepositoryImpl repository() => TranscriptionQueueRepositoryImpl(
    native: native,
    modelStore: store,
    // Never touched by these tests: nothing is saved.
    database: _NoDatabase(),
    inboxDirectory: dir,
    threads: 1,
  );

  // A content URI (Android): no file path, so prepare copies the bytes.
  PickedMedia contentUri() => PickedMedia(
    name: 'voice.m4a',
    path: null,
    file: XFile.fromData(Uint8List(16), name: 'voice.m4a'),
  );

  test('a job prepared by one instance runs on another: the repository keeps no state', () async {
    final job = await repository().prepare(contentUri(), settings);
    expect(store.reservationsOf('tiny'), 1);
    final copy = File(job.mediaPath);
    expect(copy.existsSync(), isTrue);

    final events = <TranscriptionEvent>[];
    final ended = repository().transcribe(job, CancelToken()).forEach(events.add);
    await pumpEventQueue();
    native
      ..post(const NativeProgress(1, permille: 500, durationMs: 1000))
      ..post(const NativeSegment(1, startMs: 0, endMs: 900, text: 'hello'))
      ..done(1, NativeJobStatus.ok);
    await ended;

    expect(native.startedModels, [store.filePath(tiny)]);
    expect(events.last, isA<TranscriptionCompleted>());
    await pumpEventQueue();
    expect(store.reservationsOf('tiny'), 0, reason: 'the model is released when the job ends');
    expect(copy.existsSync(), isFalse, reason: 'the copied file is deleted when the job ends');
  });

  test('cancelling asks native to stop, and the stream still ends with the result', () async {
    final job = await repository().prepare(contentUri(), settings);
    final token = CancelToken();
    final events = <TranscriptionEvent>[];
    final ended = repository().transcribe(job, token).forEach(events.add);
    await pumpEventQueue();

    token.cancel();
    expect(native.cancelled, [1]);
    expect(store.reservationsOf('tiny'), 1, reason: 'native still holds the model until it stops');

    native.done(1, NativeJobStatus.cancelled);
    await ended;
    expect(events.single, isA<TranscriptionFailed>().having((e) => e.reason, 'reason', TranscriptionFailure.cancelled));
    await pumpEventQueue();
    expect(store.reservationsOf('tiny'), 0);
  });

  test('a token cancelled before the job starts never reaches native', () async {
    final job = await repository().prepare(contentUri(), settings);
    final events = await repository().transcribe(job, CancelToken()..cancel()).toList();

    expect(native.startedModels, isEmpty);
    expect(events.single, isA<TranscriptionFailed>().having((e) => e.reason, 'reason', TranscriptionFailure.cancelled));
    await pumpEventQueue();
    expect(store.reservationsOf('tiny'), 0);
  });

  test('discarding releases what the job held, once', () async {
    final job = await repository().prepare(contentUri(), settings);
    await repository().discard(job);
    await repository().discard(job);

    expect(store.reservationsOf('tiny'), 0);
    expect(File(job.mediaPath).existsSync(), isFalse);
    final events = await repository().transcribe(job, CancelToken()).toList();
    expect(
      events.single,
      isA<TranscriptionFailed>().having((e) => e.reason, 'reason', TranscriptionFailure.modelMissing),
    );
  });
}

final class _NoDatabase implements AppDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
