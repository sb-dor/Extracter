enum ModelDownloadFailure { cancelled, busy, lowStorage, network, server, sizeMismatch, hashMismatch, storage }

final class ModelDownloadException implements Exception {
  const ModelDownloadException(this.reason, {this.statusCode});

  final ModelDownloadFailure reason;
  final int? statusCode;
}

final class ModelDownloadProgress {
  const ModelDownloadProgress({required this.receivedBytes, required this.totalBytes});

  final int receivedBytes;
  final int totalBytes;
}
