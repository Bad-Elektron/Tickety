import 'package:flutter/material.dart';

import '../../../core/graphics/graphics.dart';

/// A circular action button with a gradient background.
///
/// Uses the same gradient style as ProfileAvatar and carousel cards.
class GradientActionButton extends StatelessWidget {
  /// The icon to display.
  final IconData icon;

  /// Callback when tapped.
  final VoidCallback? onTap;

  /// Size of the button.
  final double size;

  /// Seed for gradient colors.
  final int seed;

  const GradientActionButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 40,
    this.seed = 108,
  });

  @override
  Widget build(BuildContext context) {
    final config = NoisePresets.sunset(seed);

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: config.colors,
              ),
              boxShadow: [
                BoxShadow(
                  color: config.colors.first.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                icon,
                color: const Color(0xE6FFFFFF),
                size: size * 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
