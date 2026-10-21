import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/feature/transcript_detail/models/transcript_detail.dart';
import 'package:extracter/src/feature/transcript_detail/widgets/transcript_detail_config_widget.dart';
import 'package:flutter/material.dart';

/// Copy menu with two modes: plain paragraphs, or paragraphs with timestamps.
/// [compact] shows an icon button (phone app bar) instead of a labelled one.
class TranscriptCopyMenu extends StatefulWidget {
  const TranscriptCopyMenu({required this.transcript, this.compact = false, super.key});

  final TranscriptDetail transcript;
  final bool compact;

  @override
  State<TranscriptCopyMenu> createState() => _TranscriptCopyMenuState();
}

class _TranscriptCopyMenuState extends State<TranscriptCopyMenu> {
  late final _scope = TranscriptDetailConfigInhWidget.of(context);

  Future<void> _copy({required bool withTimestamps}) async {
    await _scope.copy(widget.transcript.segments, withTimestamps: withTimestamps);
    if (!mounted) return;
    final l10n = Localization.of(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(withTimestamps ? l10n.copiedWithTimestamps : l10n.copied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.notes, size: 18),
          onPressed: () => _copy(withTimestamps: false),
          child: Text(l10n.copyText),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.schedule, size: 18),
          onPressed: () => _copy(withTimestamps: true),
          child: Text(l10n.copyWithTimestamps),
        ),
      ],
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        if (widget.compact) {
          return IconButton(tooltip: l10n.copy, onPressed: toggle, icon: const Icon(Icons.copy_outlined));
        }
        return OutlinedButton.icon(
          onPressed: toggle,
          icon: const Icon(Icons.copy_outlined, size: 16),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [Text(l10n.copy), const Icon(Icons.expand_more, size: 16)],
          ),
        );
      },
    );
  }
}
