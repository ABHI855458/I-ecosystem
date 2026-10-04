import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/glass.dart';
import '../../services/community_service.dart';
import '../../services/people_service.dart';
import '../../services/post_author_pin_service.dart';
import 'profile_navigation.dart';
import 'profile_v2_icons.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

// ---------------------------------------------------------------------------
// Pinned — the second tab in the profile banner's eye sheet (see
// viewed_by_section.dart's ViewedByPanel, which hosts this alongside
// "Viewed by"). Backed by pinned_people via PostAuthorPinService's
// pin_person/list_pinned_people/unpin RPCs (supabase/migrations/
// 20260907000000_pins_complete.sql) — capped at kMaxPins, requires a
// shared community (enforced server-side by pin_person()).
//
// This replaces the dashboard prototyped as dead code in
// features/profile/profile_screen.dart (_PinnedTab / _PinnedPersonCard /
// _PinnedDetailSheet, on a screen never shown in the live app). That
// prototype's per-pin analytics (view history, time lingered, posts
// viewed) had no real backing table — they were entirely fabricated demo
// data — so only the layout language carries over here (card row, cap
// pill, empty state), not the fake stats.
// ---------------------------------------------------------------------------

const kMaxPins = 3;

class PinnedSection extends StatefulWidget {
  const PinnedSection({super.key});

  @override
  State<PinnedSection> createState() => _PinnedSectionState();
}

class _PinnedSectionState extends State<PinnedSection> {
  bool _loading = true;
  bool _loadError = false;
  List<Map<String, dynamic>> _pinned = const [];

  /// All [kMaxPins] slots, occupied or not — my_pin_slots() always returns
  /// kMaxPins rows. This is what drives the dashboard: [_pinned] alone can't
  /// distinguish a never-used slot (fills instantly) from one you just
  /// cleared (locked for 7 days), because both are simply "absent" from the
  /// pinned list.
  List<PinSlot> _slots = const [];

  /// Repaints the countdowns. One minute is the finest granularity any
  /// label shows, so a faster tick would only burn frames.
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Everyone in the communities this user has joined — the pool they can
  /// pin FROM, shown under the "Pin someone" button. Explicit request:
  /// "below pin someone shall be the list of all the members of the
  /// community the user has joined". Already-pinned people are filtered out
  /// of this list, since pinning them again is a no-op.
  List<CommunityMember> _communityMembers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        PostAuthorPinService.instance.listPinned(),
        CommunityService.instance.fetchMyCommunityMembers(),
        PostAuthorPinService.instance.pinSlots(),
      ]);
      if (!mounted) return;
      setState(() {
        _pinned = results[0] as List<Map<String, dynamic>>;
        _communityMembers = results[1] as List<CommunityMember>;
        _slots = results[2] as List<PinSlot>;
        _loading = false;
        _loadError = false;
      });
      _tick ??= Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  Future<void> _pin(CommunityMember m) async {
    HapticFeedback.selectionClick();
    try {
      await PostAuthorPinService.instance.pinPerson(m.userId);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      showGlassToast(context, _pinErrorText(e, "Couldn't pin — try again."), isError: true);
    }
  }

  /// Empties [slot]. No optimistic removal, unlike the previous version:
  /// the server can legitimately refuse this (slot still on cooldown), and
  /// optimistically showing the person as unpinned would show identity as
  /// revoked when it is in fact still granted — the wrong direction to be
  /// wrong in for a privacy control.
  Future<void> _unpinSlot(PinSlot slot) async {
    HapticFeedback.selectionClick();
    try {
      await PostAuthorPinService.instance.clearSlot(slot.slot);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      showGlassToast(context, _pinErrorText(e, "Couldn't unpin — try again."), isError: true);
    }
  }

  /// Cooldown refusals carry a human message from the RPC ("This pin slot
  /// unlocks in 3d 4h."). Show it verbatim rather than a generic failure,
  /// so a refusal never reads as a bug.
  String _pinErrorText(Object e, String fallback) {
    final msg = e is PostgrestException ? e.message : '';
    return msg.contains('unlock') || msg.contains('pin limit') ? msg : fallback;
  }

  /// Swaps [slot]'s occupant directly (PostAuthorPinService.setSlot) —
  /// distinct from unpin-then-pin, which used to be the only path: clearing
  /// a slot starts its own 7-day cooldown, so unpinning someone and then
  /// picking someone new almost always landed the new person in a
  /// DIFFERENT slot (whichever else was open), never the one you just
  /// freed — reported as "I can't change who's pinned, I can only remove
  /// them." setSlot already existed server-side for exactly this and was
  /// simply never called from any screen.
  Future<void> _openReplacePicker(PinSlot slot) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
      builder: (_) => PinPickerSheet(replacingSlot: slot.slot, currentSlotUserId: slot.userId),
    );
    if (mounted) _load();
  }

  Future<void> _openPicker() async {
    // BUG FIX (explicit report — "pinned shall have same dropdown height
    // as of viewed by"): this route had no `constraints`, unlike
    // ViewedByPanel's showModalBottomSheet call — without it
    // the sheet renders at its larger route-driven size for the entrance
    // frame before settling, which is exactly the size mismatch being
    // compared against. Same 0.78 cap as those two.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
      builder: (_) => const PinPickerSheet(),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: PV2.accent, strokeWidth: 2)),
      );
    }
    if (_loadError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text("Couldn't load your pins.", style: PV2.body(size: 12.5, color: PV2.inkCount)),
        ),
      );
    }

    // "Can I pin someone right now" is no longer just a count — a user can
    // be under the cap and still have nowhere to put anyone, because every
    // empty slot is serving out its cooldown.
    final openSlot = _slots.where((s) => s.isEmpty && !s.isLocked).firstOrNull;
    final atCap = _slots.where((s) => s.isEmpty).isEmpty;
    final canPin = openSlot != null;
    final nextUnlock = _slots
        .where((s) => s.isEmpty && s.isLocked)
        .fold<PinSlot?>(null, (a, b) => a == null || b.remaining < a.remaining ? b : a);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Pinned people sort first everywhere they show up.',
                style: PV2.body(size: 11.5, color: PV2.inkCount),
              ),
            ),
            const SizedBox(width: 8),
            CountChip(label: '${_pinned.length}/$kMaxPins'),
          ],
        ),
        const SizedBox(height: 12),
        // Always all kMaxPins slots, never a collapsed list. An empty slot and a
        // locked-empty slot look different and mean different things, and
        // neither is representable as "a row that isn't there".
        for (final s in _slots)
          _PinSlotRow(
            slot: s,
            onUnpin: s.isLocked || s.isEmpty ? null : () => _unpinSlot(s),
            onReplace: s.isLocked || s.isEmpty ? null : () => _openReplacePicker(s),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: PillButton(
            label: canPin
                ? 'Pin someone'
                : atCap
                    // Was a hardcoded "(5)" — stale since kMaxPins became 3;
                    // interpolating means this can never drift out of sync
                    // with the constant again.
                    ? 'Pin limit reached ($kMaxPins)'
                    : 'Next slot unlocks in ${nextUnlock!.remainingLabel}',
            icon: PV2Icons.plus(11, canPin ? Colors.white : PV2.inkCount),
            onTap: canPin ? _openPicker : null,
          ),
        ),
        if (_unpinnedCommunityMembers.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'FROM YOUR COMMUNITIES',
            style: PV2.body(size: 11, weight: FontWeight.w600, color: PV2.inkCount),
          ),
          const SizedBox(height: 10),
          for (final m in _unpinnedCommunityMembers)
            _CommunityMemberRow(
              member: m,
              onPin: canPin ? () => _pin(m) : null,
            ),
        ],
      ],
    );
  }

  /// Community members who aren't already pinned — the rows above already
  /// show those, and pin_person on an existing pin is a no-op.
  List<CommunityMember> get _unpinnedCommunityMembers {
    final pinnedIds = _pinned.map((p) => p['pinned_user_id']).toSet();
    return [
      for (final m in _communityMembers)
        if (!pinnedIds.contains(m.userId)) m,
    ];
  }
}

/// One community member, with a pin affordance — the same row language as
/// [_PinnedRow] so the two lists read as one surface.
class _CommunityMemberRow extends StatelessWidget {
  const _CommunityMemberRow({required this.member, required this.onPin});

  final CommunityMember member;
  final VoidCallback? onPin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => openProfile(context, member.userId),
            child: ClipOval(
              child: SizedBox(
                width: 34,
                height: 34,
                child: (member.avatarUrl ?? '').isEmpty
                    ? Container(
                        color: PV2.recessed,
                        alignment: Alignment.center,
                        child: Text(
                          member.displayName.characters.first.toUpperCase(),
                          style: PV2.body(size: 13, weight: FontWeight.w700),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: member.avatarUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            Container(color: PV2.recessed),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              member.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PV2.body(size: 13.5, weight: FontWeight.w700),
            ),
          ),
          GestureDetector(
            onTap: onPin,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(
                Icons.push_pin_outlined,
                size: 16,
                color: onPin == null ? PV2.inkCount : PV2.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the kMaxPins pin slots. Three states, deliberately all rendered as
/// the same row so the dashboard reads as a fixed set of things you own
/// rather than a list that grows:
///
///  * occupied     — avatar, name, unpin affordance (or a lock + countdown)
///  * empty, never used — the "add" state; fills instantly
///  * empty, locked     — you just changed it; countdown to when it reopens
class _PinSlotRow extends StatelessWidget {
  const _PinSlotRow({required this.slot, required this.onUnpin, required this.onReplace});

  final PinSlot slot;

  /// Null when the row can't be changed right now — either nothing is
  /// pinned, or the slot is still on cooldown.
  final VoidCallback? onUnpin;

  /// Opens the picker to swap this slot's occupant directly, in one step.
  /// Same availability as [onUnpin] — occupied and off cooldown.
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final locked = slot.isLocked;

    if (slot.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: PV2.recessed,
                border: Border.all(
                  color: locked ? PV2.recessed : PV2.inkCount.withValues(alpha: 0.35),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                locked ? Icons.lock_outline_rounded : Icons.add_rounded,
                size: 15,
                color: PV2.inkCount,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                locked ? 'Locked' : 'Empty slot ${slot.slot}',
                style: PV2.body(
                  size: 13.5,
                  weight: FontWeight.w600,
                  color: PV2.inkCount,
                ),
              ),
            ),
            if (locked)
              Text(
                'unlocks in ${slot.remainingLabel}',
                style: PV2.body(size: 11, weight: FontWeight.w600, color: PV2.inkByline),
              ),
          ],
        ),
      );
    }

    final name = (slot.name ?? '').trim().isEmpty ? 'someone' : slot.name!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => openProfile(context, slot.userId!),
            child: ClipOval(
              child: slot.avatarUrl == null
                  ? Container(width: 34, height: 34, color: PV2.recessed)
                  : CachedNetworkImage(
                      memCacheWidth: 102,
                      imageUrl: slot.avatarUrl!,
                      width: 34,
                      height: 34,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          Container(width: 34, height: 34, color: PV2.recessed),
                    ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: GestureDetector(
              onTap: () => openProfile(context, slot.userId!),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PV2.body(size: 13.5, weight: FontWeight.w700),
              ),
            ),
          ),
          if (locked) ...[
            const SizedBox(width: 8),
            Icon(Icons.lock_outline_rounded, size: 13, color: PV2.inkByline),
            const SizedBox(width: 4),
            Text(
              slot.remainingLabel,
              style: PV2.body(size: 11, weight: FontWeight.w600, color: PV2.inkByline),
            ),
          ] else ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onReplace,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(Icons.swap_horiz_rounded, size: 16, color: PV2.accent),
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onUnpin,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(Icons.push_pin_rounded, size: 16, color: PV2.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PinPickerSheet — search + pin/unpin, driven by pin state. Reuses
// PeopleService.searchPeople (Phase 0's sanitized, username-inclusive
// search) rather than duplicating it — the pool of people worth showing
// here is "everyone"; the
// shared-community requirement is enforced server-side by pin_person()
// and surfaced as a toast on failure rather than pre-filtered client-side,
// since there's no dedicated "people who share a community with me" query
// yet and duplicating one here would drift from is_community_member's own
// definition of membership.
// ---------------------------------------------------------------------------

class PinPickerSheet extends StatefulWidget {
  const PinPickerSheet({super.key, this.replacingSlot, this.currentSlotUserId});

  /// When set, selecting someone here replaces THIS slot's occupant
  /// directly (PostAuthorPinService.setSlot) in one step, instead of
  /// pin_person's auto-pick-a-slot flow — which can't target an occupied
  /// slot at all, and which the plain unpin-then-pin path around it always
  /// missed: clearing the slot restarts ITS OWN cooldown, so the follow-up
  /// pin lands in whichever OTHER slot is open, never this one.
  final int? replacingSlot;

  /// Who currently occupies [replacingSlot], so that row can read "Current"
  /// and not be tappable — the swap already has no effect on it (see
  /// apply_pin_slot's no-op branch), this just says so instead of a dead
  /// tap that looks like it did nothing.
  final String? currentSlotUserId;

  @override
  State<PinPickerSheet> createState() => _PinPickerSheetState();
}

class _PinPickerSheetState extends State<PinPickerSheet> {
  final _queryCtrl = TextEditingController();
  Future<List<Map<String, dynamic>>>? _future;
  Set<String> _pinnedIds = const {};
  final Set<String> _actionPending = {};
  bool _atCap = false;

  @override
  void initState() {
    super.initState();
    _queryCtrl.addListener(_onQueryChanged);
    _loadCommunityMembers();
    _loadPinState();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  /// Everyone in your joined communities — shown under the search bar so
  /// the sheet opens with the actual pinnable pool instead of a line telling
  /// you to start typing. Null while loading.
  List<Map<String, dynamic>>? _communityMembers;

  Future<void> _loadCommunityMembers() async {
    final people = await PeopleService.instance.communityMembers();
    if (mounted) setState(() => _communityMembers = people);
  }

  Future<void> _loadPinState() async {
    final ids = await PostAuthorPinService.instance.pinnedIds(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _pinnedIds = ids;
      _atCap = ids.length >= kMaxPins;
    });
  }

  void _onQueryChanged() {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) {
      setState(() => _future = null);
      return;
    }
    // Block body, not `() => _future = ...`: an arrow-body assignment
    // closure evaluates to its RHS, so setState would receive the in-flight
    // Future as its "return value" and hit Flutter's "setState callback
    // argument returned a Future" assertion (reproduced live during
    // verification of this screen).
    setState(() {
      _future = PeopleService.instance.searchPeople(query);
    });
  }

  Future<void> _togglePin(String userId) async {
    if (_actionPending.contains(userId)) return;
    setState(() => _actionPending.add(userId));
    HapticFeedback.selectionClick();
    try {
      final replacingSlot = widget.replacingSlot;
      if (replacingSlot != null) {
        // One-step swap — see widget doc. Closes the sheet immediately
        // rather than staying open for more toggles: replacing is a single
        // decision, not a multi-select session like the plain picker.
        await PostAuthorPinService.instance.setSlot(replacingSlot, userId);
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (_pinnedIds.contains(userId)) {
        await PostAuthorPinService.instance.unpin(userId);
        setState(() {
          _pinnedIds = {..._pinnedIds}..remove(userId);
          _atCap = _pinnedIds.length >= kMaxPins;
        });
      } else {
        await PostAuthorPinService.instance.pinPerson(userId);
        setState(() {
          _pinnedIds = {..._pinnedIds, userId};
          _atCap = _pinnedIds.length >= kMaxPins;
        });
      }
    } catch (e) {
      if (mounted) showGlassToast(context, _friendlyPinError(e), isError: true);
    } finally {
      if (mounted) setState(() => _actionPending.remove(userId));
    }
  }

  String _friendlyPinError(Object e) {
    final msg = e.toString();
    if (msg.contains('shared community')) return "You need to share a community to pin them.";
    if (msg.contains('pin limit')) return 'Pin limit reached (5).';
    if (msg.contains('cannot pin yourself')) return "You can't pin yourself.";
    if (msg.contains('already pinned in another slot')) return 'Already pinned in another slot.';
    if (msg.contains('unlocks in')) return "That slot isn't open yet.";
    return "Couldn't update pin — try again.";
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
        child: GlassSurface(
          radius: 20,
          fill: const Color(0xF0141416),
          border: const Color(0x14FFFFFF),
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.replacingSlot != null ? 'Replace this pin' : 'Pin someone',
                style: PV2.body(size: 14, weight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              NeuWell(
                radius: 14,
                shadows: PV2.insetStd,
                child: TextField(
                  controller: _queryCtrl,
                  autofocus: true,
                  style: PV2.body(size: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Search by name or username…',
                    hintStyle: PV2.body(size: 13.5, color: PV2.inkCount),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: PV2.inkCount),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(child: _results()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results() {
    if (_queryCtrl.text.trim().isEmpty) {
      final people = _communityMembers;
      if (people == null) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: CircularProgressIndicator(color: PV2.accent, strokeWidth: 2),
          ),
        );
      }
      if (people.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'Join a community to pin the people in it.',
              textAlign: TextAlign.center,
              style: PV2.body(size: 12.5, color: PV2.inkCount),
            ),
          ),
        );
      }
      // The pinnable pool, by REAL name — pin_person requires a shared
      // community server-side, so this list is exactly who can be pinned.
      // Searching narrows the same pool through searchPeople.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'IN YOUR COMMUNITIES',
              style: PV2.body(
                size: 10.5,
                weight: FontWeight.w700,
                color: PV2.inkCount,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: people.length,
              itemBuilder: (context, i) => _resultRow(people[i]),
            ),
          ),
        ],
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: PV2.accent, strokeWidth: 2)),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text("Couldn't search right now.", style: PV2.body(size: 12.5, color: PV2.inkCount)),
            ),
          );
        }
        final results = snap.data ?? const [];
        if (results.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No one found.', style: PV2.body(size: 12.5, color: PV2.inkCount)),
            ),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          itemCount: results.length,
          itemBuilder: (context, i) => _resultRow(results[i]),
        );
      },
    );
  }

  Widget _resultRow(Map<String, dynamic> user) {
    final id = user['id'] as String;
    final name = (user['name'] as String?)?.trim().isNotEmpty == true
        ? user['name'] as String
        : (user['anon_name'] as String? ?? 'someone');
    final photoUrl = user['profile_photo_url'] as String?;
    final pinned = _pinnedIds.contains(id);
    final pending = _actionPending.contains(id);
    final isCurrentInSlot = widget.replacingSlot != null && id == widget.currentSlotUserId;
    // Replacing a slot doesn't change the total pinned count — it's a swap,
    // not an addition — so the cap that blocks a NEW pin must not block it.
    final blockedByCap = widget.replacingSlot == null && _atCap;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ClipOval(
            child: photoUrl == null
                ? Container(width: 34, height: 34, color: PV2.recessed)
                : CachedNetworkImage(
              memCacheWidth: 102,
                    imageUrl: photoUrl,
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Container(width: 34, height: 34, color: PV2.recessed),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PV2.body(size: 13, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          PillButton(
            label: isCurrentInSlot
                ? 'Current'
                : pinned
                    ? 'Pinned'
                    : (blockedByCap ? 'Full' : (widget.replacingSlot != null ? 'Use' : 'Pin')),
            icon: Icon(
              pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 12,
              color: pinned ? PV2.accentSoft : Colors.white,
            ),
            onTap: isCurrentInSlot || pending || (!pinned && blockedByCap)
                ? null
                : () => _togglePin(id),
          ),
        ],
      ),
    );
  }
}
