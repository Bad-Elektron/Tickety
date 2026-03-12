import 'dart:math' as math;
import 'dart:ui';

import '../models/models.dart';

/// Result of a hit test on the venue canvas.
sealed class HitTestResult {
  const HitTestResult();
}

class SectionHit extends HitTestResult {
  final String sectionId;
  const SectionHit(this.sectionId);
}

class ElementHit extends HitTestResult {
  final String elementId;
  const ElementHit(this.elementId);
}

class SeatHit extends HitTestResult {
  final String sectionId;
  final String seatId;
  const SeatHit(this.sectionId, this.seatId);
}

class EmptyHit extends HitTestResult {
  const EmptyHit();
}

/// Which resize handle was hit.
enum ResizeHandle {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Rotate a point around a center by the given radians.
Offset _rotatePoint(Offset point, Offset center, double rad) {
  if (rad == 0) return point;
  final dx = point.dx - center.dx;
  final dy = point.dy - center.dy;
  final cosR = math.cos(rad);
  final sinR = math.sin(rad);
  return Offset(
    center.dx + dx * cosR - dy * sinR,
    center.dy + dx * sinR + dy * cosR,
  );
}

/// Hit-test resize handles for a given element shape.
/// Returns the handle hit, or null if none.
ResizeHandle? hitTestHandles(ElementShape shape, Offset point, {double handleRadius = 22}) {
  final handles = getHandlePositions(shape);
  for (final entry in handles.entries) {
    if ((point - entry.value).distance <= handleRadius) {
      return entry.key;
    }
  }
  return null;
}

/// Returns the 8 handle positions for a shape, rotated with the shape.
Map<ResizeHandle, Offset> getHandlePositions(ElementShape shape) {
  final x = shape.x;
  final y = shape.y;
  final w = shape.width;
  final h = shape.height;
  final center = shape.center;
  final rad = shape.rotation * math.pi / 180;

  final raw = {
    ResizeHandle.topLeft: Offset(x, y),
    ResizeHandle.topCenter: Offset(x + w / 2, y),
    ResizeHandle.topRight: Offset(x + w, y),
    ResizeHandle.middleLeft: Offset(x, y + h / 2),
    ResizeHandle.middleRight: Offset(x + w, y + h / 2),
    ResizeHandle.bottomLeft: Offset(x, y + h),
    ResizeHandle.bottomCenter: Offset(x + w / 2, y + h),
    ResizeHandle.bottomRight: Offset(x + w, y + h),
  };

  return raw.map((key, pos) => MapEntry(key, _rotatePoint(pos, center, rad)));
}

/// Get the position of the uniform scale handle (bottom-right corner + offset, rotated).
Offset getScaleHandlePosition(ElementShape shape) {
  const handleOffset = 20.0;
  final center = shape.center;
  final rad = shape.rotation * math.pi / 180;
  final unrotated = Offset(
    shape.x + shape.width + handleOffset,
    shape.y + shape.height + handleOffset,
  );
  return _rotatePoint(unrotated, center, rad);
}

/// Hit-test the scale handle.
bool hitTestScaleHandle(ElementShape shape, Offset point, {double radius = 22}) {
  return (point - getScaleHandlePosition(shape)).distance <= radius;
}

/// Get the morph points for a shape (4 corners), rotated with the shape.
/// If the shape already has polygon points, return those (absolute) rotated.
/// Otherwise generate 4 corners from the bounding rect, rotated.
List<Offset> getMorphPoints(ElementShape shape) {
  final center = shape.center;
  final rad = shape.rotation * math.pi / 180;

  List<Offset> pts;
  if (shape.shapeType == ShapeType.polygon && shape.points.length >= 3) {
    pts = shape.points.map((p) => Offset(shape.x + p.dx, shape.y + p.dy)).toList();
  } else {
    pts = [
      Offset(shape.x, shape.y),
      Offset(shape.x + shape.width, shape.y),
      Offset(shape.x + shape.width, shape.y + shape.height),
      Offset(shape.x, shape.y + shape.height),
    ];
  }

  return pts.map((p) => _rotatePoint(p, center, rad)).toList();
}

/// Hit-test morph points. Returns the index of the hit point, or -1.
int hitTestMorphPoint(ElementShape shape, Offset point, {double radius = 22}) {
  final pts = getMorphPoints(shape);
  for (var i = 0; i < pts.length; i++) {
    if ((point - pts[i]).distance <= radius) return i;
  }
  return -1;
}

/// Get the position of the rotation handle (above the top-center of the shape).
/// The handle is positioned 40px above the top edge, rotated with the shape.
Offset getRotationHandlePosition(ElementShape shape) {
  const handleDistance = 40.0;
  final center = shape.center;
  final rad = shape.rotation * math.pi / 180;
  // Unrotated position: top-center, 40px above
  final unrotated = Offset(shape.x + shape.width / 2, shape.y - handleDistance);
  return _rotatePoint(unrotated, center, rad);
}

/// Hit-test the rotation handle. Returns true if hit.
bool hitTestRotationHandle(ElementShape shape, Offset point, {double radius = 22}) {
  final handlePos = getRotationHandlePosition(shape);
  return (point - handlePos).distance <= radius;
}

/// Hit-test a point against the venue layout.
/// Returns the topmost item hit (seats checked first, then elements, then sections).
HitTestResult hitTest(VenueLayout layout, Offset point) {
  // Check seats within sections (topmost = last in list)
  for (final section in layout.sections.reversed) {
    if (section.shape.containsPoint(point)) {
      // Check individual seats
      for (final row in section.rows) {
        for (final seat in row.seats) {
          final seatRect = Rect.fromCenter(
            center: Offset(section.shape.x + seat.x + 8, section.shape.y + seat.y + 8),
            width: 16,
            height: 16,
          );
          if (seatRect.contains(point)) {
            return SeatHit(section.id, seat.id);
          }
        }
      }
      return SectionHit(section.id);
    }
  }

  // Check non-bookable elements
  for (final element in layout.elements.reversed) {
    if (element.shape.containsPoint(point)) {
      return ElementHit(element.id);
    }
  }

  return const EmptyHit();
}
