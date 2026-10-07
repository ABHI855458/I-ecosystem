import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/highlight_service.dart';
import 'highlight_editor_screen.dart';
import 'highlight_models.dart';
import 'highlight_story_viewer.dart';
import 'polaroid_cover.dart';

// ---------------------------------------------------------------------------
// The polaroid row on a profile — under the name, above Duos | Groups.
//
// On your own profile it always shows, starting with a dashed "+ New". On
// someone else's it shows only when they have highlights you may see (they
// put you in their Friends circle); otherwise it takes no space at all.
// ---------------------------------------------------------------------------

class HighlightsRow extends StatefulWidget {
  const HighlightsRow({
    super.key,
    required this.userId,
    required this.isMe,
    this.polaroidWidth = 92,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  /// Whose highlights. Null while the profile is still resolving its id.
  final String? userId;
  final bool isMe;
  final double polaroidWidth;
  final EdgeInsets padding;

  @override
  State<HighlightsRow> createState() => _HighlightsRowState();
}

class _HighlightsRowState extends State<HighlightsRow> {
  List<Highlight>? _items;
  int _loadedVersion = -1;

  @override
  void initState() {
    super.initState();
    HighlightService.instance.addListener(_onServiceChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(HighlightsRow old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) unawaited(_load());
  }

  @override
  void dispose() {
    HighlightService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    // A save or delete: fetch again. A "seen": the tape just comes off.
    if (HighlightService.instance.version != _loadedVersion) {
      unawaited(_load());
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final id = widget.userId;
    if (id == null) return;
    final version = HighlightService.instance.version;
    try {
      await HighlightService.instance.ready();
      final items = await HighlightService.instance.fetchForUser(id);
      if (!mounted || id != widget.userId) return;
      setState(() {
        _items = items;
        _loadedVersion = version;
      });
    } catch (e) {
      debugPrint('[HighlightsRow] load failed: $e');
      if (mounted && _items == null) setState(() => _items = const []);
    }
  }

  void _open(int index) {
    final items = _items!;
    unawaited(
      openHighlightStory(
        context,
        highlights: items,
        initialIndex: index,
        heroTag: _heroTag(items[index]),
        onEdit: widget.isMe ? _edit : null,
      ),
    );
  }

  void _edit(Highlight h) {
    unawaited(openHighlightEditor(context, existing: h));
  }

  String _heroTag(Highlight h) => 'highlight-row-${h.id}';

  @override
  Widget build(BuildContext context) {
    final items = _items;
    // Someone else's: nothing until there is something to show.
    if (!widget.isMe && (items == null || items.isEmpty)) {
      return const SizedBox.shrink();
    }
    final w = widget.polaroidWidth;
    final svc = HighlightService.instance;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: SizedBox(
        // Tall enough for a portrait polaroid (they keep their photo's
        // shape), plus room for the tape and the tilt.
        height: polaroidMaxHeightFor(w) + 24,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: widget.padding.copyWith(top: 12, bottom: 12),
          itemCount: (items?.length ?? 0) + (widget.isMe ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (context, i) {
            // Center: a horizontal list hands every child its full
            // height, which would stretch a polaroid of any other shape.
            if (widget.isMe && i == 0) {
              return Center(
                child: PolaroidAddTile(
                  width: w,
                  label: 'New',
                  tilt: -0.03,
                  onTap: () => unawaited(openHighlightEditor(context)),
                ),
              );
            }
            final index = widget.isMe ? i - 1 : i;
            final h = items![index];
            final fresh = svc.isNew(h);
            return Center(
              child: PolaroidCover(
                width: w,
                title: h.title,
                imageUrl: h.coverUrl,
                aspect: h.coverAspect,
                isVideo: h.coverIsVideo,
                tilt: polaroidTiltFor(h.id),
                isNew: fresh,
                heroTag: _heroTag(h),
                onTap: () => _open(index),
                onLongPress: widget.isMe ? () => _edit(h) : null,
              ),
            );
          },
        ),
      ),
    );
  }
}
