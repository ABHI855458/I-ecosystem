import 'package:flutter/material.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../core/supabase_config.dart';
import '../../services/current_user_service.dart';
import 'qr_payload.dart';

// ---------------------------------------------------------------------------
// Routes a decoded QrPayload to the right join flow. Both branches reuse
// EXISTING, already-RLS-verified write paths rather than inventing a new
// bypass:
//   - Duo:   duo_connect_by_scan — creates the album ALREADY accepted and
//            friends both people, because a scan is an in-person
//            handshake with nothing left to confirm.
//   - Friends: add_mutual_friends (SECURITY DEFINER) puts each person in
//            the OTHER's Friends circle — a cross-user write RLS cannot
//            allow from the client (explicit request, 2026-10-03:
//            "scanning it automatically adds them to their friends circles
//            as well"). Best-effort: a failure there never blocks the join
//            or the Duo, which are the point of the scan.
//   - Group: a plain group_members insert — the same self_join_public_group
//            RLS policy the Blurred Group Teaser's join sheet already uses
//            (see 20260925000000_group_visibility_and_teaser.sql). A
//            private group's QR would hit that same policy and be refused
//            server-side, exactly as it should.
// ---------------------------------------------------------------------------

Future<void> handleScannedPayload(
  BuildContext context,
  QrPayload payload,
) async {
  switch (payload.kind) {
    case QrPayloadKind.duo:
      await _handleDuoScan(context, payload.id, payload.code);
    case QrPayloadKind.group:
      await _handleGroupScan(context, payload.id, payload.code);
  }
}

Future<void> _handleDuoScan(
  BuildContext context,
  String otherUserId,
  String? code,
) async {
  final myId = await CurrentUserService.instance.resolveId();
  if (otherUserId == myId) {
    if (context.mounted) {
      showGlassToast(context, "That's your own Duo code.", isError: true);
    }
    return;
  }
  try {
    // A scan is BOTH halves of the handshake — the two phones are in the
    // same room — so duo_connect_by_scan opens the album already accepted
    // and friends the two of them, with nothing left to confirm (explicit
    // request, 2026-10-03: "when the QR is scanned no need of accepting
    // the duo request"). A Duo REQUEST sent from inside the app still goes
    // through the normal invite → accept flow, untouched.
    // A Duo QR made before 2026-10-04 has no secret code; the server would
    // refuse it, so say what to do instead of a generic failure.
    if (code == null) {
      if (context.mounted) {
        showGlassToast(
          context,
          'This code is out of date — ask them to reopen their QR.',
          isError: true,
        );
      }
      return;
    }
    await supabase.rpc(
      'duo_connect_by_scan',
      params: {'p_other': otherUserId, 'p_code': code},
    );
    if (!context.mounted) return;
    showGlassToast(context, "You're now connected in Duo 💞");
  } on Object catch (e) {
    if (!context.mounted) return;
    showGlassToast(context, "Couldn't connect — try again.", isError: true);
    debugPrint('[handleScannedPayload] duo scan of $otherUserId failed: $e');
  }
}

Future<void> _handleGroupScan(
  BuildContext context,
  String groupId,
  String? code,
) async {
  // Codes carrying a join code (every banner QR since
  // 20260927000000_group_qr_join_codes.sql) go through join_group_by_code,
  // which works for private groups too. The id-only branch below is kept
  // for older public-group codes already printed/shared.
  if (code != null) {
    try {
      final added = await supabase.rpc(
        'join_group_by_code',
        params: {'p_group_id': groupId, 'p_code': code},
      );
      // join_group_by_code befriends the members itself, server-side,
      // behind the code check (security hardening 2026-10-04).
      if (!context.mounted) return;
      showGlassToast(
        context,
        added == true ? 'Joined the group 🎉' : "You're already in this group.",
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      showGlassToast(
        context,
        "Couldn't join — this code may be out of date.",
        isError: true,
      );
      debugPrint(
        '[handleScannedPayload] group code scan of $groupId failed: $e',
      );
    }
    return;
  }
  try {
    final myId = await CurrentUserService.instance.resolveId();
    final already = await supabase
        .from('group_members')
        .select('user_id')
        .eq('group_id', groupId)
        .eq('user_id', myId)
        .maybeSingle();
    if (!context.mounted) return;
    if (already != null) {
      showGlassToast(context, "You're already in this group.");
      return;
    }

    await supabase.from('group_members').insert({
      'group_id': groupId,
      'user_id': myId,
      'role': 'member',
    });
    if (!context.mounted) return;
    showGlassToast(context, 'Joined the group 🎉');
  } on Object catch (e) {
    if (!context.mounted) return;
    // The self-join RLS policy refuses this for a PRIVATE group — that
    // refusal surfaces here as exactly this generic failure, which is the
    // right amount of detail for a scanner: "didn't work", not "this
    // group doesn't allow self-join", which would leak the group's
    // existence/visibility to someone who scanned a code for it.
    showGlassToast(
      context,
      "Couldn't join — this group may be invite-only.",
      isError: true,
    );
    debugPrint('[handleScannedPayload] group scan of $groupId failed: $e');
  }
}
