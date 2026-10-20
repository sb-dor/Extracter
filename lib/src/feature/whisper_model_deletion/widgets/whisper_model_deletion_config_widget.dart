import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/feature/whisper_model_deletion/controller/whisper_model_deletion_controller.dart';
import 'package:extracter/src/feature/whisper_model_deletion/data/whisper_model_deletion_repository.dart';
import 'package:extracter/src/feature/whisper_model_deletion/widgets/whisper_model_deletion_dialog_widget.dart';
import 'package:flutter/material.dart';

class WhisperModelDeletionConfigInhWidget extends InheritedWidget {
  const WhisperModelDeletionConfigInhWidget({required this.state, required super.child, super.key});

  final WhisperModelDeletionConfigWidgetState state;

  static WhisperModelDeletionConfigWidgetState of(BuildContext context) {
    final widget = context.getElementForInheritedWidgetOfExactType<WhisperModelDeletionConfigInhWidget>()?.widget;
    assert(widget != null, 'WhisperModelDeletionConfigInhWidget was not found in element tree');
    return (widget! as WhisperModelDeletionConfigInhWidget).state;
  }

  @override
  bool updateShouldNotify(WhisperModelDeletionConfigInhWidget oldWidget) => false;
}

class WhisperModelDeletionConfigWidget extends StatefulWidget {
  const WhisperModelDeletionConfigWidget({required this.spec, required this.builder, super.key});

  static Future<void> show(BuildContext context, {required WhisperModelSpec spec}) => showDialog<void>(
    context: context,
    builder: (context) =>
        WhisperModelDeletionConfigWidget(spec: spec, builder: (context) => const WhisperModelDeletionDialogWidget()),
  );

  final WhisperModelSpec spec;
  final WidgetBuilder builder;

  @override
  State<WhisperModelDeletionConfigWidget> createState() => WhisperModelDeletionConfigWidgetState();
}

class WhisperModelDeletionConfigWidgetState extends State<WhisperModelDeletionConfigWidget> {
  late final WhisperModelDeletionController whisperModelDeletionController;
  late final WhisperModelSpec spec = widget.spec;

  @override
  void initState() {
    super.initState();
    whisperModelDeletionController = WhisperModelDeletionController(
      whisperModelDeletionRepository: WhisperModelDeletionRepositoryImpl(
        modelStore: Dependencies.of(context).modelStore,
      ),
    );
  }

  @override
  void dispose() {
    whisperModelDeletionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      WhisperModelDeletionConfigInhWidget(state: this, child: widget.builder(context));
}
