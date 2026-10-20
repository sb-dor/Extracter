import 'dart:async';

import 'package:l/l.dart';

/// Catches all application errors and logs them.
///
/// Logs must never contain file names, paths or transcript text — log error
/// types and numeric codes only.
// ignore: experimental_member_use
void appZone(Future<void> Function() fn) => l.capture<void>(
  () => runZonedGuarded<void>(fn, (error, stackTrace) => l.e('Uncaught ${error.runtimeType}', stackTrace)),
  const LogOptions(handlePrint: true, outputInRelease: false, printColors: false),
);
