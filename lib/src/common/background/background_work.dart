import 'package:flutter/services.dart';
import 'package:l/l.dart';

/// Keeps transcription running while the app is in the background.
///
/// On Android this is a foreground service with a progress notification; other
/// platforms have no equivalent and use [NoopBackgroundWork].
abstract interface class IBackgroundWork {
  /// Whether work continues after the user switches apps.
  bool get keepsRunningInBackground;

  /// Shows or updates the progress notification. [permille] null means indeterminate.
  Future<void> show({required String channelName, required String title, required String text, int? permille});

  /// Removes the notification and lets the OS suspend the app again.
  Future<void> hide();
}

final class AndroidBackgroundWork implements IBackgroundWork {
  AndroidBackgroundWork({MethodChannel channel = const MethodChannel('extracter/background_work')})
    : _channel = channel;

  final MethodChannel _channel;

  @override
  bool get keepsRunningInBackground => true;

  @override
  Future<void> show({required String channelName, required String title, required String text, int? permille}) =>
      _invoke('show', {'channel': channelName, 'title': title, 'text': text, 'permille': permille ?? -1});

  @override
  Future<void> hide() => _invoke('hide');

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (e) {
      // Transcription still works in the foreground; only the notification is lost.
      l.w('background work $method: ${e.code}');
    }
  }
}

final class NoopBackgroundWork implements IBackgroundWork {
  const NoopBackgroundWork();

  @override
  bool get keepsRunningInBackground => false;

  @override
  Future<void> show({required String channelName, required String title, required String text, int? permille}) async {}

  @override
  Future<void> hide() async {}
}
