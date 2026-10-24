import 'package:extracter/src/common/background/background_work.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('extracter/background_work');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('show and hide send the notification content over the channel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final work = AndroidBackgroundWork();

    await work.show(channelName: 'Progress', title: 'Transcribing a.mp3', text: '45% done', permille: 450);
    await work.show(channelName: 'Progress', title: 'Transcribing a.mp3', text: 'Preparing…');
    await work.hide();

    expect(calls.map((c) => c.method), ['show', 'show', 'hide']);
    expect(calls[0].arguments, {
      'channel': 'Progress',
      'title': 'Transcribing a.mp3',
      'text': '45% done',
      'permille': 450,
    });
    expect((calls[1].arguments as Map)['permille'], -1, reason: 'null progress is indeterminate');
    expect(work.keepsRunningInBackground, isTrue);
  });

  test('a platform error never reaches the caller', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'denied'));
    final work = AndroidBackgroundWork();

    await expectLater(work.show(channelName: 'c', title: 't', text: 'x'), completes);
    await expectLater(work.hide(), completes);
  });

  test('the no-op implementation does nothing and reports no background support', () async {
    const work = NoopBackgroundWork();
    await work.show(channelName: 'c', title: 't', text: 'x');
    await work.hide();
    expect(work.keepsRunningInBackground, isFalse);
  });
}
