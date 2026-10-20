import 'dart:async';

import 'package:extracter/src/common/model/transcription_settings.dart';
import 'package:extracter/src/feature/transcription_settings/widgets/controllers/transcription_settings_data_controller.dart';
import 'package:extracter/src/feature/transcripts/controller/transcripts_controller.dart';
import 'package:extracter/src/feature/transcripts/data/transcripts_repository.dart';
import 'package:extracter/src/feature/transcripts/models/transcript_summary.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeTranscriptsRepository implements ITranscriptsRepository {
  FakeTranscriptsRepository(this.rows);

  /// Newest first, like the real query.
  final List<TranscriptSummary> rows;
  final List<TranscriptsCursor?> cursors = [];

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<List<TranscriptSummary>> transcripts({
    required String query,
    required TranscriptsCursor? after,
    required int limit,
  }) async {
    cursors.add(after);
    Iterable<TranscriptSummary> it = rows.where((r) => r.sourceName.contains(query));
    if (after != null) {
      it = it.where(
        (r) =>
            r.createdAt.millisecondsSinceEpoch < after.createdAtMs ||
            (r.createdAt.millisecondsSinceEpoch == after.createdAtMs && r.id < after.id),
      );
    }
    return it.take(limit).toList();
  }
}

TranscriptSummary row(int id, int minute) => TranscriptSummary(
  id: id,
  sourceName: 'file-$id.mp3',
  durationMs: 1000,
  language: 'en',
  modelId: 'base',
  translated: false,
  createdAt: DateTime(2026, 10, 20, 12, minute),
);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('TranscriptsController (keyset pagination)', () {
    // Two rows share a timestamp: only (createdAt, id) keeps them apart.
    final rows = [row(7, 50), row(6, 40), row(5, 40), row(4, 30), row(3, 20)];

    test('pages by (createdAt, id) cursor without gaps or duplicates', () async {
      final repo = FakeTranscriptsRepository(rows);
      final c = TranscriptsController(transcriptsRepository: repo, limitInPage: 2)..load();
      await settle();
      var state = c.state as Transcripts$CompletedState;
      expect(state.transcripts.map((t) => t.id), [7, 6]);
      expect(state.hasMore, isTrue);
      expect(state.cursor!.id, 6);

      c.paginate();
      await settle();
      state = c.state as Transcripts$CompletedState;
      expect(state.transcripts.map((t) => t.id), [7, 6, 5, 4]);

      c.paginate();
      await settle();
      state = c.state as Transcripts$CompletedState;
      expect(state.transcripts.map((t) => t.id), [7, 6, 5, 4, 3]);
      expect(state.hasMore, isFalse);

      c.paginate();
      await settle();
      expect(repo.cursors, hasLength(3), reason: 'no request after the last page');
      c.dispose();
    });

    test('a new row inserted while scrolling does not shift later pages', () async {
      final list = List<TranscriptSummary>.of(rows);
      final repo = FakeTranscriptsRepository(list);
      final c = TranscriptsController(transcriptsRepository: repo, limitInPage: 2)..load();
      await settle();
      list.insert(0, row(8, 59));
      c.paginate();
      await settle();
      final state = c.state as Transcripts$CompletedState;
      expect(state.transcripts.map((t) => t.id), [7, 6, 5, 4]);
      c.dispose();
    });

    test('paginate for a different query than the loaded one is ignored', () async {
      final repo = FakeTranscriptsRepository(rows);
      final c = TranscriptsController(transcriptsRepository: repo, limitInPage: 2)..load(query: 'file');
      await settle();
      c.paginate(query: 'other');
      await settle();
      expect(repo.cursors, hasLength(1));
      c.dispose();
    });
  });

  group('TranscriptionSettingsDataController', () {
    test('translate is only kept for models that support it', () {
      final data = TranscriptionSettingsDataController()
        ..applyLoaded(const TranscriptionSettings(modelId: 'base'))
        ..setTranslate(true);
      expect(data.draft.translate, isTrue);
      data.setModel('large-v3-turbo');
      expect(data.draft.translate, isFalse, reason: 'turbo cannot translate');
      data.setTranslate(true);
      expect(data.draft.translate, isFalse);
      data.setModel('unknown');
      expect(data.draft.modelId, 'large-v3-turbo');
    });

    test('notifies only on real changes', () {
      var count = 0;
      final data = TranscriptionSettingsDataController()..addListener(() => count++);
      data
        ..applyLoaded(const TranscriptionSettings())
        ..setLanguage('auto')
        ..setLanguage('ru')
        ..setLanguage('ru');
      expect(count, 1);
      expect(data.isLoaded, isTrue);
    });
  });
}
