import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../services/post_service.dart';
import 'memory_canvas.dart';
import 'memory_layout.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

class MemoryCreatorScreen extends StatefulWidget {
  const MemoryCreatorScreen({super.key});

  @override
  State<MemoryCreatorScreen> createState() => _MemoryCreatorScreenState();
}

class _MemoryCreatorScreenState extends State<MemoryCreatorScreen>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();

  MemoryLayoutId _selectedLayoutId = MemoryLayoutId.tripleHorizontal;
  MemoryLayout get _layout => MemoryLayouts.byId(_selectedLayoutId);

  late final List<XFile?> _photos;
  bool _saving = false;

  late final AnimationController _layoutSwitchAnim;

  @override
  void initState() {
    super.initState();
    _photos = List.filled(4, null, growable: false);
    _layoutSwitchAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _layoutSwitchAnim.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(int slotIndex) async {
    HapticFeedback.selectionClick();
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (file != null && mounted) {
      setState(() => _photos[slotIndex] = file);
    }
  }

  Future<void> _selectLayout(MemoryLayoutId id) async {
    if (id == _selectedLayoutId) return;
    HapticFeedback.selectionClick();
    await _layoutSwitchAnim.animateTo(0, duration: const Duration(milliseconds: 150), curve: Curves.easeIn);
    setState(() => _selectedLayoutId = id);
    await _layoutSwitchAnim.animateTo(1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  int get _filledSlots => _photos.take(_layout.maxPhotos).where((p) => p != null).length;

  Future<void> _saveDraft() async {
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _saving = false);
    _showToast('Draft saved to Memories ✓');
  }

  Future<void> _postToEveryone() async {
    if (_filledSlots == 0) {
      _showToast('Add at least one photo first');
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() => _saving = true);

    final caption = 'Memory collage · ${_layout.name}';
    final firstPhoto = _photos.firstWhere((p) => p != null, orElse: () => null);
    final post = LocalPost(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: 'local',
      username: 'you',
      visibility: 'everyone',
      caption: caption,
      photoPath: firstPhoto?.path,
    );
    await PostService.instance.addPost(post);

    if (!mounted) return;
    setState(() => _saving = false);

    _showToast('Posted to Everyone ✓');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) Navigator.of(context).pop();
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: const Color(0xFF1a1a2e),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Nav bar
          _NavBar(topPad: topPad, onClose: () => Navigator.of(context).pop()),

          // Canvas preview
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FadeTransition(
                opacity: _layoutSwitchAnim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                    CurvedAnimation(parent: _layoutSwitchAnim, curve: Curves.easeOut),
                  ),
                  child: MemoryCanvas(
                    key: ValueKey(_selectedLayoutId),
                    layout: _layout,
                    photos: _photos,
                    onSlotTap: _pickPhoto,
                  ),
                ),
              ),
            ),
          ),

          // Bottom panel
          _BottomPanel(
            layout: _layout,
            selectedLayoutId: _selectedLayoutId,
            onLayoutSelect: _selectLayout,
            photos: _photos,
            onSlotTap: _pickPhoto,
            filledSlots: _filledSlots,
            saving: _saving,
            onSaveDraft: _saveDraft,
            onPost: _postToEveryone,
            bottomPad: bottomPad,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation bar
// ---------------------------------------------------------------------------

class _NavBar extends StatelessWidget {
  const _NavBar({required this.topPad, required this.onClose});
  final double topPad;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, topPad + 8, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
            ),
          ),
          const Spacer(),
          Text(
            'Memory Creator',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 36),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom panel — layout strip + photo slots + action buttons
// ---------------------------------------------------------------------------

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.layout,
    required this.selectedLayoutId,
    required this.onLayoutSelect,
    required this.photos,
    required this.onSlotTap,
    required this.filledSlots,
    required this.saving,
    required this.onSaveDraft,
    required this.onPost,
    required this.bottomPad,
  });

  final MemoryLayout layout;
  final MemoryLayoutId selectedLayoutId;
  final void Function(MemoryLayoutId) onLayoutSelect;
  final List<XFile?> photos;
  final void Function(int) onSlotTap;
  final int filledSlots;
  final bool saving;
  final VoidCallback onSaveDraft;
  final VoidCallback onPost;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0e0e16).withValues(alpha: 0.90),
            border: const Border(top: BorderSide(color: Color(0xFF2a2a3a), width: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Layout selector strip
              _LayoutStrip(selectedId: selectedLayoutId, onSelect: onLayoutSelect),

              // Photo slots row
              _PhotoStrip(layout: layout, photos: photos, onSlotTap: onSlotTap),

              const SizedBox(height: 12),

              // Progress indicator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      '$filledSlots/${layout.maxPhotos} photos added',
                      style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white38),
                    ),
                    const Spacer(),
                    Text(
                      layout.category,
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.white24),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Action buttons
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 10),
                child: Row(
                  children: [
                    // Save Draft
                    Expanded(
                      child: _ActionButton(
                        label: 'Save Draft',
                        icon: Icons.bookmark_outline_rounded,
                        loading: false,
                        variant: _ButtonVariant.secondary,
                        onTap: saving ? null : onSaveDraft,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Post to Everyone
                    Expanded(
                      flex: 2,
                      child: _ActionButton(
                        label: 'Post to Everyone',
                        icon: Icons.send_rounded,
                        loading: saving,
                        variant: _ButtonVariant.primary,
                        onTap: saving ? null : onPost,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout selector strip
// ---------------------------------------------------------------------------

class _LayoutStrip extends StatelessWidget {
  const _LayoutStrip({required this.selectedId, required this.onSelect});
  final MemoryLayoutId selectedId;
  final void Function(MemoryLayoutId) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        itemCount: MemoryLayouts.all.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final layout = MemoryLayouts.all[i];
          return GestureDetector(
            onTap: () => onSelect(layout.id),
            child: Column(
              children: [
                LayoutThumbnail(layout: layout, isSelected: layout.id == selectedId),
                const SizedBox(height: 5),
                Text(
                  layout.name,
                  style: GoogleFonts.inter(
                    fontSize: 8,
                    color: layout.id == selectedId ? Colors.white : Colors.white38,
                    fontWeight: layout.id == selectedId ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Photo strip — tappable slots showing selected photos or placeholders
// ---------------------------------------------------------------------------

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.layout, required this.photos, required this.onSlotTap});
  final MemoryLayout layout;
  final List<XFile?> photos;
  final void Function(int) onSlotTap;

  @override
  Widget build(BuildContext context) {
    final count = layout.maxPhotos;
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final photo = i < photos.length ? photos[i] : null;
          return GestureDetector(
            onTap: () => onSlotTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48, height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: photo != null
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: photo != null
                      ? const Color(0xFF2563EB).withValues(alpha: 0.60)
                      : Colors.white.withValues(alpha: 0.12),
                  width: photo != null ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: photo != null
                    ? _PhotoThumb(path: photo.path)
                    : Icon(Icons.add_rounded, color: Colors.white.withValues(alpha: 0.30), size: 20),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.path});
  final String path;
  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.broken_image_rounded,
        color: Colors.white.withValues(alpha: 0.30),
        size: 20,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action buttons
// ---------------------------------------------------------------------------

enum _ButtonVariant { primary, secondary }

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.variant,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool loading;
  final _ButtonVariant variant;
  final VoidCallback? onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPrimary = widget.variant == _ButtonVariant.primary;
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: isPrimary
                ? const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF1d4ed8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isPrimary ? null : Colors.white.withValues(alpha: 0.07),
            border: Border.all(
              color: isPrimary
                  ? const Color(0xFF2563EB).withValues(alpha: 0.40)
                  : Colors.white.withValues(alpha: 0.12),
            ),
            boxShadow: isPrimary
                ? [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4))]
                : null,
          ),
          child: widget.loading
              ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, size: 15, color: isPrimary ? Colors.white : Colors.white60),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isPrimary ? Colors.white : Colors.white60,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
