import 'package:flutter/foundation.dart';

/// History UI state: the search text and (desktop) the selected transcript.
class TranscriptsDataController with ChangeNotifier {
  String _query = '';
  int? _selectedId;

  String get query => _query;

  int? get selectedId => _selectedId;

  void setQuery(String value) {
    final trimmed = value.trim();
    if (trimmed == _query) return;
    _query = trimmed;
    notifyListeners();
  }

  void select(int? id) {
    if (id == _selectedId) return;
    _selectedId = id;
    notifyListeners();
  }
}
