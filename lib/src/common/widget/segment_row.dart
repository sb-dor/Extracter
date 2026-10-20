import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:flutter/material.dart';

const _mono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Menlo', 'Consolas', 'Roboto Mono'],
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: AppColors.inkMuted,
);

/// One transcript line: monospace timestamp + selectable text.
/// [stacked] puts the timestamp above the text (phone width).
class SegmentRow extends StatelessWidget {
  const SegmentRow({required this.segment, this.showRange = false, this.stacked = false, super.key});

  final TranscriptSegment segment;
  final bool showRange;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final time = showRange
        ? '${FormatUtil.clock(segment.startMs)} → ${FormatUtil.clock(segment.endMs)}'
        : FormatUtil.clock(segment.startMs);
    final text = Text(segment.text, style: const TextStyle(fontSize: 15, height: 1.55));
    final border = const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.divider)),
    );
    if (stacked) {
      return DecoratedBox(
        decoration: border,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 3,
            children: [
              Text(time, style: _mono.copyWith(fontSize: 11)),
              text,
            ],
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: border,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: showRange ? 148 : 76,
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(time, style: _mono),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: text),
          ],
        ),
      ),
    );
  }
}
