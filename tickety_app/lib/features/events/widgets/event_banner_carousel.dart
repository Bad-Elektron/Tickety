import 'package:flutter/material.dart';

import '../models/event_model.dart';
import 'carousel_page_indicator.dart';
import 'event_banner_card.dart';

/// Configuration for the event banner carousel.
@immutable
class EventCarouselConfig {
  /// Height of the carousel.
  final double height;

  /// Horizontal padding around each card.
  final double cardPadding;

  /// Fraction of the viewport each item occupies (0.0 to 1.0).
  final double viewportFraction;

  /// Whether to auto-scroll through items.
  final bool autoScroll;

  /// Duration to display each item when auto-scrolling.
  final Duration autoScrollInterval;

  /// Duration of the scroll animation.
  final Duration scrollAnimationDuration;

  /// Curve for scroll animations.
  final Curve scrollAnimationCurve;

  /// Style for the page indicator.
  final CarouselIndicatorStyle indicatorStyle;

  /// Spacing between the carousel and the indicator.
  final double indicatorSpacing;

  const EventCarouselConfig({
    this.height = 280,
    this.cardPadding = 8,
    this.viewportFraction = 0.88,
    this.autoScroll = false,
    this.autoScrollInterval = const Duration(seconds: 5),
    this.scrollAnimationDuration = const Duration(milliseconds: 300),
    this.scrollAnimationCurve = Curves.easeOutCubic,
    this.indicatorStyle = const CarouselIndicatorStyle(),
    this.indicatorSpacing = 16,
  });
}

/// A horizontal carousel for displaying event banners.
///
/// Optimized for smooth touch/mouse input with:
/// - Direct 1:1 drag response
/// - Smooth spring-based page snapping
/// - Efficient rendering
class EventBannerCarousel extends StatefulWidget {
  /// List of events to display.
  final List<EventModel> events;

  /// Callback when an event card is tapped.
  final ValueChanged<EventModel>? onEventTapped;

  /// Configuration for the carousel.
  final EventCarouselConfig config;

  const EventBannerCarousel({
    super.key,
    required this.events,
    this.onEventTapped,
    this.config = const EventCarouselConfig(),
  });

  @override
  State<EventBannerCarousel> createState() => _EventBannerCarouselState();
}

class _EventBannerCarouselState extends State<EventBannerCarousel> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: widget.config.viewportFraction,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: widget.config.scrollAnimationDuration,
      curve: widget.config.scrollAnimationCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.config.height,
          child: _buildPageView(),
        ),
        SizedBox(height: widget.config.indicatorSpacing),
        _buildIndicator(),
      ],
    );
  }

  Widget _buildPageView() {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: _onPageChanged,
      itemCount: widget.events.length,
      padEnds: true,
      scrollDirection: Axis.horizontal,
      // Use bouncing physics for smooth iOS-like feel
      physics: const BouncingScrollPhysics(),
      itemBuilder: (context, index) => _buildCard(index),
    );
  }

  Widget _buildCard(int index) {
    final event = widget.events[index];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.config.cardPadding),
      child: RepaintBoundary(
        child: EventBannerCard(
          event: event,
          onTap: widget.onEventTapped != null
              ? () => widget.onEventTapped!(event)
              : null,
        ),
      ),
    );
  }

  Widget _buildIndicator() {
    return SmoothCarouselPageIndicator(
      controller: _pageController,
      itemCount: widget.events.length,
      style: widget.config.indicatorStyle,
      onDotTapped: _goToPage,
    );
  }
}
