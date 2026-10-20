import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:flutter/material.dart';

/// Primary "Add files" button; shows a spinner while files are being added.
class AddFilesButton extends StatefulWidget {
  const AddFilesButton({this.rounded = false, super.key});

  /// Pill shape for the phone app bar.
  final bool rounded;

  @override
  State<AddFilesButton> createState() => _AddFilesButtonState();
}

class _AddFilesButtonState extends State<AddFilesButton> {
  late final _scope = TranscriptionQueueConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _scope.adding,
    builder: (context, adding, _) => FilledButton.icon(
      style: widget.rounded ? FilledButton.styleFrom(shape: const StadiumBorder()) : null,
      onPressed: adding ? null : _scope.pickFiles,
      icon: adding
          ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.add, size: 18),
      label: Text(Localization.of(context).addFiles),
    ),
  );
}
