import 'package:control/control.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/utils/screen_util.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/feature/transcription_queue/controller/transcription_queue_controller.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/add_files_button.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/desktop/live_transcript_panel.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/desktop/queue_drop_zone.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/desktop/queue_job_card.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/desktop/queue_settings_bar.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/keep_open_banner.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:flutter/material.dart';

/// The wide layout: desktops, and tablets with [touch] (no drag and drop,
/// and a note on what happens when the user switches apps).
class TranscriptionQueueDesktopWidget extends StatefulWidget {
  const TranscriptionQueueDesktopWidget({this.touch = false, super.key});

  final bool touch;

  @override
  State<TranscriptionQueueDesktopWidget> createState() => _TranscriptionQueueDesktopWidgetState();
}

class _TranscriptionQueueDesktopWidgetState extends State<TranscriptionQueueDesktopWidget> {
  late final _scope = TranscriptionQueueConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final tablet = context.screenSize.isTablet;
    return SingleChildScrollView(
      padding: tablet ? const EdgeInsets.fromLTRB(24, 24, 24, 32) : const EdgeInsets.fromLTRB(40, 32, 40, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 24,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 6,
                      children: [
                        Text(l10n.tabTranscribe, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
                        Text(
                          l10n.transcribeSubtitle,
                          style: const TextStyle(fontSize: 15, color: AppColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  const AddFilesButton(),
                ],
              ),
              const QueueSettingsBar(),
              // On touch screens it only invites the first files; Add files stays in the header.
              if (widget.touch)
                StateConsumer<TranscriptionQueueController, TranscriptionQueueState>(
                  controller: _scope.queueController,
                  builder: (context, state, _) =>
                      state.jobs.isEmpty ? const QueueDropZone(touch: true) : const SizedBox.shrink(),
                )
              else
                const QueueDropZone(),
              StateConsumer<TranscriptionQueueController, TranscriptionQueueState>(
                controller: _scope.queueController,
                builder: (context, state, _) {
                  final jobs = state.jobs;
                  if (jobs.isEmpty) return const SizedBox.shrink();
                  final active = state.active;
                  final hasFinished = jobs.any(
                    (j) => j.status.isTerminal && j.status != QueueJobStatus.completedUnsaved,
                  );
                  final queue = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      Row(
                        children: [
                          Text(l10n.queue, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          _CountBadge(jobs.length),
                          const Spacer(),
                          if (hasFinished) TextButton(onPressed: _scope.clearFinished, child: Text(l10n.clearFinished)),
                        ],
                      ),
                      for (final job in jobs) QueueJobCard(job: job, since: job == active ? _scope.activeSince : null),
                    ],
                  );
                  final live = LiveTranscriptPanel(job: active ?? _lastWithText(jobs));
                  final banner = widget.touch && state.isWorking ? const KeepOpenBanner() : null;
                  // Tablets stack the queue over the live text at full width.
                  if (tablet) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 24,
                      children: [?banner, queue, live],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 24,
                    children: [
                      ?banner,
                      Wrap(
                        spacing: 24,
                        runSpacing: 24,
                        children: [
                          ConstrainedBox(constraints: const BoxConstraints(minWidth: 480, maxWidth: 700), child: queue),
                          ConstrainedBox(constraints: const BoxConstraints(minWidth: 400, maxWidth: 520), child: live),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  QueueJob? _lastWithText(List<QueueJob> jobs) {
    for (final job in jobs.reversed) {
      if (job.segments.isNotEmpty) return job;
    }
    return null;
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: const Color(0xFFEAEAE4), borderRadius: BorderRadius.circular(999)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      child: Text(
        '$count',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkSecondary),
      ),
    ),
  );
}
