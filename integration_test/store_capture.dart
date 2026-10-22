// Shared by the capture tests (store screenshots, README demo): illustrative
// History content, the TTS podcast fixtures, model install and frame capture.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:extracter/src/common/database/database.dart';
import 'package:extracter/src/common/dependencies/dependencies.dart';
import 'package:extracter/src/common/model/transcript_segment.dart';
import 'package:extracter/src/common/model/whisper_model_spec.dart';
import 'package:extracter/src/feature/whisper_model_download/data/whisper_model_download_repository.dart';
import 'package:extracter/src/feature/whisper_model_download/models/model_download.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Illustrative sample content per locale for the store listing (not real user data).
const storeSamples = <String, List<(String, int, String, List<String>)>>{
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
const storePodcasts = <String, (String, String, String)>{
  'en': ('podcast_en.m4a', 'Podcast – How to remember what you read.m4a', 'photosynthesis'),
  'ru': ('podcast_ru.m4a', 'Подкаст – как запоминать прочитанное.m4a', 'фотосинтез'),
};

/// Initializes the app's dependencies and installs the Base model if needed.
Future<Dependencies> initCaptureDependencies(WidgetTester tester) async {
  late Dependencies dependencies;
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
  return dependencies;
}

/// Replaces History with the sample transcripts of [lang].
Future<void> seedSamples(WidgetTester tester, Dependencies dependencies, String lang) => tester.runAsync(() async {
  final db = dependencies.database;
  await db.delete(db.transcriptsTable).go();
  final now = DateTime.now();
  for (final (i, (name, ms, language, lines)) in storeSamples[lang]!.indexed) {
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

/// The current frame as base64 PNG, scaled by [pixelRatio] of the physical size.
Future<String> captureFrame(WidgetTester tester, {double pixelRatio = 1}) async {
  await tester.pump(const Duration(milliseconds: 400));
  late String png;
  await tester.runAsync(() async {
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final size = tester.view.physicalSize;
    final image = await layer.toImage(Offset.zero & size, pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    png = base64Encode(bytes!.buffer.asUint8List());
  });
  return png;
}
