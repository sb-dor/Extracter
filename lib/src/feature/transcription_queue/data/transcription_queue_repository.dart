import 'dart:async';
import 'dart:io';

import 'package:extracter/src/common/database/database.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:extracter/src/feature/transcription_queue/models/picked_media.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_event.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_failure.dart';
import 'package:extracter_native/extracter_native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:l/l.dart';
import 'package:path/path.dart' as p;

abstract interface class ITranscriptionQueueRepository {
  /// Validates and readies one file: reserves the model, copies a content-URI
  /// file into app storage. Throws [QueueRejectedException].
  Future<QueueJob> prepare(PickedMedia media, TranscriptionSettings settings);

  /// Runs [job] natively. Ends with exactly one completed/failed event and
  /// then releases everything the job held (reservation, input copy).
  Stream<TranscriptionEvent> transcribe(QueueJob job);

  /// Requests cancellation; the stream still ends with its final event.
  void cancel(QueueJob job);

  /// Drops a job that never ran.
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

  /// The repository is the sole owner of these; each entry is released once.
  final Map<String, ModelReservation> _reservations = <String, ModelReservation>{};
  final Map<String, File> _inputCopies = <String, File>{};
  final Map<String, int> _nativeIds = <String, int>{};
  int _nextId = 0;

  @override
  Future<QueueJob> prepare(PickedMedia media, TranscriptionSettings settings) async {
    final id = 'job-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
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

    try {
      final path = media.path;
      String mediaPath;
      if (path != null && File(path).existsSync()) {
        mediaPath = path;
      } else {
        // Content URI (Android SAF): copy the bytes into app-private storage.
        final copy = File(p.join(_inbox.path, '$id${p.extension(media.name)}'));
        final sink = copy.openWrite();
        try {
          await sink.addStream(media.file.openRead());
        } finally {
          await sink.close();
        }
        _inputCopies[id] = copy;
        mediaPath = copy.path;
      }
      _reservations[id] = reservation;
      return QueueJob(id: id, sourceName: media.name, mediaPath: mediaPath, settings: settings);
    } on Object catch (error) {
      reservation.release();
      await _deleteCopy(id);
      l.w('prepare failed: ${error.runtimeType}');
      throw QueueRejectedException(TranscriptionFailure.unreadableFile, fileName: media.name);
    }
  }

  @override
  Stream<TranscriptionEvent> transcribe(QueueJob job) {
    late final StreamController<TranscriptionEvent> controller;
    StreamSubscription<NativeJobEvent>? subscription;
    int? nativeId;
    var closed = false;

    void close() {
      if (closed) return;
      closed = true;
      subscription?.cancel().ignore();
      _nativeIds.remove(job.id);
      _releaseJob(job.id);
      controller.close().ignore();
    }

    controller = StreamController<TranscriptionEvent>(
      onListen: () {
        final reservation = _reservations[job.id];
        if (reservation == null) {
          controller.add(const TranscriptionFailed(TranscriptionFailure.modelMissing));
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
          modelPath: reservation.path,
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
        _nativeIds[job.id] = id;
      },
      onCancel: () {
        final id = nativeId;
        if (!closed && id != null) _native.cancelJob(id);
      },
    );
    return controller.stream;
  }

  @override
  void cancel(QueueJob job) {
    final id = _nativeIds[job.id];
    if (id != null) _native.cancelJob(id);
  }

  @override
  Future<void> discard(QueueJob job) async => _releaseJob(job.id);

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

  void _releaseJob(String jobId) {
    _reservations.remove(jobId)?.release();
    _deleteCopy(jobId).ignore();
  }

  Future<void> _deleteCopy(String jobId) async {
    final copy = _inputCopies.remove(jobId);
    if (copy != null && copy.existsSync()) await copy.delete();
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
