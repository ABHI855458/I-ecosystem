/// Parses a Postgres `timestamp` (WITHOUT time zone) column value the way
/// PostgREST serializes it — e.g. `2026-09-03T01:53:36.795443`, no `Z`/
/// offset suffix. Supabase's session timezone is UTC, so that string IS
/// UTC, but `DateTime.parse` treats a suffix-less string as LOCAL time —
/// on a device whose local zone is hours off UTC (IST, PST, ...), a
/// freshly-inserted row parses as hours in the past or future relative to
/// `DateTime.now()`. That is silent and mostly cosmetic for a "2h ago"
/// label, but it is DATA-HIDING for anything that gates on a window
/// against `DateTime.now()` (a ping's reply-window expiry, in particular —
/// this is exactly the bug that made every fresh ping look pre-expired).
/// Every `timestamp` (not `timestamptz`) column this app parses should go
/// through this, not a bare `DateTime.parse`.
final _hasTzSuffix = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');
DateTime parsePostgresTimestamp(String raw) =>
    DateTime.parse(_hasTzSuffix.hasMatch(raw) ? raw : '${raw}Z');

/// Relative-time label shared by every feed card that shows a post's age.
/// `withAgo: true` gives "12h ago" (action-cluster style); false gives the
/// bare "12h" used in compact header rows.
String formatRelativeTime(DateTime? dt, {bool withAgo = false}) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return withAgo ? 'just now' : 'now';
  final String unit;
  if (diff.inMinutes < 60) {
    unit = '${diff.inMinutes}m';
  } else if (diff.inHours < 24) {
    unit = '${diff.inHours}h';
  } else {
    unit = '${diff.inDays}d';
  }
  return withAgo ? '$unit ago' : unit;
}
