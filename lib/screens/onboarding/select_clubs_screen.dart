import 'dart:async';
import '../../main_shell.dart';
import '../../core/feature_flags.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants.dart';
import '../../core/glass.dart';
import '../../core/supabase_config.dart';
import 'onboarding_circles_screen.dart';
import 'onboarding_duo_screen.dart';

// ---------------------------------------------------------------------------
// SelectClubsScreen — shown once per account, right after OnboardingScreen
// (brand-new users) or directly from AuthGate (existing accounts that
// predate this feature, or that skipped last time) — see AuthGate's
// _hasCommunity gate and OnboardingScreen._done(). "Once" is enforced by
// CurrentUserService.hasJoinedAnyCommunity() re-querying community_members
// live on every login, NOT a cached "seen it" flag — skipping without
// joining anything means this screen shows again next login, by design
// (nothing was persisted to suppress it).
//
// SCHEMA NOTE: the spec this was built from named a `communities.icon_emoji`
// column — the real, confirmed table (supabase/schema.sql) has no such
// column, only `icon_url`. Using that instead; falls back to a monogram
// glyph when null, same as every other avatar-ish spot in this app.
//
// RLS NOTE: community_members has no CREATE TABLE / policy block in
// schema.sql at all (undocumented drift, like `blocks` and `moderators`
// were before tonight) — whether a plain client insert is even allowed is
// UNVERIFIED. Wired as a direct multi-row insert per spec; if RLS rejects
// it, the failure path below will show it as a real error (not swallowed),
// and the fix would mirror pinned_people's SECURITY DEFINER RPC pattern.
// ---------------------------------------------------------------------------

class SelectClubsScreen extends StatefulWidget {
  const SelectClubsScreen({super.key});

  @override
  State<SelectClubsScreen> createState() => _SelectClubsScreenState();
}

enum _LoadState { loading, loaded, empty, error }

class _SelectClubsScreenState extends State<SelectClubsScreen> {
  _LoadState _state = _LoadState.loading;
  List<Map<String, dynamic>> _communities = [];
  final Set<String> _selected = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      // LAUNCH-BLOCKING FIX. trg_autojoin_general already inserted this
      // user's General row before this screen ever renders — but the
      // community list used to be fetched WITHOUT excluding it, so General
      // was offered as an unselected chip. _kMinCommunities requires 5 of
      // 6 total: unless the user happened to leave out General specifically,
      // the batch insert below hit community_members' PK (community_id,
      // user_id) and failed as ONE statement — losing every pick, not just
      // the colliding one. Verified live: General had 11 members (everyone,
      // from the trigger) while every other community had 1-2 — proof this
      // was failing for most real users, not a theoretical case.
      //
      // Excluding already-joined ids here removes the collision at its
      // source; the upsert in _joinInBackground below is defense in depth
      // for any community joined between this fetch and that write.
      final userId = supabase.auth.currentUser!.id;
      final results = await Future.wait([
        supabase
            .from('communities')
            .select('id, name, icon_url')
            .isFilter('deleted_at', null)
            .order('name'),
        supabase.from('community_members').select('community_id').eq('user_id', userId),
      ]);
      if (!mounted) return;
      final allRows = (results[0] as List).cast<Map<String, dynamic>>();
      final joinedIds = (results[1] as List)
          .cast<Map<String, dynamic>>()
          .map((r) => r['community_id'] as String)
          .toSet();
      _communities = allRows.where((c) => !joinedIds.contains(c['id'])).toList();
      setState(() => _state = _communities.isEmpty ? _LoadState.empty : _LoadState.loaded);
    } catch (e, st) {
      debugPrint('[SelectClubsScreen._load] fetch communities failed: $e\n$st');
      if (mounted) {
        setState(() {
          _error = "Couldn't load communities.";
          _state = _LoadState.error;
        });
      }
    }
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  bool _joining = false;

  /// Raised from 1 -> 5. Explicit request: "set the communities while
  /// joining to set minimum of 5 while joining". Below this, the empty-
  /// database bypass ([_LoadState.empty]'s own "Explore communities later"
  /// button, and this button being disabled entirely when there is nothing
  /// to join) is still the one legitimate way past it — a fresh install
  /// with under 5 communities SEEDED has no real 5 to pick from, and that
  /// is a data problem, not something to block signup over.
  // 5 -> 2 for launch (explicit request: "lower minimum clubs" — less
  // friction on the first screen; more can be joined any time later).
  static const _kMinCommunities = 2;

  /// LAUNCH-BLOCKING FIX. _communities now excludes already-joined
  /// communities (see _load), so this can legitimately offer FEWER than
  /// [_kMinCommunities] chips — e.g. a user who already joined 2 of the
  /// live 6 has only 4 left to pick from. The unclamped constant made
  /// _finish demand 5 picks from a 4-chip screen: Continue stayed enabled,
  /// every tap toasted "pick N more", and there was no way to ever satisfy
  /// it — a real dead end, not just this screen requiring more than exists.
  int get _effectiveMin =>
      _communities.length < _kMinCommunities ? _communities.length : _kMinCommunities;

  // BUG FIX / explicit request: this used to let you "Continue" (or
  // "Skip this") with zero clubs picked, joining nothing. Now mandatory —
  // at least [_effectiveMin] picks, no skip — since the next two
  // screens (Add Friends, Pin People) both need a real community roster to
  // show real people from, not an empty one.
  Future<void> _finish() async {
    final selectedIds = _selected.toList();
    final min = _effectiveMin;
    if (selectedIds.length < min) {
      final remaining = min - selectedIds.length;
      showGlassToast(
        context,
        selectedIds.isEmpty
            ? 'Pick at least $min to continue'
            : 'Pick $remaining more to continue',
      );
      return;
    }
    if (_joining) return;
    setState(() => _joining = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _joinInBackground(selectedIds, messenger);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
    if (!mounted) return;

    // The people pool for the next steps (Friends, pins, Duos) is EVERY
    // community I'm now in — the clubs just picked PLUS "General", which
    // everyone is auto-joined to. It used to be only the picked clubs, so a
    // new student saw just the one or two people who happened to share a
    // club ("I could only see abishek for pinning and friends, but everyone
    // is in General").
    var poolIds = selectedIds;
    try {
      final authId = SupabaseConfig.client.auth.currentUser?.id;
      if (authId != null) {
        final rows = await SupabaseConfig.client
            .from('community_members')
            .select('community_id')
            .eq('user_id', authId);
        poolIds = {
          ...selectedIds,
          for (final r in rows as List) (r as Map)['community_id'] as String,
        }.toList();
      }
    } catch (_) {
      // Falls back to just the picked clubs.
    }
    if (!mounted) return;

    // Clubs → Circles → app. Circles stay part of sign-up (without them a
    // new person lands in an empty Friends side with no idea who's who);
    // in fast onboarding the Circles screen goes straight into the app,
    // skipping Pin people / Duo (one Duo is asked for after the first post).
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingCirclesScreen(communityIds: poolIds),
      ),
    );
  }

  Future<void> _joinInBackground(
    List<String> communityIds,
    ScaffoldMessengerState messenger,
  ) async {
    Future<void> attempt() async {
      // community_members.user_id FKs profiles.id (= auth.uid()), NOT
      // users.id — CurrentUserService.resolveId() returns the latter, which
      // made every insert here fail its FK (and its `WITH CHECK (user_id =
      // auth.uid())` policy) silently until the retry above surfaced it as
      // "unable to join community". See the identity-reconciliation plan;
      // this is Phase 0, correct under every long-term option there.
      final userId = supabase.auth.currentUser!.id;
      // DEFENSE IN DEPTH for the PK collision fixed in _load (General
      // already excluded there). upsert+onConflict makes this insert
      // idempotent per row instead of all-or-nothing, so a community
      // joined by some other path between that fetch and this write (a
      // second device, a retried request) can no longer fail the WHOLE
      // batch — only that one row is a no-op, every other pick still
      // lands. joined_at is deliberately omitted from the payload so an
      // upsert on an existing row never overwrites its real join date.
      await supabase.from('community_members').upsert(
        [for (final id in communityIds) {'community_id': id, 'user_id': userId}],
        onConflict: 'community_id,user_id',
        ignoreDuplicates: true,
      );
    }

    try {
      await attempt();
      debugPrint('[SelectClubsScreen] joined ${communityIds.length} communities');
    } catch (e, st) {
      debugPrint('[SelectClubsScreen] join failed, retrying once: $e\n$st');
      try {
        await attempt();
        debugPrint('[SelectClubsScreen] retry succeeded');
      } catch (e2, st2) {
        debugPrint('[SelectClubsScreen] retry failed: $e2\n$st2');
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              content: GlassBox(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Couldn't save your picks — you can join from a community's page instead.",
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(
                'Join Your Communities',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pick at least $_kMinCommunities to continue — you can join more later.',
                style: GoogleFonts.inter(fontSize: 15, color: AppColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 28),
              Expanded(child: _buildBody()),
              const SizedBox(height: 12),
              // "Skip this" removed — explicit request ("they shall select
              // to continue, don't allow skip"). The empty-state's own
              // "Explore communities later" button (below, _buildBody's
              // _LoadState.empty branch) is the one legitimate bypass left:
              // if the communities table itself has nothing to join, there
              // is no real roster for Add Friends/Pin People to show
              // either, so that path goes straight to the Duo step.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _state == _LoadState.empty || _joining ? null : _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _joining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                        )
                      : const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return _SkeletonGrid();
      case _LoadState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 32),
              const SizedBox(height: 12),
              Text(_error ?? 'Something went wrong.',
                  style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        );
      case _LoadState.empty:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_outlined, color: AppColors.textMuted, size: 36),
              const SizedBox(height: 14),
              Text(
                'No communities to show yet.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "You're all set — explore communities whenever you like.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextButton(
                // Skips _finish(): with zero communities in the app there
                // is no real roster for the Add Friends/Pin People steps,
                // and _finish() requires a non-empty selection anyway. The
                // Duo step is still mandatory (it has search + QR, so it
                // needs no roster).
                onPressed: () => kFastOnboarding
                    ? Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute<void>(builder: (_) => const MainShell()),
                        (route) => false,
                      )
                    : Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OnboardingDuoScreen(communityIds: []),
                        ),
                      ),
                child: const Text('Explore communities later'),
              ),
            ],
          ),
        );
      case _LoadState.loaded:
        return SingleChildScrollView(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in _communities)
                _ClubChip(
                  id: c['id'] as String,
                  name: c['name'] as String,
                  iconUrl: c['icon_url'] as String?,
                  selected: _selected.contains(c['id']),
                  onTap: () => _toggle(c['id'] as String),
                ),
            ],
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Chip — unselected: dark neumorphic-style surface, grey text/icon.
// Selected: filled cyan, black text, white checkmark. Scale bounces past
// 1.0 on select (Curves.easeOutBack, not linear) for a spring-ish feel
// without pulling in a physics-simulation dependency for one animation.
// ---------------------------------------------------------------------------

class _ClubChip extends StatefulWidget {
  const _ClubChip({
    required this.id,
    required this.name,
    required this.iconUrl,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String name;
  final String? iconUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ClubChip> createState() => _ClubChipState();
}

class _ClubChipState extends State<_ClubChip> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: widget.selected ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: widget.selected ? AppColors.neonCyan : AppColors.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.selected ? AppColors.neonCyan : AppColors.border,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: AppColors.neonCyan.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [
                    BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 3)),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.selected)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.check_circle, size: 16, color: Colors.white),
                )
              else if (widget.iconUrl != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ClipOval(
                    child: Image.network(
                      widget.iconUrl!,
                      width: 16,
                      height: 16,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.groups_outlined, size: 16, color: AppColors.textMuted),
                    ),
                  ),
                ),
              Text(
                widget.name,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: widget.selected ? AppColors.onPrimary : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton — shimmer, not a spinner, confined to the chip grid area.
// ---------------------------------------------------------------------------

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.cardSurface,
      highlightColor: AppColors.cardSurface.withValues(alpha: 0.5),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final w in const [90.0, 120.0, 70.0, 100.0, 130.0, 80.0, 110.0, 95.0])
            Container(
              width: w,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
        ],
      ),
    );
  }
}
