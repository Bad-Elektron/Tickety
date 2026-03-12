import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/hit_test.dart';

/// CustomPainter for the venue builder canvas.
///
/// LOD (Level of Detail):
/// - zoom < 0.5: sections only (colored shapes)
/// - 0.5 - 1.0: section shapes + seat dots
/// - > 1.0: seat labels visible
class VenueCanvasPainter extends CustomPainter {
  final VenueLayout layout;
  final int canvasWidth;
  final int canvasHeight;
  final String? selectedId;
  final String? resizingId;
  final String? morphingId;
  final String? rotatingId;
  final double zoom;

  VenueCanvasPainter({
    required this.layout,
    required this.canvasWidth,
    required this.canvasHeight,
    this.selectedId,
    this.resizingId,
    this.morphingId,
    this.rotatingId,
    this.zoom = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawElements(canvas);
    _drawSections(canvas);
    if (rotatingId != null) {
      _drawRotationHandle(canvas);
    }
    if (resizingId != null) {
      _drawResizeHandles(canvas);
    }
    if (morphingId != null) {
      _drawMorphHandles(canvas);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x15888888)
      ..strokeWidth = 0.5;

    final gridSize = layout.gridSize.toDouble();
    for (var x = 0.0; x <= canvasWidth; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, canvasHeight.toDouble()), paint);
    }
    for (var y = 0.0; y <= canvasHeight; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(canvasWidth.toDouble(), y), paint);
    }

    // Canvas border
    final borderPaint = Paint()
      ..color = const Color(0x30888888)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasWidth.toDouble(), canvasHeight.toDouble()),
      borderPaint,
    );
  }

  void _drawElements(Canvas canvas) {
    for (final element in layout.elements) {
      final isSelected = element.id == selectedId;
      final shape = element.shape;

      final fillColor = _elementColor(element.type);
      final paint = Paint()
        ..color = fillColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;

      canvas.save();
      if (shape.rotation != 0) {
        canvas.translate(shape.center.dx, shape.center.dy);
        canvas.rotate(shape.rotation * math.pi / 180);
        canvas.translate(-shape.center.dx, -shape.center.dy);
      }

      if (shape.shapeType == ShapeType.polygon && shape.points.length >= 3) {
        _drawPolygon(canvas, shape, paint, isSelected);
      } else {
        final rect = Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
        canvas.drawRRect(rrect, paint);

        if (isSelected) {
          final selPaint = Paint()
            ..color = const Color(0xFF6366F1)
            ..strokeWidth = 2.5
            ..style = PaintingStyle.stroke;
          canvas.drawRRect(rrect, selPaint);
        }
      }

      // Label
      if (zoom >= 0.5) {
        final labelPos = shape.shapeType == ShapeType.polygon && shape.points.length >= 3
            ? _polygonCenter(shape)
            : Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height).center;
        _drawLabel(canvas, element.label, labelPos, const Color(0xFFFFFFFF), 12);
      }

      canvas.restore();
    }
  }

  void _drawSections(Canvas canvas) {
    for (final section in layout.sections) {
      final isSelected = section.id == selectedId;
      final shape = section.shape;
      final color = _parseColor(section.color);

      canvas.save();
      if (shape.rotation != 0) {
        canvas.translate(shape.center.dx, shape.center.dy);
        canvas.rotate(shape.rotation * math.pi / 180);
        canvas.translate(-shape.center.dx, -shape.center.dy);
      }

      if (shape.shapeType == ShapeType.polygon && shape.points.length >= 3) {
        final fillPaint = Paint()
          ..color = color.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill;
        _drawPolygon(canvas, shape, fillPaint, isSelected);
      } else {
        final rect = Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);

        // Section fill
        final paint = Paint()
          ..color = color.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill;
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
        canvas.drawRRect(rrect, paint);

        // Section border
        final borderPaint = Paint()
          ..color = color.withValues(alpha: 0.6)
          ..strokeWidth = isSelected ? 2.5 : 1.5
          ..style = PaintingStyle.stroke;
        canvas.drawRRect(rrect, borderPaint);

        // Selection highlight
        if (isSelected) {
          final selPaint = Paint()
            ..color = const Color(0xFF6366F1)
            ..strokeWidth = 2.5
            ..style = PaintingStyle.stroke;
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(10)),
            selPaint,
          );
        }
      }

      // Section name
      final labelPos = shape.shapeType == ShapeType.polygon && shape.points.length >= 3
          ? Offset(_polygonCenter(shape).dx, _polygonCenter(shape).dy - 10)
          : Offset(shape.x + shape.width / 2, shape.y + 14);
      _drawLabel(canvas, section.name, labelPos, color, 11);

      // Draw seats based on zoom level
      if (zoom >= 0.5 && section.rows.isNotEmpty) {
        _drawSeats(canvas, section, zoom >= 1.0);
      } else if (zoom >= 0.5) {
        final capacityText = '${section.seatCount} ${section.type == SectionType.standing ? 'cap' : 'seats'}';
        final capPos = shape.shapeType == ShapeType.polygon && shape.points.length >= 3
            ? _polygonCenter(shape)
            : Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height).center;
        _drawLabel(canvas, capacityText, capPos, color.withValues(alpha: 0.8), 10);
      }

      canvas.restore();
    }
  }

  void _drawPolygon(Canvas canvas, ElementShape shape, Paint fillPaint, bool isSelected) {
    final path = Path();
    final pts = shape.points.map((p) => Offset(shape.x + p.dx, shape.y + p.dy)).toList();
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();

    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..color = fillPaint.color.withValues(alpha: 0.6)
      ..strokeWidth = isSelected ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);

    if (isSelected) {
      final selPaint = Paint()
        ..color = const Color(0xFF6366F1)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, selPaint);
    }
  }

  Offset _polygonCenter(ElementShape shape) {
    if (shape.points.isEmpty) return shape.center;
    double cx = 0, cy = 0;
    for (final p in shape.points) {
      cx += p.dx; cy += p.dy;
    }
    return Offset(shape.x + cx / shape.points.length, shape.y + cy / shape.points.length);
  }

  void _drawSeats(Canvas canvas, VenueSection section, bool showLabels) {
    final sectionX = section.shape.x;
    final sectionY = section.shape.y;

    final availablePoints = <Offset>[];
    final blockedPoints = <Offset>[];
    final accessiblePoints = <Offset>[];

    for (final row in section.rows) {
      for (final seat in row.seats) {
        final point = Offset(sectionX + seat.x + 8, sectionY + seat.y + 8);
        switch (seat.status) {
          case SeatStatus.available:
            availablePoints.add(point);
          case SeatStatus.blocked:
            blockedPoints.add(point);
          case SeatStatus.accessible:
            accessiblePoints.add(point);
        }
      }
    }

    final dotPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8;

    if (availablePoints.isNotEmpty) {
      dotPaint.color = _parseColor(section.color);
      canvas.drawPoints(ui.PointMode.points, availablePoints, dotPaint);
    }
    if (blockedPoints.isNotEmpty) {
      dotPaint.color = const Color(0xFF666666);
      canvas.drawPoints(ui.PointMode.points, blockedPoints, dotPaint);
    }
    if (accessiblePoints.isNotEmpty) {
      dotPaint.color = const Color(0xFF2196F3);
      canvas.drawPoints(ui.PointMode.points, accessiblePoints, dotPaint);
    }

    if (showLabels) {
      for (final row in section.rows) {
        for (final seat in row.seats) {
          final pos = Offset(sectionX + seat.x + 8, sectionY + seat.y + 8);
          _drawLabel(canvas, '${row.label}${seat.number}', pos, const Color(0xFFFFFFFF), 7);
        }
      }
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset center, Color color, double fontSize) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: fontSize,
    ))
      ..pushStyle(ui.TextStyle(
        color: color,
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
      ))
      ..addText(text);

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 120));

    canvas.drawParagraph(
      paragraph,
      Offset(center.dx - paragraph.width / 2, center.dy - paragraph.height / 2),
    );
  }

  Color _elementColor(ElementType type) => switch (type) {
    ElementType.stage => const Color(0xFF8B5CF6),
    ElementType.bar => const Color(0xFFF59E0B),
    ElementType.entrance => const Color(0xFF10B981),
    ElementType.restroom => const Color(0xFF3B82F6),
    ElementType.label => const Color(0xFF6B7280),
  };

  Color _parseColor(String hex) {
    final hexStr = hex.replaceFirst('#', '');
    if (hexStr.length == 6) {
      return Color(int.parse('FF$hexStr', radix: 16));
    }
    return const Color(0xFF6366F1);
  }

  void _drawResizeHandles(Canvas canvas) {
    final shape = _findShape(resizingId);
    if (shape == null) return;

    final handlePos = getScaleHandlePosition(shape);
    final center = shape.center;

    // Line from center to handle
    final linePaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center, handlePos, linePaint);

    // Handle dot
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(handlePos, 10, fillPaint);
    canvas.drawCircle(handlePos, 10, strokePaint);

    // Scale icon in the dot
    final iconPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Draw diagonal arrows hint
    canvas.drawLine(
      Offset(handlePos.dx - 4, handlePos.dy - 4),
      Offset(handlePos.dx + 4, handlePos.dy + 4),
      iconPaint,
    );
    canvas.drawLine(
      Offset(handlePos.dx + 4, handlePos.dy - 4),
      Offset(handlePos.dx - 4, handlePos.dy + 4),
      iconPaint,
    );
  }

  void _drawMorphHandles(Canvas canvas) {
    final shape = _findShape(morphingId);
    if (shape == null) return;

    final pts = getMorphPoints(shape);

    // Draw edges between points
    final linePaint = Paint()
      ..color = const Color(0xFFEC4899).withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < pts.length; i++) {
      final next = (i + 1) % pts.length;
      canvas.drawLine(pts[i], pts[next], linePaint);
    }

    // Draw corner dots
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFFEC4899)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final pt in pts) {
      canvas.drawCircle(pt, 10, fillPaint);
      canvas.drawCircle(pt, 10, strokePaint);
    }
  }

  void _drawRotationHandle(Canvas canvas) {
    final shape = _findShape(rotatingId);
    if (shape == null) return;

    final handlePos = getRotationHandlePosition(shape);
    final center = shape.center;

    // Line from center to handle
    final linePaint = Paint()
      ..color = const Color(0xFF6366F1).withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center, handlePos, linePaint);

    // Handle dot
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF6366F1)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(handlePos, 10, fillPaint);
    canvas.drawCircle(handlePos, 10, strokePaint);

    // Rotation icon in the dot
    final iconPaint = Paint()
      ..color = const Color(0xFF6366F1)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Draw a small arc
    canvas.drawArc(
      Rect.fromCircle(center: handlePos, radius: 5),
      -math.pi / 2,
      math.pi * 1.3,
      false,
      iconPaint,
    );
  }

  ElementShape? _findShape(String? id) {
    if (id == null) return null;
    for (final section in layout.sections) {
      if (section.id == id) return section.shape;
    }
    for (final element in layout.elements) {
      if (element.id == id) return element.shape;
    }
    return null;
  }

  @override
  bool shouldRepaint(VenueCanvasPainter oldDelegate) {
    return layout != oldDelegate.layout ||
        selectedId != oldDelegate.selectedId ||
        resizingId != oldDelegate.resizingId ||
        morphingId != oldDelegate.morphingId ||
        rotatingId != oldDelegate.rotatingId ||
        zoom != oldDelegate.zoom;
  }
}
