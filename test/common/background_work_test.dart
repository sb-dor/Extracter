import 'package:extracter/src/common/background/background_work.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('extracter/background_work');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  const transcribing = BackgroundProgress(
    channelName: 'Progress',
    title: 'Transcribing a.mp3',
    text: '45% done',
    permille: 450,
    publicTitle: 'Transcribing a file',
  );
  const downloading = BackgroundProgress(
    channelName: 'Progress',
    title: 'Downloading the Small model',
    text: '30% of 190 MB',
    permille: 300,
  );

  test('progress is sent over the channel and cleared when the work ends', () async {
    final work = AndroidBackgroundWork();

    await work.report(BackgroundWorkKind.transcription, transcribing);
    await work.report(
      BackgroundWorkKind.transcription,
      const BackgroundProgress(channelName: 'Progress', title: 'Transcribing a.mp3', text: 'Preparing…'),
    );
    await work.report(BackgroundWorkKind.transcription, null);

    expect(calls.map((c) => c.method), ['update', 'update', 'clear']);
    expect(calls[0].arguments, {
      'channel': 'Progress',
      'title': 'Transcribing a.mp3',
      'publicTitle': 'Transcribing a file',
      'text': '45% done',
      'permille': 450,
      'kinds': ['transcription'],
    });
    expect((calls[1].arguments as Map)['permille'], -1, reason: 'null progress is indeterminate');
    expect(work.keepsRunningInBackground, isTrue);
  });

  test('unchanged progress is not re-sent', () async {
    final work = AndroidBackgroundWork();
    await work.report(BackgroundWorkKind.download, downloading);
    await work.report(BackgroundWorkKind.download, downloading);
    await work.report(BackgroundWorkKind.download, null);
    await work.report(BackgroundWorkKind.download, null);
    expect(calls.map((c) => c.method), ['update', 'clear']);
  });

  test('a download alongside a transcription is added to its line', () async {
    final work = AndroidBackgroundWork();

    await work.report(BackgroundWorkKind.download, downloading);
    await work.report(BackgroundWorkKind.transcription, transcribing);
    await work.report(BackgroundWorkKind.transcription, null);

    expect(calls.map((c) => c.method), ['update', 'update', 'update']);
    expect(calls[0].arguments, containsPair('title', 'Downloading the Small model'));
    expect(
      calls[0].arguments,
      containsPair('publicTitle', 'Downloading the Small model'),
      reason: 'a model name is not private',
    );
    expect(calls[1].arguments, {
      'channel': 'Progress',
      'title': 'Transcribing a.mp3',
      'publicTitle': 'Transcribing a file',
      'text': '45% done · Downloading the Small model',
      'permille': 450,
      'kinds': ['transcription', 'download'],
    });
    expect(calls[2].arguments, containsPair('kinds', ['download']), reason: 'the download goes on alone');
  });

  test('a platform error never reaches the caller', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'denied'));
    final work = AndroidBackgroundWork();

    await expectLater(work.report(BackgroundWorkKind.transcription, transcribing), completes);
    await expectLater(work.report(BackgroundWorkKind.transcription, null), completes);
  });

  test('the no-op implementation does nothing and reports no background support', () async {
    const work = NoopBackgroundWork();
    await work.report(BackgroundWorkKind.download, downloading);
    expect(calls, isEmpty);
    expect(work.keepsRunningInBackground, isFalse);
  });
}
