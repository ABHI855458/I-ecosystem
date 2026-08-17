import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Deterministic circular avatar — initial + gradient picked by hashing
/// [id]. Same 9-gradient palette as the production group profile screen's
/// identity block (lib/features/groups/group_profile_screen.dart's
/// _IdentityBlock), kept in sync by value since that class is private to
/// its own file.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.id,
    required this.label,
    this.size = 40,
    this.borderColor,
    this.borderWidth = 0,
  });

  final String id;
  final String label;
  final double size;
  final Color? borderColor;
  final double borderWidth;

  static const gradients = <List<Color>>[
    [Color(0xFF667EEA), Color(0xFF764BA2)],
    [Color(0xFFF093FB), Color(0xFFF5576C)],
    [Color(0xFF4FACFE), Color(0xFF00F2FE)],
    [Color(0xFFF7971E), Color(0xFFFFD200)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFFA18CD1), Color(0xFFFBC2EB)],
    [Color(0xFFFF9A56), Color(0xFFFF6F61)],
    [Color(0xFFFC5C7D), Color(0xFF6A82FB)],
    [Color(0xFFC471F5), Color(0xFFFA71CD)],
  ];

  static List<Color> gradientFor(String id) =>
      gradients[id.hashCode.abs() % gradients.length];

  @override
  Widget build(BuildContext context) {
    final colors = gradientFor(id);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: borderWidth > 0 ? Border.all(color: borderColor ?? Colors.black, width: borderWidth) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        label.isNotEmpty ? label[0].toUpperCase() : '?',
        style: GoogleFonts.spaceGrotesk(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Overlapping avatar row — 1a's member row: circles overlapping by
/// [overlap], 2px black border between each, per the design spec.
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.ids,
    required this.labels,
    this.size = 32,
    this.overlap = 11,
  });

  final List<String> ids;
  final List<String> labels;
  final double size;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) return const SizedBox.shrink();
    final step = size - overlap;
    final width = size + step * (ids.length - 1);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < ids.length; i++)
            Positioned(
              left: i * step,
              child: Avatar(
                id: ids[i],
                label: labels[i],
                size: size,
                borderColor: Colors.black,
                borderWidth: 2,
              ),
            ),
        ],
      ),
    );
  }
}
