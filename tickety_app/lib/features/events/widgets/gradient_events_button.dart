import 'package:flutter/material.dart';

import '../../../core/graphics/graphics.dart';

/// A circular events button with a gradient background.
class GradientEventsButton extends StatelessWidget {
  /// Callback when tapped.
  final VoidCallback? onTap;

  /// Size of the button.
  final double size;

  /// Seed for gradient colors.
  final int seed;

  const GradientEventsButton({
    super.key,
    this.onTap,
    this.size = 40,
    this.seed = 999,
  });

  @override
  Widget build(BuildContext context) {
    final config = NoisePresets.darkMood(seed);

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
                  color: config.colors.last.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.event_note_outlined,
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
