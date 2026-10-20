import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/feature/transcription_queue/controller/transcription_queue_controller.dart';
import 'package:extracter/src/feature/transcription_queue/data/transcription_queue_repository.dart';
import 'package:extracter/src/feature/transcription_queue/models/picked_media.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_event.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_failure.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each job's stream is driven by the test through [streams].
final class FakeQueueRepository implements ITranscriptionQueueRepository {
  final Map<String, StreamController<TranscriptionEvent>> streams = {};
  final List<String> cancelled = [];
  final List<String> discarded = [];
  final List<String> started = [];
  final Set<String> rejectNames = {};
  bool failSave = false;
  int _id = 0;
  int _saved = 0;

  @override
  Future<QueueJob> prepare(PickedMedia media, TranscriptionSettings settings) async {
    if (rejectNames.contains(media.name)) {
      throw QueueRejectedException(TranscriptionFailure.modelMissing, fileName: media.name);
    }
    final id = 'j${_id++}';
    streams[id] = StreamController<TranscriptionEvent>();
    return QueueJob(id: id, sourceName: media.name, mediaPath: '/tmp/${media.name}', settings: settings);
  }

  @override
  Stream<TranscriptionEvent> transcribe(QueueJob job) {
    started.add(job.id);
    return streams[job.id]!.stream;
  }

  @override
  void cancel(QueueJob job) => cancelled.add(job.id);

  @override
  Future<void> discard(QueueJob job) async => discarded.add(job.id);

  @override
  Future<int> save(QueueJob job) async {
    if (failSave) throw StateError('disk full');
    return ++_saved;
  }

  @override
  Future<void> clearTemporaryFiles() async {}

  Future<void> finish(String id, TranscriptionEvent last, {List<TranscriptSegment> segments = const []}) async {
    final c = streams[id]!;
    for (final s in segments) {
      c.add(TranscriptionSegmentAdded(s));
    }
    c.add(last);
    await c.close();
  }
}

PickedMedia media(String name) => PickedMedia(name: name, path: '/tmp/$name', file: XFile('/tmp/$name'));

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late FakeQueueRepository repo;
  late TranscriptionQueueController queue;
  const settings = TranscriptionSettings(modelId: 'base', language: 'auto', translate: true);

  setUp(() {
    repo = FakeQueueRepository();
    queue = TranscriptionQueueController(transcriptionQueueRepository: repo);
  });

  tearDown(() => queue.dispose());

  QueueJob job(String id) => queue.state.jobs.firstWhere((j) => j.id == id);

  test('runs jobs one at a time with their settings snapshot; saves on success', () async {
    await queue.enqueue([media('a.mp3'), media('b.mkv')], settings);
    await settle();
    expect(repo.started, ['j0'], reason: 'second job waits');
    expect(job('j0').status, QueueJobStatus.running);
    expect(job('j1').status, QueueJobStatus.pending);
    expect(job('j1').settings, settings);
    expect(queue.state, isA<TranscriptionQueue$ProcessingState>());

    repo.streams['j0']!.add(const TranscriptionProgress(permille: 420, durationMs: 60000));
    await settle();
    expect(job('j0').permille, 420);
    expect(job('j0').durationMs, 60000);

    await repo.finish(
      'j0',
      const TranscriptionCompleted(detectedLanguage: 'ru', durationMs: 60000),
      segments: const [TranscriptSegment(startMs: 0, endMs: 1000, text: 'Привет')],
    );
    await settle();
    expect(job('j0').status, QueueJobStatus.done);
    expect(job('j0').transcriptId, 1);
    expect(job('j0').detectedLanguage, 'ru');
    expect(job('j0').segments.single.text, 'Привет');
    expect(repo.started, ['j0', 'j1']);

    await repo.finish('j1', const TranscriptionFailed(TranscriptionFailure.noAudio));
    await settle();
    expect(job('j1').status, QueueJobStatus.failed);
    expect(job('j1').failure, TranscriptionFailure.noAudio);
    expect(queue.state, isA<TranscriptionQueue$IdleState>());
  });

  test('cancel pending removes and discards; cancel running waits for native ack', () async {
    await queue.enqueue([media('a'), media('b')], settings);
    await settle();
    queue.cancel('j1');
    expect(queue.state.jobs.map((j) => j.id), ['j0']);
    expect(repo.discarded, ['j1']);

    queue.cancel('j0');
    expect(job('j0').status, QueueJobStatus.cancelling);
    expect(repo.cancelled, ['j0']);
    // The queue does not move on until the stream ends with the cancel result.
    await queue.enqueue([media('c')], settings);
    await settle();
    expect(repo.started, ['j0'], reason: 'next job must not start while cancelling');

    await repo.finish('j0', const TranscriptionFailed(TranscriptionFailure.cancelled));
    await settle();
    expect(job('j0').status, QueueJobStatus.cancelled);
    expect(repo.started, ['j0', 'j2']);
  });

  test('cancel is out-of-band: works while the runner awaits the stream', () async {
    await queue.enqueue([media('a')], settings);
    await settle();
    expect(queue.isProcessing, isTrue);
    queue.cancel('j0');
    expect(repo.cancelled, ['j0'], reason: 'not queued behind handle()');
  });

  test('history write failure keeps the transcript as completedUnsaved', () async {
    repo.failSave = true;
    await queue.enqueue([media('a')], settings);
    await settle();
    await repo.finish(
      'j0',
      const TranscriptionCompleted(detectedLanguage: 'en', durationMs: 1000),
      segments: const [TranscriptSegment(startMs: 0, endMs: 900, text: 'kept')],
    );
    await settle();
    expect(job('j0').status, QueueJobStatus.completedUnsaved);
    expect(job('j0').failure, TranscriptionFailure.saveFailed);
    expect(job('j0').segments.single.text, 'kept');

    queue.clearFinished();
    expect(queue.state.jobs, hasLength(1), reason: 'unsaved work is never cleared');
    queue.remove('j0');
    expect(queue.state.jobs, hasLength(1));

    queue.markSaved('j0', 42);
    expect(job('j0').status, QueueJobStatus.done);
    expect(job('j0').transcriptId, 42);
    queue.clearFinished();
    expect(queue.state.jobs, isEmpty);
  });

  test('rejected files are reported and never enter the queue', () async {
    repo.rejectNames.add('bad.mp3');
    final rejected = await queue.enqueue([media('bad.mp3'), media('ok.mp3')], settings);
    expect(rejected.single.fileName, 'bad.mp3');
    expect(rejected.single.reason, TranscriptionFailure.modelMissing);
    expect(queue.state.jobs.map((j) => j.sourceName), ['ok.mp3']);
  });

  test('a stream that ends without a final event is a failure, not a hang', () async {
    await queue.enqueue([media('a')], settings);
    await settle();
    await repo.streams['j0']!.close();
    await settle();
    expect(job('j0').status, QueueJobStatus.failed);
    expect(job('j0').failure, TranscriptionFailure.internal);
  });

  test('toNewTranscript stores the detected language, else the chosen one', () {
    const base = QueueJob(
      id: 'x',
      sourceName: 'a.m4a',
      mediaPath: '/a',
      settings: TranscriptionSettings(language: 'uz'),
    );
    expect(base.toNewTranscript(DateTime(2026)).language, 'uz');
    expect(base.copyWith(detectedLanguage: () => 'ru').toNewTranscript(DateTime(2026)).language, 'ru');
    const auto = QueueJob(id: 'y', sourceName: 'b', mediaPath: '/b', settings: TranscriptionSettings());
    expect(auto.toNewTranscript(DateTime(2026)).language, isNull);
  });
}
