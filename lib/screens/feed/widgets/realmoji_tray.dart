import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants.dart';
import '../../../services/reaction_preset_service.dart' show ReactionPreset, ReactionPresetCategory, ReactionPresetCategoryWire;
import '../../../services/realmoji_service.dart';
import 'reaction_preset_tray.dart' show PresetAvatar;

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

class RealmojiTray extends StatefulWidget {
  const RealmojiTray({
    super.key,
    required this.category,
    required this.onSelect,
    required this.onCaptureNeeded,
  });

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

  @override
  State<RealmojiTray> createState() => _RealmojiTrayState();
}

class _RealmojiTrayState extends State<RealmojiTray> {
  Map<RealmojiType, String>? _saved;
  String? _error;

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
            child: _error != null
                ? _InlineErrorChip(onRetry: _load)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < RealmojiType.values.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        _RealmojiChip(
                          type: RealmojiType.values[i],
                          savedUrl: _saved?[RealmojiType.values[i]],
                          loading: _saved == null,
                          category: widget.category,
                          onTap: () => _tap(RealmojiType.values[i]),
                        ),
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
        child: widget.savedUrl != null
            ? PresetAvatar(
                preset: ReactionPreset(
                  id: 'realmoji:${widget.type.wire}',
                  category: widget.category,
                  emoji: widget.type.glyph,
                  photoUrl: widget.savedUrl,
                  createdAt: DateTime.now(),
                ),
                size: 48,
              )
            : Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: Text(widget.type.glyph, style: const TextStyle(fontSize: 22)),
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
