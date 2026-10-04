import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import '../../core/feature_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../core/supabase_config.dart';
import '../groups/moments/locked_replies_screen.dart';
import '../../screens/feed/widgets/moment_card.dart'
    show momentPaletteFor, momentTimeLeft;
import '../../services/block_service.dart';
import '../../services/current_user_service.dart';
import '../../services/feed_service.dart';
import '../../services/circle_service.dart';
import '../../services/group_service.dart';
import '../../services/ping_service.dart';
import '../../services/profile_view_service.dart';
import '../../services/storage_service.dart';
import '../../services/us_album_service.dart';
import 'group_profile_v2_screen.dart';
import 'profile_posts_list.dart';
import 'locked_preview.dart';
import 'profile_v2_data.dart';
import 'profile_v2_icons.dart';
import 'profile_v2_menus.dart';
import 'profile_v2_sections.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';
import 'duo_highlights.dart';

/// Someone else's profile.
///
/// This is the view of a person who is *not* the profile owner, and that
/// framing is binding: there is no anonymous-post section, no anon post count
/// and no teaser for one. The only anon reference the design permits here is
/// the anon-score numeral in the bento grid. Anonymous content lives on
/// MyProfileScreen's Anon tab, which only its owner can ever open.
class TheirProfileScreen extends StatefulWidget {
  const TheirProfileScreen({
    super.key,
    this.person = PV2Data.person,
    this.backdropIndex = 0,
    this.showMomentsTab = true,
    this.showBackButton = true,
    this.extraBottomInset = 0,
  });

  final PersonProfile person;
  final int backdropIndex;

  /// Space to reserve below the content for chrome the host floats over the
  /// page — the app shell's nav pill, for instance.
  final double extraBottomInset;

  /// Moments is a feature flag in the design — when off, the tab row collapses
  /// to Posts alone rather than showing a disabled tab.
  final bool showMomentsTab;

  final bool showBackButton;

  @override
  State<TheirProfileScreen> createState() => _TheirProfileScreenState();
}

class _TheirProfileScreenState extends State<TheirProfileScreen> {
  late int _backdrop = widget.backdropIndex;
  bool _pickerOpen = false;
  bool _moreOpen = false;
  int _tab = 0;

  // Which of MY circles this person is in. Null = still loading (or no real
  // userId — the mock PV2Data.person default has none). There are no friend
  // requests: I decide, alone and silently, which of my circles they're in.
  Set<String>? _myCircleIds;
  bool _circleActionPending = false;

  /// My own `users.id`, for sorting/labelling "my" Duo with this person
  /// among all of theirs. Null until resolved.
  String? _myUserId;

  /// My own profile photo, for the fused pair avatar on the backdrop. Null
  /// until it loads (or if I have none) — the fused avatar falls back to a
  /// plain ring for that half rather than waiting on it.
  String? _myAvatarUrl;

  // Duos — every pairing this person is in that I'm allowed to see at all
  // (DuoService.fetchAlbumsInvolving, RLS-filtered), shown as the same
  // highlight-card grid as MyProfileScreen's own Duos tab (explicit
  // request, 2026-10-01: "others profile shall also appear" like mine). A
  // pairing not involving me is additionally dropped client-side unless it
  // has at least one photo actually visible to me — see _loadPersonDuos.
  List<PersonDuoRow> _personDuos = const [];
  bool _duosLoading = true;
  Map<String, String> _duoCovers = const {};

  /// 0 = Duos, 1 = Groups — the same two-tab switch MyProfileScreen uses.
  int _duoGroupTab = 0;

  // Posts — real data (FeedService.fetchUserPosts), replacing the hardcoded
  // PV2Data.posts swatches. Read-only here: no add-post tile and no delete
  // menu, since this is someone else's profile.
  List<FeedItem> _theirPosts = const [];

  /// Post count, fetched for everyone. The locked preview shows it so a
  /// stranger can see the profile is active without seeing what is in it.
  int _theirPostCount = 0;

  // Moments — real data, same merge (posted + commented-on, de-duped) as
  // MyProfileScreen._loadMyMoments. Gated to their Friends circle in
  // _contentSection (see its own doc).
  List<MomentCard> _theirMoments = const [];

  // Groups — real data (GroupService.fetchGroupsForUser), replacing the
  // old hardcoded PV2Data.groups (same list shown on every profile,
  // regardless of whose it was, with no real navigation — see
  // _groupCard's own doc). Visible only once RLS actually allows it
  // (group_members_select_friend/groups_select_friend_member, which now mean
  // "I'm in a member's Friends circle"): otherwise the fetch simply comes
  // back empty, same silent-narrowing posture as _duo's own real-data fields.
  List<MyGroupRow> _groupRows = const [];
  Map<String, String> _groupCovers = const {};

  /// Where I stand relative to this profile, per the server:
  /// `self` | `friend` | `community` | `locked`. Null while resolving.
  ///
  /// `friend` = THEY put ME in their Friends circle (one-directional — my
  /// own circles never grant me anything on their profile). Someone who
  /// only shares a real community sees the slice of posts belonging to the
  /// communities both are in.
  String? _access;

  bool get _accessResolved => _access != null;
  bool get _isLocked => _access == 'locked';
  bool get _isFriend => _access == 'friend';

  @override
  void initState() {
    super.initState();
    // Access state first, THEN content. A viewer's device must never
    // receive the posts/moments/groups it is not allowed to see — blurring
    // content that already arrived is theatre, not privacy. _loadGated()
    // fetches only once the answer is known, and never when it is 'locked'.
    _loadAccess().then((_) => _loadGated());
    _loadMyCircleIds();
    _loadPersonDuos();
    _loadPostCount();
    _recordView();
    _loadMyAvatar();
  }

  Future<void> _loadMyAvatar() async {
    try {
      final myId = await CurrentUserService.instance.resolveId();
      final row = await supabase
          .from('users')
          .select('profile_photo_url')
          .eq('id', myId)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _myAvatarUrl = row?['profile_photo_url'] as String?);
    } catch (_) {
      // Decorative — the pair chip just shows the plain ring for my half.
    }
  }

  Future<void> _loadTheirGroups() async {
    final otherId = widget.person.userId;
    if (otherId == null) return;
    try {
      // fetchGroupsWithCounts (groups_with_counts_for_user) is already the
      // one place RLS/friendship is checked — a non-friend viewer gets []
      // back regardless of what this does with the result.
      final rows = await GroupService.instance.fetchGroupsWithCounts(otherId);
      final groupIds = [for (final row in rows) row['id'] as String];
      // Same highlight-card enrichment MyProfileScreen's own Groups tab
      // uses — avatars, streaks and covers in parallel.
      final coversFuture = GroupService.instance
          .fetchLatestPostPhotos(groupIds)
          .catchError((_) => <String, String>{});
      final streaksFuture = GroupService.instance
          .fetchGroupStreakBundle(groupIds)
          .catchError(
            (_) => <String, ({int shared, Map<String, int> members})>{},
          );
      final avatars = await GroupService.instance
          .fetchMemberAvatars(groupIds)
          .catchError((_) => <String, List<String?>>{});
      final streaks = await streaksFuture;
      final covers = await coversFuture;
      final enriched = [
        for (final row in rows)
          MyGroupRow(
            id: row['id'] as String,
            name: (row['name'] as String?) ?? 'Group',
            initial: ((row['name'] as String?) ?? 'Group').isNotEmpty
                ? (row['name'] as String)[0].toUpperCase()
                : '?',
            members: (row['member_count'] as num?)?.toInt() ?? 0,
            memories: (row['post_count'] as num?)?.toInt() ?? 0,
            dips: 0,
            last:
                '${(row['post_count'] as num?)?.toInt() ?? 0} post${(row['post_count'] as num?)?.toInt() == 1 ? '' : 's'}',
            gradient: kGroupGradients[(row['name'] as String? ?? 'Group')
                    .hashCode
                    .abs() %
                kGroupGradients.length],
            memberAvatarUrls: avatars[row['id'] as String] ?? const [],
            memberStreaks: [
              for (final uid in GroupService
                      .instance.memberIdsByGroup[row['id'] as String] ??
                  const <String>[])
                streaks[row['id'] as String]?.members[uid] ?? 0,
            ],
            groupStreak: streaks[row['id'] as String]?.shared ?? 0,
            iconUrl: row['icon_url'] as String?,
          ),
      ];
      enriched.sort((a, b) {
        final st = b.groupStreak.compareTo(a.groupStreak);
        if (st != 0) return st;
        final posts = b.memories.compareTo(a.memories);
        if (posts != 0) return posts;
        return b.members.compareTo(a.members);
      });
      if (!mounted) return;
      setState(() {
        _groupRows = enriched;
        _groupCovers = covers;
      });
    } catch (_) {
      // Leaves _groupRows empty — the section just doesn't render, same
      // fail-soft posture as every other real-data load on this screen.
    }
  }

  /// Every Duo this person is a party to that I'm allowed to see — our own
  /// pairing with them (any status, same as it'd show on my own profile),
  /// plus anyone else's accepted pairing with them that has a photo
  /// actually visible to me. RLS (us_albums_select) already keeps a
  /// stranger's unrelated pending/empty pairings off the wire entirely;
  /// this adds the one rule RLS can't express — "0 photos I can see" still
  /// drops the card, per explicit request (2026-10-01).
  Future<void> _loadPersonDuos() async {
    final otherId = widget.person.userId;
    if (otherId == null) {
      setState(() => _duosLoading = false);
      return;
    }
    try {
      final myId = await CurrentUserService.instance.resolveId();
      final rows = await DuoService.instance.fetchAlbumsInvolving(otherId);
      final kept = [
        for (final r in rows)
          if (r.partnerId == myId || r.visiblePhotoCount > 0) r,
      ]..sort((a, b) {
          final mine = (b.partnerId == myId ? 1 : 0)
              .compareTo(a.partnerId == myId ? 1 : 0);
          if (mine != 0) return mine;
          return b.visiblePhotoCount.compareTo(a.visiblePhotoCount);
        });
      if (!mounted) return;
      setState(() {
        _myUserId = myId;
        _personDuos = kept;
        _duosLoading = false;
      });
      unawaited(_loadDuoCovers(kept));
    } catch (_) {
      if (mounted) setState(() => _duosLoading = false);
    }
  }

  Future<void> _loadDuoCovers(List<PersonDuoRow> rows) async {
    try {
      final paths = await DuoService.instance
          .fetchLatestPhotoPaths([for (final r in rows) r.album.id]);
      final entries = await Future.wait([
        for (final e in paths.entries)
          StorageService.signedDuoPhotoUrl(e.value)
              .then((u) => MapEntry(e.key, u)),
      ]);
      if (!mounted) return;
      setState(() {
        _duoCovers = {
          for (final e in entries)
            if (e.value != null) e.key: e.value!,
        };
      });
    } catch (_) {}
  }

  /// Records this as a real profile view (ProfileViewService, backed by the
  /// live `profile_views` table) — fire-and-forget, same non-fatal posture
  /// as every other load here. Guarded the same way _loadTheirPosts guards
  /// the mock PV2Data.person default (no userId = nobody to record against).
  Future<void> _recordView() async {
    final otherId = widget.person.userId;
    if (otherId == null) return;
    await ProfileViewService.instance.record(otherId);
  }

  /// Their anonymous posts can never appear here — fetchUserPosts filters on
  /// visibility, and posts_select would hide them from a non-author anyway.
  /// What this viewer may see of the profile, per the server — decides what
  /// [_loadGated] is allowed to fetch at all.
  Future<void> _loadAccess() async {
    final otherId = widget.person.userId;
    if (otherId == null) {
      // Mock PV2Data.person (design gallery) — treat as locked rather than
      // guessing, so the gallery can't accidentally render a real-looking
      // open profile.
      if (mounted) setState(() => _access = 'locked');
      return;
    }
    final state = await FeedService.instance.profileAccessState(otherId);
    if (mounted) setState(() => _access = state);
  }

  Future<void> _loadGated() async {
    // Posts now load for `friend` AND `community` — the server decides which
    // posts come back (profile_posts_for_viewer), so this only has to decide
    // whether to ask at all. Moments and groups stay Friends-circle-only:
    // neither is community-scoped, so there is no slice to show anyone else.
    if (_isLocked) return;
    await Future.wait([
      _loadTheirPosts(),
      if (_isFriend) ...[
        _loadTheirMoments(),
        _loadTheirGroups(),
      ],
    ]);
  }

  Future<void> _loadTheirPosts() async {
    final otherId = widget.person.userId;
    // The mock PV2Data.person (design gallery) carries no userId — there is
    // nobody to fetch for, same guard _loadDuo makes.
    if (otherId == null) return;
    // profile_posts_for_viewer, not fetchUserPosts: the filtering is the
    // server's job. A `community` viewer gets only the shared-community
    // slice back, so the rest never reaches this device at all.
    final items = await FeedService.instance.fetchProfilePostsForViewer(otherId);
    if (!mounted) return;
    setState(
      () => _theirPosts = kMomentsEnabled
          ? items
          : items.where((i) => !i.isMoment).toList(),
    );
  }

  /// How many posts they have, without the posts themselves — so the locked
  /// preview can say "8 posts" to a stranger without shipping any of them.
  Future<void> _loadPostCount() async {
    final otherId = widget.person.userId;
    if (otherId == null) return;
    final n = await FeedService.instance.countUserPosts(otherId);
    if (mounted) setState(() => _theirPostCount = n);
  }

  static const _kMonths = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  /// Same posted+commented-on merge as MyProfileScreen._loadMyMoments, just
  /// keyed to widget.person.userId instead of the caller's own id.
  Future<void> _loadTheirMoments() async {
    final otherId = widget.person.userId;
    if (otherId == null) return;
    final results = await Future.wait([
      FeedService.instance.fetchMomentsFor(userId: otherId),
      FeedService.instance.fetchContributedMoments(userId: otherId),
    ]);
    // Their Moments that I (the viewer) have answered go first.
    final answered = await FeedService.instance.myAnsweredMomentIds();
    if (!mounted) return;
    final posted = results[0];
    final contributed = results[1];
    final postedIds = posted.map((i) => i.postId).toSet();
    final merged =
        [...posted, ...contributed.where((i) => !postedIds.contains(i.postId))];
    FeedService.sortMomentsAnsweredFirst(merged, answered);
    setState(() {
      _theirMoments = [
        for (final i in merged)
          MomentCard(
            color: momentPaletteFor(i.momentColor).colors.last,
            stamp: i.createdAt == null
                ? 'NEW'
                : '${i.createdAt!.day.toString().padLeft(2, '0')} '
                      '${_kMonths[i.createdAt!.month - 1]}',
            kind: postedIds.contains(i.postId) ? 'moment' : 'contributed',
            title: (i.caption ?? '').trim().isEmpty
                ? 'Moment'
                : i.caption!.trim(),
            meta: momentTimeLeft(i.createdAt),
            feedItem: i,
          ),
      ];
    });
  }

  void _openMoment(MomentCard moment) {
    final item = moment.feedItem;
    if (item == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LockedRepliesScreen(
          momentId: item.postId,
          title: (item.caption ?? '').trim().isEmpty
              ? 'Moment'
              : item.caption!.trim(),
          replies: const [],
        ),
      ),
    );
  }

  Future<void> _loadMyCircleIds() async {
    final id = widget.person.userId;
    if (id == null) return;
    try {
      final membership = await CircleService.instance.fetchMyMembership();
      if (mounted) setState(() => _myCircleIds = membership[id] ?? <String>{});
    } catch (_) {
      // No signed-in session (e.g. a debug-harness route with no real
      // login), a network error, etc. — leave the button hidden rather
      // than crash the whole profile screen over a non-critical feature.
    }
  }

  /// "Add to circle": pick which of MY circles this person is in. Silent —
  /// they're never notified. The server refuses anyone who shares no
  /// community with me (circle_member_is_eligible); that's said plainly.
  Future<void> _openCircleSheet() async {
    final id = widget.person.userId;
    if (id == null || _circleActionPending) return;
    HapticFeedback.selectionClick();
    List<CircleOption> circles;
    try {
      circles = await CircleService.instance.fetchMyCircles();
    } catch (_) {
      if (mounted) showGlassToast(context, "Couldn't load your circles.", isError: true);
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CirclePickerSheet(
        personName: widget.person.name,
        circles: circles,
        initial: _myCircleIds ?? const <String>{},
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _circleActionPending = true);
    try {
      await CircleService.instance.setMembership(id, picked);
    } catch (_) {
      if (mounted) {
        showGlassToast(
          context,
          "Couldn't update your circles — you need a shared community with them.",
          isError: true,
        );
      }
    } finally {
      await _loadMyCircleIds();
      if (mounted) setState(() => _circleActionPending = false);
    }
  }

  /// Confirms, then blocks this person — mutual per is_blocked_user(), so
  /// this also hides the viewer's own named content from them. Pops back
  /// since their profile isn't a useful place to stay once blocked (their
  /// content here would otherwise still show — this screen isn't the feed,
  /// it's the one place still fetching their row directly, not through the
  /// RESTRICTIVE policies that filter feeds/comments/reactions).
  Future<void> _confirmAndBlock() async {
    final id = widget.person.userId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF16151A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Block ${widget.person.name}?',
          style: PV2.body(size: 16, weight: FontWeight.w700),
        ),
        content: Text(
          "They won't be able to see your posts or profile, and you won't see theirs.",
          style: PV2.body(size: 13.5, color: PV2.inkBio),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: PV2.body(size: 14, color: PV2.inkStamp),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Block',
              style: PV2.body(
                size: 14,
                weight: FontWeight.w800,
                color: PV2.danger,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await BlockService.instance.block(id);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't block — try again.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person;

    return PV2Page(
      // Taller banner — explicit request with a reference screenshot showing
      // it filling roughly the top half of the screen. Safe to change on its
      // own: PV2Page's own doc notes backdrop height and panel pull-up are
      // tuned as a PAIR, and growing the height while holding the pull-up
      // keeps the identity panel's overlap constant, so nothing below shifts.
      backdropHeight: 390,
      pullUp: 96,
      gradient: PV2.backdrops[_backdrop],
      washX: 0.78,
      washY: 0.08,
      fadeHeight: 150,
      bannerUrl: person.bannerUrl,
      extraBottomInset: widget.extraBottomInset,
      chrome: [
        if (widget.showBackButton)
          Positioned(
            top: 16,
            left: 16,
            child: ChromeButton(
              icon: PV2Icons.back(24, Colors.white),
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        // The backdrop badge is the PAIR's ping streak now, not this
        // person's own score — explicit instruction: "remove the 240
        // showing widget on the banner of other profile visiting and add
        // there mutual ping streak count with fire, along with the two
        // users dp little fused". Their total score still has its own
        // labelled tile further down the page, where it reads as a score
        // instead of as an unexplained number on a photo.
        if (person.pairStreak > 0)
          Positioned(
            top: 16,
            right: 16,
            child: _PairStreakBadge(
              days: person.pairStreak,
              myAvatarUrl: _myAvatarUrl,
              theirAvatarUrl: person.avatarUrl,
            ),
          ),
        Positioned(
          left: 16,
          bottom: 114,
          child: BackdropPicker(
            open: _pickerOpen,
            selected: _backdrop,
            onToggle: () => setState(() => _pickerOpen = !_pickerOpen),
            onPick: (i) => setState(() {
              _backdrop = i;
              _pickerOpen = false;
            }),
          ),
        ),
      ],
      children: [
        IdentityPanel(child: _identity(person)),
        _bento(person),
        const SizedBox(height: 19),
        _duoGroupSection(),
        const SizedBox(height: 19),
        _contentSection(),
      ],
    );
  }

  // --- identity panel -----------------------------------------------------

  Widget _identity(PersonProfile person) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The verified-style checkmark next to the name was purely
                  // decorative (every profile got one, nothing behind it) —
                  // removed by request.
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PV2.display(
                      size: 27,
                      letterSpacing: -0.6,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    // Campus suffix only for a real institutional account
                    // (explicit request: outsiders are allowed in now, so
                    // nobody should see a fabricated "· RVCE").
                    person.campus.isEmpty
                        ? person.handle
                        : '${person.handle} · ${person.campus}',
                    style: PV2.mono(size: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            RingAvatar(
              // This person's own real Anon Score tier progress — see
              // PersonProfile.anonProgress's own doc (explicit request:
              // "wire it to something real"). Was a hardcoded 0.58.
              fillTurns: person.anonProgress,
              fill: PV2.cssLinear(150, const [
                Color(0xFF5A6470),
                Color(0xFF39414C),
              ]),
              imageUrl: person.avatarUrl,
              // The glowing blue dot badge here was also purely decorative
              // (no online/verified status behind it) — removed by request.
            ),
          ],
        ),
        // BLUE 1 — the ping streak between YOU and this person, directly
        // under their DP ("here the blue flame under personal dp"). It's a
        // relationship number, so it belongs next to the person it's with
        // rather than only inside the bento grid further down. Hidden at 0
        // by StreakFlamePill itself.
        if (person.pairStreak > 0) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: StreakFlamePill(count: person.pairStreak, size: 10),
          ),
        ],
        const SizedBox(height: 13),
        Text(
          person.bio,
          style: PV2.body(size: 14.5, color: PV2.inkBio, height: 1.5),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AccentButton(
                label: 'Ping',
                icon: const PingGlyph(
                  size: 15,
                  color: Colors.white,
                  strokeWidth: 2.2,
                ),
                onTap: person.userId == null
                    ? null
                    // One tap = pinged, no prompt (user decision,
                    // 2026-09-30 — only Dip keeps prompts).
                    : () async {
                        try {
                          await PingService.instance.send(
                            receiverId: person.userId!,
                            prompt: '',
                          );
                          if (mounted) {
                            showGlassToast(context, 'Pinged ${person.name} ✓');
                          }
                        } on Object catch (e) {
                          if (!mounted) return;
                          showGlassToast(
                            context,
                            e is PingLimitExceeded || e is PingAlreadyOpen
                                ? e.toString()
                                : "Couldn't send that ping.",
                            isError: true,
                          );
                        }
                      },
              ),
            ),
            const SizedBox(width: 9),
            _circleButton(),
            const SizedBox(width: 9),
            _moreButton(),
          ],
        ),
      ],
    );
  }

  /// Add-to-circle button: dim add-people icon when they're in none of my
  /// circles, accent check when they're in at least one. Either way a tap
  /// opens the circle picker. Holds its size while loading so the header
  /// doesn't jump.
  Widget _circleButton() {
    final ids = _myCircleIds;
    if (ids == null) return const SizedBox(width: 42, height: 42);
    return InsetIconButton(
      icon: ids.isEmpty
          ? PV2Icons.addPeople(17, Colors.white.withValues(alpha: 0.85))
          : Icon(Icons.how_to_reg_rounded, size: 18, color: PV2.accent),
      onTap: _circleActionPending ? null : _openCircleSheet,
    );
  }

  /// The More button and its menu.
  ///
  /// BUG FIX (explicit report — "the three dots is overlapped by other
  /// widgets"): this used to render the dropdown INLINE via a plain
  /// Stack+Positioned, a child of this Column-based header alongside
  /// _bento/_albumSection/_groupsSection/etc. Flutter paints Column
  /// children in order, each in its own layer — a Positioned overflow from
  /// an EARLIER child (this button, extending 48px below its own row) does
  /// NOT automatically paint over a LATER sibling, so the open menu was
  /// getting covered by whatever section rendered next. PV2MenuAnchor
  /// (profile_v2_menus.dart) exists specifically to solve this — it renders
  /// via OverlayPortal, escaping every ancestor's stacking/clipping — and
  /// is already how every OTHER menu on Profile v2 (settings, photo,
  /// per-post options) avoids the same trap; this was the one holdout
  /// still using the old inline approach.
  Widget _moreButton() {
    return PV2MenuAnchor(
      open: _moreOpen,
      onDismiss: () => setState(() => _moreOpen = false),
      targetAnchor: Alignment.bottomRight,
      followerAnchor: Alignment.topRight,
      offset: const Offset(0, 8),
      menu: PV2MenuPanel(
        width: 172,
        children: [
          _menuItem(
            PV2Icons.block(16, Colors.white.withValues(alpha: 0.72)),
            'Block',
            Colors.white.withValues(alpha: 0.85),
            onTap: _confirmAndBlock,
          ),
          _menuItem(
            PV2Icons.report(16, PV2.danger),
            'Report',
            PV2.danger,
          ),
        ],
      ),
      child: InsetIconButton(
        icon: PV2Icons.more(17, Colors.white.withValues(alpha: 0.8)),
        onTap: () => setState(() => _moreOpen = !_moreOpen),
      ),
    );
  }

  Widget _menuItem(
    Widget icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _moreOpen = false);
          onTap?.call();
        },
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 10),
              Text(
                label,
                style: PV2.body(
                  size: 13.5,
                  weight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- bento --------------------------------------------------------------

  /// `grid-template-columns: 1.22fr 1fr` with the streak hero spanning both
  /// rows. Expressed as a Row of two Expanded flex children so the 1.22 : 1
  /// ratio survives any column width.
  Widget _bento(PersonProfile person) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(PV2.gutter, 12, PV2.gutter, 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 122,
              child: StreakHero(
                days: person.pairStreak,
                turns: person.streakTurns,
                withName: person.name,
              ),
            ),
            const SizedBox(width: 9),
            // ONE score tile, not two.
            //
            // This column used to be an ANON SCORE tile stacked on a SCORE
            // tile, which is the old split mechanic: it showed a stranger
            // the anon half of someone's score as its own number. The score
            // is a single combined total now (anon + ping), and the total
            // plus its level is the only form it is shown in anywhere —
            // MyProfileScreen's _combinedScoreCard made the same swap for
            // your own profile. Publishing the anon half on its own is also
            // the one number on this screen that says something about a
            // person's anonymous activity, which this screen must not do.
            Expanded(
              flex: 100,
              child: _CombinedScoreTile(person: person),
            ),
          ],
        ),
      ),
    );
  }

  // --- Duos | Groups --------------------------------------------------

  /// The two-tab switch plus whichever grid is selected — same surface as
  /// MyProfileScreen's own (explicit request, 2026-10-01). Hidden entirely
  /// for the mock/design-gallery person (no real userId to query).
  Widget _duoGroupSection() {
    if (widget.person.userId == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TwoTabSwitch(
          labels: const ['Duos', 'Groups'],
          counts: [_personDuos.length, _groupRows.length],
          selected: _duoGroupTab,
          onSelect: (i) => setState(() => _duoGroupTab = i),
        ),
        const SizedBox(height: 16),
        if (_duoGroupTab == 0) _duoHighlights() else _groupHighlights(),
      ],
    );
  }

  Widget _duoHighlights() {
    if (_duosLoading) return const SizedBox.shrink();
    final otherId = widget.person.userId!;
    if (_personDuos.isEmpty) {
      return HighlightGrid(
        children: [
          HighlightCard(
            title: 'Start a Duo',
            badge: PV2Icons.plus(18, PV2.accent),
            onTap: () => openDuoAlbumBetween(
              context,
              userA: otherId,
              userB: _myUserId ?? otherId,
            ),
          ),
        ],
      );
    }
    return HighlightGrid(
      children: [
        for (final r in _personDuos)
          HighlightCard(
            title: r.partnerName,
            coverUrl: _duoCovers[r.album.id],
            note: r.partnerId != _myUserId
                ? null
                : r.album.status != DuoStatus.pending
                    ? null
                    : r.album.createdBy == _myUserId
                        ? 'invite sent'
                        : 'wants to start a Duo',
            badge: FusedAvatars(
              myUrl: widget.person.avatarUrl,
              otherUrl: r.partnerAvatarUrl,
              otherName: r.partnerName,
              size: 26,
            ),
            // The pairwise streak is only known when I'M the other side —
            // person.pairStreak is specifically "me & this profile".
            // A third party's own streak with them isn't fetched here (no
            // cheap client-safe lookup for an arbitrary pair not involving
            // the viewer) — the card just omits the flame for those.
            streak: r.partnerId == _myUserId ? widget.person.pairStreak : 0,
            onTap: () => openDuoAlbumBetween(
              context,
              userA: otherId,
              userB: r.partnerId,
              streak: r.partnerId == _myUserId ? widget.person.pairStreak : 0,
            ),
          ),
      ],
    );
  }

  Widget _groupHighlights() {
    // A stranger (not in their Friends circle) sees nothing of this at all
    // — fetchGroupsWithCounts already returns [] for them server-side; the
    // locked teaser says there's more without naming any of it.
    if (!_isFriend) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shared with their Friends circle',
              style: PV2.body(size: 12, color: PV2.inkByline),
            ),
            const SizedBox(height: 10),
            const LockedPreview(label: 'Groups', height: 130, tiles: 3),
          ],
        ),
      );
    }
    if (_groupRows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'No shared groups yet',
            style: PV2.body(size: 12.5, color: PV2.inkByline),
          ),
        ),
      );
    }
    return HighlightGrid(
      children: [
        for (final g in _groupRows)
          HighlightCard(
            title: g.name,
            coverUrl: g.id == null ? null : _groupCovers[g.id!] ?? g.iconUrl,
            streak: g.groupStreak,
            fallback: g.gradient,
            badge: MemberFaceStack(avatarUrls: g.memberAvatarUrls.take(3).toList()),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GroupProfileV2Screen(
                  groupId: g.id,
                  backdropIndex: (_backdrop + 1) % PV2.backdrops.length,
                  viaUserId: widget.person.userId,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --- posts / moments ----------------------------------------------------

  /// The communities this viewer and this profile actually share, named.
  /// Derived from the posts that came back rather than a second query —
  /// the server already filtered to exactly those communities, so their
  /// names are the honest answer to "why am I seeing this much".
  String _sharedCommunityLabel() {
    final names = <String>{
      for (final p in _theirPosts)
        if ((p.communityTag ?? '').trim().isNotEmpty) p.communityTag!.trim(),
    }.toList()..sort();

    if (names.isEmpty) return 'Shared communities only';
    if (names.length == 1) return 'Showing ${names.first}';
    if (names.length == 2) return 'Showing ${names[0]} and ${names[1]}';
    return 'Showing ${names.take(2).join(', ')} +${names.length - 2} more';
  }

  /// A quiet one-line explanation under/over the posts area. Deliberately
  /// not an error or a warning — both of these are ordinary states, and
  /// styling them as problems would read as the app being broken.
  Widget _accessNote(String title, String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: PV2.recessed,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: PV2.body(size: 12.5, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: PV2.body(size: 11.5, color: PV2.inkCount),
          ),
        ],
      ),
    );
  }

  Widget _contentSection() {
    final isFriend = _isFriend;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(PV2.pad, 0, PV2.pad, 12),
          child: NeuTabs(
            labels: [
              'Posts · ${_theirPosts.length}',
              if (widget.showMomentsTab && kMomentsEnabled)
                'Moments · ${_theirMoments.length}',
            ],
            selected: _tab,
            onSelect: (i) => setState(() => _tab = i),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PV2.pad),
          child: _tab == 0
              ? (!_accessResolved
                  // Never flash the locked wall at someone who turns out to
                  // have access — hold the shape until the server answers.
                  ? const SizedBox(
                      height: 190,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: PV2.accent,
                          ),
                        ),
                      ),
                    )
                  : _isLocked
                  // The ONLY empty state. A stranger sees that posts EXIST
                  // and how many, never what they are — and the content was
                  // never fetched (see _loadGated), so there is nothing on
                  // the device to peek at.
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LockedPreview(
                          label: _theirPostCount == 1 ? 'post' : 'posts',
                          count: _theirPostCount,
                        ),
                        const SizedBox(height: 12),
                        _accessNote(
                          "Not visible yet",
                          'Only people in their circles, or in a community '
                          'you both belong to, see what they post.',
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The community slice is explained, not silently
                        // truncated — otherwise a filtered profile is
                        // indistinguishable from a quiet one.
                        if (_access == 'community') ...[
                          _accessNote(
                            _sharedCommunityLabel(),
                            'You see posts from the communities you both '
                            'belong to. Their Friends circle sees everything.',
                          ),
                          const SizedBox(height: 12),
                        ],
                        PostsList(
                          items: _theirPosts,
                          displayName: widget.person.name,
                          avatarUrl: widget.person.avatarUrl,
                          // A community viewer's empty slice is not the
                          // same fact as an empty profile — say which.
                          emptyLabel: _access == 'community'
                              ? 'Nothing here from the communities you share.'
                              : 'No posts yet.',
                          // Item #1 — PostsList's defaults are exactly right
                          // here: no reactions viewer (only the author sees
                          // who reacted), Ping/RealMoji kept so you can
                          // still react from someone else's profile.
                        ),
                      ],
                    ))
              // Moments are ordinary visibility='everyone' posts (no RLS
              // gate of their own — see composer_screen.dart's _send), so
              // this is a profile-surface rule, same spirit as the
              // Friends-circle-only groups section.
              : !isFriend
              ? const LockedPreview(label: 'Moments', tiles: 2)
              : _theirMoments.isEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 26),
                  alignment: Alignment.center,
                  child: Text(
                    'No moments yet.',
                    style: PV2.body(
                      size: 12,
                      weight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                )
              : MomentsList(moments: _theirMoments, onTap: _openMoment),
        ),
      ],
    );
  }
}

/// The combined score on someone else's profile: total, their level, and
/// how far through that level they are.
///
/// Deliberately shows no breakdown. A viewer sees what this person's score
/// IS, not what it is made of — the halves decay at different rates and are
/// an implementation detail of the ladder, not something to publish.
class _CombinedScoreTile extends StatelessWidget {
  const _CombinedScoreTile({required this.person});

  final PersonProfile person;

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${person.combinedScore}',
                  style: PV2.display(size: 23, height: 1),
                ),
              ),
              IconWell(
                child: PingGlyph(
                  size: 17,
                  color: Colors.white.withValues(alpha: 0.5),
                  strokeWidth: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('SCORE', style: PV2.caps(size: 9, tracking: 0.11)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: PV2.recessed)),
                  FractionallySizedBox(
                    widthFactor: person.anonProgress,
                    heightFactor: 1,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [PV2.accent, PV2.accentDeep],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            person.tier.name.toUpperCase(),
            style: PV2.caps(
              size: 9,
              tracking: 0.09,
              color: PV2.accentSoft,
              weight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The pair's ping streak on the backdrop: our two profile photos fused,
/// then 🔥 and the day count. Replaces the bare combined-score chip that
/// used to sit here.
///
/// Fire emoji, not the app's blue ice flame — asked for as "fire" in so
/// many words, and an emoji can't be tinted anyway.
class _PairStreakBadge extends StatelessWidget {
  const _PairStreakBadge({
    required this.days,
    required this.myAvatarUrl,
    required this.theirAvatarUrl,
  });

  final int days;
  final String? myAvatarUrl;
  final String? theirAvatarUrl;

  @override
  Widget build(BuildContext context) {
    if (days <= 0) return const SizedBox.shrink();
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 5, right: 12),
      decoration: BoxDecoration(
        color: const Color(0x8C08080A),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Overlapped by 9px — "little fused", not two separate avatars.
          SizedBox(
            width: 24.0 + 15,
            height: 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(left: 15, child: _face(theirAvatarUrl)),
                Positioned(left: 0, child: _face(myAvatarUrl)),
              ],
            ),
          ),
          const SizedBox(width: 7),
          const Text('🔥', style: TextStyle(fontSize: 13, height: 1)),
          const SizedBox(width: 4),
          Text(
            '$days',
            style: PV2.body(size: 13, weight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _face(String? url) => Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF0B0B0E),
        ),
        padding: const EdgeInsets.all(1.5),
        child: ClipOval(
          child: (url == null || url.isEmpty)
              ? const ColoredBox(color: Color(0xFF2A2A31))
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  memCacheWidth: 96,
                  errorWidget: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF2A2A31)),
                ),
        ),
      );
}

/// Which of my circles [personName] is in — multi-select, returns the new
/// set on Save (null on dismiss). Silent: they're never told.
class _CirclePickerSheet extends StatefulWidget {
  const _CirclePickerSheet({
    required this.personName,
    required this.circles,
    required this.initial,
  });

  final String personName;
  final List<CircleOption> circles;
  final Set<String> initial;

  @override
  State<_CirclePickerSheet> createState() => _CirclePickerSheetState();
}

class _CirclePickerSheetState extends State<_CirclePickerSheet> {
  late final Set<String> _selected = {...widget.initial};

  void _toggle(CircleOption c) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.remove(c.id)) return;
      _selected.add(c.id);
      // Mirrors the server trigger: Close Friends are always Friends too.
      if (c.kind == CircleKind.closeFriends) {
        for (final f in widget.circles) {
          if (f.isFriends) _selected.add(f.id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: GlassSurface(
          radius: 20,
          fill: const Color(0xF0141416),
          border: const Color(0x14FFFFFF),
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add ${widget.personName} to…',
                style: PV2.body(size: 14, weight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                "Only you can see your circles. They won't be notified.",
                style: PV2.body(size: 12, color: PV2.inkBio),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in widget.circles)
                      CheckboxListTile(
                        value: _selected.contains(c.id),
                        onChanged: (_) => _toggle(c),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        activeColor: PV2.accent,
                        controlAffinity: ListTileControlAffinity.trailing,
                        title: Text(
                          c.name,
                          style: PV2.body(size: 13.5, weight: FontWeight.w600),
                        ),
                        subtitle: c.isFriends
                            ? Text(
                                'Sees your friends posts, Moments and groups',
                                style: PV2.body(size: 11.5, color: PV2.inkSub),
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: AccentButton(
                  label: 'Save',
                  onTap: () => Navigator.of(context).pop(_selected),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
