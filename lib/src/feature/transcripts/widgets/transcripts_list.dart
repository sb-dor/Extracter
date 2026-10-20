import 'package:control/control.dart';
import 'package:extracter/src/common/localization/generated/l10n.dart';
import 'package:extracter/src/common/widget/app_theme.dart';
import 'package:extracter/src/common/widget/state_widgets.dart';
import 'package:extracter/src/feature/transcripts/controller/transcripts_controller.dart';
import 'package:extracter/src/feature/transcripts/models/transcript_summary.dart';
import 'package:extracter/src/feature/transcripts/widgets/transcripts_config_widget.dart';
import 'package:flutter/material.dart';

/// Search field shared by both layouts.
class TranscriptsSearchField extends StatefulWidget {
  const TranscriptsSearchField({this.rounded = false, super.key});

  final bool rounded;

  @override
  State<TranscriptsSearchField> createState() => _TranscriptsSearchFieldState();
}

class _TranscriptsSearchFieldState extends State<TranscriptsSearchField> {
  late final _data = TranscriptsConfigInhWidget.of(context).transcriptsDataController;
  late final TextEditingController _text = TextEditingController(text: _data.query);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    final radius = BorderRadius.circular(widget.rounded ? 22 : 10);
    final border = OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: AppColors.borderStrong),
    );
    return TextField(
      controller: _text,
      onChanged: _data.setQuery,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: l10n.searchHint,
        prefixIcon: const Icon(Icons.search, color: AppColors.inkMuted),
        border: border,
        enabledBorder: border,
        fillColor: widget.rounded ? AppColors.surface : AppColors.surfaceMuted,
        semanticCounterText: l10n.searchTranscripts,
      ),
    );
  }
}

/// History rows with infinite scroll; [itemsBuilder] lays out the rows.
class TranscriptsList extends StatefulWidget {
  const TranscriptsList({required this.itemsBuilder, super.key});

  final List<Widget> Function(BuildContext context, List<TranscriptSummary> transcripts) itemsBuilder;

  @override
  State<TranscriptsList> createState() => _TranscriptsListState();
}

class _TranscriptsListState extends State<TranscriptsList> {
  late final _scope = TranscriptsConfigInhWidget.of(context);
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) _scope.paginate();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = Localization.of(context);
    return StateConsumer<TranscriptsController, TranscriptsState>(
      controller: _scope.transcriptsController,
      builder: (context, state, _) => switch (state) {
        Transcripts$CompletedState(:final transcripts, :final query) when transcripts.isEmpty => EmptyStateWidget(
          icon: query.isEmpty ? Icons.history : Icons.search_off,
          title: query.isEmpty ? l10n.historyEmptyTitle : l10n.searchEmptyTitle,
          message: query.isEmpty ? l10n.historyEmptyMessage : null,
        ),
        Transcripts$CompletedState(:final transcripts, :final hasMore) => ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            ...widget.itemsBuilder(context, transcripts),
            if (hasMore)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  spacing: 8,
                  children: [
                    const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    Text(l10n.loadingMore, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                  ],
                ),
              ),
          ],
        ),
        Transcripts$ErrorState() => ErrorStateWidget(message: l10n.historyLoadFailed, onRetry: _scope.load),
        _ => const LoadingStateWidget(),
      },
    );
  }
}
