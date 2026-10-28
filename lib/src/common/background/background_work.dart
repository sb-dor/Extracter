import 'package:flutter/services.dart';
import 'package:l/l.dart';

/// Long-running work that must survive the app going to the background.
/// The order is the notification's priority: the first running kind leads.
enum BackgroundWorkKind { transcription, download }

/// One line of progress for a [BackgroundWorkKind]. [permille] null means indeterminate.
final class BackgroundProgress {
  const BackgroundProgress({
    required this.channelName,
    required this.title,
    required this.text,
    this.permille,
    this.publicTitle,
  });

  /// The notification channel's name in Android settings.
  final String channelName;
  final String title;

  /// [title] without private details (a file name), for a lock screen that hides
  /// sensitive content; null when [title] has none. [text] must never have any.
  final String? publicTitle;
  final String text;
  final int? permille;
}

/// Keeps transcriptions and model downloads running while the app is in the background.
///
/// On Android this is a foreground service whose progress notification is shown
/// only while the app is not visible; other platforms have no equivalent and use
/// [NoopBackgroundWork].
abstract interface class IBackgroundWork {
  /// Whether work continues after the user switches apps.
  bool get keepsRunningInBackground;

  /// Reports [kind] as running with [progress], or as finished when [progress] is null.
  Future<void> report(BackgroundWorkKind kind, BackgroundProgress? progress);
}

final class AndroidBackgroundWork implements IBackgroundWork {
  AndroidBackgroundWork({MethodChannel channel = const MethodChannel('extracter/background_work')})
    : _channel = channel;

  final MethodChannel _channel;
  final Map<BackgroundWorkKind, BackgroundProgress> _running = {};

  /// What was last sent, so unchanged progress is not re-posted.
  Map<String, Object?>? _sent;

  @override
  bool get keepsRunningInBackground => true;

  @override
  Future<void> report(BackgroundWorkKind kind, BackgroundProgress? progress) {
    if (progress == null) {
      _running.remove(kind);
    } else {
      _running[kind] = progress;
    }
    final content = _content();
    if (_sameContent(content, _sent)) return Future<void>.value();
    _sent = content;
    return content == null ? _invoke('clear') : _invoke('update', content);
  }

  /// The leading kind gives the title and the bar; the others are appended by title,
  /// as in "45% done · Downloading the Small model".
  Map<String, Object?>? _content() {
    if (_running.isEmpty) return null;
    final kinds = BackgroundWorkKind.values.where(_running.containsKey).toList();
    final lead = _running[kinds.first]!;
    return {
      'channel': lead.channelName,
      'title': lead.title,
      'publicTitle': lead.publicTitle ?? lead.title,
      'text': [lead.text, for (final kind in kinds.skip(1)) _running[kind]!.title].join(' · '),
      'permille': lead.permille ?? -1,
      'kinds': [for (final kind in kinds) kind.name],
    };
  }

  static bool _sameContent(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (a == null || b == null) return a == b;
    return a['channel'] == b['channel'] &&
        a['title'] == b['title'] &&
        a['publicTitle'] == b['publicTitle'] &&
        a['text'] == b['text'] &&
        a['permille'] == b['permille'] &&
        (a['kinds']! as List).join() == (b['kinds']! as List).join();
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (e) {
      // The work still runs in the foreground; only the background notification is lost.
      l.w('background work $method: ${e.code}');
    }
  }
}

final class NoopBackgroundWork implements IBackgroundWork {
  const NoopBackgroundWork();

  @override
  bool get keepsRunningInBackground => false;

  @override
  Future<void> report(BackgroundWorkKind kind, BackgroundProgress? progress) async {}
}
