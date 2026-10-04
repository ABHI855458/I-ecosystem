Drop the preset-C mask asset here as **`preset_c.png`** (PNG with alpha
transparency, square, front-facing/upright orientation matching the
"Concealment Mask" design's preset C — almond lens, dense web-free fracture).

`lib/features/face_filter/face_mask_presets.dart` references this exact
path (`assets/masks/preset_c.png`) — renaming the file means updating that
constant too.
