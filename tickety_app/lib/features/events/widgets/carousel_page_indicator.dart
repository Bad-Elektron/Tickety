import 'package:flutter/material.dart';

/// Configuration for the carousel page indicator appearance.
@immutable
class CarouselIndicatorStyle {
  /// Size of each indicator dot.
  final double dotSize;

  /// Width of the active (selected) indicator.
  final double activeDotWidth;

  /// Spacing between dots.
  final double spacing;

  /// Color of inactive dots.
  final Color inactiveColor;

  /// Color of the active dot.
  final Color activeColor;

  /// Duration of the animation when changing pages.
  final Duration animationDuration;

  /// Curve of the animation.
  final Curve animationCurve;

  const CarouselIndicatorStyle({
    this.dotSize = 8.0,
    this.activeDotWidth = 24.0,
    this.spacing = 8.0,
    this.inactiveColor = const Color(0x80FFFFFF),
    this.activeColor = Colors.white,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeInOut,
  });

  /// Creates a copy with modified properties.
  CarouselIndicatorStyle copyWith({
    double? dotSize,
    double? activeDotWidth,
    double? spacing,
    Color? inactiveColor,
    Color? activeColor,
    Duration? animationDuration,
    Curve? animationCurve,
  }) {
    return CarouselIndicatorStyle(
      dotSize: dotSize ?? this.dotSize,
      activeDotWidth: activeDotWidth ?? this.activeDotWidth,
      spacing: spacing ?? this.spacing,
      inactiveColor: inactiveColor ?? this.inactiveColor,
      activeColor: activeColor ?? this.activeColor,
      animationDuration: animationDuration ?? this.animationDuration,
      animationCurve: animationCurve ?? this.animationCurve,
    );
  }
}

/// A page indicator with animated dots for carousels.
///
/// This widget displays a row of dots that indicate the current page
/// in a carousel or page view. The active dot expands to be wider
/// than inactive dots.
///
/// Example usage:
/// ```dart
/// CarouselPageIndicator(
///   itemCount: 5,
///   currentIndex: _currentPage,
///   onDotTapped: (index) => _pageController.animateToPage(index),
/// )
/// ```
class CarouselPageIndicator extends StatelessWidget {
  /// Total number of pages/items in the carousel.
  final int itemCount;

  /// Currently active page index (0-based).
  final int currentIndex;

  /// Callback when a dot is tapped. If null, dots are not interactive.
  final ValueChanged<int>? onDotTapped;

  /// Visual style configuration.
  final CarouselIndicatorStyle style;

  const CarouselPageIndicator({
    super.key,
    required this.itemCount,
    required this.currentIndex,
    this.onDotTapped,
    this.style = const CarouselIndicatorStyle(),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        itemCount,
        (index) => _buildDot(index),
      ),
    );
  }

  Widget _buildDot(int index) {
    final isActive = index == currentIndex;

    return GestureDetector(
      onTap: onDotTapped != null ? () => onDotTapped!(index) : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: style.spacing / 2),
        child: AnimatedContainer(
          duration: style.animationDuration,
          curve: style.animationCurve,
          width: isActive ? style.activeDotWidth : style.dotSize,
          height: style.dotSize,
          decoration: BoxDecoration(
            color: isActive ? style.activeColor : style.inactiveColor,
            borderRadius: BorderRadius.circular(style.dotSize / 2),
          ),
        ),
      ),
    );
  }
}

/// A page indicator that animates smoothly based on page scroll position.
///
/// Unlike [CarouselPageIndicator], this variant uses a [PageController]
/// to provide smooth, physics-based animations as the user scrolls.
/// Uses AnimatedBuilder for efficient rebuilds during scrolling.
class SmoothCarouselPageIndicator extends StatelessWidget {
  /// Controller for the associated PageView.
  final PageController controller;

  /// Total number of pages.
  final int itemCount;

  /// Callback when a dot is tapped.
  final ValueChanged<int>? onDotTapped;

  /// Visual style configuration.
  final CarouselIndicatorStyle style;

  const SmoothCarouselPageIndicator({
    super.key,
    required this.controller,
    required this.itemCount,
    this.onDotTapped,
    this.style = const CarouselIndicatorStyle(),
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final currentPage = controller.hasClients
              ? (controller.page ?? controller.initialPage.toDouble())
              : controller.initialPage.toDouble();

          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              itemCount,
              (index) => _buildDot(index, currentPage),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDot(int index, double currentPage) {
    // Calculate how "active" this dot should be (0.0 to 1.0)
    final distance = (currentPage - index).abs();
    final activeRatio = (1.0 - distance).clamp(0.0, 1.0);

    // Interpolate width based on how close we are to this index
    final width = style.dotSize +
        (style.activeDotWidth - style.dotSize) * activeRatio;

    // Interpolate color
    final color = Color.lerp(
      style.inactiveColor,
      style.activeColor,
      activeRatio,
    )!;

    return GestureDetector(
      onTap: onDotTapped != null ? () => onDotTapped!(index) : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: style.spacing / 2),
        child: Container(
          width: width,
          height: style.dotSize,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(style.dotSize / 2),
          ),
        ),
      ),
    );
  }
}
