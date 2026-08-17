import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants.dart';
import '../../../services/reaction_preset_service.dart';
import '../../../widgets/reaction_picker_popup.dart' show kQuickReactionEmojis, kQuickReactionColors;

// ---------------------------------------------------------------------------
// PresetAvatar — the shared visual for one saved reaction preset: a
// circular selfie with a small emoji badge overlaid at its bottom-right
// corner (BeReal RealMoji style) for Everyone presets, or a plain emoji
// centered on a dark circle for Anonymous presets (no photo, ever — see
// reaction_preset_service.dart's category rule). Used by both the
// quick-pick tray below AND the full library screen
// (reaction_library_screen.dart) so the two never visually drift apart.
// ---------------------------------------------------------------------------

class PresetAvatar extends StatelessWidget {
  const PresetAvatar({super.key, required this.preset, this.size = 52});
  final ReactionPreset preset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photoUrl = preset.photoUrl;
    if (photoUrl == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cardSurface,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Center(child: Text(preset.emoji, style: TextStyle(fontSize: size * 0.46))),
      );
    }

    final badgeSize = size * 0.42;
    // Extra room on the right/bottom so the emoji badge can overhang the
    // photo circle's edge without being clipped by this widget's own bounds.
    return SizedBox(
      width: size + badgeSize * 0.3,
      height: size + badgeSize * 0.3,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: CachedNetworkImage(
              imageUrl: photoUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(color: AppColors.cardSurface),
              errorWidget: (context, url, error) => Container(
                color: AppColors.cardSurface,
                child: Icon(Icons.face_retouching_natural, color: AppColors.textMuted, size: size * 0.4),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0D0D12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.25),
              ),
              child: Center(
                child: Text(preset.emoji, style: TextStyle(fontSize: badgeSize * 0.55)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ReactionPresetTray — Part 3 of the reaction-preset feature: the horizontal
// glass reaction bar. Shown instead of a fresh camera capture when the user
// taps a post's reaction-entry badge, for BOTH categories (Anonymous routes
// through this exact same widget now — see PostReactionCorner's call sites
// in photo_post_card.dart/text_post_card.dart — rather than a separate
// fixed-emoji popup).
//
// Two groups, left to right:
//   1. Plain/standard emoji (kQuickReactionEmojis) — always rendered
//      immediately, never gated on the presets fetch, so a viewer can
//      quick-react even with zero saved presets or a failed preset load.
//   2. The viewer's own saved presets for this category — a genuine async
//      segment (shimmer while loading, compact inline retry on error,
//      absent entirely when empty) appended after a divider, never a
//      full-bar takeover the way an earlier version of this widget did.
// Then a trailing "+" bolt to jump into the Part 2 add flow.
//
// Selecting a plain emoji reuses the exact same onSelect(ReactionPreset)
// contract the tray already has for real presets — see _selectPlain below —
// so PostReactions.selectPreset (post_card_shared.dart) needs no changes at
// all to support it; its existing `photoUrl == null` branch already does
// the right thing (a plain emoji reaction, no camera, no upload).
//
// Reads ReactionPresetService's in-memory cache first (instant, no loading
// flash on the 2nd+ post a viewer reacts to in a session) and only shows
// the loading shimmer on a genuine cold fetch.
// ---------------------------------------------------------------------------

class ReactionPresetTray extends StatefulWidget {
  const ReactionPresetTray({
    super.key,
    required this.category,
    required this.onSelect,
    required this.onAddNew,
  });

  final ReactionPresetCategory category;

  /// Called with the tapped preset (or a synthetic one for a plain emoji —
  /// see _selectPlain) — applying it to the post (the upsert itself) is the
  /// caller's job, same division of responsibility FaceReactionCapture uses
  /// (this widget only picks, it doesn't write).
  final ValueChanged<ReactionPreset> onSelect;

  /// "+ add new" — jumps straight into the Part 2 add flow
  /// (reaction_library_screen.dart's runAddPresetFlow), always shown as the
  /// trailing option.
  final VoidCallback onAddNew;

  @override
  State<ReactionPresetTray> createState() => _ReactionPresetTrayState();
}

class _ReactionPresetTrayState extends State<ReactionPresetTray> {
  List<ReactionPreset>? _presets;
  String? _error;

  @override
  void initState() {
    super.initState();
    final cached = ReactionPresetService.instance.cached(widget.category);
    if (cached != null) {
      _presets = cached;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final presets = await ReactionPresetService.instance.fetchPresets(widget.category);
      if (!mounted) return;
      setState(() => _presets = presets);
    } catch (e, st) {
      debugPrint('[ReactionPresetTray._load] fetchPresets(${widget.category}) failed: $e\n$st');
      if (!mounted) return;
      setState(() => _error = "Couldn't load your reactions.");
    }
  }

  /// A plain emoji tap is packaged as a throwaway preset (never persisted,
  /// never touches reaction_presets) purely so it can travel through the
  /// same onSelect(ReactionPreset) pipe real presets use — see this file's
  /// own doc comment above.
  void _selectPlain(String emoji) {
    HapticFeedback.mediumImpact();
    widget.onSelect(ReactionPreset(
      id: 'plain:$emoji',
      category: widget.category,
      emoji: emoji,
      photoUrl: null,
      createdAt: DateTime.now(),
    ));
  }

  void _selectPreset(ReactionPreset preset) {
    HapticFeedback.mediumImpact();
    widget.onSelect(preset);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
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
                for (int i = 0; i < kQuickReactionEmojis.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  _ReactionChip(
                    onTap: () => _selectPlain(kQuickReactionEmojis[i]),
                    child: _PlainEmojiOption(
                      emoji: kQuickReactionEmojis[i],
                      color: kQuickReactionColors[i],
                    ),
                  ),
                ],
                ..._presetsSegment(),
                const SizedBox(width: 10),
                _AddNewOption(onTap: widget.onAddNew),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _presetsSegment() {
    final error = _error;
    if (error != null) {
      return [
        const SizedBox(width: 10),
        const _DividerBar(),
        const SizedBox(width: 10),
        _InlineErrorChip(onRetry: _load),
      ];
    }
    final presets = _presets;
    if (presets == null) {
      return const [
        SizedBox(width: 10),
        _DividerBar(),
        SizedBox(width: 10),
        _LoadingRow(),
      ];
    }
    if (presets.isEmpty) return const [];
    return [
      const SizedBox(width: 10),
      const _DividerBar(),
      const SizedBox(width: 10),
      for (int i = 0; i < presets.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        _ReactionChip(
          onTap: () => _selectPreset(presets[i]),
          child: PresetAvatar(preset: presets[i], size: 48),
        ),
      ],
    ];
  }
}

/// Shared tap-bounce (scale + haptic) wrapper for any reaction option —
/// plain emoji or saved preset alike — so bounce state is owned per-chip
/// instead of a single int index into one homogeneous list (which stopped
/// working once this tray started mixing two differently-sized groups).
class _ReactionChip extends StatefulWidget {
  const _ReactionChip({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<_ReactionChip> {
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
    return GestureDetector(
      onTap: _tap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _bouncing ? 1.18 : 1.0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}

/// Visually distinct from PresetAvatar (neutral cardSurface/photo) —
/// tinted with the same kQuickReactionColors ReactionPickerPopup already
/// uses elsewhere, so "standard emoji" reads as its own group at a glance.
class _PlainEmojiOption extends StatelessWidget {
  const _PlainEmojiOption({required this.emoji, required this.color});
  final String emoji;
  final Color color;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
    );
  }
}

class _AddNewOption extends StatelessWidget {
  const _AddNewOption({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
        ),
        child: const Icon(Icons.bolt, color: Colors.white70, size: 22),
      ),
    );
  }
}

class _DividerBar extends StatelessWidget {
  const _DividerBar();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.18));
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.cardSurface,
      highlightColor: AppColors.cardSurface.withValues(alpha: 0.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < 2; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact inline segment — a small tappable error glyph, not a full-bar
/// takeover, since the plain-emoji group before it is always usable
/// regardless of whether the preset fetch succeeded.
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
