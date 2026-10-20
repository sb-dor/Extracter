enum ModelDownloadFailure { cancelled, busy, lowStorage, network, server, sizeMismatch, hashMismatch, storage }

final class ModelDownloadException implements Exception {
  const ModelDownloadException(this.reason, {this.statusCode});

  final ModelDownloadFailure reason;
  final int? statusCode;
}

/// Cancels an in-flight download; idempotent.
final class DownloadCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  set onCancel(void Function()? callback) => _onCancel = callback;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

final class ModelDownloadProgress {
  const ModelDownloadProgress({required this.receivedBytes, required this.totalBytes});

  final int receivedBytes;
  final int totalBytes;
}
