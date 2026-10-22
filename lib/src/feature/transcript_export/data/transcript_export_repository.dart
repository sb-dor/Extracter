import 'dart:io';
import 'dart:ui';

import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/utils/transcript_formatters.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum ExportResult { saved, shared, cancelled }

abstract interface class ITranscriptExportRepository {
  Future<ExportResult> export({
    required String sourceName,
    required List<TranscriptSegment> segments,
    required TranscriptFormat format,
    Rect? shareOrigin,
  });
}

/// Desktop: "Save as" dialog. Mobile: a temp file handed to the share sheet.
final class TranscriptExportRepositoryImpl implements ITranscriptExportRepository {
  TranscriptExportRepositoryImpl({bool? useShareSheet})
    : _share = useShareSheet ?? (Platform.isAndroid || Platform.isIOS);

  final bool _share;

  @override
  Future<ExportResult> export({
    required String sourceName,
    required List<TranscriptSegment> segments,
    required TranscriptFormat format,
    Rect? shareOrigin,
  }) async {
    final content = TranscriptFormatters.format(format, segments, title: exportBaseName(sourceName));
    final fileName = '${exportBaseName(sourceName)}.${format.extension}';
    if (!_share) {
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          XTypeGroup(label: format.extension.toUpperCase(), extensions: [format.extension]),
        ],
      );
      if (location == null) return ExportResult.cancelled;
      await File(location.path).writeAsString(content, flush: true);
      return ExportResult.saved;
    }
    final directory = Directory(p.join((await getTemporaryDirectory()).path, 'exports'));
    if (directory.existsSync()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, fileName));
    await file.writeAsString(content, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: format.mimeType)],
        subject: fileName,
        sharePositionOrigin: shareOrigin,
      ),
    );
    return result.status == ShareResultStatus.dismissed ? ExportResult.cancelled : ExportResult.shared;
  }

  /// "voice-note-0912.ogg" → "voice-note-0912"; strips path separators.
  static String exportBaseName(String sourceName) {
    final base = p.basenameWithoutExtension(sourceName).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return base.isEmpty ? 'transcript' : base;
  }
}
