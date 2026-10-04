import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/glass.dart' show showPingToast;
import '../../core/ping_haptics.dart';
import '../../screens/feed/widgets/face_reaction_capture.dart';
import '../../screens/feed/widgets/realmoji_tray.dart';
import '../../services/ping_realmoji_service.dart';
import '../../services/reaction_preset_service.dart';
import '../../services/realmoji_service.dart';

// ---------------------------------------------------------------------------
// RealMoji reactions in Ping — the picker, the stacked faces, and the "who
// reacted" sheet (explicit request, 2026-10-03: "make the reactions in ping
// RealMoji reactions same as the friends feed ... and create a mechanism to
// see those reactions").
//
// Deliberately reuses the friends feed's own pieces so a ping reaction looks
// and behaves exactly like a feed one:
//   * RealmojiTray — the same picker, saved selfies ringed, a heart first.
//   * FaceReactionCapture — the same selfie camera when an emoji has no
//     saved selfie yet; the shot is saved to the person's RealMoji library
//     (RealmojiService.captureSelfieOnly), so it's there for the feed too.
// ---------------------------------------------------------------------------

const _kCyan = Color(0xFF29D3E8);

/// Opens the RealMoji picker for a reply ([replyId]) or a ping ([pingId]).
/// [onHeart] keeps the quick heart in the same tray (it stays alongside
/// RealMoji). [onReacted] runs after a reaction lands, to refresh the
/// caller's own faces.
Future<void> showPingRealmojiPicker(
  BuildContext context, {
  String? replyId,
  String? pingId,
  VoidCallback? onHeart,
  bool heartLiked = false,
  VoidCallback? onReacted,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .35),
    builder: (sheetCtx) {
      Future<void> react(RealmojiType type) async {
        Navigator.of(sheetCtx).pop();
        try {
          await PingRealmojiService.instance.react(
            replyId: replyId,
            pingId: pingId,
            type: type,
          );
          // A reaction is a little reward of its own.
          unawaited(pingThud());
          onReacted?.call();
        } catch (_) {
          if (context.mounted) {
            showPingToast(context, "Couldn't react.", isError: true);
          }
        }
      }

      Future<void> captureThenReact(RealmojiType type) async {
        Navigator.of(sheetCtx).pop();
        final result = await Navigator.of(context).push<FaceReactionResult>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => FaceReactionCapture(
              presetEmoji: type.glyph,
              title: 'Capture your RealMoji',
              accentColor: _kCyan,
              onFallbackToEmoji: () {
                if (context.mounted) {
                  showPingToast(
                    context,
                    'Front camera needed for a RealMoji.',
                    isError: true,
                  );
                }
              },
            ),
          ),
        );
        if (result == null) return;
        try {
          await RealmojiService.instance.captureSelfieOnly(
            feedScope: ReactionPresetCategory.everyone.wire,
            emojiType: type,
            selfie: result.selfie,
          );
          await PingRealmojiService.instance.react(
            replyId: replyId,
            pingId: pingId,
            type: type,
          );
          unawaited(pingThud());
          onReacted?.call();
        } catch (_) {
          if (context.mounted) {
            showPingToast(context, "Couldn't save that RealMoji.", isError: true);
          }
        }
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          child: Material(
            color: Colors.transparent,
            child: RealmojiTray(
              category: ReactionPresetCategory.everyone,
              onSelect: (preset) {
                // The tray reports a RealMoji pick as "realmoji:<wire>".
                final wire = preset.id.startsWith('realmoji:')
                    ? preset.id.substring('realmoji:'.length)
                    : null;
                if (wire == null) return;
                react(realmojiTypeFromWire(wire));
              },
              onCaptureNeeded: captureThenReact,
              onHeart: onHeart == null
                  ? null
                  : () {
                      Navigator.of(sheetCtx).pop();
                      onHeart();
                    },
              heartLiked: heartLiked,
            ),
          ),
        ),
      );
    },
  );
}

/// A reactor's face: their saved selfie for that emoji, else the emoji.
class PingRealmojiFace extends StatelessWidget {
  const PingRealmojiFace({super.key, required this.r, this.size = 28});
  final PingRealmoji r;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = r.imageUrl;
    final emoji = Center(
      child: Text(r.type.glyph, style: TextStyle(fontSize: size * .55)),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A1A20),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: ClipOval(
        child: url == null || url.isEmpty
            ? emoji
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: (size * 3).round(),
                errorWidget: (_, _, _) => emoji,
              ),
      ),
    );
  }
}

/// Up to three overlapping reactor faces + a count; tapping opens the full
/// "who reacted" sheet. Renders nothing when there are no reactions.
class PingRealmojiStack extends StatelessWidget {
  const PingRealmojiStack({
    super.key,
    required this.reactions,
    this.size = 24,
  });

  final List<PingRealmoji> reactions;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final shown = reactions.take(3).toList();
    final overlap = size * .62;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showPingRealmojiReactors(context, reactions),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size + overlap * (shown.length - 1),
            height: size,
            child: Stack(
              children: [
                for (var i = 0; i < shown.length; i++)
                  Positioned(
                    left: overlap * i,
                    child: PingRealmojiFace(r: shown[i], size: size),
                  ),
              ],
            ),
          ),
          if (reactions.length > 1) ...[
            const SizedBox(width: 5),
            Text(
              '${reactions.length}',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Everyone who reacted, with their RealMoji selfie — the "see the
/// reactions" half of the request.
Future<void> showPingRealmojiReactors(
  BuildContext context,
  List<PingRealmoji> reactions,
) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E12),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              reactions.length == 1
                  ? '1 reaction'
                  : '${reactions.length} reactions',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: reactions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final r = reactions[i];
                  return Row(
                    children: [
                      PingRealmojiFace(r: r, size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          r.isMine ? 'You' : r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Text(r.type.glyph, style: const TextStyle(fontSize: 22)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

