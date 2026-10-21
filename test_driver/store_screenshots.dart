// Receives the store screenshots from integration_test/store_screenshots_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final out = Directory('store/google_play/raw')..createSync(recursive: true);
    final shots = (data?['screenshots'] as Map<String, Object?>?) ?? const {};
    for (final MapEntry(:key, :value) in shots.entries) {
      File('${out.path}/$key.png').writeAsBytesSync(base64Decode(value! as String));
    }
    stdout.writeln('wrote ${shots.length} screenshots to ${out.path}');
  },
);
