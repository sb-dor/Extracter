import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:extracter/src/common/utils/format_util.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/status_pill.dart';
import 'package:extracter/src/feature/whisper_model_download/controller/whisper_model_download_controller.dart';
import 'package:extracter/src/feature/whisper_models/models/whisper_model_item.dart';
import 'package:extracter/src/feature/whisper_models/widgets/whisper_model_labels.dart';
import 'package:flutter/material.dart';

/// One model in the catalogue. [compact] is the phone layout.
class WhisperModelCard extends StatelessWidget {
  const WhisperModelCard({
    required this.item,
    required this.selected,
    required this.download,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onDelete,
    required this.onSelect,
    this.compact = false,
    super.key,
  });

  final WhisperModelItem item;
  final bool selected;
  final WhisperModelDownloadState download;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;
  final VoidCallback onDelete;
  final VoidCallback onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final spec = item.spec;
    final downloading = download is WhisperModelDownload$InProgressState && download.downloadingModelId == spec.id;
    final title = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [
        Text(
          modelName(l10n, spec.id),
          style: TextStyle(
            fontSize: compact ? 16 : 17,
            fontWeight: FontWeight.w600,
            color: item.fitsDevice ? AppColors.ink : AppColors.inkMuted,
          ),
        ),
        Text(FormatUtil.bytes(spec.sizeBytes), style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
        if (selected && item.isInstalled) StatusPill(label: l10n.modelSelected, tone: PillTone.solidAccent),
      ],
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        title,
        if (!item.fitsDevice)
          Row(
            spacing: 6,
            children: [
              const Icon(Icons.lock_outline, size: 14, color: AppColors.inkSecondary),
              Flexible(
                child: Text(
                  spec.supportsTranslate
                      ? l10n.modelNeedsMemory(spec.minRamGb)
                      : l10n.modelNeedsMemoryNoTranslation(spec.minRamGb),
                  style: const TextStyle(fontSize: 13, color: AppColors.inkSecondary),
                ),
              ),
            ],
          )
        else
          Text(modelDescription(l10n, spec.id), style: const TextStyle(fontSize: 14, color: AppColors.inkSecondary)),
        if (!compact)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              MetaChip(l10n.modelLanguages),
              spec.supportsTranslate
                  ? MetaChip(l10n.modelTranslates)
                  : MetaChip(l10n.modelNoTranslation, tone: PillTone.warning),
            ],
          ),
      ],
    );
    final progress = downloading ? download as WhisperModelDownload$InProgressState : null;
    final actions = _Actions(
      item: item,
      selected: selected,
      progress: progress,
      otherDownloadRunning: download is WhisperModelDownload$InProgressState && !downloading,
      onDownload: onDownload,
      onCancelDownload: onCancelDownload,
      onDelete: onDelete,
      onSelect: onSelect,
      compact: compact,
    );
    final border = BorderSide(
      color: selected && item.isInstalled ? AppColors.accent : AppColors.border,
      width: selected && item.isInstalled ? 1.5 : 1,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.fromBorderSide(border),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  Row(
                    children: [
                      Expanded(child: info),
                      if (progress == null) actions,
                    ],
                  ),
                  if (progress != null) actions,
                ],
              )
            : LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 760
                    ? Row(
                        spacing: 24,
                        children: [
                          Expanded(child: info),
                          SizedBox(width: 180, child: _AccuracyMeter(level: spec.accuracy)),
                          SizedBox(width: 300, child: actions),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 16,
                        children: [
                          info,
                          _AccuracyMeter(level: spec.accuracy),
                          actions,
                        ],
                      ),
              ),
      ),
    );
  }
}

class _AccuracyMeter extends StatelessWidget {
  const _AccuracyMeter({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [
      Text(Localization.of(context).modelAccuracy, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
      Semantics(
        label: Localization.of(context).modelAccuracyValue(level),
        child: Row(
          spacing: 4,
          children: [
            for (var i = 1; i <= 5; i++)
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= level ? AppColors.accent : AppColors.track,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.item,
    required this.selected,
    required this.progress,
    required this.otherDownloadRunning,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onDelete,
    required this.onSelect,
    required this.compact,
  });

  final WhisperModelItem item;
  final bool selected;
  final WhisperModelDownload$InProgressState? progress;
  final bool otherDownloadRunning;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;
  final VoidCallback onDelete;
  final VoidCallback onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final progress = this.progress;
    if (progress != null) {
      final fraction = progress.totalBytes == 0 ? 0.0 : progress.receivedBytes / progress.totalBytes;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.modelDownloading((fraction * 100).floor()),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent),
                ),
              ),
              OutlinedButton(onPressed: onCancelDownload, child: Text(l10n.cancel)),
            ],
          ),
          LinearProgressIndicator(value: fraction, borderRadius: BorderRadius.circular(3)),
          Text(
            l10n.modelDownloadedOf(FormatUtil.bytes(progress.receivedBytes), FormatUtil.bytes(progress.totalBytes)),
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      );
    }
    switch (item.fileState) {
      case ModelFileState.installed:
        final inUse = item.reservations > 0;
        // Wrap, not Row: long translations ("Установлена · Выбрать") must not overflow.
        return Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            if (!selected) ...[
              if (!compact)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    const Icon(Icons.check, size: 14, color: AppColors.accent),
                    Text(
                      l10n.modelInstalled,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent),
                    ),
                  ],
                ),
              OutlinedButton(onPressed: onSelect, child: Text(l10n.modelUse)),
            ],
            Tooltip(
              message: inUse ? l10n.modelInUseByQueue(item.reservations) : l10n.delete,
              child: IconButton(
                onPressed: inUse ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
                color: AppColors.error,
                disabledColor: AppColors.inkDisabled,
              ),
            ),
          ],
        );
      case ModelFileState.downloading || ModelFileState.deleting:
        return const Align(
          alignment: Alignment.centerRight,
          child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case ModelFileState.absent:
        return Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: item.fitsDevice && !otherDownloadRunning ? AppColors.accent : AppColors.border),
            ),
            onPressed: item.fitsDevice && !otherDownloadRunning ? onDownload : null,
            icon: const Icon(Icons.download, size: 18),
            label: Text(l10n.modelDownload),
          ),
        );
    }
  }
}
