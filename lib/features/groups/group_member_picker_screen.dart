import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../services/anon_identity.dart';
import '../../services/circle_service.dart';
import '../../services/people_service.dart';

// ---------------------------------------------------------------------------
// GroupMemberPickerScreen — multi-select people picker for group-album
// INVITES. Picked people are invited, not added: they join only by accepting
// (group_invites — see 20260926000000_circles_replace_friendships.sql).
//
// Pool: people in any of my circles first, then everyone else in my
// communities. There's no friendship gate any more — the invite itself is
// the consent step.
//
// The pool is small enough that one fetch up front plus client-side
// filtering (rather than a debounced query per keystroke against the
// backend) is simpler and has no meaningful cost — there's no longer a
// network round-trip to debounce, so the Timer this screen used to carry is
// gone too.
// ---------------------------------------------------------------------------

class GroupMemberPickerScreen extends StatefulWidget {
  const GroupMemberPickerScreen({super.key, this.excludeIds = const {}});

  /// User ids to hide from results — already-selected picks, or (when
  /// opened from an existing group's "add members" flow) existing members.
  final Set<String> excludeIds;

  @override
  State<GroupMemberPickerScreen> createState() => _GroupMemberPickerScreenState();
}

class _GroupMemberPickerScreenState extends State<GroupMemberPickerScreen> {
  final _queryCtrl = TextEditingController();

  List<Map<String, dynamic>>? _friends;
  bool _loadError = false;

  final Map<String, Map<String, dynamic>> _selected = {};

  @override
  void initState() {
    super.initState();
    _queryCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = false);
    try {
      final results = await Future.wait([
        CircleService.instance.fetchPeopleInMyCircles(),
        PeopleService.instance.communityMembers(),
      ]);
      final seen = <String>{};
      final people = [
        for (final u in [...results[0], ...results[1]])
          if (seen.add(u['id'] as String)) u,
      ];
      if (!mounted) return;
      setState(() => _friends = people);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
  }

  void _toggle(Map<String, dynamic> user) {
    HapticFeedback.selectionClick();
    final id = user['id'] as String;
    setState(() {
      if (_selected.containsKey(id)) {
        _selected.remove(id);
      } else {
        _selected[id] = user;
      }
    });
  }

  void _confirm() {
    Navigator.of(context).pop(_selected.values.toList());
  }

  List<Map<String, dynamic>> get _visibleFriends {
    final friends = _friends;
    if (friends == null) return const [];
    final q = _queryCtrl.text.trim().toLowerCase();
    return friends.where((u) {
      if (widget.excludeIds.contains(u['id'])) return false;
      if (q.isEmpty) return true;
      final name = (u['name'] as String? ?? '').toLowerCase();
      final anonName = (activeAnonName(
                anonName: u['anon_name'] as String?,
                anonName2: u['anon_name_2'] as String?,
                activeAnonSlot: u['active_anon_slot'] as int?,
              ) ??
              '')
          .toLowerCase();
      return name.contains(q) || anonName.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16, topPad + 10, 16, 10),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TextField(
                      controller: _queryCtrl,
                      autofocus: true,
                      style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search people to invite…',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Text(
                '${_selected.length} selected',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
              ),
            ),
          Expanded(child: _buildResults(bottomPad)),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              minimum: EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: GestureDetector(
                  onTap: _confirm,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.coral,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    // heightFactor: 1 — load-bearing, not decoration. BUG
                    // FIX (reported as "when I tried to add a person it's
                    // coming like this", with the whole screen filled
                    // coral): a bare Center has null width/height factors,
                    // which makes it expand to the LARGEST size its
                    // constraints allow. Scaffold.bottomNavigationBar
                    // passes loose constraints (maxHeight = the whole
                    // Scaffold), so this Container — which has padding but
                    // no explicit height — grew to fill the entire screen,
                    // painting it coral with the label floating in the
                    // middle. It only ever showed once someone was
                    // selected, because that's when this bar first renders.
                    // heightFactor: 1 makes it shrink-wrap the label again.
                    child: Center(
                      heightFactor: 1,
                      child: Text(
                        'Invite ${_selected.length} ${_selected.length == 1 ? 'person' : 'people'}',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildResults(double bottomPad) {
    if (_friends == null) {
      if (_loadError) {
        return _MessageState(
          icon: Icons.error_outline_rounded,
          message: "Couldn't load people.",
          actionLabel: 'Retry',
          onAction: _load,
        );
      }
      return const Center(
        child: CircularProgressIndicator(color: AppColors.coral, strokeWidth: 2),
      );
    }

    final results = _visibleFriends;
    if (results.isEmpty) {
      final noFriendsAtAll = _friends!.where((u) => !widget.excludeIds.contains(u['id'])).isEmpty;
      return _MessageState(
        icon: Icons.person_off_outlined,
        message: noFriendsAtAll
            ? 'No one to invite yet — join a community first.'
            : 'No one matches that search.',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 20),
      itemCount: results.length,
      separatorBuilder: (context, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final user = results[i];
        final id = user['id'] as String;
        return _PersonRow(
          user: user,
          selected: _selected.containsKey(id),
          onTap: () => _toggle(user),
        );
      },
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.user, required this.selected, required this.onTap});

  final Map<String, dynamic> user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final anonName = activeAnonName(
      anonName: user['anon_name'] as String?,
      anonName2: user['anon_name_2'] as String?,
      activeAnonSlot: user['active_anon_slot'] as int?,
    );
    final name = (user['name'] as String?)?.trim().isNotEmpty == true
        ? user['name'] as String
        : (anonName ?? 'someone');
    final handle = anonName;
    final photoUrl = user['profile_photo_url'] as String?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.coral.withValues(alpha: 0.55) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            ClipOval(
              child: photoUrl == null
                  ? Container(
                      width: 40,
                      height: 40,
                      color: AppColors.background,
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    )
                  : CachedNetworkImage(
              memCacheWidth: 120,
                      imageUrl: photoUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(width: 40, height: 40, color: AppColors.background),
                      errorWidget: (_, _, _) => Container(width: 40, height: 40, color: AppColors.background),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  if (handle != null)
                    Text(
                      '@$handle',
                      style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.coral : Colors.transparent,
                border: Border.all(color: selected ? AppColors.coral : AppColors.border, width: 1.5),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textMuted, size: 36),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, height: 1.5),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    actionLabel!,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
