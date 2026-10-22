// Receives the frames captured by integration_test/store_screenshots_test.dart
// and integration_test/demo_gif_test.dart, and writes them as PNGs to the
// directory the test names in `outDir` (store/google_play/raw by default).
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final out = Directory((data?['outDir'] as String?) ?? 'store/google_play/raw')..createSync(recursive: true);
    final shots = (data?['screenshots'] as Map<String, Object?>?) ?? const {};
    for (final MapEntry(:key, :value) in shots.entries) {
      File('${out.path}/$key.png').writeAsBytesSync(base64Decode(value! as String));
    }
    stdout.writeln('wrote ${shots.length} screenshots to ${out.path}');
  },
);
