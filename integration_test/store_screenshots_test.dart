// Renders Google Play phone screenshots (1080x1920, 9:16) of the real app in
// English and Russian: seeded History, a live transcription, detail, models.
//
//   flutter drive --driver test_driver/store_screenshots.dart \
//     --target integration_test/store_screenshots_test.dart -d <android> \
//     --dart-define=FIXTURES_DIR=/data/local/tmp/fx
// The driver writes the PNGs to store/google_play/raw/.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:extracter/src/common/database/database.dart';
import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/common/widget/app.dart';
import 'package:extracter/src/feature/transcription_queue/models/picked_media.dart';
import 'package:extracter/src/feature/transcription_queue/widgets/transcription_queue_config_widget.dart';
import 'package:extracter/src/feature/whisper_model_download/data/whisper_model_download_repository.dart';
import 'package:extracter/src/feature/whisper_model_download/models/model_download.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Illustrative sample content per locale for the store listing (not real user data).
const _samples = <String, List<(String, int, String, List<String>)>>{
  'en': [
    (
      'Biology lecture – photosynthesis.mp4',
      3126000,
      'en',
      [
        'Today we look at how plants turn light into chemical energy.',
        'Photosynthesis happens in the chloroplasts, mostly in the leaves.',
        'The light reactions split water and release oxygen as a by-product.',
        'The Calvin cycle then uses that energy to build glucose from carbon dioxide.',
        'Next week we will compare this with cellular respiration.',
      ],
    ),
    (
      'Team meeting – Monday.m4a',
      1867000,
      'en',
      [
        'Let’s start with the release checklist for this week.',
        'The Android build passed review, iOS is still waiting.',
        'Marketing needs the final screenshots by Thursday.',
        'Action items: update the store texts and book the user interviews.',
      ],
    ),
    (
      'Interview with a chef.mp3',
      2694000,
      'en',
      [
        'I opened my first restaurant when I was twenty-four.',
        'Everything on the menu changes with the seasons.',
        'The best advice I ever got was to taste everything, every day.',
      ],
    ),
    ('Voice note.ogg', 74000, 'en', ['Pick up milk and bread on the way home.', 'Call Anna about Friday’s meeting.']),
  ],
  'ru': [
    (
      'Лекция по биологии – фотосинтез.mp4',
      3126000,
      'ru',
      [
        'Сегодня разберём, как растения превращают свет в химическую энергию.',
        'Фотосинтез происходит в хлоропластах, в основном в листьях.',
        'В световой фазе вода расщепляется, а кислород выделяется как побочный продукт.',
        'Затем цикл Кальвина использует эту энергию, чтобы получить глюкозу из углекислого газа.',
        'На следующей неделе сравним это с клеточным дыханием.',
      ],
    ),
    (
      'Планёрка – понедельник.m4a',
      1867000,
      'ru',
      [
        'Начнём с чек-листа релиза на эту неделю.',
        'Сборка для Android прошла проверку, iOS ещё ждёт.',
        'Маркетингу нужны финальные скриншоты к четвергу.',
        'Задачи: обновить тексты для магазина и назначить интервью с пользователями.',
      ],
    ),
    (
      'Интервью с шеф-поваром.mp3',
      2694000,
      'ru',
      [
        'Свой первый ресторан я открыл в двадцать четыре года.',
        'Всё меню меняется вместе с сезоном.',
        'Лучший совет, который я получил: пробовать всё, каждый день.',
      ],
    ),
    (
      'Голосовая заметка.ogg',
      74000,
      'ru',
      ['Не забыть купить молоко и хлеб по дороге домой.', 'Позвонить Анне насчёт встречи в пятницу.'],
    ),
  ],
};

/// Per locale: TTS podcast fixture, its display name, and the History entry to open.
const _podcast = <String, (String, String, String)>{
  'en': ('podcast_en.m4a', 'Podcast – How to remember what you read.m4a', 'photosynthesis'),
  'ru': ('podcast_ru.m4a', 'Подкаст – как запоминать прочитанное.m4a', 'фотосинтез'),
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (tester) async {
    const fixturesDir = String.fromEnvironment('FIXTURES_DIR');
    late Dependencies dependencies;
    final shots = <String, String>{};
    await tester.runAsync(() async {
      dependencies = await Dependencies.initialize();
      final base = WhisperModelSpec.byId('base')!;
      if (!dependencies.modelStore.isInstalled(base.id)) {
        await WhisperModelDownloadRepositoryImpl(
          modelStore: dependencies.modelStore,
          freeDiskBytes: dependencies.native.freeDiskBytes,
        ).download(base, DownloadCancelToken()).drain<void>();
      }
    });

    Future<void> shot(String name) async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
        final image = await layer.toImage(Offset.zero & tester.view.physicalSize);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        shots[name] = base64Encode(bytes!.buffer.asUint8List());
      });
    }

    Future<void> seed(String lang) => tester.runAsync(() async {
      final db = dependencies.database;
      await db.delete(db.transcriptsTable).go();
      final now = DateTime.now();
      for (final (i, (name, ms, language, lines)) in _samples[lang]!.indexed) {
        final step = ms ~/ lines.length;
        await db.insertTranscript(
          NewTranscript(
            sourceName: name,
            durationMs: ms,
            language: language,
            modelId: i.isEven ? 'base' : 'small',
            translated: false,
            createdAt: now.subtract(Duration(hours: i * 20 + 1)),
            segments: [
              for (final (j, text) in lines.indexed)
                TranscriptSegment(startMs: j * step, endMs: (j + 1) * step - 400, text: text),
            ],
          ),
        );
      }
    });

    Future<void> tap(Finder finder) async {
      await tester.tap(finder.last);
      await tester.pump(const Duration(milliseconds: 600));
    }

    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = const Size(1080, 1920);
    for (final locale in const [Locale('en'), Locale('ru')]) {
      tester.platformDispatcher.localesTestValue = [locale];
      final tag = locale.languageCode;
      final (fixture, podcastName, detailEntry) = _podcast[tag]!;
      await seed(tag);
      await tester.pumpWidget(dependencies.inject(child: const App()));
      await tester.pump(const Duration(seconds: 2));

      // 1. Live transcription of a real file.
      final state = tester.state<TranscriptionQueueConfigWidgetState>(find.byType(TranscriptionQueueConfigWidget));
      final path = p.join(fixturesDir, fixture);
      unawaited(state.addFiles([PickedMedia(name: podcastName, path: path, file: XFile(path))]));
      // Wait until the card shows live text (the latest two segments).
      for (var i = 0; i < 180; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        if (state.queueController.state.jobs.any((job) => job.segments.length >= 2)) break;
      }
      await shot('${tag}_1_transcribe');
      for (final job in state.queueController.state.jobs) {
        state.cancel(job.id);
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));

      // 2. History, 3. transcript, 4. copy menu, 5. models.
      await tap(find.byIcon(Icons.history));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await shot('${tag}_2_history');
      await tap(find.textContaining(detailEntry));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await tester.pump(const Duration(milliseconds: 600));
      await shot('${tag}_3_transcript');
      await tap(find.byIcon(Icons.copy_outlined));
      await shot('${tag}_4_copy');
      // One system back leaves the transcript (the menu is an overlay, not a
      // route); a second one would close the activity.
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 600));
      await tap(find.byIcon(Icons.memory));
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await shot('${tag}_5_models');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    }
    tester.view.reset();
    tester.platformDispatcher.clearLocalesTestValue();
    binding.reportData = {'screenshots': shots};
    expect(shots, hasLength(10));
  });
}
