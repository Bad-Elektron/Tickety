import 'dart:math';
import 'dart:ui';

/// Configuration for noise generation algorithms.
///
/// This class encapsulates all parameters needed to generate procedural noise
/// patterns, allowing for consistent and reproducible results across the application.
class NoiseConfig {
  /// Base colors used in the noise gradient.
  final List<Color> colors;

  /// Seed for random number generation. Use the same seed for reproducible results.
  final int seed;

  /// Controls the scale/zoom of the noise pattern. Lower values = larger patterns.
  final double scale;

  /// Number of octaves for fractal noise. More octaves = more detail.
  final int octaves;

  /// How much each octave contributes relative to the previous.
  /// Values < 1.0 make higher octaves contribute less.
  final double persistence;

  /// How much the frequency increases per octave.
  final double lacunarity;

  const NoiseConfig({
    required this.colors,
    this.seed = 0,
    this.scale = 0.01,
    this.octaves = 4,
    this.persistence = 0.5,
    this.lacunarity = 2.0,
  }) : assert(colors.length >= 2, 'At least 2 colors required for gradient');

  /// Creates a copy with modified parameters.
  NoiseConfig copyWith({
    List<Color>? colors,
    int? seed,
    double? scale,
    int? octaves,
    double? persistence,
    double? lacunarity,
  }) {
    return NoiseConfig(
      colors: colors ?? this.colors,
      seed: seed ?? this.seed,
      scale: scale ?? this.scale,
      octaves: octaves ?? this.octaves,
      persistence: persistence ?? this.persistence,
      lacunarity: lacunarity ?? this.lacunarity,
    );
  }
}

/// Generates procedural noise patterns for visual effects.
///
/// This class implements Perlin-like noise generation that can be used
/// to create colorful, organic-looking backgrounds and textures.
///
/// Example usage:
/// ```dart
/// final generator = NoiseGenerator(
///   config: NoiseConfig(
///     colors: [Colors.purple, Colors.blue, Colors.cyan],
///     seed: 42,
///   ),
/// );
/// final color = generator.getColorAt(x, y);
/// ```
class NoiseGenerator {
  final NoiseConfig config;
  late final Random _random;
  late final List<int> _permutation;

  NoiseGenerator({required this.config}) {
    _random = Random(config.seed);
    _permutation = _generatePermutation();
  }

  /// Generates the permutation table used for noise computation.
  List<int> _generatePermutation() {
    final perm = List<int>.generate(256, (i) => i);
    // Fisher-Yates shuffle
    for (var i = 255; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final temp = perm[i];
      perm[i] = perm[j];
      perm[j] = temp;
    }
    // Duplicate for overflow handling
    return [...perm, ...perm];
  }

  /// Smoothstep interpolation function for smoother gradients.
  double _fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);

  /// Linear interpolation between two values.
  double _lerp(double a, double b, double t) => a + t * (b - a);

  /// Computes gradient contribution at a grid point.
  double _grad(int hash, double x, double y) {
    final h = hash & 3;
    final u = h < 2 ? x : y;
    final v = h < 2 ? y : x;
    return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
  }

  /// Computes 2D Perlin noise value at the given coordinates.
  ///
  /// Returns a value typically in the range [-1, 1].
  double noise2D(double x, double y) {
    // Find unit grid cell
    final xi = x.floor() & 255;
    final yi = y.floor() & 255;

    // Relative position within cell
    final xf = x - x.floor();
    final yf = y - y.floor();

    // Fade curves
    final u = _fade(xf);
    final v = _fade(yf);

    // Hash coordinates of cube corners
    final aa = _permutation[_permutation[xi] + yi];
    final ab = _permutation[_permutation[xi] + yi + 1];
    final ba = _permutation[_permutation[xi + 1] + yi];
    final bb = _permutation[_permutation[xi + 1] + yi + 1];

    // Blend contributions from corners
    final x1 = _lerp(_grad(aa, xf, yf), _grad(ba, xf - 1, yf), u);
    final x2 = _lerp(_grad(ab, xf, yf - 1), _grad(bb, xf - 1, yf - 1), u);

    return _lerp(x1, x2, v);
  }

  /// Computes fractal Brownian motion (fBm) noise.
  ///
  /// Combines multiple octaves of noise for more natural-looking results.
  double fractalNoise(double x, double y) {
    var total = 0.0;
    var amplitude = 1.0;
    var frequency = 1.0;
    var maxValue = 0.0;

    for (var i = 0; i < config.octaves; i++) {
      total += noise2D(x * frequency, y * frequency) * amplitude;
      maxValue += amplitude;
      amplitude *= config.persistence;
      frequency *= config.lacunarity;
    }

    // Normalize to [0, 1]
    return (total / maxValue + 1) / 2;
  }

  /// Gets the interpolated color at the given coordinates.
  ///
  /// Uses fractal noise to determine the color position in the gradient.
  Color getColorAt(double x, double y) {
    final noiseValue = fractalNoise(x * config.scale, y * config.scale);
    return _interpolateColor(noiseValue);
  }

  /// Interpolates between the configured colors based on a value [0, 1].
  Color _interpolateColor(double t) {
    final colors = config.colors;
    if (colors.length == 2) {
      return Color.lerp(colors[0], colors[1], t)!;
    }

    // Multi-color gradient interpolation
    final scaledT = t * (colors.length - 1);
    final index = scaledT.floor().clamp(0, colors.length - 2);
    final localT = scaledT - index;

    return Color.lerp(colors[index], colors[index + 1], localT)!;
  }

  /// Generates a complete noise field as a list of colors.
  ///
  /// Useful for caching or pre-computing noise patterns.
  List<Color> generateField(int width, int height) {
    final field = <Color>[];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        field.add(getColorAt(x.toDouble(), y.toDouble()));
      }
    }
    return field;
  }
}

/// Predefined noise configurations for common use cases.
abstract class NoisePresets {
  /// Vibrant, colorful noise suitable for event banners.
  static NoiseConfig vibrantEvents(int seed) => NoiseConfig(
    colors: const [
      Color(0xFFFF6B6B), // Coral red
      Color(0xFF4ECDC4), // Teal
      Color(0xFF45B7D1), // Sky blue
      Color(0xFFDDA0DD), // Plum
      Color(0xFFF7DC6F), // Soft yellow
    ],
    seed: seed,
    scale: 0.008,
    octaves: 4,
    persistence: 0.6,
    lacunarity: 2.0,
  );

  /// Subtle, professional gradient.
  static NoiseConfig subtle(int seed) => NoiseConfig(
    colors: const [
      Color(0xFF667eea),
      Color(0xFF764ba2),
    ],
    seed: seed,
    scale: 0.005,
    octaves: 3,
    persistence: 0.4,
    lacunarity: 2.0,
  );

  /// Warm sunset colors.
  static NoiseConfig sunset(int seed) => NoiseConfig(
    colors: const [
      Color(0xFFf093fb),
      Color(0xFFf5576c),
      Color(0xFFffecd2),
    ],
    seed: seed,
    scale: 0.006,
    octaves: 4,
    persistence: 0.5,
    lacunarity: 2.0,
  );

  /// Cool ocean-inspired colors.
  static NoiseConfig ocean(int seed) => NoiseConfig(
    colors: const [
      Color(0xFF0077B6),
      Color(0xFF00B4D8),
      Color(0xFF90E0EF),
      Color(0xFFCAF0F8),
    ],
    seed: seed,
    scale: 0.007,
    octaves: 5,
    persistence: 0.55,
    lacunarity: 2.0,
  );

  /// Dark, moody atmosphere.
  static NoiseConfig darkMood(int seed) => NoiseConfig(
    colors: const [
      Color(0xFF1a1a2e),
      Color(0xFF16213e),
      Color(0xFF0f3460),
      Color(0xFF533483),
    ],
    seed: seed,
    scale: 0.009,
    octaves: 4,
    persistence: 0.5,
    lacunarity: 2.0,
  );
}
