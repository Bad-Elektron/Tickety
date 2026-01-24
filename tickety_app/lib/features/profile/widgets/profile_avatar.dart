import 'package:flutter/material.dart';

import '../../../core/graphics/graphics.dart';
import '../../../core/state/state.dart';

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
    final appState = AppState();

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return RepaintBoundary(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: size + 6,
                height: size + 6,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
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
                    // Tier badge
                    Positioned(
                      top: -2,
                      right: 0,
                      child: _TierBadge(
                        tier: appState.tier,
                        size: size * 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier, required this.size});

  final AccountTier tier;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tierColor = Color(tier.color);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tierColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).scaffoldBackgroundColor,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: tierColor.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(
        _getIcon(),
        size: size * 0.55,
        color: Colors.white,
      ),
    );
  }

  IconData _getIcon() {
    switch (tier) {
      case AccountTier.base:
        return Icons.person;
      case AccountTier.pro:
        return Icons.star;
      case AccountTier.enterprise:
        return Icons.diamond;
    }
  }
}
