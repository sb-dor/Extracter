import 'package:control/control.dart';
import 'package:extracter/src/common/utils/local_pagination_util.dart';
import 'package:extracter/src/feature/transcripts/data/transcripts_repository.dart';
import 'package:extracter/src/feature/transcripts/models/transcript_summary.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcripts_controller.freezed.dart';

@freezed
sealed class TranscriptsState with _$TranscriptsState {
  const factory TranscriptsState.initial() = Transcripts$InitialState;

  const factory TranscriptsState.inProgress() = Transcripts$InProgressState;

  const factory TranscriptsState.error({Object? error}) = Transcripts$ErrorState;

  /// [cursor] is where the NEXT page starts (keyset; approved deviation from
  /// the page-int shape). [query] echoes the search the rows answer.
  const factory TranscriptsState.completed({
    required List<TranscriptSummary> transcripts,
    required TranscriptsCursor? cursor,
    required bool hasMore,
    required String query,
  }) = Transcripts$CompletedState;
}

/// History list. Query-stateless: the search term comes in on every call.
final class TranscriptsController extends StateController<TranscriptsState> with SequentialControllerHandler {
  TranscriptsController({
    required ITranscriptsRepository transcriptsRepository,
    LocalPaginationUtil localPaginationUtil = const LocalPaginationUtil(),
    int limitInPage = 30,
    super.initialState = const TranscriptsState.initial(),
  }) : _repository = transcriptsRepository,
       _pagination = localPaginationUtil,
       _limit = limitInPage;

  final ITranscriptsRepository _repository;
  final LocalPaginationUtil _pagination;
  final int _limit;

  /// For the config widget: reload when transcripts are added or deleted.
  Stream<void> get changes => _repository.changes;

  /// First page. [silent] keeps the current rows visible (background refresh).
  void load({String query = '', bool silent = false}) => handle(() async {
    if (!silent || state is! Transcripts$CompletedState) setState(const TranscriptsState.inProgress());
    final rows = await _repository.transcripts(query: query, after: null, limit: _limit);
    setState(_completed(rows, rows, query));
  }, error: (error, stackTrace) async => setState(TranscriptsState.error(error: error)));

  void paginate({String query = ''}) => handle(() async {
    final current = state;
    if (current is! Transcripts$CompletedState || !current.hasMore || current.query != query) return;
    final next = await _repository.transcripts(query: query, after: current.cursor, limit: _limit);
    setState(_completed([...current.transcripts, ...next], next, query));
  }, error: (error, stackTrace) async => setState(TranscriptsState.error(error: error)));

  TranscriptsState _completed(List<TranscriptSummary> all, List<TranscriptSummary> page, String query) =>
      TranscriptsState.completed(
        transcripts: List.unmodifiable(all),
        cursor: all.isEmpty ? null : TranscriptsCursor.after(all.last),
        hasMore: _pagination.checkIsListHasMorePageBool(list: page, limitInPage: _limit),
        query: query,
      );
}
