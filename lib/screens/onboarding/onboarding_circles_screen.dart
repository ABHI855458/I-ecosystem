import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/feature_flags.dart';
import '../../main_shell.dart';
import '../../services/circle_service.dart';
import '../../services/people_service.dart';
import 'onboarding_pin_people_screen.dart';

// ---------------------------------------------------------------------------
// OnboardingCirclesScreen — mandatory step right after SelectClubsScreen.
//
// Replaces the old "Add Friends" request step: there are no friend requests
// any more. Instead the user builds their own audience — the preset circles
// (Friends, Close Friends, Family, Roommates / Work, seeded server-side) plus
// any custom one — out of the real roster of the communities they just
// joined. Those circles are what later shows under "Circles" on the profile.
//
// Friends is compulsory: Continue stays disabled until at least one person
// is in it (unless nobody else has joined those communities yet — then
// there's no one to add and blocking would strand the user). Membership is
// silent: nobody is notified or asked to accept.
//
// The roster is exactly circle_member_is_eligible()'s pool (shares a
// community with me), so every tick here is an insert the server accepts.
// ---------------------------------------------------------------------------

class OnboardingCirclesScreen extends StatefulWidget {
  const OnboardingCirclesScreen({super.key, required this.communityIds});

  final List<String> communityIds;

  @override
  State<OnboardingCirclesScreen> createState() => _OnboardingCirclesScreenState();
}

class _OnboardingCirclesScreenState extends State<OnboardingCirclesScreen> {
  bool _loading = true;
  bool _loadError = false;
  List<Map<String, dynamic>> _people = const [];
  List<CircleOption> _circles = const [];

  /// circle id -> member user ids (local mirror, updated optimistically).
  final Map<String, Set<String>> _members = {};
  final Set<String> _busy = {};
  String? _activeCircleId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  CircleOption? get _friends {
    for (final c in _circles) {
      if (c.isFriends) return c;
    }
    return null;
  }

  Future<void> _load() async {
    try {
      await CircleService.instance.ensureDefaultCircles();
      final results = await Future.wait([
        // Empty = "all my communities" (debug harness / re-entry).
        PeopleService.instance.communityMembers(
          communityIds: widget.communityIds.isEmpty ? null : widget.communityIds,
        ),
        CircleService.instance.fetchMyCircles(),
        CircleService.instance.fetchMyMembership(),
      ]);
      final people = results[0] as List<Map<String, dynamic>>;
      final circles = results[1] as List<CircleOption>;
      final membership = results[2] as Map<String, Set<String>>;
      if (!mounted) return;
      setState(() {
        _people = people;
        _circles = circles;
        _members.clear();
        for (final c in circles) {
          _members[c.id] = <String>{};
        }
        membership.forEach((userId, circleIds) {
          for (final id in circleIds) {
            (_members[id] ??= <String>{}).add(userId);
          }
        });
        _activeCircleId ??= _friends?.id ?? (circles.isEmpty ? null : circles.first.id);
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('[OnboardingCirclesScreen._load] failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadError = true;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(String userId) async {
    final circleId = _activeCircleId;
    if (circleId == null || _busy.contains(userId)) return;
    final set = _members[circleId] ??= <String>{};
    final adding = !set.contains(userId);
    final circle = _circles.firstWhere((c) => c.id == circleId);
    HapticFeedback.selectionClick();
    setState(() {
      _busy.add(userId);
      adding ? set.add(userId) : set.remove(userId);
      // Mirrors the server trigger: Close Friends are always Friends too.
      final f = _friends;
      if (adding && circle.kind == CircleKind.closeFriends && f != null) {
        (_members[f.id] ??= <String>{}).add(userId);
      }
    });
    try {
      if (adding) {
        await CircleService.instance.addMember(circleId, userId);
      } else {
        await CircleService.instance.removeMember(circleId, userId);
      }
    } catch (_) {
      if (mounted) {
        setState(() => adding ? set.remove(userId) : set.add(userId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update that circle — try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(userId));
    }
  }

  Future<void> _newCircle() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: const Text('New circle'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'e.g. Gym crew'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final id = await CircleService.instance.createCircle(name);
      if (!mounted) return;
      setState(() {
        _circles = [..._circles, CircleOption(id: id, name: name.trim())];
        _members[id] = <String>{};
        _activeCircleId = id;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't create that circle.")),
        );
      }
    }
  }

  bool get _canContinue {
    if (_loading) return false;
    // A failed load no longer lets people skip past: picking Friends is
    // compulsory ("make sure they select their friends compulsorily"), and
    // a network blip is exactly when someone would sail through with an
    // empty Friends circle. The Retry button in _body() is the way on.
    // Only a genuinely empty pool — nobody in their communities yet, so
    // there is literally no one to add — still lets them continue.
    if (_loadError) return false;
    if (_people.isEmpty) return true;
    final f = _friends;
    return f != null && (_members[f.id]?.isNotEmpty ?? false);
  }

  void _continue() {
    if (kFastOnboarding) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const MainShell()),
        (route) => false,
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnboardingPinPeopleScreen(communityIds: widget.communityIds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final friendsEmpty = !_loading && !_canContinue;
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
                'Build your circles',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You decide who sees what. Put people from your clubs into circles — '
                "they won't be notified. Your Friends circle needs at least one person.",
                style: GoogleFonts.inter(fontSize: 15, color: AppColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 16),
              if (!_loading && !_loadError) _circleTabs(),
              const SizedBox(height: 12),
              Expanded(child: _body()),
              const SizedBox(height: 12),
              if (friendsEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Add at least one person to Friends to continue.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canContinue ? _continue : null,
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

  Widget _circleTabs() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in _circles)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${c.name} · ${_members[c.id]?.length ?? 0}'),
                selected: c.id == _activeCircleId,
                onSelected: (_) => setState(() => _activeCircleId = c.id),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.cardSurface,
                labelStyle: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.id == _activeCircleId ? AppColors.onPrimary : AppColors.textPrimary,
                ),
                side: const BorderSide(color: AppColors.border),
                showCheckmark: false,
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 16, color: AppColors.textPrimary),
            label: const Text('New circle'),
            onPressed: _newCircle,
            backgroundColor: AppColors.cardSurface,
            side: const BorderSide(color: AppColors.border),
            labelStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
          ),
        ],
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
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _loadError = false;
                });
                _load();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_people.isEmpty) {
      return Center(
        child: Text(
          "No one else has joined yet — you'll be the first!\nYou can fill your circles from your profile later.",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14, height: 1.5),
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
    final inActive = _members[_activeCircleId]?.contains(id) ?? false;
    final elsewhere = [
      for (final c in _circles)
        if (c.id != _activeCircleId && (_members[c.id]?.contains(id) ?? false)) c.name,
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _busy.contains(id) ? null : () => _toggle(id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: inActive ? AppColors.primary : AppColors.border),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  if (elsewhere.isNotEmpty)
                    Text(
                      elsewhere.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              inActive ? Icons.check_circle : Icons.add_circle_outline,
              color: inActive ? AppColors.primary : AppColors.textMuted,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
