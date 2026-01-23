import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Scroll physics optimized for mobile carousel UX.
///
/// Features:
/// - Snappy page transitions
/// - Low friction for responsive feel
/// - Easy swipe triggering
class MobileCarouselScrollPhysics extends PageScrollPhysics {
  const MobileCarouselScrollPhysics({super.parent});

  @override
  MobileCarouselScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return MobileCarouselScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingVelocity => 50.0; // Lower threshold for easier swiping

  @override
  double get maxFlingVelocity => 8000.0;

  @override
  double get dragStartDistanceMotionThreshold => 2.0;
}

/// Input types supported by the application.
enum InputType {
  touch,
  mouse,
  stylus,
  unknown,
}

/// Detects and provides information about the current input method.
class InputDetector {
  InputType _lastInputType = InputType.unknown;

  InputType get lastInputType => _lastInputType;

  /// Call this from pointer events to track input type.
  void handlePointerEvent(PointerEvent event) {
    _lastInputType = _detectInputType(event);
  }

  InputType _detectInputType(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      return InputType.touch;
    } else if (event.kind == PointerDeviceKind.mouse) {
      return InputType.mouse;
    } else if (event.kind == PointerDeviceKind.stylus) {
      return InputType.stylus;
    }
    return InputType.unknown;
  }

  /// Returns appropriate scroll physics based on input type.
  ScrollPhysics getScrollPhysics() {
    switch (_lastInputType) {
      case InputType.touch:
      case InputType.stylus:
        return const MobileCarouselScrollPhysics();
      case InputType.mouse:
        return const PageScrollPhysics();
      case InputType.unknown:
        return const MobileCarouselScrollPhysics();
    }
  }
}

/// A widget that detects input type and provides it to descendants.
class InputDetectorWidget extends StatefulWidget {
  final Widget child;
  final ValueChanged<InputType>? onInputTypeChanged;

  const InputDetectorWidget({
    super.key,
    required this.child,
    this.onInputTypeChanged,
  });

  static InputDetector? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_InputDetectorInherited>()
        ?.detector;
  }

  @override
  State<InputDetectorWidget> createState() => _InputDetectorWidgetState();
}

class _InputDetectorWidgetState extends State<InputDetectorWidget> {
  final InputDetector _detector = InputDetector();
  InputType _currentType = InputType.unknown;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointer,
      onPointerMove: _handlePointer,
      behavior: HitTestBehavior.translucent,
      child: _InputDetectorInherited(
        detector: _detector,
        child: widget.child,
      ),
    );
  }

  void _handlePointer(PointerEvent event) {
    _detector.handlePointerEvent(event);
    if (_detector.lastInputType != _currentType) {
      _currentType = _detector.lastInputType;
      widget.onInputTypeChanged?.call(_currentType);
    }
  }
}

class _InputDetectorInherited extends InheritedWidget {
  final InputDetector detector;

  const _InputDetectorInherited({
    required this.detector,
    required super.child,
  });

  @override
  bool updateShouldNotify(_InputDetectorInherited oldWidget) {
    return detector != oldWidget.detector;
  }
}
