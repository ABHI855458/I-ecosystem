import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../services/circle_service.dart';
import '../people/find_people_screen.dart';
import 'manage_circles_screen.dart';
import 'profile_navigation.dart' show openProfile;
import 'profile_v2_icons.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

// ---------------------------------------------------------------------------
// "N in your circle" — everyone you've put in a circle, as one list (the
// screen the count under your name opens). It replaces the Circles card
// that used to sit on the profile: a followers-style list of PEOPLE, with
// the circles as filter chips, rather than a list of circles to dig into.
//
// Only ever your own. Other people's circles stay private; on their
// profile you see the friends you share instead (PeopleService.mutualFriends).
// ---------------------------------------------------------------------------

/// The people shown for a chip + search box. Pure, for tests. [membership]
/// maps a person's id to the ids of my circles they are in; [circleId] null
/// means "All".
List<Map<String, dynamic>> filterCirclePeople(
  List<Map<String, dynamic>> people,
  Map<String, Set<String>> membership, {
  String? circleId,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final p in people)
      if ((circleId == null ||
              (membership[p['id']] ?? const <String>{}).contains(circleId)) &&
          (q.isEmpty ||
              ((p['name'] as String?) ?? '').toLowerCase().contains(q) ||
              ((p['username'] as String?) ?? '').toLowerCase().contains(q)))
        p,
  ];
}

class CirclePeopleScreen extends StatefulWidget {
  const CirclePeopleScreen({super.key});

  @override
  State<CirclePeopleScreen> createState() => _CirclePeopleScreenState();
}

class _CirclePeopleScreenState extends State<CirclePeopleScreen> {
  final _query = TextEditingController();
  List<Map<String, dynamic>>? _people;
  Map<String, Set<String>> _membership = const {};
  List<CircleOption> _circles = const [];
  String? _filter;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        CircleService.instance.fetchPeopleInMyCircles(),
        CircleService.instance.fetchMyMembership(),
        CircleService.instance.fetchMyCircles(),
      ]);
      if (!mounted) return;
      setState(() {
        _people = results[0] as List<Map<String, dynamic>>;
        _membership = results[1] as Map<String, Set<String>>;
        _circles = results[2] as List<CircleOption>;
        _failed = false;
        if (_filter != null && !_circles.any((c) => c.id == _filter)) {
          _filter = null;
        }
      });
    } catch (e) {
      debugPrint('[CirclePeople] load failed: $e');
      if (mounted) setState(() => _failed = _people == null);
    }
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) unawaited(_load());
  }

  int _countIn(String circleId) => [
    for (final p in _people ?? const <Map<String, dynamic>>[])
      if ((_membership[p['id']] ?? const <String>{}).contains(circleId)) p,
  ].length;

  Future<void> _editCircles(Map<String, dynamic> person) async {
    final id = person['id'] as String;
    final name = ((person['name'] as String?) ?? '').trim();
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CirclesForPersonSheet(
        name: name.isEmpty ? 'them' : name,
        circles: _circles,
        initial: _membership[id] ?? const {},
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await CircleService.instance.setMembership(id, picked);
      if (!mounted) return;
      showGlassToast(
        context,
        picked.isEmpty
            ? 'Removed ${name.isEmpty ? 'them' : name} from your circle'
            : 'Updated',
      );
    } catch (_) {
      if (mounted) {
        showGlassToast(context, "Couldn't update. Try again.", isError: true);
      }
    }
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final shown = people == null
        ? const <Map<String, dynamic>>[]
        : filterCirclePeople(
            people,
            _membership,
            circleId: _filter,
            query: _query.text,
          );
    return Scaffold(
      backgroundColor: PV2.page,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PV2.columnWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(people?.length),
                _searchField(),
                const SizedBox(height: 12),
                _chips(people?.length ?? 0),
                const SizedBox(height: 6),
                Expanded(
                  child: people == null
                      ? Center(
                          child: _failed
                              ? Text(
                                  "Couldn't load your circle.",
                                  style: PV2.body(
                                    size: 13,
                                    color: PV2.inkMember,
                                  ),
                                )
                              : const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: PV2.accent,
                                  ),
                                ),
                        )
                      : RefreshIndicator(
                          color: PV2.accent,
                          backgroundColor: PV2.raised,
                          onRefresh: _load,
                          child: _list(shown, total: people.length),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(int? count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Your circle', style: PV2.display(size: 21)),
                if (count != null)
                  Text(
                    count == 1 ? '1 person' : '$count people',
                    style: PV2.body(size: 12, color: PV2.inkMember),
                  ),
              ],
            ),
          ),
          GestureDetector(
            key: const ValueKey('circle-add-people'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_push(const FindPeopleScreen())),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: PV2.accentButton,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PV2Icons.plus(13, PV2.onAccent),
                  const SizedBox(width: 6),
                  Text(
                    'Add people',
                    style: PV2.body(
                      size: 12.5,
                      weight: FontWeight.w800,
                      color: PV2.onAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    final typing = _query.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: NeuWell(
        radius: 16,
        child: TextField(
          controller: _query,
          onChanged: (_) => setState(() {}),
          cursorColor: PV2.accent,
          style: PV2.body(size: 14),
          decoration: InputDecoration(
            hintText: 'Search your circle',
            hintStyle: PV2.body(size: 14, color: PV2.inkBio),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            prefixIcon: Icon(Icons.search_rounded, size: 18, color: PV2.inkBio),
            suffixIcon: typing
                ? GestureDetector(
                    onTap: () => setState(_query.clear),
                    child: Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: PV2.inkBio,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _chips(int total) {
    Widget chip(String label, int count, String? id) {
      final on = _filter == id;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _filter = id);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 34,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            color: on ? PV2.accent.withValues(alpha: 0.16) : PV2.raised,
            border: Border.all(
              color: on ? PV2.accent.withValues(alpha: 0.8) : PV2.hairlineBright,
            ),
          ),
          child: Text(
            '$label  $count',
            style: PV2.body(
              size: 12.5,
              weight: FontWeight.w700,
              color: on ? PV2.accentSoft : PV2.inkBio,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip('All', total, null),
          for (final c in _circles) ...[
            const SizedBox(width: 8),
            chip(c.name, _countIn(c.id), c.id),
          ],
        ],
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> shown, {required int total}) {
    final bottom = MediaQuery.paddingOf(context).bottom + 24;
    if (shown.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 18, 20, bottom),
        children: [
          Text(
            total == 0
                ? 'Nobody in your circle yet. The people you add here are '
                      'the ones who see what you post to friends.'
                : 'Nobody here matches.',
            style: PV2.body(size: 13, color: PV2.inkMember, height: 1.45),
          ),
          const SizedBox(height: 14),
          _manageLink(),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(16, 4, 8, bottom),
      itemCount: shown.length + 1,
      itemBuilder: (context, i) {
        if (i == shown.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 8, 0),
            child: _manageLink(),
          );
        }
        return _row(shown[i]);
      },
    );
  }

  Widget _manageLink() {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_push(const ManageCirclesScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Manage circles  ›',
            style: PV2.body(
              size: 13,
              weight: FontWeight.w700,
              color: PV2.accent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final name = ((p['name'] as String?) ?? '').trim();
    final username = ((p['username'] as String?) ?? '').trim();
    final photo = p['profile_photo_url'] as String?;
    final inIds = _membership[id] ?? const <String>{};
    final circleNames = [
      for (final c in _circles)
        if (inIds.contains(c.id)) c.name,
    ].join(', ');
    final sub = [
      if (username.isNotEmpty) '@$username',
      if (circleNames.isNotEmpty) circleNames,
    ].join(' · ');

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(openProfile(context, id)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: PV2.raised,
                    backgroundImage: photo != null && photo.isNotEmpty
                        ? CachedNetworkImageProvider(photo)
                        : null,
                    child: photo == null || photo.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: PV2.body(size: 16, weight: FontWeight.w700),
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
                          name.isEmpty ? 'someone' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PV2.body(size: 14.5, weight: FontWeight.w700),
                        ),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PV2.body(size: 12, color: PV2.inkMember),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_editCircles(p)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: PV2Icons.more(20, PV2.inkBio),
          ),
        ),
      ],
    );
  }
}

/// Tick which of my circles this person is in. Pops the new set on "Done",
/// an empty set on "Remove from your circle", null when dismissed.
class _CirclesForPersonSheet extends StatefulWidget {
  const _CirclesForPersonSheet({
    required this.name,
    required this.circles,
    required this.initial,
  });

  final String name;
  final List<CircleOption> circles;
  final Set<String> initial;

  @override
  State<_CirclesForPersonSheet> createState() => _CirclesForPersonSheetState();
}

class _CirclesForPersonSheetState extends State<_CirclesForPersonSheet> {
  late final Set<String> _picked = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF151518),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: EdgeInsets.fromLTRB(20, 18, 20, bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Circles for ${widget.name}', style: PV2.display(size: 18)),
          const SizedBox(height: 4),
          Text(
            'They see what you post to the circles you tick.',
            style: PV2.body(size: 12.5, color: PV2.inkMember),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in widget.circles)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (!_picked.remove(c.id)) _picked.add(c.id);
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.name,
                              style: PV2.body(
                                size: 14.5,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _picked.contains(c.id)
                                  ? PV2.accent
                                  : Colors.transparent,
                              border: Border.all(
                                color: _picked.contains(c.id)
                                    ? PV2.accent
                                    : PV2.hairlineActive,
                                width: 1.6,
                              ),
                            ),
                            child: _picked.contains(c.id)
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 15,
                                    color: PV2.onAccent,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(_picked),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: PV2.accentButton,
              ),
              child: Text(
                'Done',
                style: PV2.body(
                  size: 14.5,
                  weight: FontWeight.w800,
                  color: PV2.onAccent,
                ),
              ),
            ),
          ),
          if (widget.initial.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(context).pop(<String>{}),
              child: Text(
                'Remove from your circle',
                style: PV2.body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: PV2.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
