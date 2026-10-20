import 'package:control/control.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/common/widget/adaptive_dialog_widget.dart';
import 'package:extracter/src/feature/whisper_model_deletion/controller/whisper_model_deletion_controller.dart';
import 'package:extracter/src/feature/whisper_model_deletion/widgets/whisper_model_deletion_config_widget.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_model_labels.dart';
import 'package:flutter/material.dart';

class WhisperModelDeletionDialogWidget extends StatefulWidget {
  const WhisperModelDeletionDialogWidget({super.key});

  @override
  State<WhisperModelDeletionDialogWidget> createState() => _WhisperModelDeletionDialogWidgetState();
}

class _WhisperModelDeletionDialogWidgetState extends State<WhisperModelDeletionDialogWidget> {
  late final _scope = WhisperModelDeletionConfigInhWidget.of(context);
  late final _controller = _scope.whisperModelDeletionController;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return StateConsumer<WhisperModelDeletionController, WhisperModelDeletionState>(
      controller: _controller,
      listener: (context, controller, oldState, newState) {
        switch (newState) {
          case WhisperModelDeletion$CompletedState():
            Navigator.pop(context);
          case WhisperModelDeletion$ErrorState(:final inUse):
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(inUse ? l10n.modelDeleteInUse : l10n.modelDeleteFailed)));
            Navigator.pop(context);
          case _:
            break;
        }
      },
      builder: (context, state, child) => AdaptiveDialogWidget(
        icon: Icons.delete_outline,
        tone: DialogTone.destructive,
        title: l10n.modelDeleteTitle(modelName(l10n, _scope.spec.id)),
        content: l10n.modelDeleteMessage(FormatUtil.bytes(_scope.spec.sizeBytes)),
        confirmLabel: l10n.delete,
        inProgress: state is WhisperModelDeletion$InProgressState,
        onConfirm: () => _controller.delete(_scope.spec.id),
      ),
    );
  }
}
