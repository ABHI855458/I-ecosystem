import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants.dart';
import '../../../services/reaction_preset_service.dart' show ReactionPreset, ReactionPresetCategory, ReactionPresetCategoryWire;
import '../../../services/realmoji_service.dart';

// ---------------------------------------------------------------------------
// RealmojiTray — REPLACES ReactionPresetTray as PostReactionCorner's popup
// content (see post_card_shared.dart's _PostReactionCornerState._show()).
// Same floating-glass-bar shell/positioning as the old tray (untouched —
// PostReactionCorner itself wasn't rewritten), but the content is now the
// 6 fixed RealmojiType slots instead of an arbitrary fetched preset list —
// no "+ add new" bolt, since there's nothing arbitrary left to add.
//
// Reuses PresetAvatar (reaction_preset_tray.dart) unchanged for the saved-
// selfie circular thumbnail — that widget already just renders a
// ReactionPreset's photoUrl+emoji, and RealMoji's data maps onto that DTO
// shape 1:1 (id/category/emoji=glyph/photoUrl=image_url/createdAt).
// ---------------------------------------------------------------------------

/// The default like: a plain heart, saved as an ordinary emoji reaction.
const kHeartEmoji = '❤️';

class RealmojiTray extends StatefulWidget {
  const RealmojiTray({
    super.key,
    required this.category,
    required this.onSelect,
    required this.onCaptureNeeded,
    this.onEmoji,
    this.onHeart,
    this.heartLiked = false,
  });

  /// The default ❤️ like, always first in the tray and needing no selfie
  /// ("give a default heart button to like the post"). Null hides it.
  final VoidCallback? onHeart;

  /// Whether the viewer has already hearted this post (filled heart).
  final bool heartLiked;

  final ReactionPresetCategory category;

  /// Called for a slot that already has a saved selfie — instant react,
  /// no camera. Packaged as a ReactionPreset so PostReactions.selectPreset's
  /// existing onSelect(ReactionPreset) contract needs no signature change.
  final ValueChanged<ReactionPreset> onSelect;

  /// Called for a slot with no saved selfie yet — the tray has no postId
  /// of its own (PostReactionCorner only gives it `category`), so the
  /// actual capture-then-react flow is the caller's job, same division of
  /// responsibility the old tray's onAddNew had.
  final ValueChanged<RealmojiType> onCaptureNeeded;

  /// Plain-emoji reaction picked from the tray's "+" mode.
  ///
  /// The tray's RealMoji slots each need a selfie; the "+" flips this SAME
  /// tray over to ordinary emoji, which react instantly and need no camera.
  /// Null hides the "+" entirely — a surface that has no emoji path should
  /// not advertise one.
  final ValueChanged<String>? onEmoji;

  @override
  State<RealmojiTray> createState() => _RealmojiTrayState();
}

class _RealmojiTrayState extends State<RealmojiTray> {
  Map<RealmojiType, String>? _saved;
  String? _error;

  /// "+" mode: the tray shows plain emoji instead of RealMoji slots.
  /// Tapping "+" again returns to the RealMojis, so one control toggles
  /// between the two rather than opening a second, separate picker.
  bool _emojiMode = false;

  /// The plain-emoji set offered in "+" mode. Deliberately the same glyphs
  /// the RealmojiTypes already use, so the two modes read as two ways to
  /// send the same reaction — one with your face, one without.
  static const _emojis = <String>[
    '👍', '❤️', '😂', '😮', '🔥', '😍',
    '😎', '😭', '👏', '😉', '🥳', '💯',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final saved = await RealmojiService.instance.savedSelfies(feedScope: widget.category.wire);
      if (!mounted) return;
      setState(() => _saved = saved);
    } catch (e, st) {
      debugPrint('[RealmojiTray._load] savedSelfies(${widget.category}) failed: $e\n$st');
      if (!mounted) return;
      setState(() => _error = "Couldn't load your RealMojis.");
    }
  }

  /// Captured RealMojis first, then the rest in their declared order.
  ///
  /// There are 18 types now and only a few are ever captured, so the ones
  /// that react INSTANTLY were scattered among a dozen that open the camera
  /// instead — you had to hunt for your own. Explicit request: "the saved
  /// reactions shall appear first". Order within each group is stable
  /// (RealmojiType's declaration order), so nothing reshuffles under a
  /// finger between opens.
  List<RealmojiType> get _ordered {
    final saved = _saved;
    if (saved == null || saved.isEmpty) return RealmojiType.values;
    return [
      ...RealmojiType.values.where(saved.containsKey),
      ...RealmojiType.values.where((t) => !saved.containsKey(t)),
    ];
  }

  void _tap(RealmojiType type) {
    final url = _saved?[type];
    if (url != null) {
      HapticFeedback.mediumImpact();
      widget.onSelect(ReactionPreset(
        id: 'realmoji:${type.wire}',
        category: widget.category,
        emoji: type.glyph,
        photoUrl: url,
        createdAt: DateTime.now(),
      ));
    } else {
      HapticFeedback.selectionClick();
      widget.onCaptureNeeded(type);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Default ❤️ first: a like needs no selfie, so it
                      // works even when the RealMojis failed to load.
                      if (widget.onHeart != null) ...[
                        _HeartChip(
                          liked: widget.heartLiked,
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            widget.onHeart!();
                          },
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (_error != null)
                        _InlineErrorChip(onRetry: _load)
                      else ...[
                      // The "+" toggle leads, so it stays in the same place
                      // whichever mode the tray is in.
                      if (widget.onEmoji != null) ...[
                        _ModeToggleChip(
                          emojiMode: _emojiMode,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _emojiMode = !_emojiMode);
                          },
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (_emojiMode)
                        for (var i = 0; i < _emojis.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          _PlainEmojiChip(
                            emoji: _emojis[i],
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              widget.onEmoji!(_emojis[i]);
                            },
                          ),
                        ]
                      else
                        for (var i = 0; i < _ordered.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          _RealmojiChip(
                            type: _ordered[i],
                            savedUrl: _saved?[_ordered[i]],
                            loading: _saved == null,
                            category: widget.category,
                            onTap: () => _tap(_ordered[i]),
                          ),
                        ],
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _RealmojiChip extends StatefulWidget {
  const _RealmojiChip({
    required this.type,
    required this.savedUrl,
    required this.loading,
    required this.category,
    required this.onTap,
  });

  final RealmojiType type;
  final String? savedUrl;
  final bool loading;
  final ReactionPresetCategory category;
  final VoidCallback onTap;

  @override
  State<_RealmojiChip> createState() => _RealmojiChipState();
}

class _RealmojiChipState extends State<_RealmojiChip> {
  bool _bouncing = false;

  void _tap() {
    setState(() => _bouncing = true);
    widget.onTap();
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => _bouncing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return Shimmer.fromColors(
        baseColor: AppColors.cardSurface,
        highlightColor: AppColors.cardSurface.withValues(alpha: 0.5),
        child: Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTap: _tap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _bouncing ? 1.18 : 1.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.elasticOut,
        // Variant 1A, same as the RealMoji library grid and the anon
        // reaction strip: circular photo, ring floating outside it, and the
        // emoji sitting directly ON the photo's bottom-right with NO
        // background plate. PresetAvatar's own badge is a small glyph in a
        // dark disc clipped to the circle's edge — the same treatment that
        // made the badge unreadable in the library ("see here the emoji how
        // it's looking — it shall look like the 1A design").
        child: _Chip1A(
          size: 48,
          glyph: widget.type.glyph,
          photoUrl: widget.savedUrl,
        ),
      ),
    );
  }
}

/// The tray's default like. Same 48px circle as the RealMoji chips; filled
/// pink when the viewer has already liked the post, outlined otherwise.
class _HeartChip extends StatefulWidget {
  const _HeartChip({required this.liked, required this.onTap});
  final bool liked;
  final VoidCallback onTap;

  @override
  State<_HeartChip> createState() => _HeartChipState();
}

class _HeartChipState extends State<_HeartChip> {
  bool _bouncing = false;

  void _tap() {
    setState(() => _bouncing = true);
    widget.onTap();
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => _bouncing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFFF4D6D);
    return GestureDetector(
      onTap: _tap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _bouncing ? 1.18 : 1.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.elasticOut,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.liked ? pink.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.10),
            border: Border.all(
              color: widget.liked ? pink : Colors.white.withValues(alpha: 0.28),
              width: 1.5,
            ),
          ),
          child: Icon(
            widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: widget.liked ? pink : Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _InlineErrorChip extends StatelessWidget {
  const _InlineErrorChip({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.errorRed.withValues(alpha: 0.14),
          border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.4)),
        ),
        child: Icon(Icons.refresh_rounded, color: AppColors.errorRed.withValues(alpha: 0.9), size: 20),
      ),
    );
  }
}


/// A tray chip in the handoff's variant 1A: photo, ring outside it, emoji
/// over the bottom-right with no plate. Shared shape with the RealMoji
/// library grid and the anon reaction strip so one RealMoji looks like
/// itself everywhere it appears.
class _Chip1A extends StatelessWidget {
  const _Chip1A({
    required this.size,
    required this.glyph,
    required this.photoUrl,
  });

  final double size;
  final String glyph;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final captured = photoUrl != null && photoUrl!.isNotEmpty;
    // 1A ratios, against the spec's 168px photo.
    const ringInset = 6 / 168;
    const badgeBox = 52 / 168;
    const badgeFont = 32 / 168;

    final inset = size * ringInset;
    final d = size - inset * 2;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: captured
                    ? AppColors.neonCyan
                    : AppColors.neonCyan.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
          ),
          SizedBox(
            width: d,
            height: d,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                    child: ClipOval(
                      child: captured
                          ? CachedNetworkImage(
              memCacheWidth: 1080,
                              imageUrl: photoUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Center(
                                child: Text(glyph, style: TextStyle(fontSize: d * 0.42)),
                              ),
                            )
                          : Center(
                              child: Text(glyph, style: TextStyle(fontSize: d * 0.46)),
                            ),
                    ),
                  ),
                ),
                // Only over a PHOTO — on an uncaptured slot the glyph is
                // already the whole chip, and a second copy of it in the
                // corner would just be the same information twice.
                if (captured)
                  Positioned(
                    right: -d * 0.04,
                    bottom: -d * 0.04,
                    width: d * badgeBox,
                    height: d * badgeBox,
                    child: Center(
                      child: Text(
                        glyph,
                        style: TextStyle(
                          fontSize: d * badgeFont * 1.15,
                          shadows: const [
                            Shadow(color: Color(0xCC000000), blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "+" / "×" control that flips [RealmojiTray] between its RealMoji
/// slots and plain emoji. One control, two modes — see RealmojiTray.onEmoji.
class _ModeToggleChip extends StatelessWidget {
  const _ModeToggleChip({required this.emojiMode, required this.onTap});

  final bool emojiMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: emojiMode ? 0.26 : 0.12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
        ),
        child: Icon(
          emojiMode ? Icons.close_rounded : Icons.add_rounded,
          size: 24,
          color: Colors.white.withValues(alpha: 0.95),
        ),
      ),
    );
  }
}

/// A plain-emoji slot in the tray's "+" mode. No selfie, no camera — taps
/// react immediately.
class _PlainEmojiChip extends StatelessWidget {
  const _PlainEmojiChip({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24, height: 1)),
      ),
    );
  }
}
