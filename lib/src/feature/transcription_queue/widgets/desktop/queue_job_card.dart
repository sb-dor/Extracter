import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/status_pill.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/models/transcription_failure.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/queue_labels.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:flutter/material.dart';

/// One queue row on desktop, styled by the job's status.
class QueueJobCard extends StatefulWidget {
  const QueueJobCard({required this.job, this.since, super.key});

  final QueueJob job;

  /// When the job started running (time-left estimate).
  final DateTime? since;

  @override
  State<QueueJobCard> createState() => _QueueJobCardState();
}

class _QueueJobCardState extends State<QueueJobCard> {
  late final _scope = TranscriptionQueueConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final job = widget.job;
    final active = job.status == QueueJobStatus.running || job.status == QueueJobStatus.cancelling;
    final (iconBg, iconFg) = switch (job.status) {
      QueueJobStatus.running || QueueJobStatus.cancelling => (AppColors.accentSoft, AppColors.accent),
      QueueJobStatus.completedUnsaved => (AppColors.warningSoft, AppColors.warning),
      QueueJobStatus.failed => (AppColors.errorSoft, AppColors.error),
      _ => (AppColors.chip, AppColors.inkSecondary),
    };
    final failed = job.status == QueueJobStatus.failed;
    final header = Row(
      spacing: 12,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
          child: Icon(
            job.status == QueueJobStatus.completedUnsaved ? Icons.warning_amber_rounded : Icons.audio_file_outlined,
            size: 18,
            color: iconFg,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.sourceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              Text(
                failed ? failureMessage(l10n, job.failure ?? TranscriptionFailure.internal) : jobMeta(l10n, job),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: failed ? AppColors.error : AppColors.inkMuted),
              ),
            ],
          ),
        ),
        _StatusPill(job: job),
        ..._trailing(l10n, job),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? AppColors.accent : AppColors.border, width: active ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            header,
            if (active) ..._progress(l10n, job),
            if (job.status == QueueJobStatus.completedUnsaved)
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(l10n.unsavedExplanation, style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary)),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                      ),
                      onPressed: () => _scope.retrySave(job),
                      child: Text(l10n.retrySave),
                    ),
                    OutlinedButton(onPressed: () => _scope.export(job), child: Text(l10n.exportEllipsis)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _progress(Localization l10n, QueueJob job) {
    final permille = job.permille;
    final since = widget.since;
    final left = since == null ? null : remainingLabel(l10n, job, DateTime.now().difference(since));
    final duration = job.durationMs;
    return [
      LinearProgressIndicator(value: permille == null ? null : permille / 1000, borderRadius: BorderRadius.circular(3)),
      Row(
        children: [
          Expanded(
            child: Text(
              job.status == QueueJobStatus.cancelling
                  ? l10n.cancelling
                  : permille != null && duration != null
                  ? l10n.transcribedOf(FormatUtil.duration(duration * permille ~/ 1000), FormatUtil.duration(duration))
                  : l10n.transcribing,
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ),
          if (left != null && job.status == QueueJobStatus.running)
            Text(left, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
        ],
      ),
    ];
  }

  List<Widget> _trailing(Localization l10n, QueueJob job) => switch (job.status) {
    QueueJobStatus.running => [
      OutlinedButton.icon(
        onPressed: () => _scope.cancel(job.id),
        icon: const Icon(Icons.close, size: 16),
        label: Text(l10n.cancel),
      ),
    ],
    QueueJobStatus.pending => [
      IconButton(
        tooltip: l10n.removeFromQueue,
        onPressed: () => _scope.cancel(job.id),
        icon: const Icon(Icons.close, size: 18, color: AppColors.inkSecondary),
      ),
    ],
    QueueJobStatus.done => [
      TextButton(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
        onPressed: job.transcriptId == null ? null : () => _scope.openTranscript(job.transcriptId!),
        child: Text(l10n.open),
      ),
    ],
    QueueJobStatus.failed || QueueJobStatus.cancelled => [
      IconButton(
        tooltip: l10n.removeFromQueue,
        onPressed: () => _scope.remove(job.id),
        icon: const Icon(Icons.close, size: 18, color: AppColors.inkSecondary),
      ),
    ],
    QueueJobStatus.cancelling || QueueJobStatus.completedUnsaved => const [],
  };
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.job});

  final QueueJob job;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return switch (job.status) {
      QueueJobStatus.running => StatusPill(
        label: job.permille == null ? l10n.transcribing : l10n.transcribingPercent(job.permille! ~/ 10),
        tone: PillTone.accent,
      ),
      QueueJobStatus.cancelling => StatusPill(label: l10n.cancelling),
      QueueJobStatus.pending => StatusPill(label: l10n.waiting),
      QueueJobStatus.done => StatusPill(label: l10n.saved, tone: PillTone.accent, icon: Icons.check),
      QueueJobStatus.completedUnsaved => StatusPill(label: l10n.notSaved, tone: PillTone.warning),
      QueueJobStatus.failed => StatusPill(label: l10n.failed, tone: PillTone.error),
      QueueJobStatus.cancelled => StatusPill(label: l10n.cancelled),
    };
  }
}
