import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/collage_layout.dart';
import '../../widgets/memory_canvas.dart';

const kStudioAccent = Color(0xFF00FFF7);

/// A 64x64 chip rendering a tiny live preview of a collage style.
class StudioStyleChip extends StatelessWidget {
  final CollageLayout layout;
  final List<ImageProvider?> images;
  final bool selected;
  final VoidCallback onTap;

  const StudioStyleChip({
    super.key,
    required this.layout,
    required this.images,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? kStudioAccent : Colors.white24,
                width: selected ? 3 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: kStudioAccent.withValues(alpha: 0.45),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: RepaintBoundary(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: 90,
                  height: 160,
                  child: IgnorePointer(
                    child: MemoryCanvas(layout: layout, images: images),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 64,
            child: Text(
              layout.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 9,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
