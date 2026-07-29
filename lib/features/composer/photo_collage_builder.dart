import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum CollageLayout { grid2x2, scrapbook3x2, scrapbook2x3, triptych, scattered, polaroid }

enum CollageSurface { carpet, woodenTable, marble, corkBoard, linen, paper, darkSlate, pastel }

// Surface data: (enum, name, desc, gradientTop, gradientBottom, useDarkText)
const _kSurfaces = [
  (CollageSurface.carpet,      'Carpet',      'Cozy textured floor',   Color(0xFF5C2D30), Color(0xFF3D1A1C), false),
  (CollageSurface.woodenTable, 'Wood Table',  'Warm oak grain',        Color(0xFF7A5230), Color(0xFF4A2E10), false),
  (CollageSurface.marble,      'Marble',      'Clean stone surface',   Color(0xFFF0EEEC), Color(0xFFD0CCC8), true),
  (CollageSurface.corkBoard,   'Cork Board',  'Pin-board style',       Color(0xFFCAA868), Color(0xFFA88840), true),
  (CollageSurface.linen,       'Linen',       'Soft cloth texture',    Color(0xFFD4C8B8), Color(0xFFBCB0A0), true),
  (CollageSurface.paper,       'Paper',       'Scrapbook paper',       Color(0xFFF5F0E0), Color(0xFFEAE0C8), true),
  (CollageSurface.darkSlate,   'Dark Slate',  'Moody dark surface',    Color(0xFF18191E), Color(0xFF0E0F14), false),
  (CollageSurface.pastel,      'Pastel',      'Soft color wash',       Color(0xFFEAD4EE), Color(0xFFD0D4F0), true),
];

// ---------------------------------------------------------------------------
// CollageBuilderScreen — 5-step flow
// ---------------------------------------------------------------------------

class CollageBuilderScreen extends StatefulWidget {
  const CollageBuilderScreen({super.key, this.onPost, this.initialStep = 0});

  final VoidCallback? onPost;
  final int initialStep;

  @override
  State<CollageBuilderScreen> createState() => _CollageBuilderScreenState();
}

class _CollageBuilderScreenState extends State<CollageBuilderScreen> {
  late int _step = widget.initialStep; // 0=surface, 1=layout, 2=arrange, 3=style, 4=preview

  CollageSurface _surface = CollageSurface.carpet;
  CollageLayout _layout = CollageLayout.grid2x2;
  final List<File?> _selectedPhotos = List<File?>.filled(4, null);
  bool _polaroidStyle = false;
  bool _randomRotation = true;
  double _gap = 4.0;

  static const _stepTitles = [
    'Choose a Surface',
    'Choose Layout',
    'Arrange Photos',
    'Styling',
    'Preview',
  ];

  void _next() {
    if (_step == 4) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Collage posted!', style: GoogleFonts.inter(fontSize: 14)),
          backgroundColor: AppColors.coral,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onPost?.call();
      Navigator.of(context).pop();
    } else {
      setState(() => _step++);
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _pickPhoto(int index) async {
    final result = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (result == null || !mounted) return;
    setState(() => _selectedPhotos[index] = File(result.path));
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SizedBox(height: top),
          _buildTopBar(),
          _buildProgressBar(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: _buildStepContent(),
              ),
            ),
          ),
          _buildBottomBar(bottom),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _back,
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Create Collage',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Step ${_step + 1} of 5: ${_stepTitles[_step]}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (_step < 4)
            GestureDetector(
              onTap: _next,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Next →',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: (_step + 1) / 5,
          backgroundColor: AppColors.border,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.coral),
          minHeight: 2,
        ),
      ),
    );
  }

  Widget _buildBottomBar(double bottomPadding) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _back,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _step == 0 ? 'Cancel' : '← Back',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _next,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                color: _step == 4 ? AppColors.coral : AppColors.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: (_step == 4 ? AppColors.coral : AppColors.primary)
                        .withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                _step == 4 ? 'Post This ✦' : 'Continue →',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _step == 4 ? Colors.white : AppColors.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildSurfaceStep();
      case 1:
        return _buildLayoutStep();
      case 2:
        return _buildArrangeStep();
      case 3:
        return _buildStyleStep();
      default:
        return _buildPreviewStep();
    }
  }

  // ── Step 0: Surface ────────────────────────────────────────────────────────

  LinearGradient _surfaceGradient(CollageSurface s) {
    final data = _kSurfaces.firstWhere((e) => e.$1 == s);
    return LinearGradient(
      colors: [data.$4, data.$5],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Widget _buildSurfaceStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick the surface your photos sit on',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
            ),
            itemCount: _kSurfaces.length,
            itemBuilder: (ctx, i) {
              final (surf, name, desc, c1, c2, useDarkText) = _kSurfaces[i];
              final isSelected = _surface == surf;
              final labelColor = useDarkText ? const Color(0xFF1A1A1A) : Colors.white;
              return GestureDetector(
                onTap: () => setState(() => _surface = surf),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [c1, c2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: isSelected ? AppColors.coral : Colors.transparent,
                      width: isSelected ? 2.5 : 0,
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (isSelected)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: AppColors.coral,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 10,
                        left: 12,
                        right: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: labelColor,
                              ),
                            ),
                            Text(
                              desc,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: labelColor.withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Step 1: Layout ─────────────────────────────────────────────────────────

  Widget _buildLayoutStep() {
    final layouts = [
      (CollageLayout.grid2x2, '2×2 Grid', Icons.grid_view_rounded, '4 photos'),
      (CollageLayout.scrapbook3x2, '3+2 Stack', Icons.dashboard_rounded, '5 photos'),
      (CollageLayout.scrapbook2x3, '2+3 Stack', Icons.view_quilt_rounded, '5 photos'),
      (CollageLayout.triptych, 'Triptych', Icons.view_column_rounded, '3 photos'),
      (CollageLayout.scattered, 'Scattered', Icons.auto_awesome_rounded, 'Organic'),
      (CollageLayout.polaroid, 'Polaroid', Icons.photo_camera_back_rounded, 'With frames'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose how photos are arranged',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.85,
            children: layouts.map((l) {
              final (lyt, label, icon, sub) = l;
              final isSelected = _layout == lyt;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _layout = lyt;
                    final count = lyt == CollageLayout.triptych
                        ? 3
                        : (lyt == CollageLayout.scrapbook3x2 ||
                                lyt == CollageLayout.scrapbook2x3)
                            ? 5
                            : 4;
                    if (_selectedPhotos.length < count) {
                      _selectedPhotos.addAll(List<File?>.filled(count - _selectedPhotos.length, null));
                    } else if (_selectedPhotos.length > count) {
                      _selectedPhotos.removeRange(count, _selectedPhotos.length);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.coral.withValues(alpha: 0.12)
                        : AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppColors.coral : AppColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 28,
                        color: isSelected ? AppColors.coral : AppColors.textMuted,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppColors.coral
                              : AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Arrange (tap to pick · drag to reorder) ──────────────────────

  Widget _buildArrangeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            'Tap a slot to pick a photo — drag ≡ to reorder',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _selectedPhotos.length,
            onReorderItem: (oldIdx, newIdx) {
              setState(() {
                final item = _selectedPhotos.removeAt(oldIdx);
                _selectedPhotos.insert(newIdx, item);
              });
            },
            itemBuilder: (ctx, i) {
              final photo = _selectedPhotos[i];
              return GestureDetector(
                key: ValueKey(i),
                onTap: () => _pickPhoto(i),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Text(
                        '${i + 1}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: photo != null
                              ? Image.file(photo, fit: BoxFit.cover, width: 52, height: 52)
                              : const ColoredBox(
                                  color: Color(0xFF1C2030),
                                  child: Icon(
                                    Icons.add_photo_alternate_outlined,
                                    color: Color(0xFF999999),
                                    size: 22,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              photo != null ? 'Photo ${i + 1}' : 'Tap to pick',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'Drag ≡ to reorder',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.drag_handle_rounded,
                        color: AppColors.textMuted,
                        size: 22,
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Step 3: Style ──────────────────────────────────────────────────────────

  Widget _buildStyleStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Customize the look',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          // Live mini-preview
          Container(
            height: 220,
            decoration: BoxDecoration(
              gradient: _surfaceGradient(_surface),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.40)),
            ),
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _buildCollageWidget(
                _selectedPhotos,
                _layout,
                _polaroidStyle,
                _randomRotation,
                _gap,
                previewMode: true,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Polaroid style toggle
          _buildToggleRow(
            'Polaroid Style',
            'White borders + shadow on each photo',
            _polaroidStyle,
            (v) => setState(() => _polaroidStyle = v),
          ),
          const SizedBox(height: 12),
          // Random rotation toggle
          _buildToggleRow(
            'Random Rotation',
            'Slight tilt on each photo (±3°)',
            _randomRotation,
            (v) => setState(() => _randomRotation = v),
          ),
          const SizedBox(height: 20),
          // Gap slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Gap between photos',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${_gap.round()}px',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: AppColors.coral,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.coral,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.coral,
              overlayColor: AppColors.coral.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _gap,
              min: 0,
              max: 12,
              divisions: 12,
              onChanged: (v) => setState(() => _gap = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.coral,
            inactiveTrackColor: AppColors.border,
          ),
        ],
      ),
    );
  }

  // ── Step 4: Preview ────────────────────────────────────────────────────────

  Widget _buildPreviewStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your collage',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap "Post This" to share with your community',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mock post header
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1A1A22),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person_outline,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Anonymous',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'just now',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Surface backdrop — photos sit on the chosen texture
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: _surfaceGradient(_surface),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: _buildCollageWidget(
                      _selectedPhotos,
                      _layout,
                      _polaroidStyle,
                      _randomRotation,
                      _gap,
                      previewMode: false,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Surface + styling badges
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _styleBadge(_kSurfaces.firstWhere((e) => e.$1 == _surface).$2),
                    _styleBadge(_layout.name),
                    if (_polaroidStyle) _styleBadge('Polaroid'),
                    if (_randomRotation) _styleBadge('Rotated'),
                    _styleBadge('Gap ${_gap.round()}px'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _styleBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          color: AppColors.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Collage widget builder — shared between style preview + post preview
// ---------------------------------------------------------------------------

Widget _buildCollageWidget(
  List<File?> photos,
  CollageLayout layout,
  bool polaroidStyle,
  bool rotation,
  double gap, {
  bool previewMode = false,
}) {
  final heights = previewMode
      ? const _CollageHeights(cell: 60, triptychH: 60, sideH: 60)
      : const _CollageHeights(cell: 130, triptychH: 170, sideH: 150);

  Widget photoTile(File? f, double angle) {
    final inner = f != null
        ? Image.file(f, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
        : const ColoredBox(color: Color(0xFF1C2030));

    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(polaroidStyle ? 2 : 4),
      child: inner,
    );

    Widget result = polaroidStyle
        ? Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(1, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 20),
            child: clipped,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: inner,
          );

    return rotation
        ? Transform.rotate(angle: angle, child: result)
        : result;
  }

  final angles = [-0.02, 0.015, -0.018, 0.012, -0.016];

  switch (layout) {
    case CollageLayout.triptych:
      return SizedBox(
        height: heights.triptychH,
        child: Row(
          children: List.generate(math.min(3, photos.length), (i) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? gap / 2 : 0),
                child: photoTile(photos[i], angles[i % angles.length]),
              ),
            );
          }),
        ),
      );

    case CollageLayout.grid2x2:
    case CollageLayout.scattered:
      return Column(
        children: [
          SizedBox(
            height: heights.cell,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: gap / 2),
                    child: photoTile(
                      photos.isNotEmpty ? photos[0] : null,
                      angles[0],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: gap / 2),
                    child: photoTile(
                      photos.length > 1 ? photos[1] : null,
                      angles[1],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: gap),
          SizedBox(
            height: heights.cell,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: gap / 2),
                    child: photoTile(
                      photos.length > 2 ? photos[2] : null,
                      angles[2],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: gap / 2),
                    child: photoTile(
                      photos.length > 3 ? photos[3] : null,
                      angles[3],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

    case CollageLayout.scrapbook3x2:
      return Column(
        children: [
          SizedBox(
            height: heights.cell,
            child: Row(
              children: List.generate(3, (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? gap / 2 : 0),
                  child: photoTile(
                    i < photos.length ? photos[i] : null,
                    angles[i % angles.length],
                  ),
                ),
              )),
            ),
          ),
          SizedBox(height: gap),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: previewMode ? 8 : 16),
            child: SizedBox(
              height: heights.cell,
              child: Row(
                children: List.generate(2, (i) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 0 ? gap / 2 : 0),
                    child: photoTile(
                      (i + 3) < photos.length ? photos[i + 3] : null,
                      angles[(i + 3) % angles.length],
                    ),
                  ),
                )),
              ),
            ),
          ),
        ],
      );

    case CollageLayout.scrapbook2x3:
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: previewMode ? 8 : 16),
            child: SizedBox(
              height: heights.cell,
              child: Row(
                children: List.generate(2, (i) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 0 ? gap / 2 : 0),
                    child: photoTile(
                      i < photos.length ? photos[i] : null,
                      angles[i % angles.length],
                    ),
                  ),
                )),
              ),
            ),
          ),
          SizedBox(height: gap),
          SizedBox(
            height: heights.cell,
            child: Row(
              children: List.generate(3, (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 2 ? gap / 2 : 0),
                  child: photoTile(
                    (i + 2) < photos.length ? photos[i + 2] : null,
                    angles[(i + 2) % angles.length],
                  ),
                ),
              )),
            ),
          ),
        ],
      );

    case CollageLayout.polaroid:
      // Force polaroid style regardless of toggle
      final halfH = heights.cell.toDouble();
      return SizedBox(
        height: halfH + 30,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(math.min(4, photos.length), (i) {
            final angle = angles[i % angles.length];
            return Transform.rotate(
              angle: angle,
              child: Container(
                width: previewMode ? 50 : 100,
                margin: EdgeInsets.only(right: i < 3 ? gap : 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(1, 3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(5, 5, 5, 15),
                child: SizedBox(
                  height: previewMode ? 46 : 90,
                  child: photos[i] != null
                      ? Image.file(photos[i]!, fit: BoxFit.cover, width: double.infinity)
                      : const ColoredBox(color: Color(0xFF1C2030)),
                ),
              ),
            );
          }),
        ),
      );
  }
}

class _CollageHeights {
  const _CollageHeights({
    required this.cell,
    required this.triptychH,
    required this.sideH,
  });

  final double cell;
  final double triptychH;
  final double sideH;
}
