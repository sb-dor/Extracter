import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:flutter/material.dart';

/// The dashed "Drop audio or video files here" area. The drop target itself
/// covers the whole window (config widget); this highlights while dragging.
/// With [touch] (tablets) it invites choosing files instead.
class QueueDropZone extends StatefulWidget {
  const QueueDropZone({this.touch = false, super.key});

  final bool touch;

  @override
  State<QueueDropZone> createState() => _QueueDropZoneState();
}

class _QueueDropZoneState extends State<QueueDropZone> {
  late final _scope = TranscriptionQueueConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: _scope.dragging,
      builder: (context, dragging, _) => CustomPaint(
        painter: _DashedBorderPainter(color: dragging ? AppColors.accent : const Color(0xFFB9C7C4)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: dragging ? AppColors.accentSoft : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            spacing: 10,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
                child: Padding(
                  padding: EdgeInsets.all(15),
                  child: Icon(Icons.upload_outlined, color: AppColors.accent, size: 26),
                ),
              ),
              Text(
                widget.touch ? l10n.addFilesHere : l10n.dropFilesHere,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              Text(
                l10n.supportedFormats,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 4),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                ),
                onPressed: _scope.pickFiles,
                child: Text(l10n.browseFiles),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 12) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
