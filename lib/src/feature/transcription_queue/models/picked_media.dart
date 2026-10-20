import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

/// A file the user picked or dropped. [path] is null when the platform only
/// gave a content URI (Android); the repository then copies [file] in.
@immutable
class PickedMedia {
  const PickedMedia({required this.name, required this.path, required this.file});

  final String name;
  final String? path;
  final XFile file;
}
