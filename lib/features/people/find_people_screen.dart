import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../screens/feed/widgets/people_suggestion_strip.dart'
    show showCirclePicker;
import '../../services/circle_service.dart';
import '../../services/people_service.dart';
import '../profile_v2/profile_navigation.dart' show openProfile;
import '../profile_v2/profile_v2_icons.dart';
import '../profile_v2/profile_v2_tokens.dart';
import '../profile_v2/profile_v2_widgets.dart';

// ---------------------------------------------------------------------------
// Find people — one search for the whole app (opened from the Chat header
// and from "Add people" on the circle list).
//
// Type a name: rows show the person, how many friends you share ("2
// mutual"), an Add button, and tapping the row opens their profile. People
// you share friends with come first. Before you type it lists suggestions,
// again most-mutuals first.
//
// "Mutual" = in your Friends circle and also in theirs (the mutual_friends
// RPCs — see 20261007020000_mutual_friends.sql).
// ---------------------------------------------------------------------------

/// Orders people rows most-mutuals first, keeping the incoming order among
/// equals. Pure, for tests. [idOf] reads a row's user id.
List<Map<String, dynamic>> sortByMutuals(
  List<Map<String, dynamic>> rows,
  Map<String, int> mutuals, {
  String? Function(Map<String, dynamic> row) idOf = _idOf,
}) {
  final indexed = [
    for (var i = 0; i < rows.length; i++) (i, rows[i]),
  ];
  indexed.sort((a, b) {
    final ma = mutuals[idOf(a.$2)] ?? 0;
    final mb = mutuals[idOf(b.$2)] ?? 0;
    if (ma != mb) return mb.compareTo(ma);
    return a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

String? _idOf(Map<String, dynamic> row) =>
    (row['id'] ?? row['user_id']) as String?;

class FindPeopleScreen extends StatefulWidget {
  const FindPeopleScreen({super.key});

  @override
  State<FindPeopleScreen> createState() => _FindPeopleScreenState();
}

class _FindPeopleScreenState extends State<FindPeopleScreen> {
  final _query = TextEditingController();
  Timer? _debounce;

  /// Bumped per search so a slow earlier answer can't overwrite a newer one.
  int _searchGen = 0;
  bool _searching = false;
  List<Map<String, dynamic>>? _results;
  List<Map<String, dynamic>>? _suggested;
  Map<String, int> _mutuals = const {};

  /// user id -> the circles I already have them in (so the button reads
  /// "In Friends" rather than offering to add them again).
  Map<String, Set<String>> _membership = const {};
  Map<String, String> _circleNames = const {};
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_loadSuggested());
    unawaited(_loadMembership());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadMembership() async {
    try {
      final results = await Future.wait<Object>([
        CircleService.instance.fetchMyMembership(),
        CircleService.instance.fetchMyCircles(),
      ]);
      if (!mounted) return;
      setState(() {
        _membership = results[0] as Map<String, Set<String>>;
        _circleNames = {
          for (final c in results[1] as List<CircleOption>) c.id: c.name,
        };
      });
    } catch (_) {
      // Worst case the button says "Add" for someone already added, and
      // adding again is a no-op server-side.
    }
  }

  Future<void> _loadSuggested() async {
    // Already mutual-first from the server, with mutual_count on each row.
    final rows = await PeopleService.instance.suggestedPeople(limit: 40);
    if (!mounted) return;
    setState(() {
      _suggested = rows;
      _mutuals = {
        ..._mutuals,
        for (final r in rows)
          if (r['user_id'] is String)
            r['user_id'] as String: (r['mutual_count'] as num?)?.toInt() ?? 0,
      };
    });
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      _searchGen++;
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(q));
  }

  Future<void> _search(String q) async {
    final gen = ++_searchGen;
    try {
      final rows = await PeopleService.instance.searchPeople(q);
      final counts = await PeopleService.instance.mutualCounts([
        for (final r in rows)
          if (r['id'] is String) r['id'] as String,
      ]);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _mutuals = {..._mutuals, ...counts};
        _results = sortByMutuals(rows, counts);
        _searching = false;
      });
    } catch (_) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
      showGlassToast(context, "Couldn't search right now.", isError: true);
    }
  }

  Future<void> _add(Map<String, dynamic> row) async {
    final id = _idOf(row);
    if (id == null || _busy.contains(id)) return;
    HapticFeedback.selectionClick();
    final name = ((row['name'] as String?) ?? '').trim();
    final picked = await showCirclePicker(
      context,
      name: name,
      photoUrl: row['profile_photo_url'] as String?,
    );
    if (picked == null || !mounted) return;
    setState(() => _busy.add(id));
    try {
      await CircleService.instance.addMember(picked.id, id);
      if (!mounted) return;
      setState(() {
        _membership = {
          ..._membership,
          id: {...?_membership[id], picked.id},
        };
        _circleNames = {..._circleNames, picked.id: picked.name};
      });
      showGlassToast(
        context,
        'Added ${name.isEmpty ? 'them' : name} to ${picked.name}',
      );
    } catch (_) {
      if (mounted) {
        // circle_member_is_eligible: you can only add someone you share a
        // community with.
        showGlassToast(
          context,
          "Couldn't add them. You can add people from your communities.",
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final typing = _query.text.trim().isNotEmpty;
    final rows = typing ? _results : _suggested;
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
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
                      Text('Find people', style: PV2.display(size: 21)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: NeuWell(
                    radius: 16,
                    child: TextField(
                      key: const ValueKey('find-people-field'),
                      controller: _query,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: _onQueryChanged,
                      cursorColor: PV2.accent,
                      style: PV2.body(size: 14),
                      decoration: InputDecoration(
                        hintText: 'Search by name or username',
                        hintStyle: PV2.body(size: 14, color: PV2.inkBio),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: PV2.inkBio,
                        ),
                        suffixIcon: typing
                            ? GestureDetector(
                                onTap: () {
                                  _query.clear();
                                  _onQueryChanged('');
                                },
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
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                  child: Text(
                    typing ? 'RESULTS' : 'PEOPLE YOU MAY KNOW',
                    style: PV2.caps(
                      size: 10.5,
                      tracking: 0.14,
                      color: PV2.inkMember,
                    ),
                  ),
                ),
                Expanded(child: _list(rows, typing: typing)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>>? rows, {required bool typing}) {
    if (rows == null || (typing && _searching && rows.isEmpty)) {
      return const Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: 28),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: PV2.accent,
            ),
          ),
        ),
      );
    }
    if (rows.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Text(
            typing
                ? 'Nobody by that name.'
                : 'No suggestions right now. Search for someone by name.',
            style: PV2.body(size: 13, color: PV2.inkMember),
          ),
        ),
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        16,
        2,
        16,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      itemCount: rows.length,
      itemBuilder: (context, i) => _row(rows[i]),
    );
  }

  Widget _row(Map<String, dynamic> row) {
    final id = _idOf(row);
    final name = ((row['name'] as String?) ?? '').trim();
    final username = ((row['username'] as String?) ?? '').trim();
    final photo = row['profile_photo_url'] as String?;
    final mutual = id == null ? 0 : (_mutuals[id] ?? 0);
    final circles = id == null ? const <String>{} : (_membership[id] ?? const {});
    final inCircle = circles.isNotEmpty;
    final circleLabel = inCircle
        ? (_circleNames[circles.first] ?? 'your circle')
        : null;
    final busy = id != null && _busy.contains(id);

    final sub = [
      if (username.isNotEmpty) '@$username',
      if (mutual > 0) '$mutual mutual',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: id == null
                  ? null
                  : () => unawaited(openProfile(context, id)),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
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
                            style: PV2.body(
                              size: 12,
                              color: mutual > 0 ? PV2.accentSoft : PV2.inkMember,
                              weight: mutual > 0
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: inCircle || busy ? null : () => unawaited(_add(row)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 34,
              constraints: const BoxConstraints(minWidth: 62, maxWidth: 130),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                gradient: inCircle ? null : PV2.accentButton,
                color: inCircle ? PV2.disabledFill : null,
              ),
              child: busy
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: PV2.onAccent,
                      ),
                    )
                  : Text(
                      inCircle ? 'In $circleLabel' : 'Add',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PV2.body(
                        size: 12.5,
                        weight: FontWeight.w800,
                        color: inCircle ? PV2.inkMember : PV2.onAccent,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
