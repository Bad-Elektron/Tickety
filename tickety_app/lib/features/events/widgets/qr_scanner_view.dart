import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera-based QR code scanner for ticket check-in.
///
/// Displays a camera viewfinder with targeting overlay and
/// calls [onScanned] when a QR code is detected.
class QrScannerView extends StatefulWidget {
  const QrScannerView({
    super.key,
    required this.onScanned,
    this.onError,
  });

  /// Called when a QR code is successfully scanned.
  final void Function(String ticketIdOrNumber) onScanned;

  /// Called when an error occurs with the scanner.
  final void Function(String error)? onError;

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _torchEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScanner();
  }

  Future<void> _initializeScanner() async {
    try {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to initialize camera: $e';
        });
        widget.onError?.call(_errorMessage!);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _controller?.stop();
      case AppLifecycleState.resumed:
        _controller?.start();
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final value = barcode.rawValue;

    if (value == null || value.isEmpty) return;

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    // Parse the QR content - could be just ticket ID or full URL
    final ticketIdOrNumber = _parseQrContent(value);

    widget.onScanned(ticketIdOrNumber);

    // Reset processing after a short delay to prevent duplicate scans
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    });
  }

  /// Parses QR code content to extract ticket ID or number.
  ///
  /// Supports formats:
  /// - Plain ticket ID: "uuid-here"
  /// - Plain ticket number: "TKT-123-4567"
  /// - URL format: "https://tickety.app/ticket/uuid-here"
  String _parseQrContent(String content) {
    // Check if it's a URL
    if (content.startsWith('http')) {
      final uri = Uri.tryParse(content);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        // Return the last path segment (assumed to be ticket ID)
        return uri.pathSegments.last;
      }
    }

    // Check if it's JSON with ticket info
    if (content.startsWith('{')) {
      // Simple extraction - look for id or ticket_number
      final idMatch = RegExp(r'"id"\s*:\s*"([^"]+)"').firstMatch(content);
      if (idMatch != null) return idMatch.group(1)!;

      final numberMatch =
          RegExp(r'"ticket_number"\s*:\s*"([^"]+)"').firstMatch(content);
      if (numberMatch != null) return numberMatch.group(1)!;
    }

    // Return as-is (plain ticket ID or number)
    return content.trim();
  }

  void _toggleTorch() {
    _controller?.toggleTorch();
    setState(() => _torchEnabled = !_torchEnabled);
    HapticFeedback.lightImpact();
  }

  void _switchCamera() {
    _controller?.switchCamera();
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_hasError) {
      return _ErrorView(
        message: _errorMessage ?? 'Scanner unavailable',
        onRetry: () {
          setState(() {
            _hasError = false;
            _errorMessage = null;
          });
          _initializeScanner();
        },
      );
    }

    if (_controller == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
        // Camera view
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: MobileScanner(
            controller: _controller!,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return _ErrorView(
                message: error.errorDetails?.message ?? 'Camera error',
                onRetry: () => _controller?.start(),
              );
            },
          ),
        ),

        // Scanning overlay
        _ScannerOverlay(
          isProcessing: _isProcessing,
          borderColor: _isProcessing ? Colors.green : colorScheme.primary,
        ),

        // Controls overlay
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Torch toggle
              _ControlButton(
                icon: _torchEnabled ? Icons.flash_on : Icons.flash_off,
                label: 'Flash',
                isActive: _torchEnabled,
                onPressed: _toggleTorch,
              ),
              // Camera switch
              _ControlButton(
                icon: Icons.flip_camera_ios,
                label: 'Flip',
                onPressed: _switchCamera,
              ),
            ],
          ),
        ),

        // Processing indicator
        if (_isProcessing)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Processing...',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Scanning viewfinder overlay with animated border.
class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({
    required this.isProcessing,
    required this.borderColor,
  });

  final bool isProcessing;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanAreaSize = constraints.maxWidth * 0.7;
        final left = (constraints.maxWidth - scanAreaSize) / 2;
        final top = (constraints.maxHeight - scanAreaSize) / 2;

        return Stack(
          children: [
            // Semi-transparent overlay
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _OverlayPainter(
                scanRect: Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize),
              ),
            ),
            // Scanning frame
            Positioned(
              left: left,
              top: top,
              child: Container(
                width: scanAreaSize,
                height: scanAreaSize,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: borderColor,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            // Corner accents
            ..._buildCornerAccents(left, top, scanAreaSize),
          ],
        );
      },
    );
  }

  List<Widget> _buildCornerAccents(double left, double top, double size) {
    const cornerLength = 24.0;
    const cornerWidth = 4.0;

    return [
      // Top-left
      Positioned(
        left: left - 1,
        top: top - 1,
        child: _CornerAccent(
          borderColor: borderColor,
          length: cornerLength,
          width: cornerWidth,
          corner: _Corner.topLeft,
        ),
      ),
      // Top-right
      Positioned(
        right: left - 1,
        top: top - 1,
        child: _CornerAccent(
          borderColor: borderColor,
          length: cornerLength,
          width: cornerWidth,
          corner: _Corner.topRight,
        ),
      ),
      // Bottom-left
      Positioned(
        left: left - 1,
        bottom: top - 1,
        child: _CornerAccent(
          borderColor: borderColor,
          length: cornerLength,
          width: cornerWidth,
          corner: _Corner.bottomLeft,
        ),
      ),
      // Bottom-right
      Positioned(
        right: left - 1,
        bottom: top - 1,
        child: _CornerAccent(
          borderColor: borderColor,
          length: cornerLength,
          width: cornerWidth,
          corner: _Corner.bottomRight,
        ),
      ),
    ];
  }
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CornerAccent extends StatelessWidget {
  const _CornerAccent({
    required this.borderColor,
    required this.length,
    required this.width,
    required this.corner,
  });

  final Color borderColor;
  final double length;
  final double width;
  final _Corner corner;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: length,
      height: length,
      child: CustomPaint(
        painter: _CornerPainter(
          color: borderColor,
          strokeWidth: width,
          corner: corner,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final _Corner corner;

  _CornerPainter({
    required this.color,
    required this.strokeWidth,
    required this.corner,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    switch (corner) {
      case _Corner.topLeft:
        path.moveTo(0, size.height);
        path.lineTo(0, 0);
        path.lineTo(size.width, 0);
      case _Corner.topRight:
        path.moveTo(0, 0);
        path.lineTo(size.width, 0);
        path.lineTo(size.width, size.height);
      case _Corner.bottomLeft:
        path.moveTo(0, 0);
        path.lineTo(0, size.height);
        path.lineTo(size.width, size.height);
      case _Corner.bottomRight:
        path.moveTo(0, size.height);
        path.lineTo(size.width, size.height);
        path.lineTo(size.width, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.corner != corner;
  }
}

class _OverlayPainter extends CustomPainter {
  final Rect scanRect;

  _OverlayPainter({required this.scanRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.5);

    // Draw overlay with cutout
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()
          ..addRRect(
            RRect.fromRectAndRadius(scanRect, const Radius.circular(12)),
          ),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_OverlayPainter oldDelegate) {
    return oldDelegate.scanRect != scanRect;
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isActive
          ? colorScheme.primaryContainer
          : Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive ? colorScheme.primary : Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? colorScheme.primary : Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.camera_alt_outlined,
                size: 48,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Camera Unavailable',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
