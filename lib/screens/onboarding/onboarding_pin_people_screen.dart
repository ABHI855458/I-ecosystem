import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/supabase_config.dart';
import '../../features/profile_v2/pinned_section.dart' show kMaxPins;
import 'onboarding_duo_screen.dart';
import '../../services/post_author_pin_service.dart';

// ---------------------------------------------------------------------------
// OnboardingPinPeopleScreen — last mandatory onboarding step (explicit
// request: "give ... the pin people ui explain what pin does as such ...
// pin any 5 people here"). Same real roster OnboardingCirclesScreen
// used (members of the just-joined communities), with an explanation of
// what pinning actually does (identity reveal on notifications — see
// PostAuthorPinService's own doc) and a real pin toggle capped at
// kMaxPins, same server-enforced cap the profile's own Pinned sheet uses.
// No skip: Continue is the only way forward, into MainShell.
// ---------------------------------------------------------------------------

class OnboardingPinPeopleScreen extends StatefulWidget {
  const OnboardingPinPeopleScreen({super.key, required this.communityIds});

  final List<String> communityIds;

  @override
  State<OnboardingPinPeopleScreen> createState() => _OnboardingPinPeopleScreenState();
}

class _OnboardingPinPeopleScreenState extends State<OnboardingPinPeopleScreen> {
  bool _loading = true;
  bool _loadError = false;
  List<Map<String, dynamic>> _people = const [];
  Set<String> _pinnedIds = const {};
  final Set<String> _pending = {};

  bool get _atCap => _pinnedIds.length >= kMaxPins;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final myAuthId = supabase.auth.currentUser!.id;
      final memberRows = await supabase
          .from('community_members')
          .select('user_id')
          .inFilter('community_id', widget.communityIds);
      final authIds = {
        for (final r in memberRows as List) (r as Map)['user_id'] as String,
      }..remove(myAuthId);

      List<Map<String, dynamic>> people = const [];
      if (authIds.isNotEmpty) {
        final userRows = await supabase
            .from('users')
            .select('id, name, profile_photo_url')
            .inFilter('auth_id', authIds.toList())
            .isFilter('deleted_at', null);
        people = (userRows as List).cast<Map<String, dynamic>>()
          ..sort(
            (a, b) => ((a['name'] as String?) ?? '')
                .toLowerCase()
                .compareTo(((b['name'] as String?) ?? '').toLowerCase()),
          );
      }

      final pinned = await PostAuthorPinService.instance.pinnedIds(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _people = people;
        _pinnedIds = pinned;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('[OnboardingPinPeopleScreen._load] failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = true;
        _loading = false;
      });
    }
  }

  Future<void> _togglePin(String userId) async {
    if (_pending.contains(userId)) return;
    final wasPinned = _pinnedIds.contains(userId);
    if (!wasPinned && _atCap) return;

    setState(() => _pending.add(userId));
    HapticFeedback.selectionClick();
    try {
      if (wasPinned) {
        await PostAuthorPinService.instance.unpin(userId);
        if (mounted) setState(() => _pinnedIds = {..._pinnedIds}..remove(userId));
      } else {
        await PostAuthorPinService.instance.pinPerson(userId);
        if (mounted) setState(() => _pinnedIds = {..._pinnedIds, userId});
      }
    } catch (_) {
      // Leave state as-is — the row just doesn't visibly change.
    } finally {
      if (mounted) setState(() => _pending.remove(userId));
    }
  }

  // Not the feed yet: the mandatory Duo step comes last.
  void _finish() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingDuoScreen(communityIds: widget.communityIds),
      ),
    );
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
                'Pin Your People',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.push_pin_rounded, color: AppColors.neonCyan, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Pinning someone means you'll always know it's them — when they post "
                        "anonymously, visit your profile, or react to something of yours, you'll "
                        "see their real name instead of staying anonymous to you. Pin up to $kMaxPins people.",
                        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'PEOPLE IN YOUR CLUBS',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.6),
                  ),
                  const Spacer(),
                  Text(
                    '${_pinnedIds.length}/$kMaxPins pinned',
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(child: _body()),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_loadError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 32),
            const SizedBox(height: 12),
            Text("Couldn't load people.", style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () { setState(() => _loading = true); _load(); }, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_people.isEmpty) {
      return Center(
        child: Text(
          "No one to pin yet — you can pin people once more of your clubs fill up.",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      itemCount: _people.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _personRow(_people[i]),
    );
  }

  Widget _personRow(Map<String, dynamic> person) {
    final id = person['id'] as String;
    final name = (person['name'] as String?)?.trim().isNotEmpty == true
        ? person['name'] as String
        : 'someone';
    final photoUrl = person['profile_photo_url'] as String?;
    final pinned = _pinnedIds.contains(id);
    final pending = _pending.contains(id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pinned ? AppColors.neonCyan : AppColors.border),
      ),
      child: Row(
        children: [
          ClipOval(
            child: photoUrl == null
                ? Container(width: 40, height: 40, color: AppColors.background)
                : Image.network(
                    photoUrl,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(width: 40, height: 40, color: AppColors.background),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: pending || (!pinned && _atCap) ? null : () => _togglePin(id),
            style: OutlinedButton.styleFrom(
              backgroundColor: pinned ? AppColors.neonCyan.withValues(alpha: 0.14) : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              side: BorderSide(color: pinned ? AppColors.neonCyan : AppColors.border),
              minimumSize: Size.zero,
            ),
            icon: Icon(
              pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 14,
              color: pinned ? AppColors.neonCyan : AppColors.textMuted,
            ),
            label: Text(
              pinned ? 'Pinned' : (_atCap ? 'Full' : 'Pin'),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: pinned ? AppColors.neonCyan : AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
