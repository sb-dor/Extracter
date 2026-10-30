import 'dart:io';

import 'package:extracter/src/common/model_store/model_store.dart';
import 'package:l/l.dart';

/// What a prepared job holds until it ends: the reserved model, and for a
/// content URI (Android) the copy of the file in app storage.
///
/// The job carries these itself, so the repository keeps no record of jobs.
final class JobResources {
  JobResources({this.reservation, this.inputCopy});

  final ModelReservation? reservation;
  final File? inputCopy;
  bool _released = false;

  /// The reserved model's path, or null once released (or never reserved).
  String? get modelPath => _released ? null : reservation?.path;

  /// Frees the model and deletes the copy; idempotent.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    reservation?.release();
    final copy = inputCopy;
    try {
      if (copy != null && copy.existsSync()) await copy.delete();
    } on FileSystemException catch (error) {
      l.w('input copy not deleted: ${error.osError?.errorCode}');
    }
  }
}
