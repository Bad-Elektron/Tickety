import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'noise_generator.dart';

/// Generates a noise image for efficient rendering.
///
/// This creates the noise pattern once and returns it as a [ui.Image],
/// avoiding expensive per-frame computations.
class NoiseImageGenerator {
  final NoiseGenerator generator;
  final int width;
  final int height;
  final int resolution;

  NoiseImageGenerator({
    required this.generator,
    required this.width,
    required this.height,
    this.resolution = 4,
  });

  /// Generates the noise image.
  Future<ui.Image> generate() async {
    final pixelWidth = (width / resolution).ceil();
    final pixelHeight = (height / resolution).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..style = PaintingStyle.fill;

    for (var y = 0; y < pixelHeight; y++) {
      for (var x = 0; x < pixelWidth; x++) {
        final color = generator.getColorAt(
          x.toDouble() * resolution,
          y.toDouble() * resolution,
        );
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          paint,
        );
      }
    }

    final picture = recorder.endRecording();
    return picture.toImage(pixelWidth, pixelHeight);
  }
}

/// Paints a pre-generated noise image efficiently.
class CachedNoisePainter extends CustomPainter {
  final ui.Image image;
  final BoxFit fit;

  CachedNoisePainter({
    required this.image,
    this.fit = BoxFit.cover,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final srcRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = false;

    canvas.drawImageRect(image, srcRect, dstRect, paint);
  }

  @override
  bool shouldRepaint(CachedNoisePainter oldDelegate) {
    return oldDelegate.image != image;
  }
}

/// A simple gradient painter as a fast fallback.
class GradientFallbackPainter extends CustomPainter {
  final List<Color> colors;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  GradientFallbackPainter({
    required this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || colors.isEmpty) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = LinearGradient(
      begin: begin.resolve(TextDirection.ltr),
      end: end.resolve(TextDirection.ltr),
      colors: colors,
    );

    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(GradientFallbackPainter oldDelegate) {
    return oldDelegate.colors != colors ||
        oldDelegate.begin != begin ||
        oldDelegate.end != end;
  }
}
