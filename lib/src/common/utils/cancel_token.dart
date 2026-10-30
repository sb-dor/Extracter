/// Cancels a long-running operation (a download, a transcription); idempotent.
///
/// The caller keeps the token; the repository only reads it, so the repository
/// itself keeps no record of what is running.
final class CancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  /// Runs once on [cancel]; set it to null when the operation ends.
  set onCancel(void Function()? callback) => _onCancel = callback;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}
