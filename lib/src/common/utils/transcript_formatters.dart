import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/utils/format_util.dart';

enum TranscriptFormat {
  txt('txt', 'text/plain'),
  srt('srt', 'application/x-subrip'),
  vtt('vtt', 'text/vtt'),
  md('md', 'text/markdown');

  const TranscriptFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

/// Pure exporters for transcript segments.
abstract final class TranscriptFormatters {
  static String format(TranscriptFormat format, List<TranscriptSegment> segments, {String? title}) => switch (format) {
    TranscriptFormat.txt => toTxt(segments),
    TranscriptFormat.srt => toSrt(segments),
    TranscriptFormat.vtt => toVtt(segments),
    TranscriptFormat.md => toMarkdown(segments, title: title),
  };

  /// Clipboard text: one paragraph per segment with a blank line between them.
  /// [withTimestamps] prefixes each paragraph with `[00:00:00 → 00:00:07]`.
  static String toClipboard(List<TranscriptSegment> segments, {bool withTimestamps = false}) => [
    for (final s in segments)
      if (s.text.trim().isNotEmpty)
        withTimestamps
            ? '[${FormatUtil.clock(s.startMs)} → ${FormatUtil.clock(s.endMs)}] ${s.text.trim()}'
            : s.text.trim(),
  ].join('\n\n');

  /// One segment per line.
  static String toTxt(List<TranscriptSegment> segments) {
    final buffer = StringBuffer();
    for (final s in segments) {
      final text = s.text.trim();
      if (text.isNotEmpty) buffer.writeln(text);
    }
    return buffer.toString();
  }

  /// SubRip: numbered cues, `HH:MM:SS,mmm --> HH:MM:SS,mmm`.
  static String toSrt(List<TranscriptSegment> segments) {
    final buffer = StringBuffer();
    var index = 1;
    for (final s in segments) {
      final text = s.text.trim();
      if (text.isEmpty) continue;
      buffer
        ..writeln(index++)
        ..writeln('${timestamp(s.startMs, ',')} --> ${timestamp(_end(s), ',')}')
        ..writeln(text)
        ..writeln();
    }
    return buffer.toString();
  }

  /// Markdown: optional `# title`, then one paragraph per segment.
  /// [withTimestamps] prefixes each paragraph with `**[00:01:12]**`.
  static String toMarkdown(List<TranscriptSegment> segments, {String? title, bool withTimestamps = true}) {
    final paragraphs = [
      for (final s in segments)
        if (s.text.trim().isNotEmpty)
          withTimestamps ? '**[${FormatUtil.clock(s.startMs)}]** ${s.text.trim()}' : s.text.trim(),
    ];
    final body = paragraphs.join('\n\n');
    final heading = title?.trim();
    if (heading == null || heading.isEmpty) return body.isEmpty ? '' : '$body\n';
    if (body.isEmpty) return '# $heading\n';
    return '# $heading\n\n$body\n';
  }

  /// WebVTT: `WEBVTT` header, `HH:MM:SS.mmm --> HH:MM:SS.mmm` cues.
  static String toVtt(List<TranscriptSegment> segments) {
    final buffer = StringBuffer('WEBVTT\n\n');
    for (final s in segments) {
      // "-->" inside cue text would end the cue timing line early.
      final text = s.text.trim().replaceAll('-->', '->');
      if (text.isEmpty) continue;
      buffer
        ..writeln('${timestamp(s.startMs, '.')} --> ${timestamp(_end(s), '.')}')
        ..writeln(text)
        ..writeln();
    }
    return buffer.toString();
  }

  /// `HH:MM:SS<sep>mmm`; hours are not capped at 99.
  static String timestamp(int ms, String millisSeparator) {
    final clamped = ms < 0 ? 0 : ms;
    final h = clamped ~/ 3600000;
    final m = clamped ~/ 60000 % 60;
    final s = clamped ~/ 1000 % 60;
    final millis = clamped % 1000;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}$millisSeparator${millis.toString().padLeft(3, '0')}';
  }

  // Players reject zero-length cues.
  static int _end(TranscriptSegment s) => s.endMs > s.startMs ? s.endMs : s.startMs + 1;
}
