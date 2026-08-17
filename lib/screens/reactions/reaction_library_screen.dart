import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants.dart';
import '../../core/glass.dart';
import '../../services/reaction_preset_service.dart';
import '../../widgets/emoji_selection_row.dart';
import '../feed/widgets/face_reaction_capture.dart';
import '../feed/widgets/reaction_preset_tray.dart' show PresetAvatar;

// ---------------------------------------------------------------------------
// runAddPresetFlow — Part 2's add flow (emoji, then camera for Everyone),
// pulled out as a standalone function rather than private State method so
// BOTH this screen's own "+" tile AND the quick-pick tray's "+ add new"
// (reaction_preset_tray.dart, wired from post_card_shared.dart) drive the
// exact same flow — per spec, "+ add new" should "jump into the Part 2 add
// flow directly," not a reimplementation of it.
//
// Returns the saved ReactionPreset, or null if the user backed out at any
// step or the save itself failed (a real error is surfaced via toast before
// returning null — never swallowed silently).
// ---------------------------------------------------------------------------

Future<ReactionPreset?> runAddPresetFlow(
  BuildContext context,
  ReactionPresetCategory category,
) async {
  final emoji = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const EmojiSelectionRow(title: 'Pick an emoji for your reaction'),
  );
  if (emoji == null || !context.mounted) return null;

  if (category == ReactionPresetCategory.anonymous) {
    // Anonymous presets are emoji-only, always — no camera step, ever (a
    // real face on the anon feed breaks anonymity). This is the ONLY
    // branch that can ever produce an anonymous-category preset.
    try {
      return await ReactionPresetService.instance.addAnonymousPreset(emoji: emoji);
    } catch (e, st) {
      debugPrint('[runAddPresetFlow] addAnonymousPreset failed: $e\n$st');
      if (context.mounted) {
        showGlassToast(context, "Couldn't save your reaction.", isError: true);
      }
      return null;
    }
  }

  // Everyone category — emoji was picked FIRST (the reverse of the live
  // in-post reaction flow, which captures the selfie first); reusing
  // FaceReactionCapture with presetEmoji locks that choice in and skips
  // its internal post-capture emoji row entirely.
  // Full-screen push, not a sheet — see FaceReactionCapture's own doc.
  final result = await Navigator.of(context).push<FaceReactionResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => FaceReactionCapture(
        presetEmoji: emoji,
        title: 'Create your reaction',
        // Everyone presets always require a selfie (no emoji-only variant
        // exists for this category) — if the camera genuinely isn't
        // available there's nothing useful to fall back to here, so this
        // just explains why before the widget pops itself with null.
        onFallbackToEmoji: () {
          if (context.mounted) {
            showGlassToast(
              context,
              'Front camera needed to create this reaction — try again once it\'s available.',
              isError: true,
            );
          }
        },
      ),
    ),
  );
  if (result == null || !context.mounted) return null;

  try {
    return await ReactionPresetService.instance.addEveryonePreset(
      emoji: result.emoji,
      selfie: result.selfie,
    );
  } catch (e, st) {
    debugPrint('[runAddPresetFlow] addEveryonePreset failed: $e\n$st');
    if (context.mounted) {
      showGlassToast(context, "Couldn't save your reaction.", isError: true);
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// ReactionLibraryScreen — Part 2. Opened from the feed's persistent
// top-left entry icon (see home_screen.dart's _ReactionLibraryEntryButton).
// Two categories, each with its own independently-loaded preset grid: a
// user's Anonymous presets and Everyone presets are entirely separate sets
// (reaction_preset_service.dart), so failing to load one never blocks the
// other.
// ---------------------------------------------------------------------------

class ReactionLibraryScreen extends StatefulWidget {
  const ReactionLibraryScreen({super.key, this.initialCategory = ReactionPresetCategory.anonymous});

  /// Which tab (Anon / Friends) opens first — the calling post card passes
  /// its own feed's category (see post_card_shared.dart's
  /// openReactionLibrary), so tapping the library button on a Friends-feed
  /// post lands straight on Friends instead of always defaulting to Anon.
  final ReactionPresetCategory initialCategory;

  @override
  State<ReactionLibraryScreen> createState() => _ReactionLibraryScreenState();
}

class _ReactionLibraryScreenState extends State<ReactionLibraryScreen> {
  late ReactionPresetCategory _tab = widget.initialCategory;

  final Map<ReactionPresetCategory, List<ReactionPreset>?> _presets = {
    ReactionPresetCategory.anonymous: null,
    ReactionPresetCategory.everyone: null,
  };
  final Map<ReactionPresetCategory, String?> _errors = {
    ReactionPresetCategory.anonymous: null,
    ReactionPresetCategory.everyone: null,
  };

  @override
  void initState() {
    super.initState();
    _load(ReactionPresetCategory.anonymous);
    _load(ReactionPresetCategory.everyone);
  }

  Future<void> _load(ReactionPresetCategory category, {bool forceRefresh = false}) async {
    setState(() => _errors[category] = null);
    try {
      final presets =
          await ReactionPresetService.instance.fetchPresets(category, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() => _presets[category] = presets);
    } catch (e, st) {
      debugPrint('[ReactionLibraryScreen._load] fetchPresets($category) failed: $e\n$st');
      if (!mounted) return;
      setState(() => _errors[category] = "Couldn't load your reactions.");
    }
  }

  Future<void> _addPreset(ReactionPresetCategory category) async {
    final preset = await runAddPresetFlow(context, category);
    if (preset == null || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _presets[category] = [...(_presets[category] ?? const []), preset];
    });
  }

  Future<void> _deletePreset(ReactionPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmDialog(preset: preset),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ReactionPresetService.instance.deletePreset(preset);
      if (!mounted) return;
      setState(() {
        _presets[preset.category] =
            (_presets[preset.category] ?? const []).where((p) => p.id != preset.id).toList();
      });
    } catch (e, st) {
      debugPrint('[ReactionLibraryScreen._deletePreset] deletePreset(${preset.id}) failed: $e\n$st');
      if (mounted) showGlassToast(context, "Couldn't delete that reaction.", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Your Reactions',
          style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Record a reaction once, then react instantly on any post — no fresh selfie every time.',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.55), height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: _CategoryToggle(
              active: _tab,
              onChanged: (c) => setState(() => _tab = c),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildCategoryBody(_tab)),
        ],
      ),
    );
  }

  Widget _buildCategoryBody(ReactionPresetCategory category) {
    final error = _errors[category];
    if (error != null) {
      return _ErrorState(message: error, onRetry: () => _load(category, forceRefresh: true));
    }
    final presets = _presets[category];
    if (presets == null) {
      return const _LoadingGrid();
    }
    return RefreshIndicator(
      onRefresh: () => _load(category, forceRefresh: true),
      color: AppColors.coral,
      backgroundColor: AppColors.cardSurface,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 18,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: presets.length + 1,
        itemBuilder: (context, i) {
          if (i == presets.length) {
            return _AddTile(onTap: () => _addPreset(category));
          }
          final preset = presets[i];
          return _PresetTile(
            preset: preset,
            onDelete: () => _deletePreset(preset),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category toggle — Anonymous / Everyone, same pill-toggle visual language
// as HomeScreen's own feed switcher (_FeedToggle), rebuilt locally since
// that one is private to home_screen.dart.
// ---------------------------------------------------------------------------

class _CategoryToggle extends StatelessWidget {
  const _CategoryToggle({required this.active, required this.onChanged});
  final ReactionPresetCategory active;
  final ValueChanged<ReactionPresetCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.coral.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.coral.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip('Anon', ReactionPresetCategory.anonymous),
          _chip('Friends', ReactionPresetCategory.everyone),
        ],
      ),
    );
  }

  Widget _chip(String label, ReactionPresetCategory category) {
    final isActive = active == category;
    return GestureDetector(
      onTap: () => onChanged(category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        height: double.infinity,
        decoration: BoxDecoration(
          color: isActive ? AppColors.coral.withValues(alpha: 0.85) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grid tiles — a saved preset (long-press to delete) and the trailing "+"
// tile. PresetAvatar (reaction_preset_tray.dart) is the same visual used in
// the quick-pick tray, so a preset looks identical wherever it shows up.
// ---------------------------------------------------------------------------

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.onDelete});
  final ReactionPreset preset;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onDelete();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PresetAvatar(preset: preset, size: 60),
          const SizedBox(height: 8),
          Text(
            'Hold to delete',
            style: GoogleFonts.inter(fontSize: 9, color: Colors.white.withValues(alpha: 0.32)),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white70, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            'Add new',
            style: GoogleFonts.inter(fontSize: 9, color: Colors.white.withValues(alpha: 0.32)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading / error states — shimmer while fetching, real error + retry on
// failure (never swallowed).
// ---------------------------------------------------------------------------

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.cardSurface,
      highlightColor: AppColors.cardSurface.withValues(alpha: 0.5),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 18,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        itemCount: 8,
        itemBuilder: (context, i) => const Center(
          child: CircleAvatar(radius: 30, backgroundColor: Colors.white),
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
            Icon(Icons.error_outline, color: AppColors.errorRed.withValues(alpha: 0.85), size: 28),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(color: AppColors.coral, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Retry',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Delete confirmation
// ---------------------------------------------------------------------------

class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({required this.preset});
  final ReactionPreset preset;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16151A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Delete this reaction?',
        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      content: Text(
        "You'll lose ${preset.emoji} — this can't be undone.",
        style: GoogleFonts.inter(fontSize: 13, color: Colors.white70, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Delete', style: GoogleFonts.inter(color: AppColors.errorRed, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
