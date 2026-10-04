// ---------------------------------------------------------------------------
// Shared helper for building safe `ilike` terms inside a PostgREST `.or()`
// filter string. `,()."*` are all syntactically meaningful inside a
// PostgREST filter expression (`,` separates conditions, `()` groups
// `and`/`or`, `.` separates column/operator/value, `*` is ilike's own
// wildcard) — a raw user query containing any of them corrupts the filter
// and the request 400s. Every caller building an `or('col.ilike.%$q%,...')`
// filter from free-text user input should route through here first.
// ---------------------------------------------------------------------------

/// Strips PostgREST/ilike metacharacters from a raw search query, leaving it
/// safe to interpolate into an `.or('col.ilike.%$safe%')` filter. Returns
/// null if nothing searchable remains after stripping.
String? sanitizeSearchTerm(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final stripped = trimmed.replaceAll(RegExp(r'[,()."*]'), '').trim();
  if (stripped.isEmpty) return null;
  return stripped;
}
