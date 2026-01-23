import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Debug metrics data class.
class DebugMetrics {
  final double fps;
  final double buildMs;
  final double rasterMs;
  final double totalMs;

  const DebugMetrics({
    this.fps = 0,
    this.buildMs = 0,
    this.rasterMs = 0,
    this.totalMs = 0,
  });
}

/// A widget that displays debug information including FPS.
///
/// Uses SchedulerBinding frame callbacks to measure actual frame times
/// without forcing continuous rendering.
class DebugOverlay extends StatefulWidget {
  /// The child widget to wrap.
  final Widget child;

  /// Whether to show the debug overlay.
  final bool enabled;

  const DebugOverlay({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  final ValueNotifier<DebugMetrics> _metricsNotifier =
      ValueNotifier(const DebugMetrics());

  // Frame timing tracking - use vsync intervals for accurate FPS
  static const int _maxSamples = 60;
  final List<int> _vsyncIntervals = [];
  final List<int> _buildTimes = [];
  final List<int> _rasterTimes = [];
  int? _lastVsyncTimestamp;

  late final TimingsCallback _timingsCallback;

  @override
  void initState() {
    super.initState();
    _timingsCallback = _onFrameTimings;
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      // Use vsync-to-vsync for actual FPS (accounts for dropped frames)
      final vsyncTimestamp = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      if (_lastVsyncTimestamp != null) {
        final interval = vsyncTimestamp - _lastVsyncTimestamp!;
        _vsyncIntervals.add(interval);
        if (_vsyncIntervals.length > _maxSamples) {
          _vsyncIntervals.removeAt(0);
        }
      }
      _lastVsyncTimestamp = vsyncTimestamp;

      // Track build and raster times separately
      _buildTimes.add(timing.buildDuration.inMicroseconds);
      _rasterTimes.add(timing.rasterDuration.inMicroseconds);
      if (_buildTimes.length > _maxSamples) {
        _buildTimes.removeAt(0);
        _rasterTimes.removeAt(0);
      }
    }

    // Calculate metrics
    if (_vsyncIntervals.isNotEmpty) {
      final avgVsyncInterval = _vsyncIntervals.reduce((a, b) => a + b) /
          _vsyncIntervals.length;
      final avgBuild = _buildTimes.reduce((a, b) => a + b) / _buildTimes.length;
      final avgRaster = _rasterTimes.reduce((a, b) => a + b) / _rasterTimes.length;

      _metricsNotifier.value = DebugMetrics(
        fps: avgVsyncInterval > 0 ? 1000000 / avgVsyncInterval : 0,
        buildMs: avgBuild / 1000,
        rasterMs: avgRaster / 1000,
        totalMs: (avgBuild + avgRaster) / 1000,
      );
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timingsCallback);
    _metricsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: RepaintBoundary(
            child: DebugToolsBar(metricsNotifier: _metricsNotifier),
          ),
        ),
      ],
    );
  }
}

/// The debug tools bar widget displaying FPS and other metrics.
class DebugToolsBar extends StatelessWidget {
  /// ValueNotifier for metrics updates.
  final ValueNotifier<DebugMetrics> metricsNotifier;

  const DebugToolsBar({
    super.key,
    required this.metricsNotifier,
  });

  static Color _getFpsColor(double fps) {
    if (fps >= 55) return Colors.green;
    if (fps >= 30) return Colors.orange;
    return Colors.red;
  }

  static Color _getTimeColor(double ms) {
    if (ms <= 8) return Colors.green;
    if (ms <= 16) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: bottomPadding + 8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xD9000000),
        border: Border(
          top: BorderSide(
            color: Color(0x1AFFFFFF),
          ),
        ),
      ),
      child: ValueListenableBuilder<DebugMetrics>(
        valueListenable: metricsNotifier,
        builder: (context, metrics, _) {
          final fpsColor = _getFpsColor(metrics.fps);
          final buildColor = _getTimeColor(metrics.buildMs);
          final rasterColor = _getTimeColor(metrics.rasterMs);

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // FPS indicator
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: fpsColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${metrics.fps.toStringAsFixed(0)} FPS',
                    style: TextStyle(
                      color: fpsColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              // Build time
              Text(
                'B: ${metrics.buildMs.toStringAsFixed(1)}ms',
                style: TextStyle(
                  color: buildColor,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              // Raster time
              Text(
                'R: ${metrics.rasterMs.toStringAsFixed(1)}ms',
                style: TextStyle(
                  color: rasterColor,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              // Total
              Text(
                'T: ${metrics.totalMs.toStringAsFixed(1)}ms',
                style: const TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
