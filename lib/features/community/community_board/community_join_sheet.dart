import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/glass.dart' show showGlassToast;
import '../../../services/community_service.dart';
import 'community_tokens.dart';

// ---------------------------------------------------------------------------
// "MANAGE COMMUNITIES" popover — was a fake join-only popover with a local
// `Set<String> _joined = {}` that reset on every open (see git history);
// now a real manage sheet with two live sections:
//   YOUR COMMUNITIES — from CommunityService.fetchJoinedCommunities(), each
//     row's button is JOINED and, on tap, confirms then leaves
//     (mem_leave already permits this at the DB layer — see
//     supabase/migrations/20260904000000_community_posts.sql's header).
//   DISCOVER — every community the moderator dashboard has published
//     (CommunityService.fetchAllCommunities()) minus the ones already
//     joined; tapping JOIN joins immediately, no confirmation needed.
//
// There is no "create community" row anywhere in here, deliberately — the
// app never creates/edits/deletes a community, only membership.
//
// [onChanged] fires after a successful join or leave so the caller
// (CommunityScreen, which owns the selected-community chip strip) can
// refetch and, if the currently-selected community was just left, fall
// back to another one.
// ---------------------------------------------------------------------------

class CommunityJoinPopover extends StatefulWidget {
  const CommunityJoinPopover({super.key, required this.onClose, required this.onChanged});
  final VoidCallback onClose;
  final VoidCallback onChanged;

  @override
  State<CommunityJoinPopover> createState() => _CommunityJoinPopoverState();
}

class _CommunityJoinPopoverState extends State<CommunityJoinPopover> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  bool _loading = true;
  String? _error;
  List<CommunityOption> _joined = const [];
  List<CommunityOption> _discover = const [];

  /// Ids currently mid-join or mid-leave — disables that row's button and
  /// shows a spinner instead of optimistically flipping state that might
  /// not actually land.
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        CommunityService.instance.fetchJoinedCommunities(),
        CommunityService.instance.fetchAllCommunities(),
      ]);
      final joined = results[0];
      final all = results[1];
      final joinedIds = joined.map((c) => c.id).toSet();
      if (!mounted) return;
      setState(() {
        _joined = joined;
        _discover = all.where((c) => !joinedIds.contains(c.id)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load communities.";
        _loading = false;
      });
    }
  }

  Future<void> _join(CommunityOption c) async {
    HapticFeedback.selectionClick();
    setState(() => _busyIds.add(c.id));
    try {
      await CommunityService.instance.joinCommunity(c.id);
      if (!mounted) return;
      setState(() {
        _busyIds.remove(c.id);
        _discover = _discover.where((x) => x.id != c.id).toList();
        _joined = [..._joined, c]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyIds.remove(c.id));
      showGlassToast(context, "Couldn't join ${c.name} — try again.", isError: true);
    }
  }

  /// The one community nobody leaves — matched by name, the same way the
  /// `mem_leave` policy identifies it.
  bool _isGeneral(CommunityOption c) => c.name.trim().toLowerCase() == 'general';

  Future<void> _confirmLeave(CommunityOption c) async {
    // Belt and braces: the row is already non-tappable for General, and the
    // database refuses it regardless.
    if (_isGeneral(c)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF16151A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Leave ${c.name}?', style: CommunityType.cardTitle),
        content: Text(
          "You'll stop seeing its posts and announcements, and your streak there will be paused.",
          style: CommunityType.pollMeta.copyWith(color: CommunityColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Leave', style: TextStyle(color: CommunityColors.pink)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyIds.add(c.id));
    try {
      await CommunityService.instance.leaveCommunity(c.id);
      if (!mounted) return;
      setState(() {
        _busyIds.remove(c.id);
        _joined = _joined.where((x) => x.id != c.id).toList();
        _discover = [..._discover, c]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyIds.remove(c.id));
      showGlassToast(context, "Couldn't leave ${c.name} — try again.", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final joinedFiltered = q.isEmpty ? _joined : _joined.where((c) => c.name.toLowerCase().contains(q)).toList();
    final discoverFiltered = q.isEmpty ? _discover : _discover.where((c) => c.name.toLowerCase().contains(q)).toList();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;

    return Stack(
      children: [
        // Scrim — tap anywhere outside the popover to close.
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: 52,
          right: 14,
          left: 14,
          child: Align(
            alignment: Alignment.topRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 288),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: CommunityCurves.popoverDuration,
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(offset: Offset(0, (1 - t) * 6), child: child),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: CommunityColors.popoverBg,
                    border: Border.all(color: CommunityColors.popoverBorder),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 44, offset: const Offset(0, 18)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xFF22222B))),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('MANAGE COMMUNITIES', style: CommunityType.popoverTitle),
                                const Spacer(),
                                GestureDetector(
                                  onTap: widget.onClose,
                                  child: const Icon(Icons.close_rounded, size: 14, color: CommunityColors.textSecondary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(horizontal: 11),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0E0E13),
                                border: Border.all(color: CommunityColors.chipBorder),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.search_rounded, size: 14, color: Color(0xFF6A6B79)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchCtrl,
                                      onChanged: (v) => setState(() => _query = v),
                                      style: CommunityType.searchInput,
                                      // BUG FIX (explicit report — "enclosed
                                      // in 2 boxes", "typing goes out of
                                      // box"): the app's global
                                      // InputDecorationTheme
                                      // (core/theme.dart) sets a real
                                      // OutlineInputBorder as focusedBorder
                                      // — setting only `border:
                                      // InputBorder.none` here doesn't
                                      // override that, since `border` and
                                      // `focusedBorder` are independent
                                      // properties. The moment this field
                                      // was focused (i.e. the instant you
                                      // started typing), Flutter drew the
                                      // theme's accent-colored rounded-rect
                                      // outline ON TOP of this pill's own
                                      // background — a second, differently-
                                      // sized box the text could render
                                      // outside of. Every border variant
                                      // needs its own explicit `none`.
                                      decoration: InputDecoration(
                                        isCollapsed: true,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        errorBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        focusedErrorBorder: InputBorder.none,
                                        hintText: 'Search communities',
                                        hintStyle: CommunityType.searchInput.copyWith(color: const Color(0xFF6A6B79)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxHeight),
                        child: _buildBody(joinedFiltered, discoverFiltered),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(List<CommunityOption> joined, List<CommunityOption> discover) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: CommunityColors.pink))),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: CommunityType.noResults),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: Text('Retry', style: CommunityType.pollCta)),
          ],
        ),
      );
    }
    if (joined.isEmpty && discover.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
        child: Text('No communities found', textAlign: TextAlign.center, style: CommunityType.noResults),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(6),
      shrinkWrap: true,
      children: [
        if (joined.isNotEmpty) ...[
          _SectionLabel('YOUR COMMUNITIES'),
          for (final c in joined)
            _JoinRow(
              community: c,
              joined: true,
              busy: _busyIds.contains(c.id),
              // General cannot be left — see mem_leave's policy. Showing a
              // Leave that the database refuses would read as a bug.
              locked: _isGeneral(c),
              onTap: () => _confirmLeave(c),
            ),
        ],
        if (discover.isNotEmpty) ...[
          _SectionLabel('DISCOVER'),
          for (final c in discover)
            _JoinRow(
              community: c,
              joined: false,
              busy: _busyIds.contains(c.id),
              onTap: () => _join(c),
            ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Text(label, style: CommunityType.popoverTitle.copyWith(fontSize: 9.5)),
    );
  }
}

class _JoinRow extends StatelessWidget {
  const _JoinRow({
    required this.community,
    required this.joined,
    required this.busy,
    required this.onTap,
    this.locked = false,
  });
  final CommunityOption community;
  final bool joined;
  final bool busy;
  final VoidCallback onTap;

  /// Membership can't be given up. True for General, which every user is
  /// auto-joined to and which carries campus-wide announcements — the chip
  /// renders as a plain state badge with no tap target, rather than a
  /// button that looks live and is refused by the server.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CommunityColors.cardBg2,
              border: Border.all(color: CommunityColors.popoverBorder),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              community.name.trim().isEmpty ? '?' : community.name.trim()[0].toUpperCase(),
              style: CommunityType.joinRowName.copyWith(fontSize: 14),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(community.name.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: CommunityType.joinRowName),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: (busy || locked) ? null : onTap,
            child: AnimatedContainer(
              duration: CommunityCurves.chipDuration,
              padding: EdgeInsets.symmetric(horizontal: joined ? 10 : 12, vertical: 5),
              decoration: BoxDecoration(
                color: joined ? const Color(0x24A8E83C) : CommunityColors.pink,
                border: joined ? Border.all(color: const Color(0x66A8E83C)) : null,
                borderRadius: BorderRadius.circular(7),
              ),
              child: busy
                  ? const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: CommunityColors.textSecondary),
                    )
                  : joined
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              locked ? Icons.lock_rounded : Icons.check_rounded,
                              size: 10,
                              color: CommunityColors.lime,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              locked ? 'EVERYONE' : 'JOINED',
                              style: CommunityType.joinBtnJoined,
                            ),
                          ],
                        )
                      : Text('JOIN', style: CommunityType.joinBtnNotJoined),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "+ JOIN" trigger pill — dashed pink outline, sits at the end of the chip
// scroller, opens/closes CommunityJoinPopover.
// ---------------------------------------------------------------------------

class CommunityJoinButton extends StatelessWidget {
  const CommunityJoinButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // Dashed outline removed per explicit request — a solid hairline in
      // the same pink reads as a finished control rather than a
      // placeholder/drop-target, which is what the dashes suggested.
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 6, 11, 6),
        decoration: BoxDecoration(
          color: const Color(0x1AFA2D64),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: CommunityColors.pink.withValues(alpha: 0.45),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 12, color: CommunityColors.pink),
            const SizedBox(width: 6),
            Text('JOIN', style: CommunityType.joinPillLabel),
          ],
        ),
      ),
    );
  }
}
