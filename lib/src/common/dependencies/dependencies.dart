import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:extracter/src/common/database/database.dart';
import 'package:extracter/src/common/dependencies/dependencies_scope.dart';
import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:extracter_native/extracter_native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:l/l.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown when the bundled native library does not match the Dart bindings.
final class NativeApiMismatchException implements Exception {
  const NativeApiMismatchException(this.found);

  final int found;
}

/// App-wide dependencies, created once in [initialize].
final class Dependencies {
  Dependencies({
    required this.sharedPreferences,
    required this.database,
    required this.native,
    required this.modelStore,
    required this.httpClient,
    required this.inboxDirectory,
  });

  final SharedPreferences sharedPreferences;
  final AppDatabase database;
  final IExtracterNative native;
  final ModelStore modelStore;
  final http.Client httpClient;

  /// App-private copies of picked files that had no readable path (Android).
  final Directory inboxDirectory;

  static Dependencies of(BuildContext context) => DependenciesScope.of(context);

  static Future<Dependencies> initialize() async {
    final native = ExtracterNative();
    if (native.apiVersion != ExtracterNative.expectedApiVersion) {
      throw NativeApiMismatchException(native.apiVersion);
    }

    final support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    // Transcripts and models stay on this device: no iOS/macOS backups.
    native.excludeFromBackup(support.path);

    final cache = await getApplicationCacheDirectory();
    final inbox = Directory(p.join(cache.path, 'inbox'));
    await _resetDirectory(inbox);
    if (Platform.isAndroid || Platform.isIOS) {
      // Queue is in memory: copies left by a previous run are orphans.
      await FilePicker.clearTemporaryFiles().catchError((Object e) => l.w('clearTemporaryFiles: ${e.runtimeType}'));
    }

    final modelStore = ModelStore(directory: Directory(p.join(support.path, 'models')));
    await modelStore.initialize();

    final database = AppDatabase(
      driftDatabase(
        name: 'extracter',
        native: DriftNativeOptions(databaseDirectory: () async => support),
      ),
    );

    return Dependencies(
      sharedPreferences: await SharedPreferences.getInstance(),
      database: database,
      native: native,
      modelStore: modelStore,
      httpClient: http.Client(),
      inboxDirectory: inbox,
    );
  }

  static Future<void> _resetDirectory(Directory directory) async {
    if (directory.existsSync()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
  }

  Widget inject({required Widget child, Key? key}) => DependenciesScope(dependencies: this, key: key, child: child);
}
