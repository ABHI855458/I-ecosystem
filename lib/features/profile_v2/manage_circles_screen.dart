import 'dart:async';

import 'package:flutter/material.dart';
import 'profile_navigation.dart' show openProfile;
import 'package:flutter/services.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../services/circle_service.dart';
import '../../services/people_service.dart';
import '../people/find_people_screen.dart' show sortByMutuals;
import 'profile_v2_icons.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

/// Circles — private posting audiences the signed-in user creates and owns.
///
/// Membership is silent by design (see CircleService's own doc): this
/// screen is the ONLY place a circle's existence or roster is visible, and
/// only to the person who made it. A member added here is never told and
/// never sees this screen show anything — there is no symmetric "circles
/// I'm in" view, because that would leak exactly what circles promise not
/// to.
///
/// Circles are the whole social graph now (no friend requests): the preset
/// Friends / Close Friends / Family / Roommates / Work circles come first,
/// and Friends — the compulsory one — can't be deleted.
class ManageCirclesScreen extends StatefulWidget {
  const ManageCirclesScreen({super.key});

  @override
  State<ManageCirclesScreen> createState() => _ManageCirclesScreenState();
}

class _ManageCirclesScreenState extends State<ManageCirclesScreen> {
  List<CircleOption>? _circles;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final circles = await CircleService.instance.fetchMyCircles();
      if (mounted) setState(() => _circles = circles);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Naming a circle is step one of one flow, not its own dead end —
  /// explicit report: "after giving name the UI shall jump into selecting
  /// the accounts". So this doesn't just refresh the list and leave the
  /// person staring at it; it opens straight into that new circle's
  /// member picker, same screen [_openCircle] uses for an existing one.
  Future<void> _createCircle() async {
    final name = await _promptForName(context, title: 'New circle');
    if (name == null || name.trim().isEmpty) return;
    try {
      final id = await CircleService.instance.createCircle(name);
      if (!mounted) return;
      await _openCircle(CircleOption(id: id, name: name.trim()));
    } catch (e) {
      if (mounted) showGlassToast(context, 'Could not create that circle.', isError: true);
      await _load();
    }
  }

  Future<void> _openCircle(CircleOption circle) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CircleMembersScreen(circle: circle),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PV2.page,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PV2.columnWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      NeuWell(
                        width: 38,
                        height: 38,
                        circle: true,
                        shadows: PV2.insetStd,
                        border: PV2.hairlinePanel,
                        color: PV2.raised,
                        onTap: () => Navigator.of(context).maybePop(),
                        child: PV2Icons.back(22, Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Circles',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PV2.display(size: 20),
                        ),
                      ),
                      PillButton(
                        label: 'New',
                        icon: PV2Icons.plus(14, Colors.white),
                        onTap: _createCircle,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'A circle is a private list only you can see. Post to one and '
                    "its members see it — no one is ever notified they're on it.",
                    style: PV2.body(size: 12, color: PV2.inkBio),
                  ),
                ),
                Expanded(
                  child: _error != null
                      ? Center(
                          child: Text(
                            'Could not load your circles.',
                            style: PV2.body(size: 13, color: PV2.inkBio),
                          ),
                        )
                      : _circles == null
                          ? const Center(
                              child: CircularProgressIndicator(color: PV2.accent),
                            )
                          : _circles!.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      "You haven't made a circle yet. Tap New to "
                                      'start one.',
                                      textAlign: TextAlign.center,
                                      style: PV2.body(size: 13, color: PV2.inkBio),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                  itemCount: _circles!.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final c = _circles![i];
                                    return NeuCard(
                                      radius: 18,
                                      shadows: PV2.raisedSm,
                                      border: PV2.hairlinePanel,
                                      onTap: () => _openCircle(c),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            NeuWell(
                                              width: 40,
                                              height: 40,
                                              circle: true,
                                              shadows: PV2.insetWell,
                                              color: PV2.recessed,
                                              child: const Icon(
                                                Icons.workspaces_outline,
                                                size: 18,
                                                color: PV2.accent,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    c.name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: PV2.body(
                                                      size: 14.5,
                                                      weight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      PV2Icons.lock(9, PV2.inkStamp),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        c.memberCount == 0
                                                            ? 'No members yet'
                                                            : c.memberCount == 1
                                                                ? '1 member'
                                                                : '${c.memberCount} members',
                                                        style: PV2.body(size: 11.5, color: PV2.inkSub),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              color: Colors.white.withValues(alpha: 0.3),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> _promptForName(BuildContext context, {required String title}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: PV2.raised,
      title: Text(title, style: PV2.body(size: 15, weight: FontWeight.w700)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        style: PV2.body(size: 14),
        decoration: const InputDecoration(hintText: 'e.g. Gym crew'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

/// One circle's roster — add anyone from your communities (the same pool
/// circle_member_is_eligible() accepts), remove anyone already in it, or
/// delete the circle itself (not Friends).
class CircleMembersScreen extends StatefulWidget {
  const CircleMembersScreen({required this.circle});

  final CircleOption circle;

  @override
  State<CircleMembersScreen> createState() => CircleMembersScreenState();
}

class CircleMembersScreenState extends State<CircleMembersScreen> {
  List<CircleMember>? _members;
  List<Map<String, dynamic>>? _people;
  String? _error;

  // Search — same pattern as PinPickerSheet (pinned_section.dart): typing
  // widens the "add" pool from just your communities to a name/username
  // search over everyone, so finding one specific person doesn't mean
  // scrolling the whole community list. Ineligible picks (no shared
  // community with the searcher) still surface as the existing
  // _addPerson toast, same as an untouched _people row would — search
  // doesn't pre-filter that here for the same reason PinPickerSheet
  // doesn't: duplicating circle_member_is_eligible()'s own definition
  // client-side would drift from it.
  final _queryCtrl = TextEditingController();
  Future<List<Map<String, dynamic>>>? _searchFuture;

  @override
  void initState() {
    super.initState();
    _queryCtrl.addListener(_onQueryChanged);
    _load();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) {
      setState(() => _searchFuture = null);
      return;
    }
    // Block body, not an arrow assignment — see PinPickerSheet._onQuery
    // Changed's own note: an arrow body hands setState the in-flight
    // Future as its "return value" and trips Flutter's assertion against
    // a setState callback that returns one.
    setState(() {
      _searchFuture = _searchWithMutuals(query);
    });
  }

  /// Search results with how many friends I share with each ("2 mutual"),
  /// the ones I share friends with first (2026-10-07). The count rides on
  /// the row as `mutual_count` so [_addPersonRow] can show it.
  Future<List<Map<String, dynamic>>> _searchWithMutuals(String query) async {
    final rows = await PeopleService.instance.searchPeople(query);
    final counts = await PeopleService.instance.mutualCounts([
      for (final r in rows)
        if (r['id'] is String) r['id'] as String,
    ]);
    return sortByMutuals([
      for (final r in rows) {...r, 'mutual_count': counts[r['id']] ?? 0},
    ], counts);
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        CircleService.instance.fetchMembers(widget.circle.id),
        PeopleService.instance.communityMembers(),
      ]);
      if (mounted) {
        setState(() {
          _members = results[0] as List<CircleMember>;
          _people = results[1] as List<Map<String, dynamic>>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Optimistic: the person moves into the member list the instant "+"
  /// is tapped; the write runs behind it and a refusal puts things back.
  /// It used to await the write AND a full reload before anything moved.
  Future<void> _addPerson(String userId) async {
    final before = _members;
    final person = (_people ?? const <Map<String, dynamic>>[])
        .where((p) => p['id'] == userId)
        .firstOrNull;
    HapticFeedback.selectionClick();
    setState(() {
      _members = [
        ...?_members,
        CircleMember(
          userId: userId,
          name: (person?['name'] as String?) ?? 'someone',
          avatarUrl: person?['profile_photo_url'] as String?,
        ),
      ];
    });
    try {
      await CircleService.instance.addMember(widget.circle.id, userId);
      unawaited(_load());
    } catch (e) {
      if (mounted) setState(() => _members = before);
      // No shared community is needed any more (20260929060000); a refusal
      // now only means a network failure or a block.
      if (mounted) {
        showGlassToast(context, "Couldn't add them — try again.", isError: true);
      }
    }
  }

  /// Optimistic, same as [_addPerson].
  Future<void> _removeMember(String memberId) async {
    final before = _members;
    HapticFeedback.selectionClick();
    setState(() => _members = [
          for (final m in _members ?? const <CircleMember>[])
            if (m.userId != memberId) m,
        ]);
    try {
      await CircleService.instance.removeMember(widget.circle.id, memberId);
      unawaited(_load());
    } catch (e) {
      if (mounted) {
        setState(() => _members = before);
        showGlassToast(context, 'Could not remove them.', isError: true);
      }
    }
  }

  /// The circle's current name — starts as the one passed in, updated
  /// in place after a rename so the title changes without a reload.
  late String _name = widget.circle.name;

  /// Rename — any circle, Friends included (allowed server-side since
  /// 20260928000000_allow_friends_circle_rename.sql).
  /// CircleService.renameCircle existed but nothing in the app called it,
  /// so circles could not be renamed at all ("I'm unable to change the
  /// circle's name").
  Future<void> _renameCircle() async {
    final ctrl = TextEditingController(text: _name);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PV2.raised,
        title: Text('Rename circle', style: PV2.body(size: 15, weight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.words,
          style: PV2.body(size: 14),
          decoration: const InputDecoration(hintText: 'Circle name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    final trimmed = next?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == _name) return;
    try {
      await CircleService.instance.renameCircle(widget.circle.id, trimmed);
      if (mounted) setState(() => _name = trimmed);
    } catch (e) {
      if (mounted) showGlassToast(context, "Couldn't rename that circle.", isError: true);
    }
  }

  Future<void> _deleteCircle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PV2.raised,
        title: Text('Delete "${widget.circle.name}"?', style: PV2.body(size: 15, weight: FontWeight.w700)),
        content: Text(
          'Past posts sent to this circle stay up for whoever else can '
          "already see them — this only removes the circle itself.",
          style: PV2.body(size: 13, color: PV2.inkBio),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: PV2.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await CircleService.instance.deleteCircle(widget.circle.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showGlassToast(context, 'Could not delete that circle.', isError: true);
    }
  }

  Widget _addPersonRow(Map<String, dynamic> p) {
    final mutual = (p['mutual_count'] as num?)?.toInt() ?? 0;
    return _PersonRow(
      userId: p['id'] as String?,
      name: (p['name'] as String?) ?? 'someone',
      avatarUrl: p['profile_photo_url'] as String?,
      subtitle: mutual > 0 ? '$mutual mutual' : null,
      trailing: NeuWell(
        width: 30,
        height: 30,
        circle: true,
        shadows: PV2.raisedSm,
        border: PV2.hairlinePanel,
        color: PV2.raised,
        onTap: () => _addPerson(p['id'] as String),
        child: PV2Icons.plus(14, PV2.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memberIds = {for (final m in _members ?? const <CircleMember>[]) m.userId};
    final addable = [
      for (final p in _people ?? const <Map<String, dynamic>>[])
        if (!memberIds.contains(p['id'])) p,
    ];
    final isSearching = _queryCtrl.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: PV2.page,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PV2.columnWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      NeuWell(
                        width: 38,
                        height: 38,
                        circle: true,
                        shadows: PV2.insetStd,
                        border: PV2.hairlinePanel,
                        color: PV2.raised,
                        onTap: () => Navigator.of(context).maybePop(),
                        child: PV2Icons.back(22, Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PV2.display(size: 20),
                        ),
                      ),
                      // Every circle can be renamed, Friends included.
                      NeuWell(
                        width: 38,
                        height: 38,
                        circle: true,
                        shadows: PV2.insetStd,
                        border: PV2.hairlinePanel,
                        color: PV2.raised,
                        onTap: _renameCircle,
                        child: const Icon(Icons.edit_outlined, size: 19, color: Colors.white),
                      ),
                      // Friends still can't be deleted.
                      if (!widget.circle.isFriends) ...[
                        const SizedBox(width: 8),
                        NeuWell(
                          width: 38,
                          height: 38,
                          circle: true,
                          shadows: PV2.insetStd,
                          border: PV2.hairlinePanel,
                          color: PV2.raised,
                          onTap: _deleteCircle,
                          child: Icon(Icons.delete_outline_rounded, size: 20, color: PV2.danger),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: _error != null
                      ? Center(child: Text('Could not load this circle.', style: PV2.body(size: 13, color: PV2.inkBio)))
                      : _members == null || _people == null
                          ? const Center(child: CircularProgressIndicator(color: PV2.accent))
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              children: [
                                SectionTitle(title: 'In this circle (${_members!.length})'),
                                const SizedBox(height: 8),
                                if (_members!.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'No one yet — add people below.',
                                      style: PV2.body(size: 13, color: PV2.inkBio),
                                    ),
                                  )
                                else
                                  for (final m in _members!)
                                    _PersonRow(
                                      userId: m.userId,
                                      name: m.name,
                                      avatarUrl: m.avatarUrl,
                                      trailing: NeuWell(
                                        width: 30,
                                        height: 30,
                                        circle: true,
                                        shadows: PV2.raisedSm,
                                        border: PV2.hairlinePanel,
                                        color: PV2.raised,
                                        onTap: () => _removeMember(m.userId),
                                        child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                                      ),
                                    ),
                                const SizedBox(height: 20),
                                SectionTitle(title: 'Add people'),
                                const SizedBox(height: 8),
                                NeuWell(
                                  radius: 14,
                                  shadows: PV2.insetStd,
                                  child: TextField(
                                    controller: _queryCtrl,
                                    style: PV2.body(size: 13.5),
                                    decoration: InputDecoration(
                                      hintText: 'Search by name or username…',
                                      hintStyle: PV2.body(size: 13.5, color: PV2.inkBio),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      errorBorder: InputBorder.none,
                                      disabledBorder: InputBorder.none,
                                      focusedErrorBorder: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.search_rounded,
                                        size: 16,
                                        color: PV2.inkBio,
                                      ),
                                      suffixIcon: isSearching
                                          ? GestureDetector(
                                              onTap: () => _queryCtrl.clear(),
                                              child: Icon(
                                                Icons.close_rounded,
                                                size: 16,
                                                color: PV2.inkBio,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (isSearching)
                                  // Widens the pool beyond just shared
                                  // communities — anyone in the app, by
                                  // name/username. A pick with no shared
                                  // community still 403s server-side
                                  // (circle_member_is_eligible), surfaced by
                                  // _addPerson's existing toast — same as it
                                  // always has been for the list below.
                                  FutureBuilder<List<Map<String, dynamic>>>(
                                    future: _searchFuture,
                                    builder: (context, snap) {
                                      if (snap.connectionState == ConnectionState.waiting) {
                                        return const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 16),
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              color: PV2.accent,
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        );
                                      }
                                      if (snap.hasError) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          child: Text(
                                            "Couldn't search right now.",
                                            style: PV2.body(size: 13, color: PV2.inkBio),
                                          ),
                                        );
                                      }
                                      final results = [
                                        for (final p in snap.data ?? const <Map<String, dynamic>>[])
                                          if (!memberIds.contains(p['id'])) p,
                                      ];
                                      if (results.isEmpty) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          child: Text(
                                            'No one found.',
                                            style: PV2.body(size: 13, color: PV2.inkBio),
                                          ),
                                        );
                                      }
                                      return Column(
                                        children: [for (final p in results) _addPersonRow(p)],
                                      );
                                    },
                                  )
                                else if (addable.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'Everyone eligible is already in this circle.',
                                      style: PV2.body(size: 13, color: PV2.inkBio),
                                    ),
                                  )
                                else
                                  for (final p in addable) _addPersonRow(p),
                              ],
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.avatarUrl,
    required this.trailing,
    this.userId,
    this.subtitle,
  });

  final String name;
  final String? avatarUrl;
  final Widget trailing;

  /// A second line under the name — "2 mutual" on a search result.
  final String? subtitle;

  /// When set, tapping the photo or name opens this person's profile.
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final id = userId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: id == null || id.isEmpty ? null : () => openProfile(context, id),
              child: Row(
                children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: PV2.raised,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
            child: avatarUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: PV2.body(size: 15, weight: FontWeight.w700),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PV2.body(size: 14),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PV2.body(
                      size: 11.5,
                      weight: FontWeight.w600,
                      color: PV2.accentSoft,
                    ),
                  ),
              ],
            ),
          ),
                ],
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
