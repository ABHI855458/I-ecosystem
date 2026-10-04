import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_config.dart';
import '../auth/reset_password_screen.dart';
import '../../services/circle_service.dart';
import '../../services/current_user_service.dart';
import '../../services/people_service.dart';
import '../../services/group_service.dart';
import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';
import '../../services/ping_service.dart';
import '../../services/us_album_service.dart';
import '../../core/glass.dart' show showGlassToast;
import '../settings/blocked_users_screen.dart';
import '../settings/delete_account_screen.dart';
import '../settings/edit_profile_screen.dart';
import '../settings/legal_screen.dart';
import 'group_profile_v2_screen.dart';
import 'manage_circles_screen.dart';
import 'requests_section.dart';
import 'profile_v2_create_flows.dart';
import 'profile_v2_data.dart';
import 'profile_v2_icons.dart';
import '../qr/my_qr_sheet.dart';
import '../qr/qr_payload.dart';
import 'profile_v2_menus.dart';
import 'profile_v2_sections.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';
import 'duo_highlights.dart';
import 'viewed_by_section.dart' show ViewedByBannerButton;

/// The signed-in user's own profile.
///
/// This is the only one of the three screens that may show anonymous content,
/// and it does so behind a dedicated tab that carries an explicit "only you can
/// see this" notice. The same anon identity (name + mask) is surfaced in two
/// places by design: a summary card high on the page, and a full editor inside
/// the Anon tab — the person needs to know their alias without opening the tab,
/// and needs to be able to change it once they're in there.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({
    super.key,
    this.me,
    this.isDesignPreview = false,
    this.backdropIndex = 0,
    this.extraBottomInset = 0,
  });

  /// Mock profile data — ONLY for [ProfileV2Gallery]'s design-preview
  /// harness, which passes this (plus [isDesignPreview]) explicitly. Every
  /// real product call site leaves this null and waits for [_loadMe] to load
  /// the signed-in user's actual row; it must never fall back to demo data.
  /// (This used to default to `PV2Data.me`, which is how the "theo_b" demo
  /// profile could surface on the real profile page — see that bug fix.)
  final SelfProfile? me;

  /// True only from [ProfileV2Gallery]. Some sections are ok showing mocked
  /// content there but must never show it for a real signed-in user.
  final bool isDesignPreview;
  final int backdropIndex;

  /// Space to reserve below the content for chrome the host floats over the
  /// page — the app shell's nav pill, for instance.
  final double extraBottomInset;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

/// Which dropdown is currently open. Exactly one may be, which is why this is
/// a single enum rather than a set of booleans: the design closes every other
/// menu whenever one opens.
enum _Menu { none, settings, photo }

/// True while [showDuoPartnerPicker] is loading or showing.
///
/// The picker fetches people and Duo states BEFORE it opens anything, so a
/// second tap during that gap used to start a second fetch and open a second
/// sheet on top of the first — "start duo button clicked opens several
/// times" (reported 2026-10-04). One picker at a time; extra taps are
/// ignored until it closes.
bool _duoPickerBusy = false;

/// The "start a Duo" people picker — shared by the profile and the feed
/// header's "+" (via [openCreateChooser]).
Future<void> showDuoPartnerPicker(BuildContext context) async {
  if (_duoPickerBusy) return;
  _duoPickerBusy = true;
  try {
    await _showDuoPartnerPicker(context);
  } finally {
    _duoPickerBusy = false;
  }
}

Future<void> _showDuoPartnerPicker(BuildContext context) async {
  List<(String, String, String?)> people;
  try {
    final results = await Future.wait([
      CircleService.instance.fetchPeopleInMyCircles(),
      PeopleService.instance.communityMembers(),
    ]);
    final seen = <String>{};
    people = [
      for (final u in [...results[0], ...results[1]])
        if (seen.add(u['id'] as String))
          (
            u['id'] as String,
            (u['name'] as String?) ?? 'someone',
            u['profile_photo_url'] as String?,
          ),
    ];
  } catch (_) {
    people = const [];
  }
  if (!context.mounted) return;
  if (people.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Join a community first, then start a Duo with someone there.',
        ),
      ),
    );
    return;
  }
  // Where I already stand with each person, so the sheet shows Invite /
  // Invited / Accept / In Duo instead of offering to re-invite.
  final states = <String, _DuoInviteState>{};
  try {
    final myId = await CurrentUserService.instance.resolveId();
    for (final s in await DuoService.instance.fetchMyAlbums()) {
      states[s.otherUserId] = s.album.status == DuoStatus.accepted
          ? _DuoInviteState.inDuo
          : s.album.createdBy == myId
          ? _DuoInviteState.invited
          : _DuoInviteState.theyInvited;
    }
  } catch (_) {
    // Unknown statuses just show "Invite"; sendOrAccept is idempotent.
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) =>
        _DuoPartnerPickerSheet(people: people, states: states),
  );
}

/// Blocks a second call while one push is still in flight — see
/// [openCreateChooser]'s own doc for the bug this guards against.
bool _creatingChooser = false;

/// The "+" create chooser (Duo / Group post) from anywhere — the Friends
/// feed header opens it (explicit request, 2026-10-01: the "+" moved
/// there from the profile banner).
///
/// Pushes IMMEDIATELY, synchronously — no network round trip first. This
/// used to `await` fetching Duos + the avatar BEFORE ever pushing the
/// route, so the whole screen sat behind that round trip ("clicking plus
/// isn't opening fast") — and because nothing was pushed yet, a second
/// tap during that wait ran its own independent fetch-then-push, landing
/// a SECOND chooser on top of the first once it resolved ("clicking
/// multiple times opens it multiple times"). CreateChooserScreen now
/// fetches its own Duo data lazily once it's already on screen (see its
/// own doc) — the first screen it shows (Group / Duo / Anon) needs
/// neither. [_creatingChooser] is the remaining, narrower guard: a
/// genuine double-tap landing inside the push's own ~300ms transition,
/// before Navigator has anything on top to swallow the second tap.
Future<void> openCreateChooser(BuildContext context) async {
  if (_creatingChooser) return;
  _creatingChooser = true;
  try {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CreateChooserScreen(
          onStartNewDuo: () => showDuoPartnerPicker(context),
        ),
      ),
    );
  } finally {
    _creatingChooser = false;
  }
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  _Menu _menu = _Menu.none;

  /// 0 = Duos, 1 = Groups.
  int _tab = 0;

  /// Id of the post whose options menu is open, or null. Separate from
  /// [_menu] only because it is per-item; opening one still closes the rest.
  String? _postMenu;

  // Duos — real data (DuoService).
  List<MyDuoSummary> _myAlbums = const [];

  /// Pairwise ping streak per partner `users.id`, for each Duo card's flame.
  Map<String, int> _pairStreaks = const {};
  bool _myAlbumsLoading = true;
  String? _myUserId;

  List<MyGroupRow> _realGroups = const [];

  // Real name/bio (users.name / users.bio).
  SelfProfile? _liveMe;

  /// The real loaded user, else the design-preview mock only if the caller
  /// opted into it via [MyProfileScreen.me], else null (still loading).
  SelfProfile? get _me => _liveMe ?? widget.me;

  bool _bannerUploading = false;
  bool _avatarUploading = false;

  @override
  void initState() {
    super.initState();
    _loadMyAlbums();
    _loadMyGroups();
    _loadCircles();
    _loadMe();
  }

  /// Pull-to-refresh: re-runs every loader in parallel.
  Future<void> _refreshAll() async {
    await Future.wait([
      _loadMe(),
      _loadMyGroups(),
      _loadMyAlbums(),
      _loadCircles(),
    ]);
  }

  Future<void> _loadMe() async {
    try {
      final id = await CurrentUserService.instance.resolveId();
      final row = await supabase
          .from('users')
          .select(
            'name, username, bio, profile_photo_url, banner_url, '
            'anon_name, anon_name_2, active_anon_slot, '
            'glow_score, ping_score, campus',
          )
          .eq('id', id)
          .single();
      if (!mounted) return;
      final name = (row['name'] as String?)?.trim();
      if (name == null || name.isEmpty) return;
      final username = (row['username'] as String?)?.trim();
      final anonName1 = (row['anon_name'] as String?)?.trim();
      // Filler for the few fields with no real backing column at all
      // (campus/bestRank/bestRankIn — see the comment below). This is NOT
      // the theo_b bug: `name` above is already confirmed real and non-empty
      // by this point, so these placeholders only ride along next to a real
      // identity, never stand in for one.
      final base = widget.me ?? PV2Data.me;

      // communityCount has a real backing table (community_members, keyed
      // on the raw auth uid — see CommunityService's own KEYSPACE FIX
      // note), unlike bestRank/bestRankIn/campus below.
      var communityCount = base.communityCount;
      final authId = supabase.auth.currentUser?.id;
      if (authId != null) {
        try {
          final memberRows = await supabase
              .from('community_members')
              .select('community_id')
              .eq('user_id', authId);
          communityCount = (memberRows as List).length;
        } catch (e, st) {
          debugPrint(
            '[MyProfileScreen._loadMe] community count failed: $e\n$st',
          );
        }
      }

      // Second mounted check — the community-count fetch above is another
      // await after the first one (line 255), and this screen genuinely
      // got disposed in that gap during testing (rapid sign-out/sign-in),
      // hitting "setState() called after dispose()".
      if (!mounted) return;
      setState(() {
        _liveMe = SelfProfile(
          name: name,
          // Real username when one exists (post-Phase-3 accounts); rows
          // from before the username column existed fall back to the same
          // handleize scheme ProfileLookupService._handleize uses.
          handle: username != null && username.isNotEmpty
              ? '@$username'
              : '@${name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_')}',
          // Real now (20261001020000_derive_campus_from_email.sql) — derived
          // server-side from the account's own email domain, null for any
          // non-institutional signup. Empty string, not base.campus's old
          // 'RVCE' mock fallback: an outsider account must show nothing,
          // not a fabricated campus. bestRank/bestRankIn still have no real
          // backing column, so those stay on the mock.
          campus: (row['campus'] as String?) ?? '',
          bio: (row['bio'] as String?)?.trim().isNotEmpty == true
              ? (row['bio'] as String).trim()
              : base.bio,
          anonScore: (row['glow_score'] as int?) ?? base.anonScore,
          pingScore: (row['ping_score'] as int?) ?? base.pingScore,
          bestRank: base.bestRank,
          bestRankIn: base.bestRankIn,
          communityCount: communityCount,
          // Real anon identity — this used to always read base.anonName
          // (the PV2Data.me mock, 'quiet_moth_04'), so the profile never
          // showed a real user's actual anon name. anon_name is NOT NULL
          // live, but guard with base.anonName1 anyway rather than crash if
          // an old row somehow lacks it.
          anonName1: anonName1 != null && anonName1.isNotEmpty
              ? anonName1
              : base.anonName1,
          anonName2: (row['anon_name_2'] as String?)?.trim().isNotEmpty == true
              ? (row['anon_name_2'] as String).trim()
              : null,
          activeAnonSlot: (row['active_anon_slot'] as int?) ?? 1,
          avatarUrl: row['profile_photo_url'] as String?,
          bannerUrl: row['banner_url'] as String?,
        );
      });
    } catch (e, st) {
      debugPrint('[MyProfileScreen._loadMe] failed: $e\n$st');
    }
  }

  /// Picker → StorageService.uploadUserBanner → users.banner_url. Mirrors
  /// _pickGroupBanner in group_profile_v2_screen.dart — same shape, just a
  /// direct table write instead of GroupService.updateGroupInfo since
  /// there's no per-user equivalent of that helper.
  Future<void> _pickUserBanner() async {
    if (_bannerUploading) return;
    final xFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 88,
    );
    if (xFile == null || !mounted) return;
    setState(() => _bannerUploading = true);
    try {
      final id = await CurrentUserService.instance.resolveId();
      final url = await StorageService.uploadUserBanner(
        file: File(xFile.path),
        userId: id,
      );
      await _saveProfileImageUrl(column: 'banner_url', url: url, id: id);
      await _loadMe();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Banner updated.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't update the banner: $e")));
    } finally {
      if (mounted) setState(() => _bannerUploading = false);
    }
  }

  /// Writes an uploaded image URL onto my own `users` row, and PROVES it
  /// landed.
  ///
  /// `.select()` is the whole point. A bare `.update()` that RLS refuses
  /// returns zero rows and NO error on this project — the long-standing
  /// failure mode here — so the old code could upload the photo, write
  /// nothing, and still show a success. That is exactly the shape of "I am
  /// unable to upload the banner and DP, let it save and other people see
  /// it": the file was in the bucket, the row still pointed at the old URL,
  /// and every other surface reads the row.
  ///
  /// The policy that has to pass is `users_update_own`
  /// (`auth.uid() = auth_id`), so a refusal here means the session is stale
  /// rather than that the row is missing.
  Future<void> _saveProfileImageUrl({
    required String column,
    required String url,
    required String id,
  }) async {
    final rows = await supabase
        .from('users')
        .update({column: url})
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('the change was rejected — try signing in again');
    }
  }

  /// Circles preview for this screen's own section — see [_circlesSection].
  /// Null while loading; the section renders nothing (not an empty state)
  /// until this actually resolves, same convention [_myAlbums] follows.

  /// Circles preview for this screen's own section — see [_circlesSection].
  /// Null while loading; the section renders nothing (not an empty state)
  /// until this actually resolves, same convention [_myAlbums] follows.
  List<CircleOption>? _circles;

  Future<void> _loadCircles() async {
    try {
      final circles = await CircleService.instance.fetchMyCircles();
      if (mounted) setState(() => _circles = circles);
    } catch (_) {
      // No session or a failed read — the section just stays hidden.
    }
  }

  /// Real groups ONLY. The mock PV2Data.myGroups rows ("Design Preview",
  /// 1 member each) used to be appended after the real ones under a
  /// "never show an empty section" convention — explicit report ("remove
  /// the demo groups"): a profile that lists groups the person isn't in is
  /// worse than a profile that honestly lists none, and the fabricated
  /// rows were indistinguishable from real ones at a glance.
  List<MyGroupRow> get _groupRows => _realGroups;

  /// Enriches each of the caller's real groups with a real member count and
  /// post count (fetchMyGroups' own row has neither — it's a plain `groups`
  /// select). `dips`/`last` stay 0/blank: no dip table backs a real group
  /// yet, and inventing "X dipped Nh ago" text for one would be exactly the
  /// kind of fabricated activity PV2Data.myGroups's mock rows use, which is
  /// fine for a mock row and not for a real one.
  Future<void> _loadMyGroups() async {
    try {
      final myId = await CurrentUserService.instance.resolveId();
      final rows = await GroupService.instance.fetchGroupsWithCounts(myId);
      final groupIds = [for (final row in rows) row['id'] as String];
      // BUG FIX — the preview circles on each row used to be
      // kFaceSwatches.take(3), a fixed decorative palette with no relation
      // to who is actually in the group ("the circles shall show the real
      // DPs of both the members"). One batched fetch for every group on
      // the page, not one per row.
      // Decoration only — a slow/failed avatar or streak lookup must not
      // take the whole groups list down with it (see the catch below).
      // Avatars, streaks and covers in parallel (they used to be three
      // sequential round trips).
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
      // BLUE 2 + BLUE 3 for the group ROW — the group's shared streak and
      // each pictured member's own, so both are visible without opening
      // the group ("on group [show] the overall group streak... and as well
      // under each person's dp").
      final streaks = await streaksFuture;
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
            gradient:
                kGroupGradients[(row['name'] as String? ?? 'Group').hashCode
                        .abs() %
                    kGroupGradients.length],
            memberAvatarUrls: avatars[row['id'] as String] ?? const [],
            memberStreaks: [
              for (final uid
                  in GroupService.instance.memberIdsByGroup[row['id']
                          as String] ??
                      const <String>[])
                streaks[row['id'] as String]?.members[uid] ?? 0,
            ],
            groupStreak: streaks[row['id'] as String]?.shared ?? 0,
            iconUrl: row['icon_url'] as String?,
          ),
      ];
      // Most active groups first (explicit request): the group's shared
      // ping streak, then how many posts it has, then members. Was newest-
      // created first, so a busy group sank below a new empty one.
      enriched.sort((a, b) {
        final st = b.groupStreak.compareTo(a.groupStreak);
        if (st != 0) return st;
        final posts = b.memories.compareTo(a.memories);
        if (posts != 0) return posts;
        return b.members.compareTo(a.members);
      });
      if (!mounted) return;
      setState(() => _realGroups = enriched);
      final covers = await coversFuture;
      if (mounted) setState(() => _groupCovers = covers);
    } catch (_) {
      // KEEP whatever was already on screen. This used to set the list to
      // EMPTY on any failure — so one slow refresh (e.g. while a post was
      // uploading) made every group vanish from the profile ("by posting
      // too much the groups started disappearing"). A failed refresh now
      // just leaves the last good list in place.
    }
  }

  Future<void> _loadMyAlbums() async {
    try {
      final myId = await CurrentUserService.instance.resolveId();
      // BLUE 1 — the pairwise ping streak with each album partner, fetched
      // alongside the albums themselves so the header can render its flame
      // in the same frame the album appears in rather than popping in
      // after. Derived server-side (my_ping_streaks / ping_streak_with),
      // never stored — see STREAK SYSTEM v4's own note on why this one
      // needed no new table. Fails soft to an empty map: no streak data
      // means no flame, not a broken album list.
      final results = await Future.wait([
        DuoService.instance.fetchMyAlbums(),
        PingService.instance.fetchStreaks().catchError((_) => <String, int>{}),
      ]);
      final streaks = results[1] as Map<String, int>;
      // Duos that have photos first (explicit request, 2026-10-01 — a QR
      // scan creates an empty Duo, which goes after them), then accepted
      // before pending, the longest ping streak, the most photos.
      final albums = [...results[0] as List<MyDuoSummary>]
        ..sort((a, b) {
          final hasA = a.privateCount + a.mutualCount > 0 ? 1 : 0;
          final hasB = b.privateCount + b.mutualCount > 0 ? 1 : 0;
          if (hasA != hasB) return hasB.compareTo(hasA);
          final acc = (b.album.status == DuoStatus.accepted ? 1 : 0).compareTo(
            a.album.status == DuoStatus.accepted ? 1 : 0,
          );
          if (acc != 0) return acc;
          final st = (streaks[b.otherUserId] ?? 0).compareTo(
            streaks[a.otherUserId] ?? 0,
          );
          if (st != 0) return st;
          return (b.privateCount + b.mutualCount).compareTo(
            a.privateCount + a.mutualCount,
          );
        });
      if (mounted) {
        setState(() {
          _myUserId = myId;
          _myAlbums = albums;
          _pairStreaks = streaks;
          _myAlbumsLoading = false;
        });
      }
      unawaited(_loadDuoCovers(albums));
    } catch (_) {
      if (mounted) setState(() => _myAlbumsLoading = false);
    }
  }

  /// albumId -> signed URL of its newest photo (the card cover).
  Map<String, String> _duoCovers = const {};

  /// groupId -> newest post photo (the card cover).
  Map<String, String> _groupCovers = const {};

  Future<void> _loadDuoCovers(List<MyDuoSummary> albums) async {
    try {
      final paths = await DuoService.instance.fetchLatestPhotoPaths([
        for (final a in albums) a.album.id,
      ]);
      final entries = await Future.wait([
        for (final e in paths.entries)
          StorageService.signedDuoPhotoUrl(
            e.value,
          ).then((u) => MapEntry(e.key, u)),
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

  Future<void> _openDuo(MyDuoSummary summary) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DuoAlbumScreen.mine(
          summary: summary,
          myUserId: _myUserId,
          myAvatarUrl: _me?.avatarUrl,
          myName: _me?.handle ?? 'You',
          streak: _pairStreaks[summary.otherUserId] ?? 0,
        ),
      ),
    );
    if (!mounted) return;
    await _loadMyAlbums();
    if (changed == true) await _loadMyGroups();
  }

  /// Duo invites answered in this session, applied on screen the instant
  /// Accept/Decline is tapped (see [_respondToPendingAlbum]).
  final Set<String> _locallyAccepted = {};

  /// A pending album counts as accepted once I've tapped Accept on it here.
  bool _isPending(MyDuoSummary s) =>
      s.album.status == DuoStatus.pending &&
      !_locallyAccepted.contains(s.album.id);

  /// Duo partner picker: people in my circles first, then the rest of my
  /// communities. No friendship needed — starting a Duo sends a request the
  /// other person accepts or declines.
  Future<void> _openAddPeoplePicker() async {
    await showDuoPartnerPicker(context);
    // Invites sent or accepted in the sheet show up in "My Duos".
    if (mounted) await _loadMyAlbums();
  }

  void _closeMenus() {
    if (_menu == _Menu.none && _postMenu == null) return;
    setState(() {
      _menu = _Menu.none;
      _postMenu = null;
    });
  }

  void _toggleMenu(_Menu menu) {
    setState(() {
      _menu = _menu == menu ? _Menu.none : menu;
      _postMenu = null;
    });
  }

  /// Closes any open menu, then runs [action] on the next frame. Menus dismiss
  /// before navigating so the panel is not left hanging in the overlay during
  /// the route transition.
  void _pick(VoidCallback action) {
    _closeMenus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    // A moment posted from the FAB has to appear here without a manual
    // refresh — AddMomentScreen just pops on success. Same for a group made
    // from the Groups section's CreateGroupScreen: without this the new
    // group only showed up after a pull-to-refresh or restart.
    if (mounted) await Future.wait([_loadMyGroups(), _loadCircles()]);
  }

  /// Same as [_push], plus a [_loadMe] refresh on return — for EditProfileScreen,
  /// so a saved name/bio shows up on this page without a manual restart.
  Future<void> _pushAndReloadMe(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _loadMe();
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    if (me == null) {
      // Real user hasn't loaded yet and this isn't the design-preview
      // gallery — show a loading state, never the theo_b mock (see
      // MyProfileScreen.me's doc).
      return Scaffold(
        backgroundColor: PV2.page,
        body: Center(child: CircularProgressIndicator(color: PV2.accent)),
      );
    }

    return PV2Page(
      // Taller banner — explicit request with a reference screenshot showing
      // it filling roughly the top half of the screen. Safe to change on its
      // own: PV2Page's own doc notes backdrop height and panel pull-up are
      // tuned as a PAIR, and growing the height while holding the pull-up
      // keeps the identity panel's overlap constant, so nothing below shifts.
      backdropHeight: 390,
      pullUp: 96,
      gradient: PV2.backdrops[widget.backdropIndex % PV2.backdrops.length],
      washX: 0.78,
      washY: 0.08,
      fadeHeight: 150,
      bannerUrl: me.bannerUrl,
      extraBottomInset: widget.extraBottomInset,
      onScroll: _closeMenus,
      onRefresh: _refreshAll,
      chrome: [
        // No "+" on the banner any more — it moved to the Friends feed's
        // top-left (explicit request, 2026-10-01; see openCreateChooser).
        // Viewed-by eye, on the banner.
        const Positioned(top: 16, right: 112, child: ViewedByBannerButton()),
        // Notifications — swapped in for the old "Viewed by" eye button
        // (explicit request: eye moved to the feed page's own header, see
        // home_screen.dart, and notifications moved here in its place).
        // Same banner-chrome placement Viewed-by used, right next to
        // Friends. BUG FIX: this used to reuse home_screen.dart's own
        // _HeaderBellButton (a solid dark circle with a border — designed
        // for that screen's borderless dark chrome) verbatim in its new
        // spot. Next to this banner's actual glass ChromeButton siblings
        // (Friends, Settings) it read wrong — different size (36 vs the
        // ChromeButton family's 40), different fill (solid vs frosted
        // glass), and its icon color (AppColors.textPrimary, an off-white
        // reused from the feed's own dark palette) read dim rather than a
        // clean white — reported live as "have a white thing like
        // notification, the notification thing is cutoff." Rebuilt here
        // as a proper NotificationsBannerButton using the SAME
        // ChromeButton + badge pattern ViewedByBannerButton already uses, so it matches its neighbors
        // exactly instead of carrying over a different screen's look.
        // Notifications and Circles buttons removed from the banner
        // (explicit request); Circles stays reachable from the Circles
        // section below. Requests takes the first slot.
        // Left edge of the banner (explicit request).
        const Positioned(top: 16, left: 16, child: RequestsBannerButton()),
        // QR — promoted out of the Settings menu onto the banner itself
        // (explicit ask: "let the QR be on the banner"), same move Circles
        // already got. Mirrors Settings' own right-edge rhythm one slot in.
        Positioned(
          top: 16,
          right: 64,
          child: ChromeButton(
            icon: const Icon(
              Icons.qr_code_2_rounded,
              size: 18,
              color: Colors.white,
            ),
            onTap: () async {
              final myId = _myUserId;
              if (myId == null) return;
              final code = await fetchMyDuoCode();
              if (!context.mounted) return;
              if (code == null) {
                showGlassToast(
                  context,
                  "Couldn't load your QR — check your connection.",
                  isError: true,
                );
                return;
              }
              showMyQrSheet(
                context,
                payload: QrPayload(
                  kind: QrPayloadKind.duo,
                  id: myId,
                  code: code,
                ),
                title: 'Your Duo QR',
                subtitle:
                    'Whoever scans this instantly connects with you in Duo.',
              );
            },
          ),
        ),
        // The self view opens settings where the other-person view goes back —
        // there is nowhere to go back to from your own profile.
        Positioned(
          top: 16,
          right: 16,
          child: PV2MenuAnchor(
            open: _menu == _Menu.settings,
            onDismiss: _closeMenus,
            menu: _settingsMenu(),
            child: ChromeButton(
              icon: PV2Icons.settings(18, Colors.white),
              onTap: () => _toggleMenu(_Menu.settings),
            ),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 114,
          child: GlassSurface(
            radius: 17,
            height: 34,
            fill: const Color(0x8008080A),
            border: const Color(0x1FFFFFFF),
            padding: const EdgeInsets.only(left: 10, right: 13),
            onTap: _pickUserBanner,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_bannerUploading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  PV2Icons.camera(14, Colors.white),
                const SizedBox(width: 7),
                Text(
                  'Banner',
                  style: PV2.body(size: 11.5, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        // The profile-BANNER "Seen" pill (all-your-posts-combined) is
        // removed — explicit follow-up. Per-post Seen (DesignSoloCard's own
        // viewerSeen pill, on each individual post card here and on
        // someone else's profile) is unaffected and stays exactly as-is —
        // this only removes the one summary pill that used to sit on the
        // banner itself.
      ],
      children: [
        IdentityPanel(child: _identity(me)),
        // Explicit request: the "BEST COMMUNITY STANDING" rank card that
        // used to sit here is gone from the profile entirely. Standing now
        // lives only on the Community Board's Streaks tab, alongside the
        // rest of the ranking surfaces (see community_streaks_tab.dart's
        // STANDINGS section), rather than being duplicated here in a
        // second, less complete form.
        //
        // The whole chain behind it went with it — _scores()/_rankCard()
        // (that card was the last thing _scores still rendered; the score
        // card had already been removed from it earlier), the _standing
        // field, and _loadStanding(). CommunityService.
        // fetchBestCommunityStanding() is now unreferenced app-wide and
        // can be deleted whenever that file is next touched.
        // Two sections only (explicit request, 2026-10-01): Duos and Groups
        // as highlight cards. No anon identity, circles or post feed here.
        const SizedBox(height: 19),
        // Circles sit between the name card and Duos | Groups (explicit
        // request, 2026-10-01).
        _circlesSection(),
        const SizedBox(height: 19),
        _tabs(),
        const SizedBox(height: 16),
        if (_tab == 0) _duoHighlights() else _groupHighlights(),
      ],
    );
  }

  // --- menus --------------------------------------------------------------

  Widget _settingsMenu() {
    return PV2MenuPanel(
      width: 210,
      radius: 18,
      padding: 6,
      blur: 24,
      shadow: const BoxShadow(
        color: Color(0xE6000000),
        offset: Offset(0, 18),
        blurRadius: 42,
        spreadRadius: -14,
      ),
      children: [
        const PV2MenuLabel(label: 'Account'),
        PV2MenuItem(
          icon: Icons.edit_outlined,
          label: 'Edit Profile',
          onTap: () => _pick(() => _pushAndReloadMe(const EditProfileScreen())),
        ),
        PV2MenuItem(
          icon: Icons.donut_large_rounded,
          label: 'Circles',
          onTap: () => _pick(() => _push(const ManageCirclesScreen())),
        ),
        PV2MenuItem(
          icon: Icons.block_rounded,
          label: 'Blocked Users',
          onTap: () => _pick(() => _push(const BlockedUsersScreen())),
        ),
        // Circles now lives as its own banner-chrome button (top-left,
        // next to Notifications) — see the ChromeButton at this
        // screen's own build() for why it was moved out of here. My QR Code
        // moved the same way (top-right, next to Settings) — instant Duo
        // joining, scanning it either completes a Duo someone else already
        // invited me to, or starts a new pending one — see
        // scan_result_handler.dart. A group's own QR lives on its own
        // profile screen instead, since that's a group identity, not a
        // personal one.
        // "Scan QR Code" removed from this menu: scanning lives in the task
        // bar camera only (explicit request, 2026-10-03). Showing YOUR
        // code (the banner's QR button) is unchanged.
        PV2MenuItem(
          icon: Icons.lock_reset_rounded,
          label: 'Reset Password',
          // Reuses the same screen the forgot-password flow's last step
          // already uses (ResetPasswordScreen.updateUser) — it works on
          // any live session, recovery or already-signed-in, so there was
          // no real flow to build, just an entry point missing from
          // Settings.
          onTap: () => _pick(
            () => _push(
              ResetPasswordScreen(
                email: supabase.auth.currentUser?.email ?? '',
              ),
            ),
          ),
        ),
        PV2MenuItem(
          icon: Icons.shield_outlined,
          label: 'Privacy Policy',
          onTap: () => _pick(() => _push(LegalScreen.privacyPolicy())),
        ),
        PV2MenuItem(
          icon: Icons.description_outlined,
          label: 'EULA',
          onTap: () => _pick(() => _push(LegalScreen.eula())),
        ),
        const PV2MenuDivider(),
        PV2MenuItem(
          icon: Icons.logout_rounded,
          label: 'Log Out',
          onTap: () => _pick(_confirmAndLogOut),
        ),
        PV2MenuItem(
          icon: Icons.delete_outline_rounded,
          label: 'Delete Account',
          destructive: true,
          onTap: () => _pick(() => _push(const DeleteAccountScreen())),
        ),
      ],
    );
  }

  /// There was previously no way to sign out anywhere in the live app —
  /// the only signOut() call site was profile/profile_screen.dart, which
  /// MainShell doesn't mount (see that file's own "legacy" note). AuthGate
  /// already listens for the signedOut auth event and swaps itself to
  /// AuthScreen the moment it fires (auth_gate.dart's onAuthStateChange) —
  /// this just needs to actually fire that event, via the app's one
  /// designated logout entry point (SupabaseService.signOutAndResetCaches,
  /// which also clears every per-session cache, not just the auth token).
  Future<void> _confirmAndLogOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF16151A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Log out?',
          style: PV2.body(size: 16, weight: FontWeight.w700),
        ),
        content: Text(
          "You'll need to log back in with your email and password.",
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
              'Log Out',
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
    if (confirmed != true) return;
    await SupabaseService.signOutAndResetCaches();
  }

  Widget _photoMenu() {
    return PV2MenuPanel(
      width: 174,
      children: [
        PV2MenuItem(
          icon: Icons.photo_camera_outlined,
          label: _avatarUploading ? 'Uploading…' : 'Upload New Photo',
          iconSize: 15,
          fontSize: 13,
          gap: 9,
          radius: 11,
          labelColor: Colors.white.withValues(alpha: 0.88),
          onTap: () {
            _closeMenus();
            _pickAvatar();
          },
        ),
        PV2MenuItem(
          icon: Icons.block_rounded,
          label: 'Remove Photo',
          iconSize: 15,
          fontSize: 13,
          gap: 9,
          radius: 11,
          destructive: true,
          onTap: () {
            _closeMenus();
            _removeAvatar();
          },
        ),
      ],
    );
  }

  /// Picker -> StorageService.uploadAvatar -> users.profile_photo_url.
  /// Same shape as [_pickUserBanner] right above; both menu items used to
  /// be dead stubs that only closed the menu, so there was no way to set a
  /// profile photo at all from this screen.
  ///
  /// The write goes to the same `profile_photo_url` column every other
  /// surface already reads (FeedService._attachAuthors, the friends list,
  /// group cards), so the new photo shows up for other people everywhere
  /// without any further wiring.
  Future<void> _pickAvatar() async {
    if (_avatarUploading) return;
    final xFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Avatars render at at most ~120px; anything larger is wasted bytes
      // on every feed row that loads it.
      maxWidth: 720,
      imageQuality: 88,
    );
    if (xFile == null || !mounted) return;
    setState(() => _avatarUploading = true);
    try {
      final id = await CurrentUserService.instance.resolveId();
      final url = await StorageService.uploadAvatar(
        file: File(xFile.path),
        userId: id,
      );
      await _saveProfileImageUrl(column: 'profile_photo_url', url: url, id: id);
      await _loadMe();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't update your photo: $e")));
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (_avatarUploading) return;
    setState(() => _avatarUploading = true);
    try {
      final id = await CurrentUserService.instance.resolveId();
      // .select() for the same reason as _saveProfileImageUrl — a refused
      // clear would otherwise look exactly like a successful one.
      final rows = await supabase
          .from('users')
          .update({'profile_photo_url': null})
          .eq('id', id)
          .select('id');
      if (rows.isEmpty) {
        throw StateError('the change was rejected — try signing in again');
      }
      await _loadMe();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't remove your photo: $e")));
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  Widget _identity(SelfProfile me) {
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
                  Text(
                    me.name,
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
                    me.campus.isEmpty
                        ? me.handle
                        : '${me.handle} · ${me.campus}',
                    style: PV2.mono(size: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            RingAvatar(
              // Real Anon Score tier progress — explicit request ("wire it
              // to something real"). Was a hardcoded 0.72 that never
              // represented anything; now the same value the anon-score
              // card's own tier badge is computed from (me.anonProgress).
              fillTurns: me.anonProgress,
              fill: PV2.cssLinear(150, const [
                Color(0xFFB9AD97),
                Color(0xFFA79BBF),
              ]),
              imageUrl: me.avatarUrl,
              // The photo itself opens the same menu the badge does — the
              // badge alone was a 22px target and people could not find it
              // ("I am unable to upload the DP").
              onTap: () => _toggleMenu(_Menu.photo),
              badge: PV2MenuAnchor(
                open: _menu == _Menu.photo,
                onDismiss: _closeMenus,
                // Opens upward: the avatar sits high on the panel, and a
                // downward menu would cover the bio and action row beneath it.
                targetAnchor: Alignment.topRight,
                followerAnchor: Alignment.bottomRight,
                offset: const Offset(4, -6),
                menu: _photoMenu(),
                child: GestureDetector(
                  onTap: () => _toggleMenu(_Menu.photo),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    // 22 -> 30. The visible pip stays 22px; the extra 8 is
                    // invisible padding so the target is a real one.
                    width: 30,
                    height: 30,
                    child: Center(
                      child: _avatarUploading
                          ? Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: PV2.accent,
                                shape: BoxShape.circle,
                                border: Border.all(color: PV2.raised, width: 3),
                              ),
                              child: const SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: PV2.accent,
                                shape: BoxShape.circle,
                                border: Border.all(color: PV2.raised, width: 3),
                              ),
                              child: PV2Icons.camera(10, Colors.white),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          me.bio,
          style: PV2.body(size: 14.5, color: PV2.inkBio, height: 1.5),
        ),
        // Explicit removal request: the standalone "Edit profile" pill (plus
        // its neighboring send icon, which never had a real action wired to
        // it — onTap: () {}) used to sit here. Editing your profile is
        // still reachable via the settings menu (gear icon -> Edit Profile,
        // PV2MenuItem) — this only removes the duplicate, more prominent
        // entry point on the page body itself.
      ],
    );
  }

  // --- "Us" albums --------------------------------------------------------

  Widget _cappedList({required int visible, required List<Widget> children}) {
    const rowExtent = 68.0;
    final list = ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: children.length <= visible,
      physics: children.length <= visible
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 7),
      itemBuilder: (_, i) => children[i],
    );
    if (children.length <= visible) return list;
    return SizedBox(height: rowExtent * visible - 7 + 18, child: list);
  }

  Widget _circlesSection() {
    final circles = _circles;
    if (circles == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(PV2.pad, 0, PV2.pad, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: SectionTitle(
                  title: 'Circles',
                  count: '${circles.length}',
                  subtitle: 'your people — you decide who sees what',
                ),
              ),
              PillButton(
                label: circles.isEmpty ? 'Create' : 'Manage',
                icon: PV2Icons.plus(12, Colors.white),
                onTap: () => _pick(() => _push(const ManageCirclesScreen())),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PV2.pad),
          child: Column(
            children: [
              if (circles.isEmpty)
                _createCircleRow()
              else
                // Only 2 visible (was 3 — "too many circles visible, reduce
                // it a little"); the rest scroll inside the section, and
                // Manage lists them all.
                _cappedList(
                  visible: 2,
                  children: [for (final c in circles) _circleRow(c)],
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Mirrors [_createGroupRow]'s dashed-empty-state geometry so the two
  /// sections read as the same family when a person has neither yet.
  Widget _createCircleRow() {
    return DashedBox(
      radius: 18,
      color: PV2.accent.withValues(alpha: 0.32),
      child: NeuWell(
        radius: 18,
        shadows: PV2.insetDeep,
        border: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        onTap: () => _pick(() => _push(const ManageCirclesScreen())),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: PV2.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: PV2Icons.plus(18, PV2.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Create your first circle',
                style: PV2.body(
                  size: 13.5,
                  weight: FontWeight.w700,
                  color: PV2.accent.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleRow(CircleOption circle) {
    return NeuCard(
      radius: 18,
      shadows: PV2.raisedMd,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      // Opens THIS circle's own members (explicit request) — not the list
      // of all circles; "Manage" above still opens that list.
      onTap: () => _pick(() async {
        await _push(CircleMembersScreen(circle: circle));
        _loadCircles();
      }),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PV2.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.workspaces_outline,
              size: 18,
              color: PV2.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              circle.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PV2.body(size: 13.5, weight: FontWeight.w700),
            ),
          ),
          Text(
            circle.memberCount == 1
                ? '1 person'
                : '${circle.memberCount} people',
            style: PV2.body(size: 11.5, color: PV2.inkStamp),
          ),
        ],
      ),
    );
  }

  /// The dashed row that heads the group list. It mirrors a real group row's
  /// geometry so the list reads as one column, but is recessed and dashed so

  /// Duos | Groups — separate tabs, one grid at a time (explicit request,
  /// 2026-10-01: "like how anon and posts" were).
  Widget _tabs() {
    Widget tab(int i, String label, int count) {
      final on = _tab == i;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_tab == i) return;
            HapticFeedback.selectionClick();
            setState(() => _tab = i);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: on ? PV2.raised : PV2.recessed,
              border: Border.all(color: on ? PV2.hairlineActive : PV2.hairline),
            ),
            child: Text(
              count == 0 ? label : '$label · $count',
              style: PV2.body(
                size: 14,
                weight: FontWeight.w700,
                color: on ? Colors.white : PV2.inkTabOff,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PV2.pad),
      child: Row(
        children: [
          tab(0, 'Duos', _myAlbums.length),
          const SizedBox(width: 10),
          tab(1, 'Groups', _groupRows.length),
        ],
      ),
    );
  }

  /// Duos as highlight cards: cover = newest photo, our two faces + the
  /// blue streak flame bottom-left, their name. Tapping opens the album.
  Widget _duoHighlights() {
    if (_myAlbumsLoading) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HighlightGrid(
          children: [
            for (final d in _myAlbums)
              HighlightCard(
                title: d.otherName,
                coverUrl: _duoCovers[d.album.id],
                streak: _pairStreaks[d.otherUserId] ?? 0,
                note: !_isPending(d)
                    ? null
                    : d.album.createdBy == _myUserId
                    ? 'invite sent'
                    : 'wants to start a Duo',
                badge: FusedAvatars(
                  myUrl: _me?.avatarUrl,
                  otherUrl: d.otherAvatarUrl,
                  otherName: d.otherName,
                  size: 26,
                ),
                onTap: () => _openDuo(d),
              ),
            HighlightCard(
              title: 'Start a Duo',
              badge: PV2Icons.plus(18, PV2.accent),
              onTap: _openAddPeoplePicker,
            ),
          ],
        ),
      ],
    );
  }

  /// Groups in the same card style; tapping opens the group's profile.
  Widget _groupHighlights() {
    final rows = _groupRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HighlightGrid(
          children: [
            for (final g in rows)
              HighlightCard(
                title: g.name,
                coverUrl: g.id == null
                    ? null
                    : _groupCovers[g.id!] ?? g.iconUrl,
                streak: g.groupStreak,
                fallback: g.gradient,
                badge: MemberFaceStack(
                  avatarUrls: g.memberAvatarUrls.take(3).toList(),
                ),
                onTap: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute<void>(
                        builder: (_) => GroupProfileV2Screen(
                          groupId: g.id,
                          backdropIndex:
                              (widget.backdropIndex + 1) % PV2.backdrops.length,
                        ),
                      ),
                    )
                    .then((_) => _loadMyGroups()),
              ),
            HighlightCard(
              title: 'Create a group',
              badge: PV2Icons.plus(18, PV2.accent),
              onTap: () => _push(const CreateGroupScreen()),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Duo invite list — reached from the "add people" tile in "My Duos".
// Picking someone SENDS A DUO INVITATION right here (they're notified), it
// no longer opens their profile. Photos unlock only once they accept (the
// us_album_photos insert policy enforces that server-side too). Stays open,
// so several people can be invited in one go.
// ---------------------------------------------------------------------------

/// Where I stand with one person, for the invite button.
enum _DuoInviteState { none, invited, theyInvited, inDuo }

class _DuoPartnerPickerSheet extends StatefulWidget {
  const _DuoPartnerPickerSheet({required this.people, required this.states});

  final List<(String id, String name, String? avatarUrl)> people;
  final Map<String, _DuoInviteState> states;

  @override
  State<_DuoPartnerPickerSheet> createState() => _DuoPartnerPickerSheetState();
}

class _DuoPartnerPickerSheetState extends State<_DuoPartnerPickerSheet> {
  late final Map<String, _DuoInviteState> _states = {...widget.states};
  final Set<String> _busy = {};

  Future<void> _act(String id, String name) async {
    final state = _states[id] ?? _DuoInviteState.none;
    if (_busy.contains(id) ||
        state == _DuoInviteState.invited ||
        state == _DuoInviteState.inDuo) {
      return;
    }
    setState(() => _busy.add(id));
    HapticFeedback.mediumImpact();
    try {
      // Invite, or accept theirs if they already invited me.
      await DuoService.instance.sendOrAccept(id);
      if (!mounted) return;
      setState(
        () => _states[id] = state == _DuoInviteState.theyInvited
            ? _DuoInviteState.inDuo
            : _DuoInviteState.invited,
      );
      showGlassToast(
        context,
        state == _DuoInviteState.theyInvited
            ? "You're in a Duo with $name 💞"
            : 'Duo invite sent to $name 💞',
      );
    } catch (_) {
      if (!mounted) return;
      showGlassToast(context, "Couldn't send that invite.", isError: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.people;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
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
                'Start a Duo with…',
                style: PV2.body(size: 14, weight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'They get an invite. Photos unlock once they accept.',
                style: PV2.body(
                  size: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: people.length,
                  itemBuilder: (context, i) {
                    final f = people[i];
                    final state = _states[f.$1] ?? _DuoInviteState.none;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 6,
                      ),
                      child: Row(
                        children: [
                          ClipOval(
                            child: f.$3 == null
                                ? Container(
                                    width: 34,
                                    height: 34,
                                    color: PV2.recessed,
                                  )
                                : CachedNetworkImage(
                                    memCacheWidth: 102,
                                    imageUrl: f.$3!,
                                    width: 34,
                                    height: 34,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, _, _) => Container(
                                      width: 34,
                                      height: 34,
                                      color: PV2.recessed,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              f.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PV2.body(
                                size: 13,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _DuoInviteButton(
                            state: state,
                            busy: _busy.contains(f.$1),
                            onTap: () => _act(f.$1, f.$2),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DuoInviteButton extends StatelessWidget {
  const _DuoInviteButton({
    required this.state,
    required this.busy,
    required this.onTap,
  });

  final _DuoInviteState state;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, active) = switch (state) {
      _DuoInviteState.none => ('Invite', true),
      _DuoInviteState.theyInvited => ('Accept', true),
      _DuoInviteState.invited => ('Invited', false),
      _DuoInviteState.inDuo => ('In Duo', false),
    };
    return GestureDetector(
      onTap: active && !busy ? onTap : null,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? PV2.accent : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? PV2.accent : Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: PV2.body(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
      ),
    );
  }
}
