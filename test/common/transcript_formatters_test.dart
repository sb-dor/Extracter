import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/utils/fts_query.dart';
import 'package:extracter/src/common/utils/transcript_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const segments = [
    TranscriptSegment(startMs: 0, endMs: 3520, text: ' The quick brown fox. '),
    TranscriptSegment(startMs: 3520, endMs: 3520, text: 'Zero length --> cue'),
    TranscriptSegment(startMs: 3725000, endMs: 3726001, text: 'After an hour'),
    TranscriptSegment(startMs: 4000000, endMs: 4000100, text: '   '),
  ];

  group('TranscriptFormatters', () {
    test('timestamps pad and keep hours beyond 99', () {
      expect(TranscriptFormatters.timestamp(0, ','), '00:00:00,000');
      expect(TranscriptFormatters.timestamp(3725001, '.'), '01:02:05.001');
      expect(TranscriptFormatters.timestamp(360000000 + 1, ','), '100:00:00,001');
      expect(TranscriptFormatters.timestamp(-5, ','), '00:00:00,000');
    });

    test('TXT: one trimmed line per non-empty segment', () {
      expect(TranscriptFormatters.toTxt(segments), 'The quick brown fox.\nZero length --> cue\nAfter an hour\n');
    });

    test('SRT: numbered cues, comma millis, no zero-length cue, blanks skipped', () {
      final srt = TranscriptFormatters.toSrt(segments);
      expect(
        srt,
        '1\n00:00:00,000 --> 00:00:03,520\nThe quick brown fox.\n\n'
        '2\n00:00:03,520 --> 00:00:03,521\nZero length --> cue\n\n'
        '3\n01:02:05,000 --> 01:02:06,001\nAfter an hour\n\n',
      );
    });

    test('VTT: header, dot millis, arrow in text neutralised', () {
      final vtt = TranscriptFormatters.toVtt(segments);
      expect(vtt.startsWith('WEBVTT\n\n'), isTrue);
      expect(vtt, contains('00:00:00.000 --> 00:00:03.520\nThe quick brown fox.'));
      expect(vtt, contains('Zero length -> cue'));
      expect(vtt, isNot(contains('   \n')));
    });

    test('empty transcript', () {
      expect(TranscriptFormatters.toTxt(const []), '');
      expect(TranscriptFormatters.toSrt(const []), '');
      expect(TranscriptFormatters.toVtt(const []), 'WEBVTT\n\n');
    });
  });

  group('ftsPrefixQuery', () {
    test('quotes every token as a prefix term', () {
      expect(ftsPrefixQuery('brown fox'), '"brown"* "fox"*');
      expect(ftsPrefixQuery('  привет  мир '), '"привет"* "мир"*');
    });

    test('strips quotes so FTS syntax cannot be injected', () {
      expect(ftsPrefixQuery('a" OR "b'), '"a"* "OR"* "b"*');
      expect(ftsPrefixQuery('NEAR(x y)'), '"NEAR(x"* "y)"*');
    });

    test('blank, whitespace and quote-only input bypasses FTS', () {
      expect(ftsPrefixQuery(''), isNull);
      expect(ftsPrefixQuery('   \t\n'), isNull);
      expect(ftsPrefixQuery('"  ""  "'), isNull);
    });
  });
}
