import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/utils/transcript_formatters.dart';
import 'package:extracter/src/feature/transcript_export/controller/transcript_export_controller.dart';
import 'package:extracter/src/feature/transcript_export/data/transcript_export_repository.dart';
import 'package:extracter/src/feature/transcript_export/widgets/transcript_export_format_dialog.dart';
import 'package:flutter/material.dart';

class TranscriptExportConfigInhWidget extends InheritedWidget {
  const TranscriptExportConfigInhWidget({required this.state, required super.child, super.key});

  final TranscriptExportConfigWidgetState state;

  static TranscriptExportConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<TranscriptExportConfigInhWidget>()?.widget;
    assert(widget != null, 'TranscriptExportConfigInhWidget was not found in element tree');
    return (widget! as TranscriptExportConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(TranscriptExportConfigInhWidget oldWidget) => false;
}

/// Wraps export UI (buttons in the transcript screen, or the format dialog).
class TranscriptExportConfigWidget extends StatefulWidget {
  const TranscriptExportConfigWidget({
    required this.sourceName,
    required this.segments,
    required this.builder,
    this.closeOnDone = false,
    super.key,
  });

  /// Format picker dialog, used where there is no export bar (queue rows).
  static Future<void> showFormatPicker(
    BuildContext context, {
    required String sourceName,
    required List<TranscriptSegment> segments,
  }) => showDialog<void>(
    context: context,
    builder: (context) => TranscriptExportConfigWidget(
      sourceName: sourceName,
      segments: segments,
      closeOnDone: true,
      builder: (context) => const TranscriptExportFormatDialog(),
    ),
  );

  final String sourceName;
  final List<TranscriptSegment> segments;
  final WidgetBuilder builder;
  final bool closeOnDone;

  @override
  State<TranscriptExportConfigWidget> createState() => TranscriptExportConfigWidgetState();
}

class TranscriptExportConfigWidgetState extends State<TranscriptExportConfigWidget> {
  late final TranscriptExportController transcriptExportController;
  late final ScaffoldMessengerState? _messenger = ScaffoldMessenger.maybeOf(context);

  @override
  void initState() {
    super.initState();
    transcriptExportController = TranscriptExportController(
      transcriptExportRepository: TranscriptExportRepositoryImpl(),
    )..addListener(_onState);
  }

  @override
  void dispose() {
    transcriptExportController
      ..removeListener(_onState)
      ..dispose();
    super.dispose();
  }

  void export(TranscriptFormat format, {Rect? shareOrigin}) => transcriptExportController.export(
    sourceName: widget.sourceName,
    segments: widget.segments,
    format: format,
    shareOrigin: shareOrigin,
  );

  void _onState() {
    final state = transcriptExportController.state;
    final l10n = Localization.of(context);
    switch (state) {
      case TranscriptExport$CompletedState(:final result):
        if (result == ExportResult.saved) _messenger?.showSnackBar(SnackBar(content: Text(l10n.exportSaved)));
        if (widget.closeOnDone && mounted) Navigator.maybePop(context);
      case TranscriptExport$ErrorState():
        _messenger?.showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
      case _:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => TranscriptExportConfigInhWidget(state: this, child: widget.builder(context));
}
