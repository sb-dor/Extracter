import 'package:control/control.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/state_widgets.dart';
import 'package:extracter/src/feature/transcription_queue/controller/transcription_queue_controller.dart';
import 'package:extracter/src/feature/transcription_queue/models/queue_job.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/add_files_button.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/mobile/now_transcribing_card.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/mobile/queue_settings_chips.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/mobile/queue_tile.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:flutter/material.dart';

class TranscriptionQueueMobileWidget extends StatefulWidget {
  const TranscriptionQueueMobileWidget({super.key});

  @override
  State<TranscriptionQueueMobileWidget> createState() => _TranscriptionQueueMobileWidgetState();
}

class _TranscriptionQueueMobileWidgetState extends State<TranscriptionQueueMobileWidget> {
  late final _scope = TranscriptionQueueConfigInhWidget.of(context);

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return SafeArea(
      bottom: false,
      child: StateConsumer<TranscriptionQueueController, TranscriptionQueueState>(
        controller: _scope.queueController,
        builder: (context, state, _) {
          final active = state.active;
          final pending = state.jobs.where((j) => j.status == QueueJobStatus.pending).toList();
          final finished = state.jobs.where((j) => j.status.isTerminal).toList();
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          // Long translations shrink rather than break mid-word.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n.tabTranscribe,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const AddFilesButton(rounded: true),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const QueueSettingsChips(),
                    const SizedBox(height: 12),
                    if (state.isWorking) ...[const _KeepOpenBanner(), const SizedBox(height: 12)],
                    if (active != null) ...[
                      NowTranscribingCard(job: active, since: _scope.activeSince),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
              if (state.jobs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateWidget(
                    icon: Icons.upload_outlined,
                    title: l10n.queueEmptyTitle,
                    message: l10n.queueEmptyMessage,
                  ),
                ),
              if (pending.isNotEmpty) _section(l10n.upNext(pending.length), pending),
              if (finished.isNotEmpty) _section(l10n.finished, finished),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title, List<QueueJob> jobs) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    sliver: SliverList.list(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.inkSecondary),
          ),
        ),
        for (final job in jobs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: QueueTile(job: job),
          ),
      ],
    ),
  );
}

class _KeepOpenBanner extends StatelessWidget {
  const _KeepOpenBanner();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFF6E4100)),
          Expanded(
            child: Text(
              Localization.of(context).keepAppOpen,
              style: const TextStyle(fontSize: 13, height: 1.45, color: Color(0xFF6E4100)),
            ),
          ),
        ],
      ),
    ),
  );
}
