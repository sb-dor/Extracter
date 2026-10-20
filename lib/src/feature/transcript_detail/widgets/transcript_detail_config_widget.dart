import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/utils/screen_util.dart';
import 'package:extracter/src/common/widget/app_shell.dart';
import 'package:extracter/src/feature/transcript_deletion/widgets/transcript_deletion_config_widget.dart';
import 'package:extracter/src/feature/transcript_detail/controller/transcript_detail_controller.dart';
import 'package:extracter/src/feature/transcript_detail/data/transcript_detail_repository.dart';
import 'package:extracter/src/feature/transcript_detail/widgets/desktop/transcript_detail_desktop_widget.dart';
import 'package:extracter/src/feature/transcript_detail/widgets/mobile/transcript_detail_mobile_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TranscriptDetailConfigInhWidget extends InheritedWidget {
  const TranscriptDetailConfigInhWidget({required this.state, required super.child, super.key});

  final TranscriptDetailConfigWidgetState state;

  static TranscriptDetailConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<TranscriptDetailConfigInhWidget>()?.widget;
    assert(widget != null, 'TranscriptDetailConfigInhWidget was not found in element tree');
    return (widget! as TranscriptDetailConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(TranscriptDetailConfigInhWidget oldWidget) => false;
}

/// Loads a transcript by id and shows it: a full screen on phones/tablets,
/// the detail pane of History on desktop.
class TranscriptDetailConfigWidget extends StatefulWidget {
  const TranscriptDetailConfigWidget({required this.transcriptId, this.onDeleted, super.key});

  /// Mobile: pushes the transcript screen. Desktop: selects it in History.
  static Future<void> open(BuildContext context, {required int transcriptId}) async {
    context.screenSizeMaybeWhen(
      orElse: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (context) => TranscriptDetailConfigWidget(transcriptId: transcriptId)),
        );
      },
      desktop: () => AppShellScope.of(context).showTranscript(transcriptId),
    );
  }

  final int transcriptId;

  /// Desktop pane: called after deletion. The phone screen pops itself.
  final VoidCallback? onDeleted;

  @override
  State<TranscriptDetailConfigWidget> createState() => TranscriptDetailConfigWidgetState();
}

class TranscriptDetailConfigWidgetState extends State<TranscriptDetailConfigWidget> {
  late final TranscriptDetailController transcriptDetailController;
  late final int transcriptId = widget.transcriptId;

  @override
  void initState() {
    super.initState();
    transcriptDetailController = TranscriptDetailController(
      transcriptDetailRepository: TranscriptDetailRepositoryImpl(database: Dependencies.of(context).database),
    );
    load();
  }

  @override
  void dispose() {
    transcriptDetailController.dispose();
    super.dispose();
  }

  void load() => transcriptDetailController.load(transcriptId);

  Future<void> copy(List<TranscriptSegment> segments) =>
      Clipboard.setData(ClipboardData(text: segments.map((s) => s.text).join('\n')));

  Future<void> delete() async {
    var deleted = false;
    await TranscriptDeletionConfigWidget.show(
      context,
      transcriptId: transcriptId,
      onSuccessfullyDelete: () => deleted = true,
    );
    // Act only after the dialog has closed, so the pop hits this screen.
    if (!deleted || !mounted) return;
    final onDeleted = widget.onDeleted;
    if (onDeleted != null) {
      onDeleted();
    } else {
      await Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) => TranscriptDetailConfigInhWidget(
    state: this,
    child: widget.onDeleted != null
        ? const TranscriptDetailDesktopWidget()
        : context.screenSizeMaybeWhen(
            orElse: () => const TranscriptDetailMobileWidget(),
            desktop: () => const TranscriptDetailDesktopWidget(),
          ),
  );
}
