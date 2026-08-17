import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants.dart';
import '../../core/glass.dart';
import '../../core/supabase_config.dart';
import '../../main_shell.dart';
import '../../services/current_user_service.dart';

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
      final rows = await supabase
          .from('communities')
          .select('id, name, icon_url')
          .isFilter('deleted_at', null)
          .order('name') as List;
      if (!mounted) return;
      _communities = rows.cast<Map<String, dynamic>>();
      setState(() => _state = _communities.isEmpty ? _LoadState.empty : _LoadState.loaded);
    } catch (e, st) {
      debugPrint('[SelectClubsScreen._load] fetch communities failed: $e\n$st');
      if (mounted) {
        setState(() {
          _error = "Couldn't load clubs.";
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

  void _finish() {
    final selectedIds = _selected.toList();
    // Captured before navigating — ScaffoldMessenger resolves to this app's
    // single root messenger (MaterialApp-level), so it stays valid to show
    // a SnackBar on even after this screen's own context is gone.
    final messenger = ScaffoldMessenger.of(context);

    if (selectedIds.isEmpty) {
      showGlassToast(context, 'Pick at least one to personalize your feed');
    }

    // Optimistic: never make the user wait on the network here — navigate
    // now, join in the background, retry once on failure.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MainShell()),
      (route) => false,
    );
    if (selectedIds.isNotEmpty) {
      unawaited(_joinInBackground(selectedIds, messenger));
    }
  }

  Future<void> _joinInBackground(
    List<String> communityIds,
    ScaffoldMessengerState messenger,
  ) async {
    Future<void> attempt() async {
      final userId = await CurrentUserService.instance.resolveId();
      await supabase.from('community_members').insert([
        for (final id in communityIds) {'community_id': id, 'user_id': userId},
      ]);
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
                        "Couldn't save your club picks — you can join from a club's page instead.",
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
                'Choose Your Clubs',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pick communities to shape your feed — you can join more later.',
                style: GoogleFonts.inter(fontSize: 15, color: AppColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 28),
              Expanded(child: _buildBody()),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _state == _LoadState.empty ? null : _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: _finish,
                  child: Text('Skip this', style: GoogleFonts.inter(color: AppColors.textMuted)),
                ),
              ),
              const SizedBox(height: 8),
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
                'No clubs to show yet.',
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
                onPressed: _finish,
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
