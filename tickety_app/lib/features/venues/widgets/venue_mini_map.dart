import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/models.dart';

/// A read-only miniature venue map for the ticket buying flow.
///
/// Computes a tight bounding box around all sections/elements so the
/// content fills the view. Supports pinch-to-zoom and scroll-to-zoom.
/// Tapping a section calls [onSectionTap].
class VenueMiniMap extends StatefulWidget {
  final VenueLayout layout;
  final int canvasWidth;
  final int canvasHeight;
  final Set<String> highlightedSectionIds;
  final ValueChanged<String>? onSectionTap;
  final double height;

  const VenueMiniMap({
    super.key,
    required this.layout,
    required this.canvasWidth,
    required this.canvasHeight,
    this.highlightedSectionIds = const {},
    this.onSectionTap,
    this.height = 240,
  });

  @override
  State<VenueMiniMap> createState() => _VenueMiniMapState();
}

class _VenueMiniMapState extends State<VenueMiniMap> {
  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Compute the tight bounding box enclosing all sections and elements.
  Rect _contentBounds() {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    void expandShape(ElementShape shape) {
      if (shape.shapeType == ShapeType.polygon && shape.points.length >= 3) {
        for (final p in shape.points) {
          final px = shape.x + p.dx;
          final py = shape.y + p.dy;
          minX = math.min(minX, px);
          minY = math.min(minY, py);
          maxX = math.max(maxX, px);
          maxY = math.max(maxY, py);
        }
      } else {
        minX = math.min(minX, shape.x);
        minY = math.min(minY, shape.y);
        maxX = math.max(maxX, shape.x + shape.width);
        maxY = math.max(maxY, shape.y + shape.height);
      }
    }

    for (final section in widget.layout.sections) {
      expandShape(section.shape);
    }
    for (final element in widget.layout.elements) {
      expandShape(element.shape);
    }

    // Fallback if empty
    if (minX == double.infinity) {
      return Rect.fromLTWH(0, 0, widget.canvasWidth.toDouble(), widget.canvasHeight.toDouble());
    }

    // Add padding (10% of the larger dimension)
    final pad = math.max(maxX - minX, maxY - minY) * 0.1;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  void _handleTap(TapDownDetails details) {
    if (widget.onSectionTap == null) return;

    final box = context.findRenderObject() as RenderBox;
    final localPos = details.localPosition;

    // Invert the InteractiveViewer transform to get scene coordinates
    final inverseMatrix = Matrix4.inverted(_controller.value);
    final scenePoint = MatrixUtils.transformPoint(inverseMatrix, localPos);

    // The painter maps content bounds into the widget size
    final bounds = _contentBounds();
    final scaleX = box.size.width / bounds.width;
    final scaleY = box.size.height / bounds.height;
    final scale = math.min(scaleX, scaleY);
    final offsetX = (box.size.width - bounds.width * scale) / 2;
    final offsetY = (box.size.height - bounds.height * scale) / 2;

    final canvasX = (scenePoint.dx - offsetX) / scale + bounds.left;
    final canvasY = (scenePoint.dy - offsetY) / scale + bounds.top;

    for (final section in widget.layout.sections.reversed) {
      if (_sectionContains(section, canvasX, canvasY)) {
        widget.onSectionTap?.call(section.id);
        return;
      }
    }
  }

  bool _sectionContains(VenueSection section, double x, double y) {
    final shape = section.shape;
    if (shape.shapeType == ShapeType.polygon && shape.points.length >= 3) {
      final pts = shape.points.map((p) => Offset(shape.x + p.dx, shape.y + p.dy)).toList();
      var inside = false;
      for (int i = 0, j = pts.length - 1; i < pts.length; j = i++) {
        if ((pts[i].dy > y) != (pts[j].dy > y) &&
            x < (pts[j].dx - pts[i].dx) * (y - pts[i].dy) / (pts[j].dy - pts[i].dy) + pts[i].dx) {
          inside = !inside;
        }
      }
      return inside;
    }
    return Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height).contains(Offset(x, y));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bounds = _contentBounds();

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTapDown: _handleTap,
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 0.5,
          maxScale: 5.0,
          boundaryMargin: const EdgeInsets.all(100),
          child: CustomPaint(
            size: Size.infinite,
            painter: _MiniMapPainter(
              layout: widget.layout,
              contentBounds: bounds,
              highlightedIds: widget.highlightedSectionIds,
              isDark: colorScheme.brightness == Brightness.dark,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  final VenueLayout layout;
  final Rect contentBounds;
  final Set<String> highlightedIds;
  final bool isDark;

  _MiniMapPainter({
    required this.layout,
    required this.contentBounds,
    required this.highlightedIds,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scale to fit the content bounding box into the widget
    final scaleX = size.width / contentBounds.width;
    final scaleY = size.height / contentBounds.height;
    final scale = math.min(scaleX, scaleY);
    final offsetX = (size.width - contentBounds.width * scale) / 2;
    final offsetY = (size.height - contentBounds.height * scale) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);
    // Shift so content bounds start at origin
    canvas.translate(-contentBounds.left, -contentBounds.top);

    _drawElements(canvas, scale);
    _drawSections(canvas, scale);

    canvas.restore();
  }

  void _drawElements(Canvas canvas, double scale) {
    for (final element in layout.elements) {
      final shape = element.shape;
      final fillColor = _elementColor(element.type);
      final paint = Paint()
        ..color = fillColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;

      canvas.save();
      if (shape.rotation != 0) {
        canvas.translate(shape.center.dx, shape.center.dy);
        canvas.rotate(shape.rotation * math.pi / 180);
        canvas.translate(-shape.center.dx, -shape.center.dy);
      }

      if (shape.shapeType == ShapeType.polygon && shape.points.length >= 3) {
        _drawPolygon(canvas, shape, paint);
      } else {
        final rect = Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
      }

      // Label
      final labelPos = shape.shapeType == ShapeType.polygon && shape.points.length >= 3
          ? _polygonCenter(shape)
          : Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height).center;
      _drawLabel(canvas, element.label, labelPos, Colors.white.withValues(alpha: 0.8), 11 / scale);

      canvas.restore();
    }
  }

  void _drawSections(Canvas canvas, double scale) {
    for (final section in layout.sections) {
      final isHighlighted = highlightedIds.contains(section.id);
      final shape = section.shape;
      final color = _parseColor(section.color);

      canvas.save();
      if (shape.rotation != 0) {
        canvas.translate(shape.center.dx, shape.center.dy);
        canvas.rotate(shape.rotation * math.pi / 180);
        canvas.translate(-shape.center.dx, -shape.center.dy);
      }

      final fillAlpha = isHighlighted ? 0.45 : 0.18;
      final borderAlpha = isHighlighted ? 0.9 : 0.45;
      final borderWidth = (isHighlighted ? 3.0 : 1.5) / scale;

      if (shape.shapeType == ShapeType.polygon && shape.points.length >= 3) {
        final fillPaint = Paint()
          ..color = color.withValues(alpha: fillAlpha)
          ..style = PaintingStyle.fill;
        _drawPolygon(canvas, shape, fillPaint);

        final pts = shape.points.map((p) => Offset(shape.x + p.dx, shape.y + p.dy)).toList();
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (var i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        path.close();
        canvas.drawPath(path, Paint()
          ..color = color.withValues(alpha: borderAlpha)
          ..strokeWidth = borderWidth
          ..style = PaintingStyle.stroke);
      } else {
        final rect = Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

        canvas.drawRRect(rrect, Paint()
          ..color = color.withValues(alpha: fillAlpha)
          ..style = PaintingStyle.fill);
        canvas.drawRRect(rrect, Paint()
          ..color = color.withValues(alpha: borderAlpha)
          ..strokeWidth = borderWidth
          ..style = PaintingStyle.stroke);
      }

      // Section name — scale font inversely so it stays readable
      final fontSize = (isHighlighted ? 13.0 : 11.0) / scale;
      final labelColor = isHighlighted ? color : color.withValues(alpha: 0.8);
      final labelPos = shape.shapeType == ShapeType.polygon && shape.points.length >= 3
          ? _polygonCenter(shape)
          : Offset(shape.x + shape.width / 2, shape.y + shape.height / 2 - 8 / scale);
      _drawLabel(canvas, section.name, labelPos, labelColor, fontSize);

      // Capacity below name
      final capText = '${section.seatCount} ${section.type == SectionType.standing ? 'cap' : 'seats'}';
      final capPos = Offset(labelPos.dx, labelPos.dy + 14 / scale);
      _drawLabel(canvas, capText, capPos, labelColor.withValues(alpha: 0.6), 9 / scale);

      canvas.restore();
    }
  }

  void _drawPolygon(Canvas canvas, ElementShape shape, Paint paint) {
    final pts = shape.points.map((p) => Offset(shape.x + p.dx, shape.y + p.dy)).toList();
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  Offset _polygonCenter(ElementShape shape) {
    if (shape.points.isEmpty) return shape.center;
    double cx = 0, cy = 0;
    for (final p in shape.points) {
      cx += p.dx;
      cy += p.dy;
    }
    return Offset(shape.x + cx / shape.points.length, shape.y + cy / shape.points.length);
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
      ..layout(ui.ParagraphConstraints(width: 200 / 1)); // wide enough for labels

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

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) {
    return highlightedIds != oldDelegate.highlightedIds ||
        layout != oldDelegate.layout ||
        contentBounds != oldDelegate.contentBounds;
  }
}
