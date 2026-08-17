import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/glass.dart';
import '../../data/layouts.dart';
import '../../models/collage_layout.dart';
import '../../services/memory_service.dart';
import 'studio_canvas.dart';
import 'studio_style_chip.dart';

class CollageStudioScreen extends StatefulWidget {
  final List<String> photoPaths;
  const CollageStudioScreen({super.key, required this.photoPaths});

  @override
  State<CollageStudioScreen> createState() => _CollageStudioScreenState();
}

class _CollageStudioScreenState extends State<CollageStudioScreen> {
  late final List<ImageProvider> _images =
      widget.photoPaths.map<ImageProvider>((p) => FileImage(File(p))).toList();
  late final List<CollageLayout> _styles = _availableStyles();

  int _selected = 0;
  bool _saving = false;
  bool _precaching = true;

  List<CollageLayout> _availableStyles() {
    final n = widget.photoPaths.length;
    final matching = kLayouts.where((l) => l.photoCount == n).toList();
    if (matching.isNotEmpty) return matching;
    // Fallback: closest photoCount below or equal to what's available.
    final sorted = [...kLayouts]..sort((a, b) => a.photoCount.compareTo(b.photoCount));
    return [sorted.lastWhere((l) => l.photoCount <= n, orElse: () => sorted.first)];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _precache());
  }

  Future<void> _precache() async {
    if (widget.photoPaths.isEmpty) {
      setState(() => _precaching = false);
      return;
    }
    await Future.wait(_images.map((img) => precacheImage(img, context)));
    if (mounted) setState(() => _precaching = false);
  }

  Future<void> _save({required bool asDraft}) async {
    if (_styles.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await MemoryService.instance
          .createMemory(
            layoutId: _styles[_selected].id,
            photoPaths: widget.photoPaths,
            isDraft: asDraft,
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      Navigator.of(context)
        ..pop()
        ..pop();
      showGlassToast(context, asDraft ? 'Saved to drafts' : 'Posted to Everyone');
    } catch (e, st) {
      debugPrint('CollageStudioScreen._save failed: $e\n$st');
      if (!mounted) return;
      showGlassToast(
        context,
        'Upload failed — check your connection',
        isError: true,
        actionLabel: 'Retry',
        onAction: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          _save(asDraft: asDraft);
        },
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    'Collage Studio',
                    style: GoogleFonts.plusJakartaSans(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(child: Center(child: _canvasArea())),
            if (_styles.length > 1) _chipCarousel(),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _canvasArea() {
    if (widget.photoPaths.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_mosaic_outlined, color: Colors.white38, size: 56),
          const SizedBox(height: 16),
          Text('Pick your moments',
              style: GoogleFonts.plusJakartaSans(
                  color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Choose 2-4 photos to start a collage',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: _precaching ? _skeleton() : StudioCanvas(layout: _styles[_selected], images: _images),
    );
  }

  Widget _skeleton() {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          color: Colors.white10,
          child: const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white38),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipCarousel() {
    return SizedBox(
      height: 102,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: _styles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => StudioStyleChip(
          layout: _styles[i],
          images: _images,
          selected: i == _selected,
          onTap: () => setState(() => _selected = i),
        ),
      ),
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white70)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.photoPaths.isNotEmpty) ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _saving ? null : () => _save(asDraft: true),
                  child: Text('Save draft', style: GoogleFonts.inter(color: Colors.white70)),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kStudioAccent,
                    disabledBackgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _saving ? null : () => _save(asDraft: false),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text('Save',
                          style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
