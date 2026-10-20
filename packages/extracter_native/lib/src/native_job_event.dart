import 'package:meta/meta.dart';

/// Terminal status of a native job — mirrors `ex_status` in extracter_native.h.
enum NativeJobStatus {
  ok(0),
  cancelled(1),
  openFailed(2),
  decodeFailed(3),
  modelFailed(4),
  noAudio(5),
  outOfMemory(6),
  internal(7),
  timeout(8);

  const NativeJobStatus(this.code);

  final int code;

  static NativeJobStatus fromCode(int code) =>
      values.firstWhere((s) => s.code == code, orElse: () => NativeJobStatus.internal);
}

/// One event posted by a native job. Every job ends with exactly one [NativeDone].
@immutable
sealed class NativeJobEvent {
  const NativeJobEvent(this.jobId);

  final int jobId;
}

/// [permille] is 0..999, or -1 when the media duration is unknown.
final class NativeProgress extends NativeJobEvent {
  const NativeProgress(super.jobId, {required this.permille, required this.durationMs});

  final int permille;
  final int? durationMs;
}

/// A transcribed segment; times are media presentation time in milliseconds.
final class NativeSegment extends NativeJobEvent {
  const NativeSegment(super.jobId, {required this.startMs, required this.endMs, required this.text});

  final int startMs;
  final int endMs;
  final String text;
}

/// Allowlisted structured diagnostics (JSON); never paths or transcript text.
final class NativeLog extends NativeJobEvent {
  const NativeLog(super.jobId, this.json);

  final String json;
}

final class NativeDone extends NativeJobEvent {
  const NativeDone(
    super.jobId, {
    required this.status,
    required this.nativeCode,
    required this.detectedLanguage,
    required this.durationMs,
  });

  final NativeJobStatus status;

  /// Numeric FFmpeg `AVERROR` / whisper return code, 0 if none.
  final int nativeCode;
  final String? detectedLanguage;
  final int? durationMs;
}
