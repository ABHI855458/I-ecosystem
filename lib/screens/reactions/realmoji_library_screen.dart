import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/glass.dart';
import '../../services/reaction_preset_service.dart' show ReactionPresetCategory, ReactionPresetCategoryWire;
import '../../services/realmoji_service.dart';
import '../feed/widgets/face_reaction_capture.dart';

// ---------------------------------------------------------------------------
// RealmojiLibraryScreen — REPLACES ReactionLibraryScreen as the destination
// of the header's top-right '+' (see post_card_shared.dart's
// openReactionLibrary / home_screen.dart's _SlimHeader call site). Single
// scope, not a toggle — the caller passes whichever feed tab is currently
// active (home_screen.dart already tracks this via _tabIndex), since
// managing "my Anon RealMojis" while looking at the Everyone tab makes no
// sense. Fixed 6-slot grid (RealmojiType.values), not an open-ended
// add-more grid like the old library — every slot always exists, it's
// either captured (shows the selfie) or not (shows the bare glyph).
// ---------------------------------------------------------------------------

class RealmojiLibraryScreen extends StatefulWidget {
  const RealmojiLibraryScreen({super.key, required this.feedScope});

  final ReactionPresetCategory feedScope;

  @override
  State<RealmojiLibraryScreen> createState() => _RealmojiLibraryScreenState();
}

class _RealmojiLibraryScreenState extends State<RealmojiLibraryScreen> {
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
      final saved = await RealmojiService.instance.savedSelfies(feedScope: widget.feedScope.wire);
      if (!mounted) return;
      setState(() => _saved = saved);
    } catch (e, st) {
      debugPrint('[RealmojiLibraryScreen._load] savedSelfies(${widget.feedScope}) failed: $e\n$st');
      if (!mounted) return;
      setState(() => _error = "Couldn't load your RealMojis.");
    }
  }

  Future<void> _capture(RealmojiType type) async {
    // Full-screen push, not a sheet — see FaceReactionCapture's own doc.
    final result = await Navigator.of(context).push<FaceReactionResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FaceReactionCapture(
          presetEmoji: type.glyph,
          title: 'Capture your RealMoji',
          accentColor: AppColors.neonCyan,
          onFallbackToEmoji: () {
            if (mounted) {
              showGlassToast(
                context,
                'Front camera needed for a RealMoji — try again once it\'s available.',
                isError: true,
              );
            }
          },
        ),
      ),
    );
    if (result == null || !mounted) return;

    try {
      // Capture-only, no reaction — this screen manages saved selfies, it
      // has no post to react to. RealmojiService.captureAndReact bundles
      // upload+save+react as one write for the in-post flow; here we only
      // need the upload+save half, done directly against the same table.
      await RealmojiService.instance.captureSelfieOnly(
        feedScope: widget.feedScope.wire,
        emojiType: type,
        selfie: result.selfie,
      );
      HapticFeedback.mediumImpact();
      await _load();
    } catch (e, st) {
      debugPrint('[RealmojiLibraryScreen._capture] failed: $e\n$st');
      if (mounted) showGlassToast(context, "Couldn't save your RealMoji.", isError: true);
    }
  }

  Future<void> _handleTap(RealmojiType type) async {
    final url = _saved?[type];
    if (url == null) {
      await _capture(type);
      return;
    }
    final retake = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RetakeSheet(type: type, imageUrl: url),
    );
    if (retake != true || !mounted) return;

    try {
      await RealmojiService.instance.retake(feedScope: widget.feedScope.wire, emojiType: type);
      if (!mounted) return;
      setState(() => _saved = {...?_saved}..remove(type));
    } catch (e, st) {
      debugPrint('[RealmojiLibraryScreen._handleTap] retake failed: $e\n$st');
    }
    await _capture(type);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.feedScope == ReactionPresetCategory.everyone ? 'Everyone' : 'Anon';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          'Your RealMojis · $title',
          style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Capture a selfie for each RealMoji once, then react instantly on any post.',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.55), height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    final saved = _saved;
    if (saved == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.neonCyan, strokeWidth: 2));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.neonCyan,
      backgroundColor: const Color(0xFF17171B),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 20,
          crossAxisSpacing: 14,
          // Was 0.82 — at a 3-column cell width around ~107px (typical
          // phone width), that only left ~23.5px of vertical slack above
          // the square circle for the 8px gap + 12px label, and the label's
          // actual line box (font metrics, not just fontSize) needed ~24px,
          // overflowing by a hairline (~0.56px) on every row. 0.76 gives
          // ~35px of slack at the same cell width — comfortable margin
          // without visibly loosening the grid.
          childAspectRatio: 0.76,
        ),
        itemCount: RealmojiType.values.length,
        itemBuilder: (context, i) {
          final type = RealmojiType.values[i];
          return _RealmojiSlot(
            type: type,
            imageUrl: saved[type],
            onTap: () => _handleTap(type),
          );
        },
      ),
    );
  }
}

class _RealmojiSlot extends StatelessWidget {
  const _RealmojiSlot({required this.type, required this.imageUrl, required this.onTap});
  final RealmojiType type;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF17171B),
                border: Border.all(
                  color: imageUrl != null ? AppColors.neonCyan : Colors.white24,
                  width: imageUrl != null ? 2 : 1,
                ),
              ),
              child: ClipOval(
                child: imageUrl == null
                    ? Center(child: Text(type.glyph, style: const TextStyle(fontSize: 30)))
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
                              child: Text(type.glyph, style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            type.name,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _RetakeSheet extends StatelessWidget {
  const _RetakeSheet({required this.type, required this.imageUrl});
  final RealmojiType type;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xFF0D0D12), borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: CachedNetworkImage(imageUrl: imageUrl, width: 64, height: 64, fit: BoxFit.cover),
            ),
            const SizedBox(height: 10),
            Text(
              'Retake your ${type.glyph} RealMoji?',
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(color: AppColors.neonCyan, borderRadius: BorderRadius.circular(14)),
                child: Center(
                  child: Text('Retake',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Center(
                  child: Text('Cancel',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white54)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white54, height: 1.5)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(color: AppColors.neonCyan, borderRadius: BorderRadius.circular(12)),
                child: Text('Retry',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
