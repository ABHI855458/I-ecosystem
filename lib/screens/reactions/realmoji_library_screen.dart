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
    // Guarded: _load is awaited from _capture and _handleTap, both of which
    // resume after a pushed route pops — by which time this screen may be
    // gone (RefreshIndicator's onRefresh calls it too). Reproduced live on
    // device: "[RealmojiLibraryScreen._capture] failed: setState() called
    // after dispose", which then took the whole run down.
    if (!mounted) return;
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
      if (!mounted) return;
      await _load();
    } catch (e, st) {
      debugPrint('[RealmojiLibraryScreen._capture] failed: $e\n$st');
      if (!mounted) return;
      if (context.mounted) {
        showGlassToast(context, "Couldn't save your RealMoji.", isError: true);
      }
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
      // Synchronous now — see RealmojiService.retake's own doc: it only
      // clears the client-side cache entry so the picker below re-opens the
      // camera, it no longer touches the DB/storage (that used to destroy
      // the existing RealMoji even if this capture attempt was cancelled).
      RealmojiService.instance.retake(feedScope: widget.feedScope.wire, emojiType: type);
      if (!mounted) return;
      setState(() => _saved = {...?_saved}..remove(type));
    } catch (e, st) {
      debugPrint('[RealmojiLibraryScreen._handleTap] retake failed: $e\n$st');
    }
    if (!mounted) return;
    await _capture(type);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.feedScope == ReactionPresetCategory.everyone ? 'Everyone' : 'Anon';
    return Scaffold(
      // 1A canvas token (#0b0b0d), not flat black — the slot cards read as
      // surfaces against it.
      backgroundColor: const Color(0xFF0B0B0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0D),
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
          mainAxisSpacing: 22,
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

/// One RealMoji slot, built to the handoff's **variant 1A** (Profile Card —
/// stacked card): a circular photo with a decorative ring floating 6px
/// outside it, the reaction emoji sitting directly ON the photo's
/// bottom-right with NO background plate, and the name centred beneath.
///
/// The badge placement is the substantive change, not just the styling. It
/// used to be rendered INSIDE the photo's `ClipOval`, aligned bottom-right
/// with a 4px margin — so the circular clip sliced almost all of it away and
/// only a crescent of colour survived at the rim ("see the emoji is not
/// seen"). 1A puts it outside the clip, over the photo, which is why it
/// reads at any size.
///
/// Every 1A measurement is proportional to the photo rather than the spec's
/// literal 168px box, so the same card holds up in this 3-column grid and
/// would hold up at the spec's own size: ring inset and badge box are
/// expressed as fractions of the photo's diameter (6/168, 52/168, 32/168).
class _RealmojiSlot extends StatelessWidget {
  const _RealmojiSlot({required this.type, required this.imageUrl, required this.onTap});
  final RealmojiType type;
  final String? imageUrl;
  final VoidCallback onTap;

  // 1A ratios, against the spec's 168px photo.
  static const _ringInsetRatio = 6 / 168;
  static const _badgeBoxRatio = 52 / 168;
  static const _badgeFontRatio = 32 / 168;
  static const _badgeOffsetRatio = 2 / 168;

  @override
  Widget build(BuildContext context) {
    final captured = imageUrl != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                // The ring lives outside the photo, so the photo has to give
                // that space back or the ring clips against the grid cell.
                final inset = c.maxHeight * _ringInsetRatio;
                final d = c.maxHeight - inset * 2;
                final badge = d * _badgeBoxRatio;
                return Center(
                  child: SizedBox(
                    width: c.maxHeight,
                    height: c.maxHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Decorative ring — 1.5px #2e2e33 at inset -6. It
                        // takes the accent once a selfie exists, which is
                        // this screen's only "captured / not yet" signal now
                        // that the badge no longer sits in a plate.
                        Container(
                          width: d + inset * 2,
                          height: d + inset * 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: captured ? AppColors.neonCyan : const Color(0xFF2E2E33),
                              width: 1.5,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: d,
                          height: d,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Container(
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF161618),
                                  ),
                                  child: ClipOval(
                                    child: captured
                                        ? CachedNetworkImage(
              memCacheWidth: 1080,
                                            imageUrl: imageUrl!,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, _, _) => Center(
                                              child: Text(
                                                type.glyph,
                                                style: TextStyle(fontSize: d * 0.3),
                                              ),
                                            ),
                                          )
                                        : Center(
                                            child: Icon(
                                              Icons.photo_camera_rounded,
                                              size: d * 0.3,
                                              color: Colors.white.withValues(alpha: 0.22),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              // 1A: over the photo, no background plate.
                              // Outside the ClipOval above — that clip is
                              // what used to eat it.
                              Positioned(
                                right: d * _badgeOffsetRatio,
                                bottom: d * _badgeOffsetRatio,
                                width: badge,
                                height: badge,
                                child: Center(
                                  child: Text(
                                    type.glyph,
                                    style: TextStyle(
                                      fontSize: d * _badgeFontRatio,
                                      shadows: const [
                                        // The spec's badge has no plate, so
                                        // the glyph needs its own separation
                                        // from whatever photo is behind it.
                                        Shadow(color: Color(0xCC000000), blurRadius: 6),
                                      ],
                                    ),
                                  ),
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
          ),
          const SizedBox(height: 10),
          // 1A's name block: Space Grotesk 600, tight tracking, primary ink.
          Text(
            type.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: captured ? const Color(0xFFF4F4F5) : const Color(0xFF7D7D84),
              letterSpacing: -0.01 * 13,
            ),
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
              child: CachedNetworkImage(
              memCacheWidth: 192,imageUrl: imageUrl, width: 64, height: 64, fit: BoxFit.cover),
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
