import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/offline_checkin_provider.dart';
import '../../../core/services/nfc_service.dart';
import '../../../shared/widgets/widgets.dart';
import '../models/event_model.dart';
import '../widgets/connectivity_indicator.dart';
import '../widgets/qr_scanner_view.dart';
import '../widgets/verification_card.dart';
import 'vendor_event_screen.dart';

/// Screen for ushers to scan and validate tickets at an event.
///
/// Features offline check-in with 3-tier verification:
/// 1. Offline Cache — instant HashMap lookup
/// 2. Blockchain — NFT ownership verification
/// 3. Database — live status confirmation
///
/// Door list is auto-downloaded on screen open. Background sync
/// pushes local check-ins to Supabase every 7 seconds when online.
class UsherEventScreen extends ConsumerStatefulWidget {
  const UsherEventScreen({
    super.key,
    required this.event,
    this.canSwitchToSelling = false,
  });

  final EventModel event;
  final bool canSwitchToSelling;

  @override
  ConsumerState<UsherEventScreen> createState() => _UsherEventScreenState();
}

class _UsherEventScreenState extends ConsumerState<UsherEventScreen>
    with SingleTickerProviderStateMixin {
  int _sessionCheckedIn = 0;

  // NFC state
  bool _isNfcAvailable = false;
  bool _isNfcScanning = false;
  bool _nfcContinuousMode = false;
  bool _isHoldingButton = false;
  final NfcService _nfcService = NfcService.instance;

  // Camera state
  bool _showCamera = false;

  // Check-in state
  bool _isCheckingIn = false;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Auto-download door list, then invalidate cache provider for My Events chips
    Future.microtask(() async {
      await ref.read(offlineCheckInProvider.notifier).downloadDoorList(widget.event.id);
      ref.invalidate(doorListCachedProvider(widget.event.id));
    });

    // Check NFC availability
    _checkNfcAvailability();

    // Pulse animation for NFC scanning
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _checkNfcAvailability() async {
    final available = await _nfcService.isNfcAvailable();
    if (mounted) {
      setState(() => _isNfcAvailable = available);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stopNfcScanning();
    super.dispose();
  }

  Future<void> _startNfcScanning() async {
    if (!_isNfcAvailable) {
      _showError('NFC is not available on this device');
      return;
    }

    setState(() => _isNfcScanning = true);
    _pulseController.repeat(reverse: true);
    HapticFeedback.mediumImpact();

    await _nfcService.startReading(
      onTagRead: (payload) {
        if (payload.eventId == widget.event.id) {
          _verifyTicket(payload.ticketId);
        } else {
          _showError('Ticket is for a different event');
          HapticFeedback.heavyImpact();
        }
      },
      onError: (error) {
        _showError(error);
        HapticFeedback.heavyImpact();
      },
    );
  }

  Future<void> _stopNfcScanning() async {
    await _nfcService.stopReading();
    if (mounted) {
      setState(() => _isNfcScanning = false);
    }
    _pulseController.stop();
    _pulseController.reset();
  }

  void _onHoldStart() {
    if (_nfcContinuousMode) return;
    setState(() => _isHoldingButton = true);
    unawaited(_startNfcScanning());
  }

  void _onHoldEnd() {
    if (_nfcContinuousMode) return;
    setState(() => _isHoldingButton = false);
    unawaited(_stopNfcScanning());
  }

  void _toggleContinuousMode(bool value) {
    setState(() {
      _nfcContinuousMode = value;
      if (value) {
        unawaited(_startNfcScanning());
      } else if (!_isHoldingButton) {
        unawaited(_stopNfcScanning());
      }
    });
    HapticFeedback.selectionClick();
  }

  void _openCamera() {
    setState(() => _showCamera = true);
  }

  void _closeCamera() {
    setState(() => _showCamera = false);
  }

  /// Run 3-tier verification pipeline for a scanned ticket.
  Future<void> _verifyTicket(String ticketIdOrNumber) async {
    if (ticketIdOrNumber.trim().isEmpty) {
      _showError('Please enter a ticket number');
      return;
    }

    HapticFeedback.mediumImpact();

    // Close camera if open
    if (_showCamera) _closeCamera();

    final result = await ref
        .read(offlineCheckInProvider.notifier)
        .verifyTicket(ticketIdOrNumber.trim(), widget.event.id);

    if (!mounted) return;

    // Haptic feedback based on result
    if (result.isAdmittable) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  /// Confirm check-in for the verified ticket.
  Future<void> _confirmCheckIn() async {
    final verification = ref.read(offlineCheckInProvider).currentVerification;
    final ticket = verification?.ticket;
    if (ticket == null) return;

    setState(() => _isCheckingIn = true);

    final success = await ref
        .read(offlineCheckInProvider.notifier)
        .confirmCheckIn(ticket.ticketId);

    if (!mounted) return;

    if (success) {
      setState(() {
        _sessionCheckedIn++;
        _isCheckingIn = false;
      });
      ref.read(offlineCheckInProvider.notifier).clearVerification();
      HapticFeedback.heavyImpact();
      _showSuccess('Ticket checked in!');
    } else {
      setState(() => _isCheckingIn = false);
      _showError('Failed to check in ticket');
    }
  }

  /// Dismiss the current verification result.
  void _dismissVerification() {
    ref.read(offlineCheckInProvider.notifier).clearVerification();
  }

  void _showError(String message) {
    if (!mounted) return;
    ErrorSnackBar.show(context, message);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = widget.event.getNoiseConfig();
    final offlineState = ref.watch(offlineCheckInProvider);

    // Show camera view if open
    if (_showCamera) {
      return _CameraOverlay(
        event: widget.event,
        onScanned: _verifyTicket,
        onClose: _closeCamera,
        onError: _showError,
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar with gradient
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.event.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 4,
                      color: Colors.black26,
                    ),
                  ],
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: config.colors,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              // Camera button
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: Material(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _openCamera,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.qr_code_scanner,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              // Role switch button
              if (widget.canSwitchToSelling)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => VendorEventScreen(
                              event: widget.event,
                              canSwitchToUsher: true,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.point_of_sale,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Sell',
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
                ),
              // Usher badge
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.badge_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Usher',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Connectivity banner
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ConnectivityIndicator(
                isOnline: offlineState.isOnline,
                pendingSyncCount: offlineState.pendingSyncCount,
                expanded: true,
              ),
            ),
          ),

          // Stats bar
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatItem(
                        icon: Icons.login,
                        value: '${offlineState.checkedInCount}',
                        label: 'Checked In',
                        color: Colors.green,
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: colorScheme.outline.withValues(alpha: 0.3),
                      ),
                      _StatItem(
                        icon: Icons.confirmation_number_outlined,
                        value: '${offlineState.totalTickets}',
                        label: 'Total',
                        color: colorScheme.tertiary,
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: colorScheme.outline.withValues(alpha: 0.3),
                      ),
                      _StatItem(
                        icon: Icons.nfc_rounded,
                        value: '$_sessionCheckedIn',
                        label: 'This Session',
                        color: colorScheme.primary,
                      ),
                      if (offlineState.pendingSyncCount > 0) ...[
                        Container(
                          width: 1,
                          height: 40,
                          color: colorScheme.outline.withValues(alpha: 0.3),
                        ),
                        _StatItem(
                          icon: Icons.sync,
                          value: '${offlineState.pendingSyncCount}',
                          label: 'Pending',
                          color: Colors.amber.shade700,
                        ),
                      ],
                    ],
                  ),
                  // Door list freshness
                  if (offlineState.doorListDownloadedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _formatDoorListAge(offlineState.doorListDownloadedAt!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Door list download progress
          if (offlineState.isDownloading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(
                      'Downloading door list...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

          // Main content
          SliverFillRemaining(
            hasScrollBody: false,
            child: offlineState.currentVerification != null
                ? _buildVerificationResult(offlineState)
                : _buildNfcScanView(),
          ),
        ],
      ),
    );
  }

  String _formatDoorListAge(DateTime downloadedAt) {
    final diff = DateTime.now().difference(downloadedAt);
    final offlineState = ref.read(offlineCheckInProvider);

    String age;
    if (diff.inSeconds < 60) {
      age = 'just now';
    } else if (diff.inMinutes < 60) {
      age = '${diff.inMinutes}m ago';
    } else {
      age = '${diff.inHours}h ago';
    }

    return 'Door list downloaded $age — ${offlineState.totalTickets} tickets';
  }

  Widget _buildNfcScanView() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final offlineState = ref.watch(offlineCheckInProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),

          // NFC Scan Button
          GestureDetector(
            onTapDown: (_) => _onHoldStart(),
            onTapUp: (_) => _onHoldEnd(),
            onTapCancel: _onHoldEnd,
            onLongPressStart: (_) => _onHoldStart(),
            onLongPressEnd: (_) => _onHoldEnd(),
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: _isNfcScanning
                        ? [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.4),
                              blurRadius: 30 * _pulseAnimation.value,
                              spreadRadius: 10 * (_pulseAnimation.value - 1),
                            ),
                          ]
                        : null,
                  ),
                  child: child,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isNfcScanning
                        ? [colorScheme.primary, colorScheme.tertiary]
                        : [
                            colorScheme.surfaceContainerHighest,
                            colorScheme.surfaceContainerHigh,
                          ],
                  ),
                  border: Border.all(
                    color: _isNfcScanning
                        ? colorScheme.primary
                        : colorScheme.outline.withValues(alpha: 0.3),
                    width: 3,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.nfc_rounded,
                      size: 64,
                      color: _isNfcScanning
                          ? Colors.white
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isNfcScanning ? 'Scanning...' : 'Hold to Scan',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _isNfcScanning
                            ? Colors.white
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Instructions
          Text(
            !_isNfcAvailable
                ? 'NFC not available. Use QR scanner instead.'
                : _isNfcScanning
                    ? 'Hold device near attendee\'s phone'
                    : offlineState.isDoorListLoaded
                        ? 'Hold the button to activate NFC scanning'
                        : 'Downloading door list...',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          // Continuous mode toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _nfcContinuousMode
                    ? colorScheme.primary
                    : colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.repeat,
                  size: 20,
                  color: _nfcContinuousMode
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  'Continuous Scanning',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: _nfcContinuousMode,
                  onChanged: _toggleContinuousMode,
                ),
              ],
            ),
          ),

          const Spacer(),

          // Loading indicator
          if (offlineState.isVerifying)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Verifying ticket...',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),

          // Manual entry hint
          TextButton.icon(
            onPressed: () => _showManualEntryDialog(),
            icon: const Icon(Icons.keyboard, size: 18),
            label: const Text('Enter ticket manually'),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showManualEntryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Ticket Number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'TKT-XXXXXXX-XXXX',
            prefixIcon: Icon(Icons.confirmation_number_outlined),
          ),
          onSubmitted: (value) {
            Navigator.pop(context);
            _verifyTicket(value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _verifyTicket(controller.text);
            },
            child: const Text('Look Up'),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationResult(OfflineCheckInState offlineState) {
    return SingleChildScrollView(
      key: const ValueKey('verification_result'),
      padding: const EdgeInsets.only(bottom: 32),
      child: VerificationCard(
        result: offlineState.currentVerification!,
        onDismiss: _dismissVerification,
        onCheckIn: _confirmCheckIn,
        isCheckingIn: _isCheckingIn,
      ),
    );
  }
}

/// Camera overlay for QR scanning.
class _CameraOverlay extends StatelessWidget {
  const _CameraOverlay({
    required this.event,
    required this.onScanned,
    required this.onClose,
    required this.onError,
  });

  final EventModel event;
  final void Function(String) onScanned;
  final VoidCallback onClose;
  final void Function(String) onError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Camera view
          QrScannerView(
            onScanned: onScanned,
            onError: onError,
          ),

          // Header overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onClose,
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Scan QR Code',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              event.title,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom hint
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Point camera at the ticket QR code',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
