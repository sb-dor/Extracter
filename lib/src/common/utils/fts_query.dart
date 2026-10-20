/// Builds a safe FTS5 `MATCH` expression from user input: every whitespace
/// token becomes a quoted prefix term (`"token"*`), never raw FTS syntax.
/// Returns null when nothing searchable remains — callers then skip FTS.
String? ftsPrefixQuery(String input) {
  final tokens = input
      .split(RegExp(r'\s+'))
      .map((t) => t.replaceAll('"', ''))
      .where((t) => t.isNotEmpty)
      .map((t) => '"$t"*')
      .toList();
  return tokens.isEmpty ? null : tokens.join(' ');
}
