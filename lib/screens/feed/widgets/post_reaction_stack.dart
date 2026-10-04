import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/realmoji_service.dart';

// ---------------------------------------------------------------------------
// PostReactionStack — the overlapping reactor faces that sit bottom-left on a
// photo, with a tap-through list of who reacted with what.
//
// The Anon feed has had this for a while (_OnPhotoReactionStack), and it is
// the only place in the app where you can see other people's RealMoji
// reactions at a glance. Profile posts and group-profile posts had no
// equivalent — the reactions existed, were counted, and were simply not
// visible on the post.
//
// This is the NAMED version of that widget, so it differs from the anon one
// in the way it must: an anonymous post can only ever show emoji and counts
// (see RealmojiService.fetchAnonCounts' own doc on why no user_id can reach
// that feed), while here the reactors are ordinary named people and the
// sheet says who they are.
//
// Self-loading: it takes a post id and fetches its own reactors, because the
// two screens that use it build their cards from different models and
// neither carries reaction data. Fails soft to nothing — a post with no
// reactions and a post whose reactions failed to load both render as an
// absent stack rather than an error.
// ---------------------------------------------------------------------------

class PostReactionStack extends StatefulWidget {
  const PostReactionStack({
    super.key,
    this.postId,
    this.groupPostId,
  }) : assert(postId != null || groupPostId != null,
            'needs a post to load reactions for');

  /// A `posts` row. Mutually exclusive with [groupPostId].
  final String? postId;

  /// A `group_posts` row — the group profile's own post table.
  final String? groupPostId;

  @override
  State<PostReactionStack> createState() => _PostReactionStackState();
}

class _PostReactionStackState extends State<PostReactionStack> {
  List<RealmojiReaction> _reactions = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PostReactionStack old) {
    super.didUpdateWidget(old);
    if (old.postId != widget.postId ||
        old.groupPostId != widget.groupPostId) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final rows = await RealmojiService.instance.fetchReactors(
        widget.postId,
        groupPostId: widget.groupPostId,
      );
      if (!mounted) return;
      setState(() {
        _reactions = rows;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _openList() {
    if (_reactions.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ReactorSheet(reactions: _reactions),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to show until something has actually reacted. Deliberately
    // renders NOTHING rather than an empty pill: this sits on top of
    // someone's photo, and a permanent chip there is clutter on the many
    // posts with no reactions yet.
    if (!_loaded || _reactions.isEmpty) return const SizedBox.shrink();

    final withPhotos =
        _reactions.where((r) => (r.selfieUrl ?? '').isNotEmpty).toList();
    final chips = withPhotos.take(3).toList();

    return GestureDetector(
      onTap: _openList,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Negative overlap via Transform.translate — Padding and
          // Container.margin assert on negative values outright.
          if (chips.isNotEmpty)
            for (var i = 0; i < chips.length; i++)
              Transform.translate(
                offset: Offset(i == 0 ? 0 : -9.0 * i, 0),
                child: _FaceChip(reaction: chips[i]),
              )
          else
            // Every reactor has retaken their RealMoji away (or reacted
            // before RealMoji existed): show the glyphs so the stack still
            // agrees with the count beside it.
            for (var i = 0; i < _reactions.take(3).length; i++)
              Transform.translate(
                offset: Offset(i == 0 ? 0 : -7.0 * i, 0),
                child: _GlyphChip(glyph: _reactions[i].emojiType.glyph),
              ),
          const SizedBox(width: 6),
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Center(
              child: Text(
                '${_reactions.length}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceChip extends StatelessWidget {
  const _FaceChip({required this.reaction});
  final RealmojiReaction reaction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  offset: Offset(0, 2),
                  blurRadius: 6,
                  color: Color(0x3D000000),
                ),
              ],
            ),
            child: ClipOval(
              child: CachedNetworkImage(
                memCacheWidth: 90,
                imageUrl: reaction.selfieUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) =>
                    const ColoredBox(color: Color(0xFF2A2A32)),
              ),
            ),
          ),
          // The emoji they reacted WITH, tucked on the corner of their
          // face — the face alone says who, not what.
          Positioned(
            right: -2,
            bottom: -2,
            child: Text(
              reaction.emojiType.glyph,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlyphChip extends StatelessWidget {
  const _GlyphChip({required this.glyph});
  final String glyph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFF2F2F4),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(offset: Offset(0, 2), blurRadius: 6, color: Color(0x3D000000)),
        ],
      ),
      child: Text(glyph, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// Who reacted, and with what. Named people — this is not the anon feed.
class _ReactorSheet extends StatelessWidget {
  const _ReactorSheet({required this.reactions});
  final List<RealmojiReaction> reactions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF16151A),
            border: Border.all(color: const Color(0x1FFFFFFF)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'REACTIONS · ${reactions.length}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.12 * 10.5,
                  color: const Color(0xFF9A9AA5),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: reactions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = reactions[i];
                    return Row(
                      children: [
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: (r.selfieUrl ?? '').isEmpty
                              ? Container(
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF2A2A32),
                                  ),
                                  child: Text(
                                    r.emojiType.glyph,
                                    style: const TextStyle(fontSize: 17),
                                  ),
                                )
                              : ClipOval(
                                  child: CachedNetworkImage(
                                    memCacheWidth: 114,
                                    imageUrl: r.selfieUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, _, _) => const ColoredBox(
                                      color: Color(0xFF2A2A32),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            r.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFF2F2F4),
                            ),
                          ),
                        ),
                        Text(
                          r.emojiType.glyph,
                          style: const TextStyle(fontSize: 19),
                        ),
                      ],
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
