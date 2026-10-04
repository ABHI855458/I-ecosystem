import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../features/profile_v2/profile_navigation.dart';
import '../../../services/realmoji_service.dart';

// ---------------------------------------------------------------------------
// RealmojiReactorStack — Everyone feed only. Small overlapping circular
// selfie avatars stacked along the bottom of a post (per spec item 4),
// distinct from ReactorCluster (reactor_cluster.dart)'s floating corner
// bob-animation cluster: this is a plain horizontal row of REAL captured
// RealMoji selfies, not profile avatars, and it opens a full reactor list
// on tap rather than just showing a count.
// ---------------------------------------------------------------------------

class RealmojiReactorStack extends StatelessWidget {
  const RealmojiReactorStack({
    super.key,
    required this.reactors,
    this.avatarSize = 26,
    this.maxShown = 5,
  });

  /// Newest-first, from RealmojiService.fetchReactors.
  final List<RealmojiReaction> reactors;
  final double avatarSize;
  final int maxShown;

  @override
  Widget build(BuildContext context) {
    if (reactors.isEmpty) return const SizedBox.shrink();
    final shown = reactors.take(maxShown).toList();
    final overflow = reactors.length - shown.length;

    return GestureDetector(
      onTap: () => _showFullList(context),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: avatarSize,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: avatarSize + (shown.length - 1) * (avatarSize * 0.62),
              height: avatarSize,
              child: Stack(
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: i * (avatarSize * 0.62),
                      child: _ReactorAvatar(reaction: shown[i], size: avatarSize),
                    ),
                ],
              ),
            ),
            if (overflow > 0) ...[
              const SizedBox(width: 6),
              Text(
                '+$overflow',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFullList(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ReactorListSheet(reactors: reactors),
    );
  }
}

class _ReactorAvatar extends StatelessWidget {
  const _ReactorAvatar({required this.reaction, required this.size});
  final RealmojiReaction reaction;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badgeSize = size * 0.5;
    return SizedBox(
      width: size + badgeSize / 2,
      height: size + badgeSize / 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: ClipOval(
              child: reaction.selfieUrl == null
                  ? Container(
                      color: const Color(0xFF17171B),
                      alignment: Alignment.center,
                      child: Text(reaction.emojiType.glyph,
                          style: TextStyle(fontSize: size * 0.5)),
                    )
                  : CachedNetworkImage(
              memCacheWidth: 1080,
                      imageUrl: reaction.selfieUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(color: const Color(0xFF17171B)),
                    ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
              child: Text(reaction.emojiType.glyph, style: TextStyle(fontSize: badgeSize * 0.55)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactorListSheet extends StatelessWidget {
  const _ReactorListSheet({required this.reactors});
  final List<RealmojiReaction> reactors;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(
                '${reactors.length} reactions',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: reactors.length,
                itemBuilder: (context, i) {
                  final r = reactors[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        openProfile(context, r.userId);
                      },
                      child: Row(
                        children: [
                          _ReactorAvatar(reaction: r, size: 34),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              r.userName,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(r.emojiType.glyph, style: const TextStyle(fontSize: 18)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
