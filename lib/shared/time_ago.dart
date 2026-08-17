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
