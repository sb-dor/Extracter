/// Why a queue job did not produce a transcript (or was refused).
enum TranscriptionFailure {
  cancelled,
  openFailed,
  decodeFailed,
  noAudio,
  modelFailed,
  modelMissing,
  outOfMemory,
  timeout,
  lowStorage,
  unreadableFile,
  saveFailed,
  internal,
}

/// Thrown by `prepare` when a file cannot be added to the queue.
final class QueueRejectedException implements Exception {
  const QueueRejectedException(this.reason, {required this.fileName});

  final TranscriptionFailure reason;
  final String fileName;
}
