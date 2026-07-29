import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/feed_service.dart';

class SinglePostDetailScreen extends StatefulWidget {
  const SinglePostDetailScreen({super.key, required this.item});
  final FeedItem item;

  @override
  State<SinglePostDetailScreen> createState() => _SinglePostDetailScreenState();
}

class _SinglePostDetailScreenState extends State<SinglePostDetailScreen> {
  bool _liked = false;
  int _likes = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 20),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background
          _buildBlurredBg(),
          // Centered photo
          Center(child: _buildPhoto()),
          // Bottom content
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFooter(),
          ),
        ],
      ),
    );
  }

  Widget _buildBlurredBg() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPhotoWidget(fit: BoxFit.cover),
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),
      ],
    );
  }

  Widget _buildPhoto() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 160),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _buildPhotoWidget(fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildPhotoWidget({required BoxFit fit}) {
    final item = widget.item;
    if (item.photoPath != null) {
      return Image.file(File(item.photoPath!), fit: fit);
    }
    if (item.photoUrl != null) {
      return CachedNetworkImage(imageUrl: item.photoUrl!, fit: fit);
    }
    final color = _hashColor(item.postId);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Color _hashColor(String id) {
    const colors = [
      Color(0xFF1C2A3C),
      Color(0xFF301A28),
      Color(0xFF1E2C1E),
      Color(0xFF2A1A10),
      Color(0xFF1A203C),
    ];
    return colors[id.hashCode.abs() % colors.length];
  }

  Widget _buildFooter() {
    final item = widget.item;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.caption != null && item.caption!.isNotEmpty)
              Text(
                item.caption!,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            if (item.musicTitle != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.music_note, color: Colors.white54, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${item.musicTitle}${item.musicArtist != null ? ' · ${item.musicArtist}' : ''}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _liked = !_liked;
                      _likes += _liked ? 1 : -1;
                    });
                  },
                  child: Row(
                    children: [
                      Icon(
                        _liked ? Icons.favorite : Icons.favorite_border,
                        color: _liked
                            ? const Color(0xFFE1306C)
                            : Colors.white54,
                        size: 22,
                      ),
                      if (_likes > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '$_likes',
                          style: TextStyle(
                            color: _liked
                                ? const Color(0xFFE1306C)
                                : Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: () {},
                  child: const Icon(Icons.chat_bubble_outline,
                      color: Colors.white54, size: 22),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {},
                  child: const Icon(Icons.share_outlined,
                      color: Colors.white54, size: 22),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
