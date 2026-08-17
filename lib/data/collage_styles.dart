import 'package:flutter/material.dart';
import '../models/collage_layout.dart';
import '../models/photo_slot.dart';

// Collage Studio styles (v2) — Google-Photos-style collage editor.
// Reuses the existing CollageLayout/PhotoSlot/ShapeClipper/DecorationPainter
// architecture; see lib/data/layouts.dart for the legacy 12 layouts.

const _sage = Color(0xFFD9DDD3);
const _cream = Color(0xFFF7F4EA);
const _tornTeal1 = Color(0xFF3E5C58);
const _tornTeal2 = Color(0xFF314744);
const _warmGray = Color(0xFF8E8B86);
const _glowPink = Color(0xFFF3A7C0);
const _glowGreen = Color(0xFFB9D96E);
const _glowTeal = Color(0xFF7FD9C8);
const _sparkleGold = Color(0xFFB9A77C);
const _archGray = Color(0xFF8A8A8A);
const _vintageCream = Color(0xFFF1EBDC);
const _filmGray = Color(0xFFA8ACB4);
const _flower1 = Color(0xFFF6E7C9);
const _flower2 = Color(0xFFEFC9DE);
const _flower3 = Color(0xFFC9E4EF);
const _flower4 = Color(0xFFD9C9EF);
const _pebbleCream = Color(0xFFEDE7D9);
const _pebbleBrush = Color(0xFFA08C5B);
const _daisyTeal = Color(0xFF2C9C96);
const _translucentWhite = Color(0x99FFFFFF);

final List<CollageLayout> kCollageStudioStyles = [
  // 1. bigLeft
  const CollageLayout(
    id: 'studio_big_left_2',
    name: 'Big Left',
    category: 'Studio',
    photoCount: 2,
    familyId: 'bigLeft',
    background: CollageBackground.solid(Colors.black),
    slots: [
      PhotoSlot(x: 0.00, y: 0.15, w: 0.485, h: 0.70),
      PhotoSlot(x: 0.505, y: 0.15, w: 0.495, h: 0.70),
    ],
  ),
  const CollageLayout(
    id: 'studio_big_left_3',
    name: 'Big Left',
    category: 'Studio',
    photoCount: 3,
    familyId: 'bigLeft',
    background: CollageBackground.solid(Colors.black),
    slots: [
      PhotoSlot(x: 0.00, y: 0.15, w: 0.485, h: 0.70),
      PhotoSlot(x: 0.505, y: 0.15, w: 0.495, h: 0.34),
      PhotoSlot(x: 0.505, y: 0.508, w: 0.495, h: 0.342),
    ],
  ),
  const CollageLayout(
    id: 'studio_big_left_4',
    name: 'Big Left',
    category: 'Studio',
    photoCount: 4,
    familyId: 'bigLeft',
    background: CollageBackground.solid(Colors.black),
    slots: [
      PhotoSlot(x: 0.00, y: 0.15, w: 0.485, h: 0.70),
      PhotoSlot(x: 0.505, y: 0.15, w: 0.495, h: 0.223),
      PhotoSlot(x: 0.505, y: 0.3865, w: 0.495, h: 0.223),
      PhotoSlot(x: 0.505, y: 0.623, w: 0.495, h: 0.227),
    ],
  ),

  // 2. bigTop
  const CollageLayout(
    id: 'studio_big_top_2',
    name: 'Big Top',
    category: 'Studio',
    photoCount: 2,
    familyId: 'bigTop',
    background: CollageBackground.solid(Colors.black),
    slots: [
      PhotoSlot(x: 0.00, y: 0.00, w: 1.00, h: 0.495),
      PhotoSlot(x: 0.00, y: 0.505, w: 1.00, h: 0.495),
    ],
  ),
  const CollageLayout(
    id: 'studio_big_top_3',
    name: 'Big Top',
    category: 'Studio',
    photoCount: 3,
    familyId: 'bigTop',
    background: CollageBackground.solid(Colors.black),
    slots: [
      PhotoSlot(x: 0.00, y: 0.00, w: 1.00, h: 0.415),
      PhotoSlot(x: 0.00, y: 0.425, w: 0.495, h: 0.575),
      PhotoSlot(x: 0.505, y: 0.425, w: 0.495, h: 0.575),
    ],
  ),
  const CollageLayout(
    id: 'studio_big_top_4',
    name: 'Big Top',
    category: 'Studio',
    photoCount: 4,
    familyId: 'bigTop',
    background: CollageBackground.solid(Colors.black),
    slots: [
      PhotoSlot(x: 0.00, y: 0.00, w: 1.00, h: 0.415),
      PhotoSlot(x: 0.00, y: 0.425, w: 0.327, h: 0.575),
      PhotoSlot(x: 0.337, y: 0.425, w: 0.327, h: 0.575),
      PhotoSlot(x: 0.674, y: 0.425, w: 0.326, h: 0.575),
    ],
  ),

  // 3. rows
  const CollageLayout(
    id: 'studio_rows',
    name: 'Rows',
    category: 'Studio',
    photoCount: 3,
    background: CollageBackground.solid(Colors.black),
    slots: [
      PhotoSlot(x: 0.00, y: 0.000, w: 1.00, h: 0.327),
      PhotoSlot(x: 0.00, y: 0.337, w: 1.00, h: 0.327),
      PhotoSlot(x: 0.00, y: 0.674, w: 1.00, h: 0.326),
    ],
  ),

  // 4. overlap
  const CollageLayout(
    id: 'studio_overlap_2',
    name: 'Overlap',
    category: 'Studio',
    photoCount: 2,
    familyId: 'overlap',
    background: CollageBackground.solid(Colors.black),
    slots: [
      PhotoSlot(x: 0.10, y: 0.14, w: 0.68, h: 0.40, rotation: 0, zIndex: 1, borderColor: Colors.white, borderWidth: 5, shadow: true),
      PhotoSlot(x: 0.24, y: 0.46, w: 0.68, h: 0.40, rotation: -5, zIndex: 2, borderColor: Colors.white, borderWidth: 5, shadow: true),
    ],
  ),
  const CollageLayout(
    id: 'studio_overlap_3',
    name: 'Overlap',
    category: 'Studio',
    photoCount: 3,
    familyId: 'overlap',
    background: CollageBackground.solid(Colors.black),
    slots: [
      PhotoSlot(x: 0.08, y: 0.10, w: 0.64, h: 0.36, rotation: 0, zIndex: 1, borderColor: Colors.white, borderWidth: 5, shadow: true),
      PhotoSlot(x: 0.28, y: 0.32, w: 0.64, h: 0.36, rotation: 4, zIndex: 2, borderColor: Colors.white, borderWidth: 5, shadow: true),
      PhotoSlot(x: 0.14, y: 0.54, w: 0.64, h: 0.36, rotation: -5, zIndex: 3, borderColor: Colors.white, borderWidth: 5, shadow: true),
    ],
  ),
  const CollageLayout(
    id: 'studio_overlap_4',
    name: 'Overlap',
    category: 'Studio',
    photoCount: 4,
    familyId: 'overlap',
    background: CollageBackground.solid(Colors.black),
    slots: [
      PhotoSlot(x: 0.06, y: 0.06, w: 0.60, h: 0.30, rotation: 0, zIndex: 1, borderColor: Colors.white, borderWidth: 5, shadow: true),
      PhotoSlot(x: 0.24, y: 0.24, w: 0.60, h: 0.30, rotation: 4, zIndex: 2, borderColor: Colors.white, borderWidth: 5, shadow: true),
      PhotoSlot(x: 0.10, y: 0.42, w: 0.60, h: 0.30, rotation: -5, zIndex: 3, borderColor: Colors.white, borderWidth: 5, shadow: true),
      PhotoSlot(x: 0.26, y: 0.60, w: 0.60, h: 0.30, rotation: 3, zIndex: 4, borderColor: Colors.white, borderWidth: 5, shadow: true),
    ],
  ),

  // 5. polaroid
  const CollageLayout(
    id: 'studio_polaroid',
    name: 'Polaroid',
    category: 'Studio',
    photoCount: 3,
    background: CollageBackground.solid(_sage),
    slots: [
      PhotoSlot(x: 0.10, y: 0.05, w: 0.55, h: 0.36, shape: MaskShape.polaroid, rotation: -3, zIndex: 1, borderColor: Colors.black, borderWidth: 9, bottomBorderExtra: 34, shadow: true),
      PhotoSlot(x: 0.34, y: 0.28, w: 0.55, h: 0.36, shape: MaskShape.polaroid, rotation: 8, zIndex: 2, borderColor: Colors.black, borderWidth: 9, bottomBorderExtra: 34, shadow: true),
      PhotoSlot(x: 0.10, y: 0.55, w: 0.55, h: 0.36, shape: MaskShape.polaroid, rotation: -6, zIndex: 3, borderColor: Colors.black, borderWidth: 9, bottomBorderExtra: 34, shadow: true),
    ],
  ),

  // 6. sketch
  CollageLayout(
    id: 'studio_sketch',
    name: 'Sketch',
    category: 'Studio',
    photoCount: 3,
    background: const CollageBackground.solid(_cream),
    slots: const [
      PhotoSlot(x: 0.10, y: 0.05, w: 0.80, h: 0.27, rotation: -2, zIndex: 1, borderColor: Colors.white, borderWidth: 6, shadow: true),
      PhotoSlot(x: 0.10, y: 0.365, w: 0.80, h: 0.27, rotation: 3, zIndex: 2, borderColor: Colors.white, borderWidth: 6, shadow: true),
      PhotoSlot(x: 0.10, y: 0.68, w: 0.80, h: 0.27, rotation: -1, zIndex: 3, borderColor: Colors.white, borderWidth: 6, shadow: true),
    ],
    decorations: const [
      CollageDecoration(position: Offset(0.16, 0.14), kind: DecorationKind.doodleCircle, size: 40, color: Color(0xFF333333)),
      CollageDecoration(position: Offset(0.84, 0.86), kind: DecorationKind.doodleCircle, size: 34, color: Color(0xFF333333)),
      CollageDecoration(position: Offset(0.84, 0.32), kind: DecorationKind.doodleDashes, size: 30, rotationDeg: -10, color: Color(0xFF333333)),
      CollageDecoration(position: Offset(0.16, 0.82), kind: DecorationKind.doodleDashes, size: 30, rotationDeg: 8, color: Color(0xFF333333)),
    ],
  ),

  // 7. tornPaper
  const CollageLayout(
    id: 'studio_torn_paper',
    name: 'Torn Paper',
    category: 'Studio',
    photoCount: 3,
    background: CollageBackground.radialGradient([_tornTeal1, _tornTeal2]),
    slots: [
      PhotoSlot(x: 0.06, y: 0.05, w: 0.52, h: 0.42, shape: MaskShape.tornPaper, rotation: -4, zIndex: 1, borderColor: Colors.white, borderWidth: 10, shadow: true, tornSeed: 11),
      PhotoSlot(x: 0.46, y: 0.12, w: 0.50, h: 0.40, shape: MaskShape.tornPaper, rotation: 5, zIndex: 2, borderColor: Colors.white, borderWidth: 10, shadow: true, tornSeed: 22),
      PhotoSlot(x: 0.14, y: 0.52, w: 0.55, h: 0.42, shape: MaskShape.tornPaper, rotation: -7, zIndex: 3, borderColor: Colors.white, borderWidth: 10, shadow: true, tornSeed: 33),
    ],
  ),

  // 8. blobGlow
  const CollageLayout(
    id: 'studio_blob_glow',
    name: 'Blob Glow',
    category: 'Studio',
    photoCount: 3,
    background: CollageBackground.solid(_warmGray),
    slots: [
      PhotoSlot(x: 0.08, y: 0.06, w: 0.55, h: 0.30, shape: MaskShape.squircle, zIndex: 1, borderGradient: [_glowPink, _glowGreen, _glowTeal], borderWidth: 4),
      PhotoSlot(x: 0.40, y: 0.30, w: 0.55, h: 0.30, shape: MaskShape.squircle, zIndex: 2, borderGradient: [_glowPink, _glowGreen, _glowTeal], borderWidth: 4),
      PhotoSlot(x: 0.15, y: 0.58, w: 0.60, h: 0.32, shape: MaskShape.squircle, zIndex: 3, borderGradient: [_glowPink, _glowGreen, _glowTeal], borderWidth: 4),
    ],
    decorations: [
      CollageDecoration(position: Offset(0.10, 0.90), kind: DecorationKind.sparkle, size: 28, color: _sparkleGold),
      CollageDecoration(position: Offset(0.90, 0.15), kind: DecorationKind.sparkle, size: 24, color: _sparkleGold),
    ],
  ),

  // 9. archHearts
  const CollageLayout(
    id: 'studio_arch_hearts',
    name: 'Arch Hearts',
    category: 'Studio',
    photoCount: 3,
    background: CollageBackground.solid(_archGray),
    slots: [
      PhotoSlot(x: 0.13, y: 0.04, w: 0.74, h: 0.56, shape: MaskShape.arch, zIndex: 1),
      PhotoSlot(x: 0.00, y: 0.60, w: 0.50, h: 0.40, zIndex: 2),
      PhotoSlot(x: 0.50, y: 0.60, w: 0.50, h: 0.40, zIndex: 3),
    ],
    decorations: [
      CollageDecoration(position: Offset(0.10, 0.07), kind: DecorationKind.hearts, size: 30, rotationDeg: -10, color: Colors.black),
      CollageDecoration(position: Offset(0.90, 0.07), kind: DecorationKind.hearts, size: 30, rotationDeg: 10, color: Colors.black),
    ],
  ),

  // 10. vintage
  const CollageLayout(
    id: 'studio_vintage_2',
    name: 'Vintage',
    category: 'Studio',
    photoCount: 2,
    familyId: 'vintage',
    background: CollageBackground.solid(Colors.white),
    slots: [
      PhotoSlot(x: 0.08, y: 0.06, w: 0.84, h: 0.42, borderColor: _vintageCream, borderWidth: 8, shape: MaskShape.roundedRect, shadow: true),
      PhotoSlot(x: 0.08, y: 0.52, w: 0.84, h: 0.42, borderColor: _vintageCream, borderWidth: 8, shape: MaskShape.roundedRect, shadow: true),
    ],
  ),
  const CollageLayout(
    id: 'studio_vintage_3',
    name: 'Vintage',
    category: 'Studio',
    photoCount: 3,
    familyId: 'vintage',
    background: CollageBackground.solid(Colors.white),
    slots: [
      PhotoSlot(x: 0.08, y: 0.06, w: 0.40, h: 0.30, borderColor: _vintageCream, borderWidth: 8, shape: MaskShape.roundedRect, shadow: true),
      PhotoSlot(x: 0.52, y: 0.06, w: 0.40, h: 0.30, borderColor: _vintageCream, borderWidth: 8, shape: MaskShape.roundedRect, shadow: true),
      PhotoSlot(x: 0.08, y: 0.40, w: 0.84, h: 0.30, borderColor: _vintageCream, borderWidth: 8, shape: MaskShape.roundedRect, shadow: true),
    ],
  ),
  const CollageLayout(
    id: 'studio_vintage_4',
    name: 'Vintage',
    category: 'Studio',
    photoCount: 4,
    familyId: 'vintage',
    background: CollageBackground.solid(Colors.white),
    slots: [
      PhotoSlot(x: 0.08, y: 0.06, w: 0.40, h: 0.30, borderColor: _vintageCream, borderWidth: 8, shape: MaskShape.roundedRect, shadow: true),
      PhotoSlot(x: 0.52, y: 0.06, w: 0.40, h: 0.30, borderColor: _vintageCream, borderWidth: 8, shape: MaskShape.roundedRect, shadow: true),
      PhotoSlot(x: 0.08, y: 0.40, w: 0.40, h: 0.30, borderColor: _vintageCream, borderWidth: 8, shape: MaskShape.roundedRect, shadow: true),
      PhotoSlot(x: 0.52, y: 0.40, w: 0.40, h: 0.30, borderColor: _vintageCream, borderWidth: 8, shape: MaskShape.roundedRect, shadow: true),
    ],
  ),

  // 11. filmStrip
  const CollageLayout(
    id: 'studio_film_strip',
    name: 'Film Strip',
    category: 'Studio',
    photoCount: 3,
    background: CollageBackground.solid(_filmGray),
    slots: [
      PhotoSlot(x: 0.08, y: 0.05, w: 0.84, h: 0.27, rotation: -6, zIndex: 1, borderColor: Colors.white, borderWidth: 6, shadow: true),
      PhotoSlot(x: 0.08, y: 0.365, w: 0.84, h: 0.27, rotation: 4, zIndex: 2, borderColor: Colors.white, borderWidth: 6, shadow: true),
      PhotoSlot(x: 0.08, y: 0.68, w: 0.84, h: 0.27, rotation: -3, zIndex: 3, borderColor: Colors.white, borderWidth: 6, shadow: true),
    ],
    decorations: [
      CollageDecoration(position: Offset(0.5, 0.05), kind: DecorationKind.filmSprockets, size: 0.80, color: Colors.black54),
      CollageDecoration(position: Offset(0.5, 0.30), kind: DecorationKind.filmSprockets, size: 0.80, color: Colors.black54),
      CollageDecoration(position: Offset(0.5, 0.365), kind: DecorationKind.filmSprockets, size: 0.80, color: Colors.black54),
      CollageDecoration(position: Offset(0.5, 0.61), kind: DecorationKind.filmSprockets, size: 0.80, color: Colors.black54),
      CollageDecoration(position: Offset(0.5, 0.68), kind: DecorationKind.filmSprockets, size: 0.80, color: Colors.black54),
      CollageDecoration(position: Offset(0.5, 0.93), kind: DecorationKind.filmSprockets, size: 0.80, color: Colors.black54),
    ],
  ),

  // 12. flower
  const CollageLayout(
    id: 'studio_flower',
    name: 'Flower',
    category: 'Studio',
    photoCount: 3,
    background: CollageBackground.linearGradient([_flower1, _flower2, _flower3, _flower4]),
    slots: [
      PhotoSlot(x: 0.08, y: 0.06, w: 0.50, h: 0.30, shape: MaskShape.blob1, zIndex: 1, borderColor: _translucentWhite, borderWidth: 6),
      PhotoSlot(x: 0.42, y: 0.32, w: 0.52, h: 0.32, shape: MaskShape.blob2, zIndex: 2, borderColor: _translucentWhite, borderWidth: 6),
      PhotoSlot(x: 0.12, y: 0.62, w: 0.55, h: 0.34, shape: MaskShape.circle, zIndex: 3, borderColor: _translucentWhite, borderWidth: 6),
    ],
  ),

  // 13. pebble
  const CollageLayout(
    id: 'studio_pebble',
    name: 'Pebble',
    category: 'Studio',
    photoCount: 3,
    background: CollageBackground.solid(_pebbleCream),
    slots: [
      PhotoSlot(x: 0.08, y: 0.06, w: 0.55, h: 0.28, shape: MaskShape.blob1, zIndex: 2),
      PhotoSlot(x: 0.38, y: 0.34, w: 0.55, h: 0.30, shape: MaskShape.blob2, zIndex: 3),
      PhotoSlot(x: 0.12, y: 0.62, w: 0.60, h: 0.32, shape: MaskShape.blob3, zIndex: 4),
    ],
    decorations: [
      CollageDecoration(position: Offset(0.5, 0.20), kind: DecorationKind.brushLine, size: 1.3, rotationDeg: -24, color: _pebbleBrush, behindPhotos: true),
      CollageDecoration(position: Offset(0.5, 0.50), kind: DecorationKind.brushLine, size: 1.3, rotationDeg: -24, color: _pebbleBrush, behindPhotos: true),
      CollageDecoration(position: Offset(0.5, 0.80), kind: DecorationKind.brushLine, size: 1.3, rotationDeg: -24, color: _pebbleBrush, behindPhotos: true),
    ],
  ),

  // 14. daisy
  const CollageLayout(
    id: 'studio_daisy',
    name: 'Daisy',
    category: 'Studio',
    photoCount: 3,
    background: CollageBackground.solid(_daisyTeal),
    slots: [
      PhotoSlot(x: 0.10, y: 0.04, w: 0.80, h: 0.28, shape: MaskShape.roundedRect, zIndex: 1, borderColor: Colors.white, borderWidth: 5),
      PhotoSlot(x: 0.10, y: 0.36, w: 0.80, h: 0.28, shape: MaskShape.roundedRect, zIndex: 2, borderColor: Colors.white, borderWidth: 5),
      PhotoSlot(x: 0.10, y: 0.68, w: 0.80, h: 0.28, shape: MaskShape.roundedRect, zIndex: 3, borderColor: Colors.white, borderWidth: 5),
    ],
    decorations: [
      CollageDecoration(position: Offset(0.06, 0.03), kind: DecorationKind.daisy, size: 26),
      CollageDecoration(position: Offset(0.94, 0.03), kind: DecorationKind.daisy, size: 26),
      CollageDecoration(position: Offset(0.02, 0.5), kind: DecorationKind.daisy, size: 26),
      CollageDecoration(position: Offset(0.98, 0.5), kind: DecorationKind.daisy, size: 26),
      CollageDecoration(position: Offset(0.06, 0.97), kind: DecorationKind.daisy, size: 26),
      CollageDecoration(position: Offset(0.94, 0.97), kind: DecorationKind.daisy, size: 26),
    ],
  ),
];
