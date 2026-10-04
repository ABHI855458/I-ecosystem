import 'package:flutter/material.dart';

import '../features/composer/dual_photo_compositor.dart' show kFriendsPostAspect;

// ---------------------------------------------------------------------------
// Post size ("Tall" vs "Classic") is a POSTER-time choice about THAT post,
// not a viewer preference. Explicit correction after an earlier version of
// this made it a shared, persisted setting that restyled every post in the
// feed for every viewer: "only the poster gets to design the post size —
// who posts, not [everyone else] in the feed, they don't get to change it.
// Only the poster's option. Remove the Tall/Classic [toggle for viewers] —
// the post size the user posts at shall be [that post's] default."
//
// So there is no service, no shared_preferences, no ValueNotifier here any
// more — just the enum, the aspect it maps to, and a picker a COMPOSER
// screen owns as its own local state, threading the chosen value into that
// one post's own aspect_ratio column (posts.aspect_ratio / the group_posts
// twin added alongside this). Every feed card then renders each post at
// THAT post's own stored ratio — never a global.
// ---------------------------------------------------------------------------

enum PostSizePreset {
  /// 2:3 — the taller frame this app moved to. The default a post gets when
  /// its poster never touches the picker.
  big,

  /// 3:4 — the shorter frame posts used before that change. Kept as a real
  /// per-post choice, not a one-way migration.
  classic,
}

extension PostSizePresetAspect on PostSizePreset {
  /// Width / height, the value an AspectRatio takes directly.
  double get aspect => switch (this) {
        PostSizePreset.big => kFriendsPostAspect, // 2/3
        PostSizePreset.classic => 3 / 4,
      };

  String get label => switch (this) {
        PostSizePreset.big => 'Tall',
        PostSizePreset.classic => 'Classic',
      };
}

/// Reads a post's own stored `aspect_ratio` (posts/group_posts, text) back
/// into a display ratio. Values on record are inconsistent — some rows
/// predate this per-post model and carry a bare decimal ("0.8") or a literal
/// ratio ("4:5") from earlier code paths — so this parses either shape and
/// falls back to [kFriendsPostAspect] (this app's own default frame) for
/// anything unreadable or absent, rather than crashing a card over it.
double parseStoredAspectRatio(String? raw) {
  if (raw == null || raw.trim().isEmpty) return kFriendsPostAspect;
  final direct = double.tryParse(raw);
  if (direct != null && direct > 0) return direct;
  final parts = raw.split(':');
  if (parts.length == 2) {
    final w = double.tryParse(parts[0].trim());
    final h = double.tryParse(parts[1].trim());
    if (w != null && h != null && h > 0) return w / h;
  }
  return kFriendsPostAspect;
}

/// The "POST SIZE · Tall / Classic" pill row a composer screen drops above
/// its photo preview. Purely controlled — [value]/[onChanged] are that
/// screen's own local state (defaulting to [PostSizePreset.big]), baked
/// into the post at send time and never read back from anywhere shared.
class PostSizePresetPicker extends StatelessWidget {
  const PostSizePresetPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PostSizePreset value;
  final ValueChanged<PostSizePreset> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'POST SIZE',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            letterSpacing: 1.6,
            color: Colors.white.withValues(alpha: 0.38),
          ),
        ),
        const SizedBox(width: 12),
        for (final preset in PostSizePreset.values) ...[
          GestureDetector(
            onTap: value == preset ? null : () => onChanged(preset),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                color: value == preset
                    ? Colors.white.withValues(alpha: 0.13)
                    : Colors.transparent,
                border: Border.all(
                  color: Colors.white
                      .withValues(alpha: value == preset ? 0.30 : 0.10),
                ),
              ),
              child: Text(
                preset.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      value == preset ? FontWeight.w700 : FontWeight.w500,
                  color: Colors.white
                      .withValues(alpha: value == preset ? 0.95 : 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}
