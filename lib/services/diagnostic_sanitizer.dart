/// Shared helpers that strip sensitive payloads from diagnostic text before
/// it reaches migration failure screens, restore error messages or logs.
///
/// The migration plan (「迁移诊断日志脱敏」) forbids book content, remark
/// text, resource bytes and full personal paths in diagnostics; every
/// user-visible database failure must go through [sanitizeDiagnosticText].
library;

/// Markers that `SqliteException.toString()` uses to append the causing SQL
/// statement and its bound parameters. Those sections can contain card
/// content or book titles, so diagnostics are cut at the earliest marker.
const sqliteErrorDetailMarkers = <String>['Causing statement', 'parameters:'];

/// Returns a sanitized rendering of [value]:
///
/// - text from the first [sqliteErrorDetailMarkers] marker on is dropped;
/// - every key of [pathReplacements] is replaced with its token (longest
///   path first, so nested roots do not leave partial prefixes behind);
/// - empty replacement keys are ignored.
String sanitizeDiagnosticText(
  Object value, {
  Map<String, String> pathReplacements = const <String, String>{},
}) {
  var text = value.toString();
  for (final marker in sqliteErrorDetailMarkers) {
    final cutoff = text.indexOf(marker);
    if (cutoff != -1) {
      text = text.substring(0, cutoff).trimRight();
    }
  }
  final keys = pathReplacements.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    if (key.isEmpty) continue;
    text = text.replaceAll(key, pathReplacements[key]!);
  }
  return text;
}
