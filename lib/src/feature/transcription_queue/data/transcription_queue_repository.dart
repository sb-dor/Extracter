import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:extracter/src/common/database/database.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:extracter/src/common/utils/cancel_token.dart';
import 'package:extracter/src/feature/transcription_queue/models/job_resources.dart';
import 'package:extracter/src/feature/transcription_queue/models/picked_media.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_event.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_failure.dart';
import 'package:extracter_native/extracter_native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:l/l.dart';
import 'package:path/path.dart' as p;

/// Stateless: what a job holds travels with it ([QueueJob.resources]) and
/// cancelling goes through the caller's [CancelToken].
abstract interface class ITranscriptionQueueRepository {
  /// Validates and readies one file: reserves the model, copies a content-URI
  /// file into app storage. Throws [QueueRejectedException].
  Future<QueueJob> prepare(PickedMedia media, TranscriptionSettings settings);

  /// Runs [job] natively once listened to. Ends with exactly one
  /// completed/failed event and then releases the job's resources.
  ///
  /// [token] asks native to stop; the stream still ends with its final event
  /// (cancelled), so the next job never starts while this one unwinds.
  Stream<TranscriptionEvent> transcribe(QueueJob job, CancelToken token);

  /// Drops a job that never ran, releasing its resources.
  Future<void> discard(QueueJob job);

  /// Stores a finished job in history; returns the transcript id.
  Future<int> save(QueueJob job);

  /// Called when the queue drains.
  Future<void> clearTemporaryFiles();
}

final class TranscriptionQueueRepositoryImpl implements ITranscriptionQueueRepository {
  TranscriptionQueueRepositoryImpl({
    required IExtracterNative native,
    required ModelStore modelStore,
    required AppDatabase database,
    required Directory inboxDirectory,
    int? threads,
  }) : _native = native,
       _modelStore = modelStore,
       _database = database,
       _inbox = inboxDirectory,
       _threads = threads ?? (Platform.numberOfProcessors - 1).clamp(1, 8);

  /// Below this, a job could not even store its transcript.
  static const int minFreeBytes = 100 * 1000 * 1000;

  final IExtracterNative _native;
  final ModelStore _modelStore;
  final AppDatabase _database;
  final Directory _inbox;
  final int _threads;

  static final math.Random _random = math.Random();

  @override
  Future<QueueJob> prepare(PickedMedia media, TranscriptionSettings settings) async {
    final id = 'job-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
    final free = _native.freeDiskBytes(_inbox.path);
    if (free != null && free < minFreeBytes) {
      throw QueueRejectedException(TranscriptionFailure.lowStorage, fileName: media.name);
    }

    final ModelReservation reservation;
    try {
      reservation = _modelStore.reserve(settings.modelId);
    } on ModelNotInstalledException {
      throw QueueRejectedException(TranscriptionFailure.modelMissing, fileName: media.name);
    }

    File? copy;
    try {
      final path = media.path;
      String mediaPath;
      if (path != null && File(path).existsSync()) {
        mediaPath = path;
      } else {
        // Content URI (Android SAF): copy the bytes into app-private storage.
        final file = copy = File(p.join(_inbox.path, '$id${p.extension(media.name)}'));
        final sink = file.openWrite();
        try {
          await sink.addStream(media.file.openRead());
        } finally {
          await sink.close();
        }
        mediaPath = file.path;
      }
      return QueueJob(
        id: id,
        sourceName: media.name,
        mediaPath: mediaPath,
        settings: settings,
        resources: JobResources(reservation: reservation, inputCopy: copy),
      );
    } on Object catch (error) {
      await JobResources(reservation: reservation, inputCopy: copy).release();
      l.w('prepare failed: ${error.runtimeType}');
      throw QueueRejectedException(TranscriptionFailure.unreadableFile, fileName: media.name);
    }
  }

  @override
  Stream<TranscriptionEvent> transcribe(QueueJob job, CancelToken token) {
    // Everything below belongs to this one stream and ends with it.
    late final StreamController<TranscriptionEvent> controller;
    StreamSubscription<NativeJobEvent>? subscription;
    int? nativeId;
    var closed = false;

    void close() {
      if (closed) return;
      closed = true;
      token.onCancel = null;
      subscription?.cancel().ignore();
      job.resources?.release().ignore();
      controller.close().ignore();
    }

    controller = StreamController<TranscriptionEvent>(
      onListen: () {
        final modelPath = job.resources?.modelPath;
        if (modelPath == null) {
          controller.add(const TranscriptionFailed(TranscriptionFailure.modelMissing));
          close();
          return;
        }
        if (token.isCancelled) {
          controller.add(const TranscriptionFailed(TranscriptionFailure.cancelled));
          close();
          return;
        }
        // Events are delivered asynchronously, so none can arrive before
        // nativeId is assigned below.
        subscription = _native.events.listen((event) {
          if (closed || event.jobId != nativeId) return;
          switch (event) {
            case NativeProgress(:final permille, :final durationMs):
              controller.add(TranscriptionProgress(permille: permille < 0 ? null : permille, durationMs: durationMs));
            case NativeSegment(:final startMs, :final endMs, :final text):
              controller.add(TranscriptionSegmentAdded(TranscriptSegment(startMs: startMs, endMs: endMs, text: text)));
            case NativeLog(:final json):
              l.d('native job ${event.jobId}: $json');
            case NativeDone(:final status, :final detectedLanguage, :final durationMs, :final nativeCode):
              if (status == NativeJobStatus.ok) {
                controller.add(TranscriptionCompleted(detectedLanguage: detectedLanguage, durationMs: durationMs));
              } else {
                l.i('native job ${event.jobId} ended: ${status.name} ($nativeCode)');
                controller.add(TranscriptionFailed(_failureOf(status)));
              }
              close();
          }
        });
        final id = _native.startJob(
          mediaPath: job.mediaPath,
          modelPath: modelPath,
          language: job.settings.language,
          translate: job.settings.translate,
          threads: _threads,
        );
        if (id <= 0) {
          // No DONE will follow a synchronous start failure.
          controller.add(TranscriptionFailed(_failureOf(NativeJobStatus.fromCode(-id))));
          close();
          return;
        }
        nativeId = id;
        token.onCancel = () => _native.cancelJob(id);
      },
      onCancel: () {
        final id = nativeId;
        if (!closed && id != null) _native.cancelJob(id);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> discard(QueueJob job) async => job.resources?.release();

  @override
  Future<int> save(QueueJob job) => _database.insertTranscript(job.toNewTranscript(DateTime.now()));

  @override
  Future<void> clearTemporaryFiles() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await FilePicker.clearTemporaryFiles();
    } on Object catch (error) {
      l.w('clearTemporaryFiles failed: ${error.runtimeType}');
    }
  }

  static TranscriptionFailure _failureOf(NativeJobStatus status) => switch (status) {
    NativeJobStatus.ok => TranscriptionFailure.internal,
    NativeJobStatus.cancelled => TranscriptionFailure.cancelled,
    NativeJobStatus.openFailed => TranscriptionFailure.openFailed,
    NativeJobStatus.decodeFailed => TranscriptionFailure.decodeFailed,
    NativeJobStatus.modelFailed => TranscriptionFailure.modelFailed,
    NativeJobStatus.noAudio => TranscriptionFailure.noAudio,
    NativeJobStatus.outOfMemory => TranscriptionFailure.outOfMemory,
    NativeJobStatus.timeout => TranscriptionFailure.timeout,
    NativeJobStatus.internal => TranscriptionFailure.internal,
  };
}
