import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/glass.dart' show showPingToast;
import '../../../core/ping_haptics.dart';
import '../../../features/highlights/highlight_models.dart';
import '../../../features/highlights/highlight_story_viewer.dart';
import '../../../features/highlights/highlights_wall_screen.dart';
import '../../../features/highlights/polaroid_pile.dart';
import '../../../features/people/find_people_screen.dart';
import '../../../features/ping/ping_turns.dart';
import '../../../features/ping/reply_story_viewer.dart';
import '../../../features/profile_v2/profile_v2_icons.dart';
import '../../../features/profile_v2/profile_v2_tokens.dart';
import '../../../services/circle_service.dart';
import '../../../services/current_user_service.dart';
import '../../../services/feed_refresh_signal.dart';
import '../../../services/highlight_service.dart';
import '../../../services/ping_service.dart';
import '../../../shared/time_ago.dart';

// ---------------------------------------------------------------------------
// The top section of the Friends feed, directly under the Friends | Anon
// pill, closed off from the posts by one thin line.
//
//   left  — REPLIES: everyone who has replied to a ping of yours that is
//           still open. Tap a face for their reply story — the latest
//           first, then the earlier ones (see ReplyStoryViewer). They stay
//           here after being opened, to be watched "again and again" until
//           the ping is over; people with something new come first, in a
//           bright ring.
//           Only when nobody has replied: PING SOMEONE — friends you can
//           ping right now; a tap pings them there and then.
//   right — the polaroid pile: your friends' highlights. Tap the card to
//           see what is on it; tap HIGHLIGHTS for the whole Wall.
//
// This is a REPLIES row, not a to-do list. An earlier version put YOUR
// TURN (people who pinged you, waiting on an answer) in here; that was
// removed on request ("in the top section it shall not be your turn, it
// shall be the replies row of who have replied me only", 2026-10-07).
// Who is waiting on you lives on the Ping page and on the camera's send
// screen ("Pinged you").
//
// One row on purpose: a strip of faces with a tray of highlights under it
// was rejected as cluttered ("if one below other won't be good"). It is
// drawn BIG — faces you can read from arm's length, a pile you can see the
// photo on — after the first, half-size version read as an afterthought
// ("this section shall be elegant and big", 2026-10-07).
//
// Friends feed only — never Anon, never the Ping page (whose OPEN LOOPS
// section this replaces).
// ---------------------------------------------------------------------------

class FeedTopRow extends StatefulWidget {
  const FeedTopRow({super.key});

  static const double height = 184;

  /// Ask every mounted row to fetch again (the feed's pull-to-refresh).
  static void refresh() => _refreshTick.value++;
  static final _refreshTick = ValueNotifier<int>(0);

  @override
  State<FeedTopRow> createState() => _FeedTopRowState();
}

class _FeedTopRowState extends State<FeedTopRow> with WidgetsBindingObserver {
  // The row is the feed list's first item, so it is disposed when scrolled
  // far away and rebuilt on the way back. Starting again from what was last
  // shown keeps it from flashing a different mode before the data returns.
  static List<ReplyStory> _lastReplies = const [];
  static List<Map<String, dynamic>> _lastPingable = const [];
  static Map<String, int> _lastStreaks = const {};
  static List<Highlight> _lastWall = const [];

  /// False until each side has answered once since launch. Until then an
  /// empty list means "not asked yet", not "nothing there" — drawing the
  /// empty states for that first second announced "Your circle is empty"
  /// to someone with nineteen people in it.
  static bool _pingsLoaded = false;
  static bool _wallLoaded = false;

  List<ReplyStory> _replies = _lastReplies;
  List<Map<String, dynamic>> _pingable = _lastPingable;
  Map<String, int> _streaks = _lastStreaks;
  List<Highlight> _wall = _lastWall;
  int _wallVersion = -1;
  bool _pilePlaying = false;
  bool _storyOpen = false;

  /// Replies opened in the story on this device. The server learns of each
  /// a moment later, so a reload in between must not bring the face back.
  static final _openedHere = <String>{};

  /// Ids being pinged right now — a second tap on the same face is ignored.
  final _pinging = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    feedRefreshSignal.addListener(_reloadAll);
    FeedTopRow._refreshTick.addListener(_reloadAll);
    pingInboxChanged.addListener(_reloadPings);
    HighlightService.instance.addListener(_onHighlightsChanged);
    _reloadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    feedRefreshSignal.removeListener(_reloadAll);
    FeedTopRow._refreshTick.removeListener(_reloadAll);
    pingInboxChanged.removeListener(_reloadPings);
    HighlightService.instance.removeListener(_onHighlightsChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pings and replies arrive while the app is in the background.
    if (state == AppLifecycleState.resumed) _reloadAll();
  }

  void _reloadAll() {
    unawaited(_loadPings());
    unawaited(_loadWall());
  }

  void _reloadPings() => unawaited(_loadPings());

  void _onHighlightsChanged() {
    if (HighlightService.instance.version != _wallVersion) {
      unawaited(_loadWall());
    } else if (mounted) {
      setState(() {});
    }
  }

  /// Everything the left side can show, in one round trip each. A request
  /// that fails keeps what is already on screen (null = failed, which is
  /// not the same as empty).
  Future<void> _loadPings() async {
    try {
      final me = await CurrentUserService.instance.resolveId();
      final results = await Future.wait<Object?>([
        PingService.instance.fetchReplies(),
        PingService.instance.fetchSent(),
        CircleService.instance
            .fetchFriendsCircleUsers()
            .then<Object?>((v) => v)
            .catchError((_) => null),
        PingService.instance
            .fetchStreaks()
            .then<Object?>((v) => v)
            .catchError((_) => null),
      ]);
      if (!mounted) return;
      final replies = results[0] as List<ReceivedReplyRow>?;
      final sent = results[1] as List<OutboundPingRow>?;
      final friends = results[2] as List<Map<String, dynamic>>?;
      final streaks = results[3] as Map<String, int>?;
      setState(() {
        if (replies != null && friends != null) _pingsLoaded = true;
        if (replies != null) {
          _replies = _lastReplies = replyStories(
            replies,
            opened: _openedHere,
          );
        }
        if (streaks != null) _streaks = _lastStreaks = streaks;
        if (friends != null && sent != null) {
          _pingable = _lastPingable = pingablePeople(
            friends: friends,
            sent: sent,
            streaks: _streaks,
            myId: me,
          );
        }
      });
    } catch (e) {
      debugPrint('[FeedTopRow] pings failed: $e');
    }
  }

  Future<void> _loadWall() async {
    final version = HighlightService.instance.version;
    try {
      await HighlightService.instance.ready();
      final wall = await HighlightService.instance.fetchWall();
      if (!mounted) return;
      setState(() {
        _wall = _lastWall = wall;
        _wallVersion = version;
        _wallLoaded = true;
      });
    } catch (e) {
      debugPrint('[FeedTopRow] wall failed: $e');
    }
  }

  /// A reply face: their reply story, latest first — with the same thud
  /// as pinging someone on the Ping page ("tapping on the replies shall
  /// also give the same vibrations as pinging someone", 2026-10-07).
  /// The whole row is handed over, as with stories: when theirs ends the
  /// next person's plays, and a sideways swipe moves between people.
  Future<void> _openReplies(int index) async {
    if (_storyOpen || index >= _replies.length) return;
    _storyOpen = true;
    unawaited(pingThud());
    try {
      final opened = await openReplyStory(
        context,
        stories: _replies,
        initialIndex: index,
      );
      _openedHere.addAll(opened);
      if (!mounted) return;
      // Nobody leaves the row for having been opened: they move behind
      // the people who still have something new, and lose the bright ring.
      setState(() {
        _replies = _lastReplies = replyStories([
          for (final s in _replies) ...s.replies,
        ], opened: _openedHere);
      });
      unawaited(_loadPings());
    } finally {
      _storyOpen = false;
    }
  }

  /// PING SOMEONE: one tap pings them, the same way a face on the Ping
  /// page does — the thud and the toast come at once, the face leaves the
  /// row (they can't be pinged again until this ping closes), and it comes
  /// back only if the send turns out to have failed.
  Future<void> _ping(Map<String, dynamic> person) async {
    final id = person['id'] as String;
    if (!_pinging.add(id)) return;
    final name = _firstName(person);
    unawaited(pingThud());
    final index = _pingable.indexOf(person);
    setState(() {
      _pingable = _lastPingable = [
        for (final p in _pingable)
          if (p['id'] != id) p,
      ];
    });
    showPingToast(context, 'Pinged $name ✓');
    try {
      await PingService.instance.send(receiverId: id, prompt: '');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        final back = [..._pingable];
        back.insert(index.clamp(0, back.length), person);
        _pingable = _lastPingable = back;
      });
      showPingToast(
        context,
        e is PingLimitExceeded ||
                e is PingAlreadyOpen ||
                e is PingSelfNotAllowed ||
                e is PingBlocked
            ? e.toString()
            : "Couldn't ping $name.",
        isError: true,
      );
    } finally {
      _pinging.remove(id);
    }
  }

  static String _firstName(Map<String, dynamic> person) {
    final name = ((person['name'] as String?) ?? '').trim();
    return name.isEmpty ? 'them' : name.split(' ').first;
  }

  /// What the pile's card shows: the newest highlight I haven't watched,
  /// else the most recent friend's, else my own.
  ({Highlight? top, List<Highlight> fresh}) _pile() {
    final svc = HighlightService.instance;
    final friends = sortForWall([
      for (final h in _wall)
        if (!svc.isMine(h)) h,
    ], isNew: svc.isNew);
    return (
      top: friends.isNotEmpty
          ? friends.first
          : (_wall.isNotEmpty ? _wall.first : null),
      fresh: [
        for (final h in friends)
          if (svc.isNew(h)) h,
      ],
    );
  }

  /// The card: play what is on it — every new highlight back to back, or,
  /// with nothing new, the one photo showing ("if clicked on photo it shall
  /// be seen", 2026-10-07; it used to skip straight to the Wall's grid).
  /// Watched to the end, it lands on the Wall.
  Future<void> _openPile() async {
    if (_pilePlaying) return;
    _pilePlaying = true;
    try {
      unawaited(HapticFeedback.selectionClick());
      final pile = _pile();
      final queue = pile.fresh.isNotEmpty
          ? pile.fresh
          : [if (pile.top != null) pile.top!];
      if (queue.isNotEmpty) {
        final finished = await openHighlightStory(context, highlights: queue);
        // Swiped away part-way: back to the feed, not on to the Wall.
        if (!finished || !mounted) return;
      }
      await openHighlightsWall(context);
    } finally {
      _pilePlaying = false;
    }
  }

  /// The HIGHLIGHTS heading: straight to the Wall.
  Future<void> _openWall() async {
    if (_pilePlaying) return;
    _pilePlaying = true;
    try {
      unawaited(HapticFeedback.selectionClick());
      await openHighlightsWall(context);
    } finally {
      _pilePlaying = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pile = _pile();
    return SizedBox(
      height: FeedTopRow.height,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 14, 0),
              child: Row(
                // Both sides start at the top, so the two small headings
                // (e.g. YOUR TURN / HIGHLIGHTS) sit on one line.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _left()),
                  const SizedBox(width: 10),
                  PolaroidPile(
                    top: pile.top,
                    loading: !_wallLoaded,
                    newCount: pile.fresh.length,
                    onTap: () => unawaited(_openPile()),
                    onOpenWall: () => unawaited(_openWall()),
                  ),
                ],
              ),
            ),
          ),
          // The one thin line between this section and the posts.
          Container(
            key: const ValueKey('feed-top-divider'),
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0.11),
                  Colors.white.withValues(alpha: 0.11),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const [0, 0.12, 0.88, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Replies — and only when there are none at all, who to ping.
  Widget _left() {
    if (_replies.isNotEmpty) {
      return _strip(
        key: const ValueKey('row-replies'),
        heading: 'REPLIES',
        badge: _replies.fold<int>(0, (n, s) => n + s.unseen),
        count: _replies.length,
        itemBuilder: (i) => _ReplyFace(
          story: _replies[i],
          onTap: () => unawaited(_openReplies(i)),
        ),
      );
    }
    if (_pingable.isNotEmpty) {
      return _strip(
        key: const ValueKey('row-ping-someone'),
        heading: 'PING SOMEONE',
        count: _pingable.length,
        itemBuilder: (i) {
          final person = _pingable[i];
          return _PingFace(
            name: _firstName(person),
            avatarUrl: person['profile_photo_url'] as String?,
            streak: _streaks[person['id']] ?? 0,
            onTap: () => unawaited(_ping(person)),
          );
        },
      );
    }
    // Still waiting on the first answer: quiet placeholders, no claims.
    if (!_pingsLoaded) return const _StripSkeleton();
    // Nobody in the circle yet: the one thing worth offering is people.
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        key: const ValueKey('row-find-people'),
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const FindPeopleScreen()),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your circle is empty',
              style: PV2.display(size: 19, letterSpacing: -0.2),
            ),
            const SizedBox(height: 6),
            Text(
              'Find people to ping  ›',
              style: PV2.body(
                size: 14.5,
                weight: FontWeight.w700,
                color: PV2.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _strip({
    required Key key,
    required String heading,
    required int count,
    required Widget Function(int index) itemBuilder,
    int badge = 0,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              heading,
              style: PV2.caps(size: 11.5, tracking: 0.14, color: PV2.inkMember),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  color: PV2.accent.withValues(alpha: 0.16),
                ),
                child: Text(
                  '$badge',
                  style: PV2.body(
                    size: 11,
                    weight: FontWeight.w800,
                    color: PV2.accent,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _kTileHeight,
          // Faces scrolling towards the pile fade out before they reach it
          // — clipped hard, the last one looked cut in half; not clipped
          // at all, it slid underneath the polaroid.
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.86, 1],
            ).createShader(rect),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // Room above for the corner badges, which sit just outside
              // their face; room at the end so the last face can scroll
              // clear of the fade.
              padding: const EdgeInsets.only(top: 4, right: 30),
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => itemBuilder(i),
            ),
          ),
        ),
      ],
    );
  }
}

/// What the left side shows before its first load: the shape of a strip,
/// with nothing in it.
class _StripSkeleton extends StatelessWidget {
  const _StripSkeleton();

  @override
  Widget build(BuildContext context) {
    final fill = Colors.white.withValues(alpha: 0.05);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 84,
          height: 11,
          margin: const EdgeInsets.only(top: 2, bottom: 15),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: _kRing,
                height: _kRing,
                margin: const EdgeInsets.only(right: 18),
                decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
              ),
          ],
        ),
      ],
    );
  }
}

const double _kFace = 60; // the photo itself
const double _kRing = 72; // photo + its ring and the gap between them
// Face + gap + two text lines is 115 at the default font size; the rest is
// room for a larger system font before anything can overflow.
const double _kTileHeight = 132;

/// The shared tile: a ringed face, an optional badge on its corner, a name
/// and one short caption under it.
class _RowFace extends StatelessWidget {
  const _RowFace({
    required this.name,
    required this.caption,
    required this.avatar,
    required this.onTap,
    this.ring = const _Ring.quiet(),
    this.captionColor = PV2.inkMember,
    this.topRight,
    this.bottomRight,
  });

  final String name;
  final String caption;
  final Widget avatar;
  final VoidCallback onTap;
  final _Ring ring;
  final Color captionColor;
  final Widget? topRight;
  final Widget? bottomRight;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 78,
        child: Column(
          children: [
            SizedBox(
              width: _kRing,
              height: _kRing,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // The ring is its own painted circle with the page colour
                  // punched through, so it can be a gradient.
                  Container(
                    width: _kRing,
                    height: _kRing,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: ring.gradient,
                      color: ring.gradient == null ? ring.color : null,
                    ),
                  ),
                  Container(
                    width: _kRing - ring.width * 2,
                    height: _kRing - ring.width * 2,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: PV2.page,
                    ),
                  ),
                  SizedBox(width: _kFace, height: _kFace, child: avatar),
                  if (topRight != null)
                    Positioned(right: -3, top: -3, child: topRight!),
                  if (bottomRight != null)
                    Positioned(right: -6, bottom: -4, child: bottomRight!),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: PV2.body(
                size: 13,
                weight: FontWeight.w700,
                color: PV2.ink,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: PV2.body(
                size: 11,
                weight: FontWeight.w600,
                color: captionColor,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How a face is ringed: a bright gradient for something new to open, a
/// quiet hairline for the rest.
class _Ring {
  const _Ring.quiet()
    : gradient = null,
      color = const Color(0x29FFFFFF),
      width = 1.5;
  const _Ring.unopened()
    : gradient = const SweepGradient(
        colors: [
          PV2.accentSoft,
          PV2.accent,
          PV2.streakBlue,
          Color(0xFF8E7BFF),
          PV2.accentSoft,
        ],
      ),
      color = PV2.accent,
      width = 2.8;

  final Gradient? gradient;
  final Color color;
  final double width;
}

Widget _circle({String? url, required Widget fallback}) {
  final has = url != null && url.isNotEmpty;
  return CircleAvatar(
    radius: _kFace / 2,
    backgroundColor: const Color(0xFF1B1B22),
    backgroundImage: has ? CachedNetworkImageProvider(url) : null,
    child: has ? null : fallback,
  );
}

Widget _initial(String name) => Text(
  name.isEmpty ? '?' : name[0].toUpperCase(),
  style: PV2.display(size: 23),
);

/// Someone who has replied to a ping of mine. With something unopened:
/// a bright ring, a count when there is more than one, and "replied · 5m".
/// Once everything of theirs has been seen the ring goes quiet and the
/// caption just says when — the face stays, to be opened again.
class _ReplyFace extends StatelessWidget {
  const _ReplyFace({required this.story, required this.onTap});

  final ReplyStory story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = story.name.trim().split(' ').first;
    final fresh = story.unseen > 0;
    final at = story.newest.createdAt;
    return _RowFace(
      name: name.isEmpty ? 'Someone' : name,
      caption: !fresh
          ? formatRelativeTime(at, withAgo: true)
          : story.unseen > 1
          ? '${story.unseen} new'
          : 'replied · ${formatRelativeTime(at)}',
      captionColor: fresh ? PV2.accent : PV2.inkMember,
      ring: fresh ? const _Ring.unopened() : const _Ring.quiet(),
      topRight: story.unseen > 1
          ? Container(
              constraints: const BoxConstraints(minWidth: 23),
              height: 23,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                gradient: PV2.accentButton,
                border: Border.all(color: PV2.page, width: 2),
              ),
              child: Text(
                '${story.unseen}',
                style: PV2.body(
                  size: 11,
                  weight: FontWeight.w800,
                  color: PV2.onAccent,
                  height: 1.1,
                ),
              ),
            )
          : null,
      avatar: _circle(url: story.avatarUrl, fallback: _initial(name)),
      onTap: onTap,
    );
  }
}

/// A friend I can ping right now. The blue flame is my streak with them;
/// the word under the name says what a tap does, because it does it at
/// once.
class _PingFace extends StatelessWidget {
  const _PingFace({
    required this.name,
    required this.avatarUrl,
    required this.streak,
    required this.onTap,
  });

  final String name;
  final String? avatarUrl;
  final int streak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _RowFace(
      name: name,
      caption: 'Ping',
      captionColor: PV2.accent,
      bottomRight: streak > 0
          ? PV2Icons.blueFlameStreak(streak, flameSize: 27)
          : null,
      avatar: _circle(url: avatarUrl, fallback: _initial(name)),
      onTap: onTap,
    );
  }
}
