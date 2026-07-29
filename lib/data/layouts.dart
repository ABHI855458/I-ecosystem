import 'package:flutter/material.dart';
import '../models/collage_layout.dart';
import '../models/photo_slot.dart';
import 'collage_styles.dart';

const _black = Color(0xFF000000);
const _darkGrey = Color(0xFF2A2A2A);
const _charcoal = Color(0xFF1A1A1A);
const _deepGreen = Color(0xFF1A4D2E);
const _concrete = Color(0xFF4A4A4A);
const _cream = Color(0xFFF5F1E8);
const _turquoise = Color(0xFF20B2AA);
const _gold = Color(0xFFFFD700);
const _neonPink = Color(0xFFFF1493);
const _deepBlue = Color(0xFF0066FF);
const _teal = Color(0xFF0D5D5D);

final List<CollageLayout> kLegacyLayouts = [
  // 1. Triple Horizontal Split
  CollageLayout(
    id: 'triple_horizontal',
    name: 'Triple Split',
    category: 'Structural',
    photoCount: 3,
    background: const CollageBackground.solid(_black),
    slots: const [
      PhotoSlot(x: 0.00, y: 0.000, w: 1.00, h: 0.335),
      PhotoSlot(x: 0.00, y: 0.335, w: 1.00, h: 0.330),
      PhotoSlot(x: 0.00, y: 0.665, w: 1.00, h: 0.335),
    ],
  ),

  // 2. Unequal Split Grid
  CollageLayout(
    id: 'unequal_split',
    name: 'Unequal Grid',
    category: 'Structural',
    photoCount: 3,
    background: const CollageBackground.solid(_black),
    slots: const [
      PhotoSlot(x: 0.00, y: 0.00, w: 1.00, h: 0.50),
      PhotoSlot(x: 0.00, y: 0.50, w: 0.50, h: 0.50),
      PhotoSlot(x: 0.50, y: 0.50, w: 0.50, h: 0.50),
    ],
  ),

  // 3. Column Stack
  CollageLayout(
    id: 'column_stack',
    name: 'Column Stack',
    category: 'Structural',
    photoCount: 3,
    background: const CollageBackground.solid(_charcoal),
    slots: const [
      PhotoSlot(x: 0.10, y: 0.10, w: 0.80, h: 0.24, shape: MaskShape.roundedRect),
      PhotoSlot(x: 0.10, y: 0.38, w: 0.80, h: 0.24, shape: MaskShape.roundedRect),
      PhotoSlot(x: 0.10, y: 0.66, w: 0.80, h: 0.24, shape: MaskShape.roundedRect),
    ],
  ),

  // 4. Polaroid Stack
  CollageLayout(
    id: 'polaroid_stack',
    name: 'Polaroid Stack',
    category: 'Artistic',
    photoCount: 4,
    background: const CollageBackground.solid(_deepGreen),
    slots: const [
      PhotoSlot(x: 0.10, y: 0.30, w: 0.50, h: 0.45, shape: MaskShape.polaroid, rotation: -8, zIndex: 1),
      PhotoSlot(x: 0.05, y: 0.10, w: 0.45, h: 0.40, shape: MaskShape.polaroid, rotation:  5, zIndex: 3),
      PhotoSlot(x: 0.50, y: 0.05, w: 0.45, h: 0.40, shape: MaskShape.polaroid, rotation: -3, zIndex: 2),
      PhotoSlot(x: 0.55, y: 0.50, w: 0.40, h: 0.35, shape: MaskShape.polaroid, rotation: 12, zIndex: 1),
    ],
  ),

  // 5. Torn Paper Collage
  CollageLayout(
    id: 'torn_paper',
    name: 'Torn Paper',
    category: 'Artistic',
    photoCount: 4,
    background: const CollageBackground.solid(_darkGrey),
    hasDecorations: true,
    decorationType: 'torn',
    slots: const [
      PhotoSlot(x: 0.05, y: 0.05, w: 0.45, h: 0.45, rotation: -2, zIndex: 2, borderColor: Colors.white, borderWidth: 8),
      PhotoSlot(x: 0.50, y: 0.10, w: 0.45, h: 0.40, rotation:  3, zIndex: 1, borderColor: Colors.white, borderWidth: 8),
      PhotoSlot(x: 0.10, y: 0.50, w: 0.45, h: 0.45, rotation:  1, zIndex: 3, borderColor: Colors.white, borderWidth: 8),
      PhotoSlot(x: 0.55, y: 0.55, w: 0.40, h: 0.40, rotation: -4, zIndex: 2, borderColor: Colors.white, borderWidth: 8),
    ],
  ),

  // 6. Retro Scrapbook
  CollageLayout(
    id: 'scrapbook',
    name: 'Scrapbook',
    category: 'Artistic',
    photoCount: 3,
    background: const CollageBackground.solid(_cream),
    hasDecorations: true,
    decorationType: 'scrapbook',
    slots: const [
      PhotoSlot(x: 0.08, y: 0.15, w: 0.84, h: 0.22, borderColor: _cream, borderWidth: 6),
      PhotoSlot(x: 0.08, y: 0.42, w: 0.84, h: 0.22, borderColor: _cream, borderWidth: 6),
      PhotoSlot(x: 0.08, y: 0.69, w: 0.84, h: 0.22, borderColor: _cream, borderWidth: 6),
    ],
  ),

  // 7. Film Negative Strip
  CollageLayout(
    id: 'film_negative',
    name: 'Film Strip',
    category: 'Artistic',
    photoCount: 4,
    background: const CollageBackground.solid(Color(0xFF0F0F0F)),
    hasDecorations: true,
    decorationType: 'sprockets',
    slots: const [
      PhotoSlot(x: 0.15, y: 0.08, w: 0.70, h: 0.20, borderColor: Color(0xFF0F0F0F), borderWidth: 4),
      PhotoSlot(x: 0.15, y: 0.31, w: 0.70, h: 0.20, borderColor: Color(0xFF0F0F0F), borderWidth: 4),
      PhotoSlot(x: 0.15, y: 0.54, w: 0.70, h: 0.20, borderColor: Color(0xFF0F0F0F), borderWidth: 4),
      PhotoSlot(x: 0.15, y: 0.77, w: 0.70, h: 0.20, borderColor: Color(0xFF0F0F0F), borderWidth: 4),
    ],
  ),

  // 8. Perforated Film Roll
  CollageLayout(
    id: 'perforated_roll',
    name: 'Film Roll',
    category: 'Artistic',
    photoCount: 3,
    background: const CollageBackground.solid(_concrete),
    hasDecorations: true,
    decorationType: 'sprockets',
    slots: const [
      PhotoSlot(x: 0.12, y: 0.15, w: 0.76, h: 0.22),
      PhotoSlot(x: 0.12, y: 0.42, w: 0.76, h: 0.22),
      PhotoSlot(x: 0.12, y: 0.69, w: 0.76, h: 0.22),
    ],
  ),

  // 9. Abstract Liquid / Blobs
  CollageLayout(
    id: 'liquid_blobs',
    name: 'Liquid Blobs',
    category: 'Organic',
    photoCount: 3,
    background: const CollageBackground.solid(_teal),
    hasDecorations: true,
    decorationType: 'dots',
    slots: const [
      PhotoSlot(x: 0.05, y: 0.10, w: 0.40, h: 0.35, shape: MaskShape.blob1),
      PhotoSlot(x: 0.55, y: 0.05, w: 0.40, h: 0.40, shape: MaskShape.blob2, rotation: 15),
      PhotoSlot(x: 0.20, y: 0.55, w: 0.60, h: 0.40, shape: MaskShape.blob3, rotation: -8),
    ],
  ),

  // 10. Geometric Wave
  CollageLayout(
    id: 'geometric_wave',
    name: 'Geo Wave',
    category: 'Organic',
    photoCount: 3,
    background: const CollageBackground.solid(_darkGrey),
    hasDecorations: true,
    decorationType: 'hearts',
    slots: const [
      PhotoSlot(x: 0.08, y: 0.15, w: 0.35, h: 0.30, shape: MaskShape.pill,  borderColor: _gold,     borderWidth: 8),
      PhotoSlot(x: 0.57, y: 0.10, w: 0.38, h: 0.35, shape: MaskShape.pill,  borderColor: _neonPink, borderWidth: 8),
      PhotoSlot(x: 0.25, y: 0.60, w: 0.50, h: 0.35, shape: MaskShape.wave,  borderColor: _deepBlue, borderWidth: 8),
    ],
  ),

  // 11. Floral Frame
  CollageLayout(
    id: 'floral_frame',
    name: 'Floral',
    category: 'Organic',
    photoCount: 3,
    background: const CollageBackground.solid(_turquoise),
    hasDecorations: true,
    decorationType: 'daisies',
    slots: const [
      PhotoSlot(x: 0.12, y: 0.12, w: 0.76, h: 0.22),
      PhotoSlot(x: 0.12, y: 0.39, w: 0.76, h: 0.22),
      PhotoSlot(x: 0.12, y: 0.66, w: 0.76, h: 0.22),
    ],
  ),

  // 12. Golden Glitter
  CollageLayout(
    id: 'golden_glitter',
    name: 'Golden',
    category: 'Organic',
    photoCount: 3,
    background: const CollageBackground.solid(_charcoal),
    hasDecorations: true,
    decorationType: 'glitter',
    slots: const [
      PhotoSlot(x: 0.10, y: 0.10, w: 0.80, h: 0.24, shape: MaskShape.roundedRect, borderColor: _gold, borderWidth: 6),
      PhotoSlot(x: 0.10, y: 0.38, w: 0.80, h: 0.24, shape: MaskShape.roundedRect, borderColor: _gold, borderWidth: 6),
      PhotoSlot(x: 0.10, y: 0.66, w: 0.80, h: 0.24, shape: MaskShape.roundedRect, borderColor: _gold, borderWidth: 6),
    ],
  ),
];

final List<CollageLayout> kLayouts = [...kLegacyLayouts, ...kCollageStudioStyles];

CollageLayout layoutById(String id) =>
    kLayouts.firstWhere((l) => l.id == id, orElse: () => kLayouts.first);
