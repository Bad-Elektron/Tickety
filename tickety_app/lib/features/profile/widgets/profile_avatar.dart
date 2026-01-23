import 'package:flutter/material.dart';

import '../../../core/graphics/graphics.dart';

/// A circular avatar widget with a gradient background.
///
/// Used in the app header for profile navigation. Features
/// circular ink splash feedback and customizable size.
class ProfileAvatar extends StatelessWidget {
  /// Callback when the avatar is tapped.
  final VoidCallback? onTap;

  /// Diameter of the avatar.
  final double size;

  /// Seed for the gradient colors.
  final int seed;

  const ProfileAvatar({
    super.key,
    this.onTap,
    this.size = 40,
    this.seed = 42,
  });

  @override
  Widget build(BuildContext context) {
    final config = NoisePresets.vibrantEvents(seed);

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
                Icons.person_outline,
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
