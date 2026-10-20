import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/feature/transcript_deletion/controller/transcript_deletion_controller.dart';
import 'package:extracter/src/feature/transcript_deletion/data/transcript_deletion_repository.dart';
import 'package:extracter/src/feature/transcript_deletion/widgets/transcript_deletion_dialog_widget.dart';
import 'package:flutter/material.dart';

class TranscriptDeletionConfigInhWidget extends InheritedWidget {
  const TranscriptDeletionConfigInhWidget({required this.state, required super.child, super.key});

  final TranscriptDeletionConfigWidgetState state;

  static TranscriptDeletionConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<TranscriptDeletionConfigInhWidget>()?.widget;
    assert(widget != null, 'TranscriptDeletionConfigInhWidget was not found in element tree');
    return (widget! as TranscriptDeletionConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(TranscriptDeletionConfigInhWidget oldWidget) => false;
}

class TranscriptDeletionConfigWidget extends StatefulWidget {
  const TranscriptDeletionConfigWidget({
    required this.transcriptId,
    required this.builder,
    this.onSuccessfullyDelete,
    super.key,
  });

  static Future<void> show(BuildContext context, {required int transcriptId, VoidCallback? onSuccessfullyDelete}) =>
      showDialog<void>(
        context: context,
        builder: (context) => TranscriptDeletionConfigWidget(
          transcriptId: transcriptId,
          onSuccessfullyDelete: onSuccessfullyDelete,
          builder: (context) => const TranscriptDeletionDialogWidget(),
        ),
      );

  final int transcriptId;
  final WidgetBuilder builder;
  final VoidCallback? onSuccessfullyDelete;

  @override
  State<TranscriptDeletionConfigWidget> createState() => TranscriptDeletionConfigWidgetState();
}

class TranscriptDeletionConfigWidgetState extends State<TranscriptDeletionConfigWidget> {
  late final TranscriptDeletionController transcriptDeletionController;
  late final int transcriptId = widget.transcriptId;
  late final VoidCallback? onSuccessfullyDelete = widget.onSuccessfullyDelete;

  @override
  void initState() {
    super.initState();
    transcriptDeletionController = TranscriptDeletionController(
      transcriptDeletionRepository: TranscriptDeletionRepositoryImpl(database: Dependencies.of(context).database),
    );
  }

  @override
  void dispose() {
    transcriptDeletionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TranscriptDeletionConfigInhWidget(state: this, child: widget.builder(context));
}
