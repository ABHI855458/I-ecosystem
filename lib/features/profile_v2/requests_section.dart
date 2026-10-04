import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../core/supabase_config.dart';
import '../../services/current_user_service.dart';
import '../../services/group_service.dart';
import '../../services/storage_service.dart';
import '../../services/us_album_service.dart';
import '../notifications/notifications_screen.dart' show notifState;
import 'audience_picker_sheet.dart';
import 'profile_v2_sections.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

// ---------------------------------------------------------------------------
// Requests — the profile banner's inbox for everything that waits on YOU,
// in the slot friend requests used to have (friend requests are gone; see
// CircleService). Four kinds:
//   * Duo invites        — someone started a Duo with you: Accept / Decline.
//   * Group invites      — you were invited into a group album: Accept /
//                          Decline (group_invites).
//   * Duo photos         — your partner added a shared photo; it goes live
//                          only once you pick YOUR audience and approve
//                          (approve_duo_photo).
//   * New group posts    — someone posted in one of your groups; share it
//                          onward to your own circles/communities
//                          (share_group_post). Last 7 days, until shared.
// ---------------------------------------------------------------------------

class _DuoPhotoRequest {
  const _DuoPhotoRequest({
    required this.photoId,
    required this.partnerName,
    this.partnerAvatarUrl,
    this.photoUrl,
  });
  final String photoId;
  final String partnerName;
  final String? partnerAvatarUrl;
  final String? photoUrl;
}

class _GroupPostRequest {
  const _GroupPostRequest({
    required this.id,
    required this.groupName,
    required this.authorName,
    this.photoUrl,
    this.caption,
  });
  final String id;
  final String groupName;
  final String authorName;
  final String? photoUrl;
  final String? caption;
}

class _Requests {
  const _Requests({
    this.duoInvites = const [],
    this.groupInvites = const [],
    this.duoPhotos = const [],
    this.groupPosts = const [],
  });
  final List<MyDuoSummary> duoInvites;
  final List<GroupInvite> groupInvites;
  final List<_DuoPhotoRequest> duoPhotos;
  final List<_GroupPostRequest> groupPosts;

  int get count =>
      duoInvites.length + groupInvites.length + duoPhotos.length + groupPosts.length;
}

Future<_Requests> _loadRequests() async {
  final myId = await CurrentUserService.instance.resolveId();

  final results = await Future.wait([
    DuoService.instance.fetchMyAlbums().catchError((_) => <MyDuoSummary>[]),
    GroupService.instance.fetchMyGroupInvites().catchError((_) => <GroupInvite>[]),
  ]);
  final albums = results[0] as List<MyDuoSummary>;
  final groupInvites = results[1] as List<GroupInvite>;

  final duoInvites = [
    for (final a in albums)
      if (a.album.status == DuoStatus.pending && a.album.createdBy != myId) a,
  ];

  // Shared photos in MY accepted Duos, added by my partner, not yet approved.
  final accepted = {
    for (final a in albums)
      if (a.album.status == DuoStatus.accepted) a.album.id: a,
  };
  var duoPhotos = const <_DuoPhotoRequest>[];
  if (accepted.isNotEmpty) {
    try {
      final rows = await supabase
          .from('us_album_photos')
          .select('id, album_id, photo_url')
          .inFilter('album_id', accepted.keys.toList())
          .eq('visibility', 'mutual')
          .isFilter('partner_approved_at', null)
          .neq('uploaded_by', myId)
          .order('created_at', ascending: false);
      final list = rows as List;
      final urls = await Future.wait([
        for (final r in list) StorageService.signedDuoPhotoUrl(r['photo_url'] as String?),
      ]);
      duoPhotos = [
        for (var i = 0; i < list.length; i++)
          _DuoPhotoRequest(
            photoId: list[i]['id'] as String,
            partnerName: accepted[list[i]['album_id']]?.otherName ?? 'Your Duo',
            partnerAvatarUrl: accepted[list[i]['album_id']]?.otherAvatarUrl,
            photoUrl: urls[i],
          ),
      ];
    } catch (_) {}
  }

  // Recent posts by others in groups I'm in, that I haven't shared yet.
  var groupPosts = const <_GroupPostRequest>[];
  try {
    final memberRows = await supabase
        .from('group_members')
        .select('group_id')
        .eq('user_id', myId);
    final groupIds = [for (final r in memberRows as List) r['group_id'] as String];
    if (groupIds.isNotEmpty) {
      final since = DateTime.now().toUtc().subtract(const Duration(days: 7));
      final rows = await supabase
          .from('group_posts')
          .select('id, caption, photo_url, photo_urls, groups(name), '
              'users!group_posts_user_id_fkey(name)')
          .inFilter('group_id', groupIds)
          .neq('user_id', myId)
          .isFilter('deleted_at', null)
          .gte('created_at', since.toIso8601String())
          .order('created_at', ascending: false)
          .limit(20);
      final list = (rows as List).cast<Map<String, dynamic>>();
      final ids = [for (final r in list) r['id'] as String];
      final shared = <String>{};
      if (ids.isNotEmpty) {
        final mine = await supabase
            .from('group_post_audiences')
            .select('group_post_id')
            .eq('shared_by', myId)
            .inFilter('group_post_id', ids);
        for (final r in mine as List) {
          shared.add(r['group_post_id'] as String);
        }
      }
      groupPosts = [
        for (final r in list)
          if (!shared.contains(r['id']))
            _GroupPostRequest(
              id: r['id'] as String,
              groupName: (r['groups']?['name'] as String?) ?? 'a group',
              authorName: (r['users']?['name'] as String?) ?? 'Someone',
              caption: r['caption'] as String?,
              photoUrl: ((r['photo_urls'] as List?)?.isNotEmpty ?? false)
                  ? (r['photo_urls'] as List).first as String
                  : r['photo_url'] as String?,
            ),
      ];
    }
  } catch (_) {}

  return _Requests(
    duoInvites: duoInvites,
    groupInvites: groupInvites,
    duoPhotos: duoPhotos,
    groupPosts: groupPosts,
  );
}

/// Set true (MainShell, on tapping a Duo invite / group invite / Duo photo /
/// new group post notification) to open the Requests panel. The profile's
/// [RequestsBannerButton] consumes it — immediately if it's on screen, or on
/// its first frame if the Profile tab hadn't been built yet.
final requestsOpenRequest = ValueNotifier<bool>(false);

/// Banner button with a live count badge; opens [_RequestsPanel].
class RequestsBannerButton extends StatefulWidget {
  const RequestsBannerButton({super.key});

  @override
  State<RequestsBannerButton> createState() => _RequestsBannerButtonState();
}

class _RequestsBannerButtonState extends State<RequestsBannerButton> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    requestsOpenRequest.addListener(_onOpenRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpenRequested());
    // BUG FIX (explicit report, 2026-09-29: "when sent a duo request the
    // request notification is coming very fast but in ui the request is
    // very very slow"): the badge only ever refreshed on this screen's
    // first build, or after the panel itself was opened and closed — a
    // brand-new invite sat un-counted until one of those happened, even
    // though its push already landed. notifState is realtime-backed (see
    // NotifState.loadReal's own doc) and gets a fresh row THE INSTANT the
    // underlying notifications INSERT does — a Duo invite, group invite,
    // shared Duo photo and new-group-post share all write one (see
    // MainShell._isRequest) — so listening to it re-counts on the same
    // beat the push notification itself fires on, not on the next time
    // this screen happens to rebuild.
    notifState.addListener(_onNotifChanged);
  }

  @override
  void dispose() {
    requestsOpenRequest.removeListener(_onOpenRequested);
    notifState.removeListener(_onNotifChanged);
    super.dispose();
  }

  bool _panelOpen = false;

  void _onNotifChanged() {
    if (mounted) unawaited(_refresh());
  }

  void _onOpenRequested() {
    if (!requestsOpenRequest.value || !mounted) return;
    requestsOpenRequest.value = false;
    if (!_panelOpen) unawaited(_open());
  }

  Future<void> _refresh() async {
    try {
      final r = await _loadRequests();
      if (mounted) setState(() => _count = r.count);
    } catch (_) {}
  }

  Future<void> _open() async {
    HapticFeedback.selectionClick();
    _panelOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RequestsPanel(),
    );
    _panelOpen = false;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ChromeButton(
          icon: const Icon(Icons.move_to_inbox_outlined, size: 18, color: Colors.white),
          onTap: _open,
        ),
        if (_count > 0)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              decoration: BoxDecoration(
                color: PV2.danger,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: PV2.page, width: 1.5),
              ),
              child: Text(
                _count > 9 ? '9+' : '$_count',
                textAlign: TextAlign.center,
                style: PV2.body(size: 9.5, weight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

class _RequestsPanel extends StatefulWidget {
  const _RequestsPanel();

  @override
  State<_RequestsPanel> createState() => _RequestsPanelState();
}

class _RequestsPanelState extends State<_RequestsPanel> {
  _Requests? _data;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
    // Same fix as the banner badge above: a request that arrives while
    // this sheet is already open shouldn't need it closed and reopened to
    // show up.
    notifState.addListener(_onNotifChanged);
  }

  @override
  void dispose() {
    notifState.removeListener(_onNotifChanged);
    super.dispose();
  }

  void _onNotifChanged() {
    if (mounted) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final r = await _loadRequests();
      if (mounted) setState(() => _data = r);
    } catch (_) {
      if (mounted) setState(() => _data = const _Requests());
    }
  }

  /// Requests already acted on in this panel — hidden the INSTANT the
  /// button is tapped, not after the server answers.
  final Set<String> _gone = {};

  /// Optimistic: the row disappears on tap and the server call runs
  /// behind it; only a failure brings it back (with a toast). It used to
  /// await the write AND a full reload of every request list (several
  /// queries) before anything moved on screen — "clicking Accept isn't
  /// reflecting fast, it's lagging a lot".
  Future<void> _run(String key, Future<void> Function() action, String done) async {
    if (_busy.contains(key) || _gone.contains(key)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _busy.add(key);
      _gone.add(key);
    });
    try {
      await action();
      if (mounted) showGlassToast(context, done);
    } catch (_) {
      if (mounted) {
        setState(() => _gone.remove(key));
        showGlassToast(context, "That didn't go through — try again.", isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(key));
      // Quiet background refresh — never blocks the tap.
      unawaited(_load());
    }
  }

  Future<void> _approveDuoPhoto(_DuoPhotoRequest p) async {
    final choice = await showAudiencePickerSheet(
      context,
      title: 'Post with ${p.partnerName}',
      subtitle: 'Pick who sees it on your side. It goes live to both of your audiences.',
      confirmLabel: 'Approve & post',
    );
    if (choice == null) return;
    await _run(
      p.photoId,
      () => DuoService.instance.approvePhoto(
        p.photoId,
        circleIds: choice.circleIds.toList(),
        communityIds: choice.communityIds.toList(),
      ),
      'Posted',
    );
  }

  Future<void> _shareGroupPost(_GroupPostRequest p) async {
    final choice = await showAudiencePickerSheet(
      context,
      title: 'Share this ${p.groupName} post',
      subtitle: 'Also show it to your own circles or communities.',
      confirmLabel: 'Share',
    );
    if (choice == null) return;
    await _run(
      p.id,
      () => GroupService.instance.sharePost(
        p.id,
        circleIds: choice.circleIds,
        communityIds: choice.communityIds,
      ),
      'Shared with your audience',
    );
  }

  Widget _avatar(String? url, {double size = 40, bool square = false}) {
    final radius = square ? BorderRadius.circular(10) : BorderRadius.circular(size);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: (url ?? '').isEmpty
            ? const ColoredBox(
                color: PV2.recessed,
                child: Icon(Icons.person, size: 18, color: Colors.white38),
              )
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                memCacheWidth: 160,
                errorWidget: (_, _, _) => const ColoredBox(color: PV2.recessed),
              ),
      ),
    );
  }

  Widget _row({
    required Widget leading,
    required String title,
    String? subtitle,
    required List<Widget> actions,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PV2.body(size: 13.5, weight: FontWeight.w700),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PV2.body(size: 12, color: PV2.inkSub),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          ...actions,
        ],
      ),
    );
  }

  Widget _pill(String label, {required bool primary, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: primary ? PV2.accent : PV2.recessed,
            borderRadius: BorderRadius.circular(20),
            border: primary ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Text(
            label,
            style: PV2.body(
              size: 12,
              weight: FontWeight.w700,
              color: primary ? Colors.black : Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _section(String title, List<Widget> rows) => [
        const SizedBox(height: 14),
        Text(title, style: PV2.caps(size: 9.5, tracking: 0.14, color: PV2.inkStamp)),
        const SizedBox(height: 4),
        ...rows,
      ];

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: GlassSurface(
          radius: 20,
          fill: const Color(0xF0141416),
          border: const Color(0x14FFFFFF),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Requests', style: PV2.body(size: 16, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                'Invites waiting on you, and posts that need your audience.',
                style: PV2.body(size: 12, color: PV2.inkBio),
              ),
              if (d == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator(color: PV2.accent)),
                )
              else if (d.duoInvites.every((a) => _gone.contains(a.album.id)) &&
                  d.groupInvites.every((g) => _gone.contains(g.id)) &&
                  d.duoPhotos.every((p) => _gone.contains(p.photoId)) &&
                  d.groupPosts.every((p) => _gone.contains(p.id)))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text("You're all caught up.", style: PV2.body(size: 13, color: PV2.inkSub)),
                  ),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (d.duoInvites.any((a) => !_gone.contains(a.album.id)))
                          ..._section('DUO INVITES', [
                            for (final a in d.duoInvites.where((a) => !_gone.contains(a.album.id)))
                              _row(
                                leading: _avatar(a.otherAvatarUrl),
                                title: '${a.otherName} started a Duo with you',
                                subtitle: 'Accept to share an album together',
                                actions: [
                                  _pill('Decline', primary: false, onTap: _busy.contains(a.album.id)
                                      ? null
                                      : () => _run(a.album.id,
                                          () => DuoService.instance.declinePending(a.album.id), 'Declined')),
                                  _pill('Accept', primary: true, onTap: _busy.contains(a.album.id)
                                      ? null
                                      : () => _run(a.album.id,
                                          () => DuoService.instance.accept(a.album.id), 'Duo started')),
                                ],
                              ),
                          ]),
                        if (d.groupInvites.any((g) => !_gone.contains(g.id)))
                          ..._section('GROUP INVITES', [
                            for (final g in d.groupInvites.where((g) => !_gone.contains(g.id)))
                              _row(
                                leading: _avatar(g.groupIconUrl, square: true),
                                title: g.groupName,
                                subtitle: '${g.inviterName} invited you',
                                actions: [
                                  _pill('Decline', primary: false, onTap: _busy.contains(g.id)
                                      ? null
                                      : () => _run(g.id,
                                          () => GroupService.instance.respondInvite(g.id, accept: false),
                                          'Declined')),
                                  _pill('Accept', primary: true, onTap: _busy.contains(g.id)
                                      ? null
                                      : () => _run(g.id,
                                          () => GroupService.instance.respondInvite(g.id, accept: true),
                                          'Joined ${g.groupName}')),
                                ],
                              ),
                          ]),
                        if (d.duoPhotos.any((p) => !_gone.contains(p.photoId)))
                          ..._section('DUO PHOTOS WAITING FOR YOU', [
                            for (final p in d.duoPhotos.where((p) => !_gone.contains(p.photoId)))
                              _row(
                                leading: _avatar(p.photoUrl, square: true, size: 44),
                                title: '${p.partnerName} added a photo',
                                subtitle: 'Pick your audience to post it together',
                                actions: [
                                  _pill('Set audience', primary: true,
                                      onTap: _busy.contains(p.photoId) ? null : () => _approveDuoPhoto(p)),
                                ],
                              ),
                          ]),
                        if (d.groupPosts.any((p) => !_gone.contains(p.id)))
                          ..._section('NEW IN YOUR GROUPS', [
                            for (final p in d.groupPosts.where((p) => !_gone.contains(p.id)))
                              _row(
                                leading: _avatar(p.photoUrl, square: true, size: 44),
                                title: '${p.authorName} posted in ${p.groupName}',
                                subtitle: p.caption,
                                actions: [
                                  _pill('Share', primary: true,
                                      onTap: _busy.contains(p.id) ? null : () => _shareGroupPost(p)),
                                ],
                              ),
                          ]),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
