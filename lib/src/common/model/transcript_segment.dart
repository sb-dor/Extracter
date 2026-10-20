import 'package:flutter/foundation.dart';

/// One timestamped piece of a transcript (media time in milliseconds).
@immutable
class TranscriptSegment {
  const TranscriptSegment({required this.startMs, required this.endMs, required this.text});

  final int startMs;
  final int endMs;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is TranscriptSegment && other.startMs == startMs && other.endMs == endMs && other.text == text;

  @override
  int get hashCode => Object.hash(startMs, endMs, text);
}
