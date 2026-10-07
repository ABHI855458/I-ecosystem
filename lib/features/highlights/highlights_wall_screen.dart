import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/highlight_service.dart';
import '../profile_v2/profile_v2_tokens.dart';
import 'highlight_editor_screen.dart';
import 'highlight_models.dart';
import 'highlight_story_viewer.dart';
import 'polaroid_cover.dart';

// ---------------------------------------------------------------------------
// The Wall — every polaroid you may see, pinned three across at slight
// angles. The place the feed's pile opens into, and the place to pin yours.
//
// Order: a dashed "Pin yours" first, then friends' polaroids you haven't
// opened (taped), then your own (labelled "You"), then the ones you've
// already watched (dimmed). Nothing is blurred.
// ---------------------------------------------------------------------------

/// One at a time, like every other pushed surface in the app.
bool _wallOpen = false;

Future<void> openHighlightsWall(BuildContext context) async {
  if (_wallOpen) return;
  _wallOpen = true;
  try {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(builder: (_) => const HighlightsWallScreen()),
    );
  } finally {
    _wallOpen = false;
  }
}

/// The Wall's order for [all]. Pure, so it can be tested without a device.
List<Highlight> orderForWall(
  List<Highlight> all, {
  required bool Function(Highlight) isNew,
  required bool Function(Highlight) isMine,
}) {
  final mine = [for (final h in all) if (isMine(h)) h];
  final theirs = sortForWall(
    [for (final h in all) if (!isMine(h)) h],
    isNew: isNew,
  );
  return [
    for (final h in theirs) if (isNew(h)) h,
    ...mine,
    for (final h in theirs) if (!isNew(h)) h,
  ];
}

class HighlightsWallScreen extends StatefulWidget {
  const HighlightsWallScreen({super.key});

  @override
  State<HighlightsWallScreen> createState() => _HighlightsWallScreenState();
}

class _HighlightsWallScreenState extends State<HighlightsWallScreen> {
  List<Highlight>? _all;
  bool _failed = false;
  int _loadedVersion = -1;

  @override
  void initState() {
    super.initState();
    HighlightService.instance.addListener(_onServiceChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    HighlightService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (HighlightService.instance.version != _loadedVersion) {
      unawaited(_load());
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final version = HighlightService.instance.version;
    try {
      await HighlightService.instance.ready();
      final all = await HighlightService.instance.fetchWall();
      if (!mounted) return;
      setState(() {
        _all = all;
        _failed = false;
        _loadedVersion = version;
      });
    } catch (e) {
      debugPrint('[HighlightsWall] load failed: $e');
      if (mounted) setState(() => _failed = _all == null);
    }
  }

  void _open(Highlight h) {
    unawaited(
      openHighlightStory(
        context,
        highlights: [h],
        heroTag: _heroTag(h),
        onEdit: HighlightService.instance.isMine(h)
            ? (h) => unawaited(openHighlightEditor(context, existing: h))
            : null,
      ),
    );
  }

  String _heroTag(Highlight h) => 'highlight-wall-${h.id}';

  @override
  Widget build(BuildContext context) {
    final svc = HighlightService.instance;
    final all = _all;
    final ordered = all == null
        ? const <Highlight>[]
        : orderForWall(all, isNew: svc.isNew, isMine: svc.isMine);

    return Scaffold(
      backgroundColor: PV2.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('The Wall', style: PV2.display(size: 27)),
                        const SizedBox(height: 2),
                        Text(
                          "your friends' polaroids",
                          style: PV2.body(size: 12.5, color: PV2.inkMember),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: all == null && !_failed
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: PV2.accent,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: PV2.accent,
                      backgroundColor: PV2.raised,
                      onRefresh: _load,
                      child: _grid(ordered),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<Highlight> ordered) {
    final svc = HighlightService.instance;
    return LayoutBuilder(
      builder: (context, box) {
        const pad = 16.0;
        const gap = 10.0;
        final cellW = (box.maxWidth - pad * 2 - gap * 2) / 3;
        final polaroidW = cellW * 0.9;
        final slotH = polaroidMaxHeightFor(polaroidW);
        final cellH = slotH + 44;
        final empty = ordered.isEmpty;
        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(
            pad,
            16,
            pad,
            MediaQuery.paddingOf(context).bottom + 28,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: gap,
            mainAxisSpacing: 6,
            childAspectRatio: cellW / cellH,
          ),
          // +1 for "Pin yours"; +1 more for the note when there is nothing
          // else on the wall yet.
          itemCount: ordered.length + 1 + (empty ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == 0) {
              return _cell(
                slotHeight: slotH,
                polaroid: PolaroidAddTile(
                  width: polaroidW,
                  label: 'Pin yours',
                  tilt: -0.035,
                  onTap: () => unawaited(openHighlightEditor(context)),
                ),
                caption: null,
              );
            }
            if (empty) {
              return Padding(
                padding: const EdgeInsets.only(top: 22, left: 4),
                child: Text(
                  _failed
                      ? "Couldn't load the wall. Pull down to try again."
                      : 'Nothing pinned yet. Be the first.',
                  style: PV2.body(size: 12.5, color: PV2.inkMember),
                ),
              );
            }
            final h = ordered[i - 1];
            final mine = svc.isMine(h);
            final fresh = svc.isNew(h);
            return _cell(
              slotHeight: slotH,
              polaroid: PolaroidCover(
                width: polaroidW,
                title: h.title,
                imageUrl: h.coverUrl,
                aspect: h.coverAspect,
                isVideo: h.coverIsVideo,
                tilt: polaroidTiltFor(h.id),
                isNew: fresh,
                dimmed: !fresh && !mine,
                heroTag: _heroTag(h),
                onTap: () => _open(h),
                onLongPress: mine
                    ? () => unawaited(openHighlightEditor(context, existing: h))
                    : null,
              ),
              caption: _WallCaption(
                name: mine ? 'You' : h.ownerName,
                avatarUrl: h.ownerAvatarUrl,
                bright: fresh || mine,
              ),
            );
          },
        );
      },
    );
  }

  /// A polaroid keeps its photo's shape, so they differ in height. Each
  /// sits at the bottom of a slot as tall as the tallest can be, which
  /// keeps the names under them on one line across the row.
  Widget _cell({
    required double slotHeight,
    required Widget polaroid,
    required Widget? caption,
  }) {
    return Column(
      children: [
        const SizedBox(height: 10),
        SizedBox(
          height: slotHeight,
          child: Align(alignment: Alignment.bottomCenter, child: polaroid),
        ),
        const SizedBox(height: 9),
        ?caption,
      ],
    );
  }
}

class _WallCaption extends StatelessWidget {
  const _WallCaption({
    required this.name,
    required this.avatarUrl,
    required this.bright,
  });

  final String name;
  final String? avatarUrl;
  final bool bright;

  @override
  Widget build(BuildContext context) {
    final has = avatarUrl != null && avatarUrl!.isNotEmpty;
    return Opacity(
      opacity: bright ? 1 : 0.55,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 8,
            backgroundColor: const Color(0xFF26262B),
            backgroundImage: has ? CachedNetworkImageProvider(avatarUrl!) : null,
            child: has
                ? null
                : Text(
                    name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: PV2.body(size: 8.5, weight: FontWeight.w800),
                  ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              name.isEmpty ? 'someone' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PV2.body(
                size: 11.5,
                weight: FontWeight.w600,
                color: PV2.inkBio,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
