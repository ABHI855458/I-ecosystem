import 'package:flutter/material.dart';

/// The row of thin bars across the top of a story: one per item, filled up
/// to the one on screen, which fills as [progress] runs. Shared by the
/// highlight story and the reply story so the two read as the same thing.
class StoryProgressBars extends StatelessWidget {
  const StoryProgressBars({
    super.key,
    required this.count,
    required this.index,
    required this.progress,
  });

  final int count;
  final int index;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 2.6,
                child: i == index
                    ? AnimatedBuilder(
                        animation: progress,
                        builder: (_, _) => LinearProgressIndicator(
                          value: progress.value,
                          backgroundColor: Colors.white.withValues(
                            alpha: 0.26,
                          ),
                          valueColor: const AlwaysStoppedAnimation(
                            Colors.white,
                          ),
                        ),
                      )
                    : ColoredBox(
                        color: Colors.white.withValues(
                          alpha: i < index ? 1 : 0.26,
                        ),
                      ),
              ),
            ),
          ),
          if (i < count - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}
