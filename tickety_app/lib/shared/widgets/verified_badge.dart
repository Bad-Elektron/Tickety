import 'package:flutter/material.dart';

/// A small verified badge (shield/checkmark) shown next to organizer names.
///
/// Uses the app's primary indigo color for consistency.
class VerifiedBadge extends StatelessWidget {
  final double size;

  const VerifiedBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.verified,
      size: size,
      color: const Color(0xFF6366F1), // App primary indigo
    );
  }
}
