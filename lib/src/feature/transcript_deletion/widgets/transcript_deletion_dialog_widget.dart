import 'package:control/control.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/adaptive_dialog_widget.dart';
import 'package:extracter/src/feature/transcript_deletion/controller/transcript_deletion_controller.dart';
import 'package:extracter/src/feature/transcript_deletion/widgets/transcript_deletion_config_widget.dart';
import 'package:flutter/material.dart';

class TranscriptDeletionDialogWidget extends StatefulWidget {
  const TranscriptDeletionDialogWidget({super.key});

  @override
  State<TranscriptDeletionDialogWidget> createState() => _TranscriptDeletionDialogWidgetState();
}

class _TranscriptDeletionDialogWidgetState extends State<TranscriptDeletionDialogWidget> {
  late final _scope = TranscriptDeletionConfigInhWidget.of(context);
  late final _controller = _scope.transcriptDeletionController;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return StateConsumer<TranscriptDeletionController, TranscriptDeletionState>(
      controller: _controller,
      listener: (context, controller, oldState, newState) {
        if (newState is TranscriptDeletion$CompletedState) {
          // Notify first so the parent screen can react, then close.
          _scope.onSuccessfullyDelete?.call();
          Navigator.pop(context);
        }
        if (newState is TranscriptDeletion$ErrorState) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.deleteFailed)));
        }
      },
      builder: (context, state, child) => AdaptiveDialogWidget(
        icon: Icons.delete_outline,
        tone: DialogTone.destructive,
        title: l10n.deleteTranscriptTitle,
        content: l10n.deleteTranscriptMessage,
        confirmLabel: l10n.delete,
        inProgress: state is TranscriptDeletion$InProgressState,
        onConfirm: () => _controller.delete(_scope.transcriptId),
      ),
    );
  }
}
