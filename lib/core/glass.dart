import 'dart:ui';
import 'package:flutter/material.dart';
import 'constants.dart';

/// Frosted glass container — wrap any widget for the glass effect.
class GlassBox extends StatelessWidget {
  const GlassBox({
    super.key,
    required this.child,
    this.borderRadius = 20.0,
    this.blur = 24.0,
    this.opacity = 0.10,
    this.borderOpacity = 0.15,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final double opacity;
  final double borderOpacity;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: borderOpacity),
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Instagram gradient button decoration.
BoxDecoration instaGradientDecoration({double radius = 14}) => BoxDecoration(
      gradient: AppColors.instaGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF833AB4).withValues(alpha: 0.40),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    );

/// Glass surface decoration (frosted).
BoxDecoration glassDecoration({double radius = 14}) => BoxDecoration(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.15),
        width: 1.0,
      ),
    );

/// A toast in the app's standard frosted-glass style. Pass [actionLabel] +
/// [onAction] for a recoverable-error toast with a retry button.
void showGlassToast(
  BuildContext context,
  String message, {
  bool isError = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 5 : 3),
        content: GlassBox(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? Colors.redAccent : Colors.greenAccent,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
}
