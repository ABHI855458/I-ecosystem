/// Picks the currently-active anon name out of a `users` row's
/// `anon_name`/`anon_name_2`/`active_anon_slot` columns.
///
/// Shared by every render site that shows a user's anon identity outside
/// SelfProfile (which has its own equivalent getter) — community_screen.dart
/// and group_member_picker_screen.dart — so "shuffle" toggling
/// `active_anon_slot` shows up everywhere consistently, not just on the
/// profile screen that owns the Shuffle button.
String? activeAnonName({
  required String? anonName,
  String? anonName2,
  int? activeAnonSlot,
}) {
  if (activeAnonSlot == 2 && anonName2 != null && anonName2.isNotEmpty) {
    return anonName2;
  }
  return anonName;
}
