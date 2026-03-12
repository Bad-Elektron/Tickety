import 'dart:math';
import 'dart:ui';

/// Types of shapes for sections and elements.
enum ShapeType {
  rectangle,
  polygon,
  circle;

  static ShapeType fromString(String? value) {
    return ShapeType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ShapeType.rectangle,
    );
  }
}

/// Describes the shape and position of a section or element on the canvas.
class ElementShape {
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final ShapeType shapeType;

  /// For polygon shapes, a list of [Offset] points relative to (x, y).
  final List<Offset> points;

  const ElementShape({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.shapeType = ShapeType.rectangle,
    this.points = const [],
  });

  /// Center point of the shape.
  Offset get center => Offset(x + width / 2, y + height / 2);

  /// Bounding rectangle.
  Rect get bounds => Rect.fromLTWH(x, y, width, height);

  /// Hit-test: does [point] fall inside this shape?
  bool containsPoint(Offset point) {
    switch (shapeType) {
      case ShapeType.rectangle:
        return _containsPointRotatedRect(point);
      case ShapeType.circle:
        final c = center;
        final rx = width / 2;
        final ry = height / 2;
        final dx = (point.dx - c.dx) / rx;
        final dy = (point.dy - c.dy) / ry;
        return dx * dx + dy * dy <= 1.0;
      case ShapeType.polygon:
        if (points.length < 3) return bounds.contains(point);
        return _pointInPolygon(point, points.map((p) => Offset(p.dx + x, p.dy + y)).toList());
    }
  }

  bool _containsPointRotatedRect(Offset point) {
    if (rotation == 0) return bounds.contains(point);
    // Rotate point into local space
    final c = center;
    final rad = -rotation * pi / 180;
    final cosR = cos(rad);
    final sinR = sin(rad);
    final dx = point.dx - c.dx;
    final dy = point.dy - c.dy;
    final localX = cosR * dx - sinR * dy + c.dx;
    final localY = sinR * dx + cosR * dy + c.dy;
    return bounds.contains(Offset(localX, localY));
  }

  /// Ray-casting point-in-polygon.
  static bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final pi = polygon[i];
      final pj = polygon[j];
      if ((pi.dy > point.dy) != (pj.dy > point.dy) &&
          point.dx < (pj.dx - pi.dx) * (point.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  ElementShape copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    ShapeType? shapeType,
    List<Offset>? points,
  }) {
    return ElementShape(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      shapeType: shapeType ?? this.shapeType,
      points: points ?? this.points,
    );
  }

  factory ElementShape.fromJson(Map<String, dynamic> json) {
    final pointsList = json['points'] as List<dynamic>? ?? [];
    return ElementShape(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 100,
      height: (json['height'] as num?)?.toDouble() ?? 100,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      shapeType: ShapeType.fromString(json['shapeType'] as String?),
      points: pointsList
          .map((p) => Offset(
                (p['x'] as num?)?.toDouble() ?? 0,
                (p['y'] as num?)?.toDouble() ?? 0,
              ))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': rotation,
      'shapeType': shapeType.name,
      if (points.isNotEmpty)
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    };
  }
}
