import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/glass.dart' show showGlassToast;
import '../../core/supabase_config.dart' show supabase;
import '../../services/block_service.dart';
import '../../services/current_user_service.dart';
import '../../services/storage_service.dart';
import '../../services/us_album_service.dart';
import '../../shared/time_ago.dart';
import 'album_photo_viewer.dart';
import '../composer/composer_screen.dart' show openCameraRoute;
import 'profile_v2_create_flows.dart';
import 'profile_v2_data.dart';
import 'profile_v2_tokens.dart';
import 'profile_v2_widgets.dart';

// ---------------------------------------------------------------------------
// Profile highlights (2026-10-01 redesign): the profile is two sections of
// Memories-style cards — Duos and Groups — instead of a scrolling feed.
// ---------------------------------------------------------------------------

/// Two avatars overlapped — mine in front.
class FusedAvatars extends StatelessWidget {
  const FusedAvatars({
    super.key,
    required this.myUrl,
    required this.otherUrl,
    required this.size,
    this.ring = Colors.black,
    this.otherName,
  });

  final String? myUrl;
  final String? otherUrl;
  final double size;
  final Color ring;

  /// Initial shown when the other person has no photo.
  final String? otherName;

  @override
  Widget build(BuildContext context) {
    final overlap = size * 0.34;
    return SizedBox(
      width: size * 2 - overlap,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: size - overlap,
            child: _circle(otherUrl, size, initial: otherName),
          ),
          Positioned(
            left: 0,
            child: Container(
              padding: EdgeInsets.all(size * 0.05),
              decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
              child: _circle(myUrl, size * 0.9),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _circle(String? url, double size, {String? initial}) =>
      ClipOval(
        child: url == null
            ? Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                color: const Color(0xFF2A3340),
                child: initial == null || initial.isEmpty
                    ? null
                    : Text(
                        initial[0].toUpperCase(),
                        style: PV2.body(
                          size: size * 0.42,
                          weight: FontWeight.w800,
                        ),
                      ),
              )
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                memCacheWidth: 300,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) =>
                    Container(width: size, height: size, color: PV2.recessed),
              ),
      );
}

/// Memories-style tile: the latest photo as cover, title and a bottom-left
/// badge row (avatars + blue streak flame).
class HighlightCard extends StatelessWidget {
  const HighlightCard({
    super.key,
    required this.title,
    required this.badge,
    required this.onTap,
    this.coverUrl,
    this.streak = 0,
    this.note,
    this.fallback = const LinearGradient(
      colors: [Color(0xFF1B2433), Color(0xFF0E1118)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  });

  final String title;
  final Widget badge;
  final VoidCallback onTap;
  final String? coverUrl;
  final int streak;

  /// Small highlighted line above the title ("wants to start a Duo").
  final String? note;
  final Gradient fallback;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 0.8,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(decoration: BoxDecoration(gradient: fallback)),
              if (coverUrl != null)
                CachedNetworkImage(
                  imageUrl: coverUrl!,
                  memCacheWidth: 600,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.45, 1],
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (note != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PV2.body(
                            size: 10.5,
                            weight: FontWeight.w700,
                            color: PV2.accentSoft,
                          ),
                        ),
                      ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PV2.display(size: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        badge,
                        const SizedBox(width: 6),
                        if (streak > 0)
                          StreakFlamePill(count: streak, size: 10),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-column grid of cards inside the profile's own scroll view.
class HighlightGrid extends StatelessWidget {
  const HighlightGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PV2.pad),
      child: Column(children: rows),
    );
  }
}

/// Two-way pill switch — "Duos · N | Groups · N" — shared by the own-profile
/// and someone-else's-profile screens so both read as the same surface
/// (explicit request, 2026-10-01: "others profile shall also appear [like
/// the personal profile]").
/// Up to 3 real member photos, overlapped — the group-row preview circles.
///
/// BUG FIX (explicit report — "in the group preview from the profile,
/// there are circles, these shall have group members' DP as such, wired
/// in"): this used to be `FaceStack(colors: kFaceSwatches.take(3))`, a
/// fixed 3-color decorative palette with no connection to who was actually
/// in the group — every group's row showed the exact same three colors.
/// Each circle now renders that member's real `profile_photo_url`, falling
/// back to a plain swatch only for a member who has no photo, not for the
/// whole stack.
class MemberFaceStack extends StatelessWidget {
  const MemberFaceStack({super.key, required this.avatarUrls, this.size = 24});

  final List<String?> avatarUrls;

  final double size;

  @override
  Widget build(BuildContext context) {
    if (avatarUrls.isEmpty) return const SizedBox.shrink();
    const overlap = 9.0;
    final step = size - overlap;
    return SizedBox(
      width: size + step * (avatarUrls.length - 1),
      height: size,
      child: Stack(
        // Reversed so the FIRST member paints on top, matching FaceStack's
        // own left-to-right stacking order.
        children: [
          for (var i = avatarUrls.length - 1; i >= 0; i--)
            Positioned(
              left: step * i,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kFaceSwatches[i % kFaceSwatches.length],
                  border: Border.all(color: PV2.raised, width: 2),
                ),
                child: avatarUrls[i] == null
                    ? null
                    : ClipOval(
                        child: CachedNetworkImage(
                          memCacheWidth: 200,
                          imageUrl: avatarUrls[i]!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class TwoTabSwitch extends StatelessWidget {
  const TwoTabSwitch({
    super.key,
    required this.labels,
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final List<int> counts;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PV2.pad),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _tab(i)),
          ],
        ],
      ),
    );
  }

  Widget _tab(int i) {
    final on = selected == i;
    return GestureDetector(
      onTap: () {
        if (selected == i) return;
        HapticFeedback.selectionClick();
        onSelect(i);
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
          counts[i] == 0 ? labels[i] : '${labels[i]} · ${counts[i]}',
          style: PV2.body(
            size: 14,
            weight: FontWeight.w700,
            color: on ? Colors.white : PV2.inkTabOff,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Duo album
// ---------------------------------------------------------------------------

/// Who is in a Duo, for the album header.
class DuoPair {
  const DuoPair({
    required this.albumId,
    required this.status,
    required this.createdBy,
    required this.aId,
    required this.aName,
    required this.aAvatar,
    required this.bId,
    required this.bName,
    required this.bAvatar,
  });

  final String albumId;
  final DuoStatus status;
  final String createdBy;
  final String aId;
  final String aName;
  final String? aAvatar;
  final String bId;
  final String bName;
  final String? bAvatar;
}

/// Opens the Duo album between [userA] and [userB] for whoever is looking —
/// a member gets the full page, anyone else sees the banner, both DPs and
/// only the photos visible to them.
/// True while [openDuoAlbumBetween] is loading or pushing — same one-at-a-time
/// rule as the Duo picker: several reads run before anything opens, and a
/// second tap during that gap opened the album twice (reported 2026-10-04).
bool _duoAlbumBusy = false;

Future<void> openDuoAlbumBetween(
  BuildContext context, {
  required String userA,
  required String userB,
  int streak = 0,
}) async {
  if (_duoAlbumBusy) return;
  _duoAlbumBusy = true;
  try {
    await _openDuoAlbumBetween(
      context,
      userA: userA,
      userB: userB,
      streak: streak,
    );
  } finally {
    _duoAlbumBusy = false;
  }
}

Future<void> _openDuoAlbumBetween(
  BuildContext context, {
  required String userA,
  required String userB,
  int streak = 0,
}) async {
  final album = await DuoService.instance.fetchAlbumBetween(userA, userB);
  if (!context.mounted) return;
  if (album == null) {
    showGlassToast(context, "This Duo album isn't visible to you");
    return;
  }
  final myId = await CurrentUserService.instance.resolveId();
  final users = await Supabase.instance.client
      .from('users')
      .select('id, name, username, profile_photo_url')
      .inFilter('id', [album.userA, album.userB]);
  final byId = {for (final u in users) u['id'] as String: u};
  // The viewer (if a member) goes first — "You & X".
  final first = album.userB == myId ? album.userB : album.userA;
  final second = first == album.userA ? album.userB : album.userA;
  String nameOf(String id) =>
      (byId[id]?['username'] as String?) ??
      (byId[id]?['name'] as String?) ??
      'someone';
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DuoAlbumScreen(
        pair: DuoPair(
          albumId: album.id,
          status: album.status,
          createdBy: album.createdBy,
          aId: first,
          aName: nameOf(first),
          aAvatar: byId[first]?['profile_photo_url'] as String?,
          bId: second,
          bName: nameOf(second),
          bAvatar: byId[second]?['profile_photo_url'] as String?,
        ),
        myUserId: myId,
        streak: streak,
      ),
    ),
  );
}

class DuoAlbumScreen extends StatefulWidget {
  const DuoAlbumScreen({
    super.key,
    required this.pair,
    required this.myUserId,
    required this.streak,
  });

  /// From one of my own Duos on my profile.
  factory DuoAlbumScreen.mine({
    Key? key,
    required MyDuoSummary summary,
    required String? myUserId,
    required String? myAvatarUrl,
    required String myName,
    required int streak,
  }) => DuoAlbumScreen(
    key: key,
    pair: DuoPair(
      albumId: summary.album.id,
      status: summary.album.status,
      createdBy: summary.album.createdBy,
      aId: myUserId ?? '',
      aName: myName,
      aAvatar: myAvatarUrl,
      bId: summary.otherUserId,
      bName: summary.otherName,
      bAvatar: summary.otherAvatarUrl,
    ),
    myUserId: myUserId,
    streak: streak,
  );

  final DuoPair pair;
  final String? myUserId;
  final int streak;

  @override
  State<DuoAlbumScreen> createState() => _DuoAlbumScreenState();
}

class _DuoAlbumScreenState extends State<DuoAlbumScreen> {
  List<AlbumPhoto>? _photos;
  Map<String, int> _seen = const {};
  String? _banner;
  bool _bannerUploading = false;
  bool _selecting = false;
  final Set<String> _selected = {};
  bool _busy = false;
  late DuoStatus _status = widget.pair.status;

  DuoPair get p => widget.pair;
  bool get _isMember => widget.myUserId == p.aId || widget.myUserId == p.bId;
  String get _otherId => widget.myUserId == p.aId ? p.bId : p.aId;
  String get _otherName => widget.myUserId == p.aId ? p.bName : p.aName;
  String get _title =>
      _isMember ? 'You & $_otherName' : '${p.aName} & ${p.bName}';
  bool get _pendingForMe =>
      _isMember &&
      _status == DuoStatus.pending &&
      p.createdBy != widget.myUserId;
  bool get _pendingSent =>
      _isMember &&
      _status == DuoStatus.pending &&
      p.createdBy == widget.myUserId;

  @override
  void initState() {
    super.initState();
    _load();
    DuoService.instance
        .fetchBannerUrl(p.albumId)
        .then((u) {
          if (mounted) setState(() => _banner = u);
        })
        .catchError((_) {});
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        DuoService.instance.fetchPhotos(p.albumId),
        DuoService.instance
            .seenCounts(p.albumId)
            .catchError((_) => <String, int>{}),
      ]);
      final rows = results[0] as List<DuoPhotoRow>;
      final urls = await Future.wait(
        rows.map((r) => StorageService.signedDuoPhotoUrl(r.photoUrl)),
      );
      final photos = [
        for (var i = rows.length - 1; i >= 0; i--)
          AlbumPhoto(
            id: rows[i].id,
            imageUrl: urls[i],
            uploaderId: rows[i].uploadedBy,
            color: PV2.recessed,
            byColor: rows[i].uploadedBy == widget.myUserId
                ? PV2.accent
                : Colors.white.withValues(alpha: 0.4),
            ago: formatRelativeTime(rows[i].createdAt),
            span: 1,
            ratio: 1,
            privacy: rows[i].isMutual
                ? PhotoPrivacy.shared
                : PhotoPrivacy.private,
          ),
      ];
      if (mounted) {
        setState(() {
          _photos = photos;
          _seen = results[1] as Map<String, int>;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _photos ??= const []);
    }
  }

  Future<void> _pickBanner() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 88,
    );
    if (x == null || !mounted) return;
    setState(() => _bannerUploading = true);
    try {
      final url = await DuoService.instance.setBanner(p.albumId, File(x.path));
      if (!mounted) return;
      if (url == null) throw StateError('upload');
      setState(() => _banner = url);
    } catch (_) {
      if (mounted)
        showGlassToast(context, "Couldn't update the banner.", isError: true);
    } finally {
      if (mounted) setState(() => _bannerUploading = false);
    }
  }

  Future<void> _togglePrivacy(AlbumPhoto photo) async {
    if (!_isMember || photo.id == null) return;
    final goingPublic = photo.isPrivate;
    HapticFeedback.selectionClick();
    setState(() => photo.toggle());
    try {
      final r = await DuoService.instance.toggleVisibility(
        photo.id!,
        mutual: goingPublic,
      );
      if (!mounted) return;
      showGlassToast(
        context,
        r == 'live'
            ? 'Shared ✓'
            : r == 'awaiting'
            ? 'Shared — goes live once $_otherName approves'
            : 'Private 🔒',
      );
      unawaited(_load());
    } catch (_) {
      if (!mounted) return;
      setState(() => photo.toggle());
      showGlassToast(
        context,
        "Couldn't change that — try again.",
        isError: true,
      );
    }
  }

  Future<void> _addMemory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DuoPostScreen(albumId: p.albumId, otherName: _otherName),
      ),
    );
    await _load();
  }

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    try {
      if (accept) {
        await DuoService.instance.accept(p.albumId);
        if (mounted) setState(() => _status = DuoStatus.accepted);
      } else {
        await DuoService.instance.declinePending(p.albumId);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
    } catch (_) {
      if (mounted) {
        showGlassToast(
          context,
          "That didn't go through — try again.",
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        title: Text(title, style: PV2.body(size: 17, weight: FontWeight.w700)),
        content: Text(body, style: PV2.body(size: 13.5, color: PV2.inkBio)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action, style: const TextStyle(color: PV2.danger)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    if (!await _confirm(
      'Delete ${ids.length} photo${ids.length == 1 ? '' : 's'}?',
      'They are removed from the Duo and from the feed for both of you.',
      'Delete',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    var failed = 0;
    for (final id in ids) {
      try {
        await DuoService.instance.deletePhoto(id);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selecting = false;
      _selected.clear();
    });
    if (failed > 0) {
      showGlassToast(
        context,
        "Couldn't delete $failed of them.",
        isError: true,
      );
    }
    await _load();
  }

  Future<void> _block() async {
    if (!await _confirm(
      'Block $_otherName?',
      "You won't see each other's posts, pings or profile.",
      'Block',
    )) {
      return;
    }
    try {
      await BlockService.instance.block(_otherId);
      if (!mounted) return;
      showGlassToast(context, 'Blocked $_otherName');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted)
        showGlassToast(context, "Couldn't block — try again.", isError: true);
    }
  }

  Future<void> _openMenu() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141417),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if ((_photos ?? const []).isNotEmpty)
              ListTile(
                leading: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.white,
                ),
                title: Text('Select photos', style: PV2.body(size: 15)),
                onTap: () => Navigator.pop(c, 'select'),
              ),
            ListTile(
              leading: const Icon(Icons.block_rounded, color: PV2.danger),
              title: Text(
                'Block $_otherName',
                style: PV2.body(size: 15, color: PV2.danger),
              ),
              onTap: () => Navigator.pop(c, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (pick == 'select') setState(() => _selecting = true);
    if (pick == 'block') await _block();
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: PV2.page,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _bannerHeader(top)),
              if (_pendingForMe || _pendingSent)
                SliverToBoxAdapter(child: _pendingRow()),
              if (photos == null)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: PV2.accent,
                      ),
                    ),
                  ),
                )
              else if (photos.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        _pendingSent || _pendingForMe
                            ? 'Photos show up once the Duo is accepted'
                            : 'No memories yet',
                        style: PV2.body(size: 13.5, color: PV2.inkByline),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    PV2.pad,
                    16,
                    PV2.pad,
                    bottom + 130,
                  ),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _tile(photos, i),
                      childCount: photos.length,
                    ),
                  ),
                ),
            ],
          ),
          Positioned(
            top: top + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _roundButton(
                  _selecting
                      ? Icons.close_rounded
                      : Icons.arrow_back_ios_new_rounded,
                  () => _selecting
                      ? setState(() {
                          _selecting = false;
                          _selected.clear();
                        })
                      : Navigator.of(context).pop(),
                ),
                const Spacer(),
                if (_isMember && !_selecting) ...[
                  // Set the banner — its own button up here, clear of the
                  // banner's bottom row (names, faces, streak).
                  _bannerUploading
                      ? const SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: EdgeInsets.all(11),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : _roundButton(Icons.image_outlined, _pickBanner),
                  const SizedBox(width: 8),
                  _roundButton(Icons.more_horiz_rounded, _openMenu),
                ],
              ],
            ),
          ),
          // Add memory — one big camera circle, bottom centre.
          if (_isMember && !_selecting && _status == DuoStatus.accepted)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottom + 22,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _addMemory();
                  },
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: PV2.accent,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.9),
                        width: 3,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      size: 34,
                      color: PV2.onAccent,
                    ),
                  ),
                ),
              ),
            ),
          if (_selecting)
            Positioned(
              left: 16,
              right: 16,
              bottom: bottom + 16,
              child: GestureDetector(
                onTap: _busy || _selected.isEmpty ? null : _deleteSelected,
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    color: _selected.isEmpty
                        ? Colors.white.withValues(alpha: 0.1)
                        : PV2.danger,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _selected.isEmpty
                              ? 'Tap photos to select'
                              : 'Delete ${_selected.length}',
                          style: PV2.body(size: 15, weight: FontWeight.w700),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The banner: shared cover photo, title bottom-left, both DPs fused +
  /// streak flame bottom-right.
  Widget _bannerHeader(double top) {
    return SizedBox(
      height: top + 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1C3B57), Color(0xFF2B1B3D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          if (_banner != null)
            CachedNetworkImage(
              imageUrl: _banner!,
              fit: BoxFit.cover,
              memCacheWidth: 1200,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.35, 0.7, 1],
                colors: [
                  Color(0x66000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  PV2.page,
                ],
              ),
            ),
          ),
          Positioned(
            left: PV2.pad,
            right: PV2.pad,
            bottom: 6,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PV2.display(size: 22),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FusedAvatars(
                      myUrl: p.aAvatar,
                      otherUrl: p.bAvatar,
                      otherName: p.bName,
                      size: 64,
                      ring: PV2.page,
                    ),
                    if (widget.streak > 0) ...[
                      const SizedBox(height: 6),
                      StreakFlamePill(count: widget.streak, size: 11),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(PV2.pad, 14, PV2.pad, 0),
      child: _pendingForMe
          ? Row(
              children: [
                Expanded(
                  child: _pill(
                    'Accept Duo',
                    Icons.check_rounded,
                    _busy ? null : () => _respond(true),
                    filled: true,
                  ),
                ),
                const SizedBox(width: 10),
                _pill(
                  'Decline',
                  Icons.close_rounded,
                  _busy ? null : () => _respond(false),
                ),
              ],
            )
          : Text(
              'Invite sent · waiting for $_otherName',
              style: PV2.body(size: 13, color: PV2.inkByline),
            ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: PV2.hairlineBright),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    ),
  );

  Widget _pill(
    String label,
    IconData icon,
    VoidCallback? onTap, {
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: filled ? PV2.accent : Colors.white.withValues(alpha: 0.08),
          border: filled ? null : Border.all(color: PV2.hairlineBright),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: filled ? PV2.onAccent : Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: PV2.body(
                size: 14,
                weight: FontWeight.w700,
                color: filled ? PV2.onAccent : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(List<AlbumPhoto> photos, int i) {
    final ph = photos[i];
    final selected = ph.id != null && _selected.contains(ph.id);
    final seen = ph.id == null ? 0 : (_seen[ph.id] ?? 0);
    return GestureDetector(
      onTap: () {
        if (_selecting) {
          if (ph.id == null) return;
          setState(() {
            if (!_selected.remove(ph.id)) _selected.add(ph.id!);
          });
          return;
        }
        final real = photos.where((x) => x.imageUrl != null).toList();
        if (real.isEmpty) return;
        showAlbumPhotoViewer(
          context,
          photos: real,
          initialIndex: real.indexOf(ph).clamp(0, real.length - 1),
          onChanged: _load,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: PV2.recessed),
            if (ph.imageUrl != null)
              CachedNetworkImage(
                imageUrl: ph.imageUrl!,
                memCacheWidth: 600,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.6, 1],
                  colors: [Color(0x00000000), Color(0x99000000)],
                ),
              ),
            ),
            // Privacy badge — lock = only the two of you, people = shared.
            // Either member can tap it.
            Positioned(
              top: 6,
              left: 6,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _isMember && !_selecting
                    ? () => _togglePrivacy(ph)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.5),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      ph.isPrivate
                          ? Icons.lock_rounded
                          : Icons.people_alt_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            if (_selecting)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? PV2.accent
                        : Colors.black.withValues(alpha: 0.35),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: PV2.onAccent,
                        )
                      : null,
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Row(
                children: [
                  Text(
                    ph.ago,
                    style: PV2.body(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const Spacer(),
                  if (!ph.isPrivate) ...[
                    Icon(
                      Icons.visibility_rounded,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$seen',
                      style: PV2.body(
                        size: 11,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "+" — full-screen create chooser: Duo or Group.
// ---------------------------------------------------------------------------

String _memories(int n) => n == 1 ? '1 memory' : '$n memories';

class CreateChooserScreen extends StatefulWidget {
  const CreateChooserScreen({super.key, required this.onStartNewDuo});

  final Future<void> Function() onStartNewDuo;

  @override
  State<CreateChooserScreen> createState() => _CreateChooserScreenState();
}

class _CreateChooserScreenState extends State<CreateChooserScreen> {
  bool _pickingDuo = false;

  /// Fetched lazily, in the BACKGROUND, the instant this screen mounts —
  /// NOT awaited before the screen opens. Explicit report: "clicking plus
  /// isn't opening fast, and clicking multiple times opens it multiple
  /// times" — the old openCreateChooser awaited this same network call
  /// BEFORE pushing the route at all, so the whole screen sat behind a
  /// round trip, and a second tap during that wait fired its own
  /// independent fetch-then-push, stacking a second chooser on top. Both
  /// choices on the FIRST screen (Group, Anon) need neither Duos nor the
  /// avatar — only tapping "Duo" ever needs this, and by then it has had
  /// the time between the two taps to resolve.
  late final Future<(List<MyDuoSummary>, String?)> _duoData = _loadDuoData();

  Future<(List<MyDuoSummary>, String?)> _loadDuoData() async {
    try {
      final results = await Future.wait<Object?>([
        DuoService.instance.fetchMyAlbums(),
        CurrentUserService.instance.resolveId().then(
          (id) => supabase
              .from('users')
              .select('profile_photo_url')
              .eq('id', id)
              .maybeSingle(),
        ),
      ]);
      final duos = [
        for (final d in results[0] as List<MyDuoSummary>)
          if (d.album.status == DuoStatus.accepted) d,
      ];
      final avatar = (results[1] as Map?)?['profile_photo_url'] as String?;
      return (duos, avatar);
    } catch (_) {
      // "Duo" still opens — just an empty list to start one from scratch.
      return (<MyDuoSummary>[], null);
    }
  }

  void _openGroup() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const GroupPostScreen()),
    );
  }

  void _openDuo(MyDuoSummary d) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            DuoPostScreen(albumId: d.album.id, otherName: d.otherName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PV2.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _pickingDuo
                        ? setState(() => _pickingDuo = false)
                        : Navigator.of(context).pop(),
                    icon: Icon(
                      _pickingDuo
                          ? Icons.arrow_back_ios_new_rounded
                          : Icons.close_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Text(
                _pickingDuo ? 'Post to which Duo?' : 'Create',
                style: PV2.display(size: 28),
              ),
            ),
            Expanded(child: _pickingDuo ? _duoList() : _choices()),
          ],
        ),
      ),
    );
  }

  Widget _choices() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Expanded(
            child: _bigChoice(
              icon: Icons.favorite_rounded,
              title: 'Duo',
              subtitle: 'A memory with one person',
              colors: const [Color(0xFF1C3B57), Color(0xFF0E1A26)],
              onTap: () => setState(() => _pickingDuo = true),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _bigChoice(
              icon: Icons.groups_rounded,
              title: 'Group',
              subtitle: 'Post to one of your groups',
              colors: const [Color(0xFF3B1F4F), Color(0xFF170E22)],
              onTap: _openGroup,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _bigChoice(
              icon: Icons.masks_rounded,
              title: 'Anon',
              subtitle: 'Post anonymously — camera opens',
              colors: const [Color(0xFF26282E), Color(0xFF111215)],
              // Straight into the anon CAMERA (explicit request,
              // 2026-10-03: "when opened anon in plus mark the camera
              // shall open for anon posting ... and then posting it") —
              // same composer the Anon tab's own camera opens, with
              // Anonymous preselected. It used to open MyAnonPostsScreen
              // (the read-only list of posts already made), which is still
              // reachable from the profile's own anon card.
              // The navigator is captured BEFORE the pop: popping
              // deactivates this card's own context, so looking it up
              // afterwards finds nothing to push onto.
              onTap: () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(
                  openCameraRoute(isAnonymous: true, lockToAnonPost: true),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _bigChoice({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: PV2.hairlineBright),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(icon, size: 40, color: Colors.white),
            const SizedBox(height: 14),
            Text(title, style: PV2.display(size: 30)),
            const SizedBox(height: 4),
            Text(subtitle, style: PV2.body(size: 14, color: PV2.inkBio)),
          ],
        ),
      ),
    );
  }

  Widget _duoList() {
    return FutureBuilder<(List<MyDuoSummary>, String?)>(
      future: _duoData,
      builder: (context, snapshot) {
        final duos = snapshot.data?.$1 ?? const <MyDuoSummary>[];
        final avatar = snapshot.data?.$2;
        final stillLoading = !snapshot.hasData;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // Brief, inline — this fetch usually finishes before the user
            // even gets here (started the instant the screen mounted, on
            // the PREVIOUS "Create" step), so this spinner is rarely seen.
            if (stillLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            for (final d in duos)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                leading: FusedAvatars(
                  myUrl: avatar,
                  otherUrl: d.otherAvatarUrl,
                  otherName: d.otherName,
                  size: 40,
                  ring: PV2.page,
                ),
                title: Text(
                  d.otherName,
                  style: PV2.body(size: 16, weight: FontWeight.w700),
                ),
                subtitle: Text(
                  _memories(d.privateCount + d.mutualCount),
                  style: PV2.body(size: 12.5, color: PV2.inkByline),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white54,
                ),
                onTap: () => _openDuo(d),
              ),
            _newDuoTile(),
          ],
        );
      },
    );
  }

  Widget _newDuoTile() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        width: 66,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PV2.accent.withValues(alpha: 0.5)),
        ),
        child: const Icon(
          Icons.person_add_alt_1_rounded,
          color: PV2.accent,
          size: 20,
        ),
      ),
      title: Text(
        'Start a new Duo',
        style: PV2.body(size: 16, weight: FontWeight.w700, color: PV2.accent),
      ),
      onTap: () async {
        Navigator.of(context).pop();
        await widget.onStartNewDuo();
      },
    );
  }
}
